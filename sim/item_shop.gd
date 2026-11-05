class_name ItemShop
extends RefCounted
## The coin item-shop: 6 weighted slots, buy-with-coins, whole-shop timed refresh.

const SLOTS := 6

signal shop_changed

var slots: Array = [null, null, null, null, null, null]
var refresh_at: float = 0.0   # shop re-rolls when now >= refresh_at (0 = fill now)

func _natural_chain(id: String) -> String:
	return id.substr(0, id.length() - 2)

func _shop_chain(row: Dictionary) -> String:
	var custom := String(row.get("CustomChain", ""))
	return custom if custom != "" else _natural_chain(String(row["Type"]))

func roll_slot(n: int, rng: RandomNumberGenerator) -> Dictionary:
	var by_chain := {}
	for r in ConfigDB.properties.values():
		if n in r.get("Slot", []):
			var ch := _shop_chain(r)
			if not by_chain.has(ch):
				by_chain[ch] = []
			by_chain[ch].append(r)
	var chain_weights: Array = []
	for slotrow in ConfigDB.shop_slots:
		var ch := String(slotrow["ChainId"])
		var w := int(slotrow.get("Slot%dWeight" % n, 0))
		if w > 0 and by_chain.has(ch):
			chain_weights.append("%s-%d" % [ch, w])
	var pool: Array
	if chain_weights.is_empty():
		# fallback: any candidate uniformly
		pool = []
		for arr in by_chain.values():
			pool.append_array(arr)
	else:
		var chosen := Weighted.roll(Weighted.parse(chain_weights), rng)
		pool = by_chain[chosen]
	if pool.is_empty():
		push_warning("ItemShop.roll_slot: no candidate items for slot %d" % n)
		return {"item": "", "price": 0, "count": 0, "sold_out": true}
	var item_weights := Weighted.parse(pool.map(
		func(r: Dictionary) -> String: return "%s-%d" % [r["Type"], int(r.get("ShopWeight", 1))]))
	var item_id := Weighted.roll(item_weights, rng)
	var prop: Dictionary = ConfigDB.properties[item_id]
	return {"item": item_id, "price": int(prop["Price"]), "count": int(prop.get("ShopCount", 1)), "sold_out": false}

func fill(rng: RandomNumberGenerator, now: float) -> bool:
	if now < refresh_at:
		return false
	var did := false
	for i in range(SLOTS):
		if slots[i] == null:
			slots[i] = roll_slot(i + 1, rng)
			did = true
	if did:
		shop_changed.emit()
	return did

func buy(n: int, wallet: EnergyWallet, game, now: float) -> Dictionary:
	var slot: Variant = slots[n - 1]
	if slot == null:
		return {"ok": false, "reason": "empty"}
	if slot["sold_out"]:
		return {"ok": false, "reason": "sold_out"}
	if not wallet.spend_coins(int(slot["price"])):
		return {"ok": false, "reason": "not_enough_coins"}
	for i in range(int(slot["count"])):
		Rewards.grant(String(slot["item"]), game, now)
	slot["sold_out"] = true
	shop_changed.emit()
	return {"ok": true, "reason": ""}

func set_refresh(now: float) -> void:
	refresh_at = now + float(ConfigDB.tuning["shop_refresh_seconds"])

func is_refreshing(now: float) -> bool:
	return now < refresh_at

func time_to_refresh(now: float) -> float:
	return maxf(0.0, refresh_at - now)

func skip_refresh(wallet: EnergyWallet, now: float) -> bool:
	if not is_refreshing(now):
		return false
	if not wallet.spend_gems(int(ConfigDB.tuning["shop_skip_gems"])):
		return false
	refresh_at = 0.0
	for i in range(SLOTS):
		slots[i] = null
	shop_changed.emit()
	return true

func to_dict() -> Dictionary:
	return {"slots": slots.duplicate(true), "refresh_at": refresh_at}

static func from_dict(d: Dictionary) -> ItemShop:
	var s := ItemShop.new()
	s.slots = (d.get("slots", [null, null, null, null, null, null]) as Array).duplicate(true)
	s.refresh_at = float(d.get("refresh_at", 0.0))
	return s
