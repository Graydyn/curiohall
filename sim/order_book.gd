class_name OrderBook
extends RefCounted

const SLOTS := 3
const REFRESH_FLOOR := 60   # exclude degenerate 1-second order types

signal orders_changed

var orders: Array = [null, null, null]
var refresh_at: Array = [0.0, 0.0, 0.0]   # slot fillable when now >= refresh_at
var next_fixed: int = 0   # index into ConfigDB.order_fixed; advances when a fixed order is placed

func pool_row(code: String) -> Dictionary:
	for row in ConfigDB.order_items:
		if String(row["Code"]) == code:
			return row
	return {}

func _roll_avatar(player_level: int, rng: RandomNumberGenerator) -> String:
	var normals_v: Variant = ConfigDB.order_avatars.get("NormalAvatars")
	var normals: Array = normals_v if normals_v is Array else []
	var pool: Array = []
	for row in normals:
		if player_level >= int(row.get("UnlockLevel", 1)):
			pool.append(String(row["Avatar"]))
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)])

func _eligible_types(player_level: int) -> Array:
	var out: Array = []
	for row in ConfigDB.order_random:
		if int(row.get("RefreshTime", 0)) >= REFRESH_FLOOR \
				and player_level >= int(row.get("UnlockLevel", 1)):
			out.append(row)
	return out

func _filter_for(type_row: Dictionary, player_level: int) -> Dictionary:
	for f in type_row.get("Filters", []):
		var lo = f.get("PlayerMin")
		var hi = f.get("PlayerMax")
		if (lo == null or player_level >= int(lo)) and (hi == null or player_level <= int(hi)):
			return f
	return {}

func _tier(code: String) -> int:
	return int(code.substr(code.length() - 2))

func _pool_for_level(player_level: int) -> Array:
	var out: Array = []
	for row in ConfigDB.order_items:
		if row != null and int(row.get("UnlockLevel", 1)) <= player_level:
			out.append(row)
	return out

func _build_order(type_row: Dictionary, player_level: int, rng: RandomNumberGenerator, now: float) -> Dictionary:
	var flt := _filter_for(type_row, player_level)
	var caps := [int(flt.get("FirstMax", 99)), int(flt.get("SecondMax", 99)), int(flt.get("ThirdMax", 99))]
	var amounts: Dictionary = type_row["ItemAmounts"]
	var kind_weights := Weighted.parse([
		"1-%d" % int(amounts.get("OneItemWeight", 100)),
		"2-%d" % int(amounts.get("TwoItemsWeight", 0)),
		"3-%d" % int(amounts.get("ThreeItemsWeight", 0)),
	])
	var pool := _pool_for_level(player_level)
	var kinds := int(Weighted.roll(kind_weights, rng))
	var items := {}
	for k in range(kinds):
		var cap: int = caps[k]
		var sub := pool.filter(func(r): return _tier(String(r["Code"])) <= cap and not items.has(String(r["Code"])))
		if sub.is_empty():
			break
		var wp := Weighted.parse(sub.map(func(r): return "%s-%d" % [r["Code"], int(r.get("Weight", 1))]))
		items[Weighted.roll(wp, rng)] = rng.randi_range(1, 2)
	var coins := 0
	var xp := 0
	for code in items:
		var row := pool_row(code)
		coins += int(row["Price"]) * int(items[code])
		xp += int(row.get("DiffScore", 1)) * int(items[code])
	return {"items": items, "coins": coins, "xp": xp, "created_at": now,
			"avatar": _roll_avatar(player_level, rng),
			"type": int(type_row["Type"]), "refresh_time": int(type_row["RefreshTime"])}

func _free_allowed_slot(slots_cfg: Array, now: float) -> int:
	for s in slots_cfg:
		var i := int(s) - 1   # config slots are 1-based
		if i >= 0 and i < SLOTS and orders[i] == null and now >= float(refresh_at[i]):
			return i
	return -1

func _build_fixed(row: Dictionary, player_level: int, rng: RandomNumberGenerator, now: float) -> Dictionary:
	var items := {}
	var coins := 0
	var xp := 0
	for key in ["Requirement1", "Requirement2", "Requirement3"]:
		if row.get(key) == null:
			continue
		var code := String(row[key])
		items[code] = int(items.get(code, 0)) + 1
		var item_row := pool_row(code)
		coins += int(item_row.get("Price", 0))
		xp += int(item_row.get("DiffScore", 1))
	return {"items": items, "coins": coins, "xp": xp, "created_at": now,
			"avatar": _roll_avatar(player_level, rng),
			"type": 0, "refresh_time": 0, "fixed": true}

## Tutorial orders are placed strictly in Id order: the next one waits for
## its UnlockLevel and for one of its allowed slots to be free.
func _fill_fixed(player_level: int, rng: RandomNumberGenerator, now: float) -> bool:
	var placed := false
	while next_fixed < ConfigDB.order_fixed.size():
		var row: Dictionary = ConfigDB.order_fixed[next_fixed]
		if player_level < int(row.get("UnlockLevel", 1)):
			break
		var slot := _free_allowed_slot(row.get("Slots", []), now)
		if slot < 0:
			break
		orders[slot] = _build_fixed(row, player_level, rng, now)
		next_fixed += 1
		placed = true
	return placed

func fill(player_level: int, rng: RandomNumberGenerator, now: float) -> bool:
	var did_fill := _fill_fixed(player_level, rng, now)
	var elig := _eligible_types(player_level)
	if elig.is_empty():
		if did_fill:
			orders_changed.emit()
		return did_fill
	for i in range(SLOTS):
		if orders[i] != null or now < float(refresh_at[i]):
			continue
		var type_row: Dictionary = elig[rng.randi_range(0, elig.size() - 1)]
		var order := _build_order(type_row, player_level, rng, now)
		if order["items"].is_empty():
			continue
		orders[i] = order
		did_fill = true
	if did_fill:
		orders_changed.emit()
	return did_fill

func can_deliver(i: int, board: MergeBoard) -> bool:
	var o: Variant = orders[i]
	if o == null:
		return false
	for code in o["items"]:
		if board.count_of(code) < int(o["items"][code]):
			return false
	return true

func deliver(i: int, board: MergeBoard) -> Dictionary:
	if not can_deliver(i, board):
		return {"ok": false, "coins": 0, "xp": 0}
	var o: Dictionary = orders[i]
	for code in o["items"]:
		board.remove_n_of(code, int(o["items"][code]))
	orders[i] = null
	orders_changed.emit()
	return {"ok": true, "coins": int(o["coins"]), "xp": int(o["xp"]), "refresh_time": int(o["refresh_time"])}

func set_cooldown(i: int, seconds: float, now: float) -> void:
	refresh_at[i] = now + seconds
	orders_changed.emit()

func is_cooling(i: int, now: float) -> bool:
	return orders[i] == null and now < float(refresh_at[i])

func time_to_refresh(i: int, now: float) -> float:
	return maxf(0.0, float(refresh_at[i]) - now)

func skip_refresh(i: int, wallet: EnergyWallet, now: float) -> bool:
	if not is_cooling(i, now):
		return false
	if not wallet.spend_gems(int(ConfigDB.tuning["order_skip_gems"])):
		return false
	refresh_at[i] = 0.0
	orders_changed.emit()
	return true

func to_dict() -> Dictionary:
	return {"orders": orders.duplicate(true), "refresh_at": refresh_at.duplicate(),
			"next_fixed": next_fixed}

static func from_dict(d: Dictionary) -> OrderBook:
	var ob := OrderBook.new()
	ob.orders = (d["orders"] as Array).duplicate(true)
	ob.refresh_at = (d.get("refresh_at", [0.0, 0.0, 0.0]) as Array).duplicate()
	ob.next_fixed = int(d.get("next_fixed", 0))
	return ob
