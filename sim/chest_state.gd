class_name ChestState
extends RefCounted
## Finite, free dispenser. Unlike GeneratorState it never recharges.

var type: String
var _budget: int = 0
var _open_ts: float = 0.0   # last dispense (or creation); gates the timed open

static func for_type(item_type: String, now: float) -> ChestState:
    if not ConfigDB.is_chest(item_type):
        return null
    var cs := ChestState.new()
    cs.type = item_type
    cs._budget = int(ConfigDB.items[item_type].get("Spread_ItemMaxNumber", 0))
    cs._open_ts = now
    return cs

func _row() -> Dictionary:
    return ConfigDB.items[type]

func remaining() -> int:
    return _budget

func is_spent() -> bool:
    return _budget <= 0

func seconds_to_open(now: float) -> float:
    var dur := float(_row().get("Spread_OpenDuration", 0))
    return maxf(0.0, dur - (now - _open_ts))

func can_open(now: float) -> bool:
    return not is_spent() and seconds_to_open(now) <= 0.0

func open(now: float, rng: RandomNumberGenerator) -> String:
    if not can_open(now):
        return ""
    var drop := Weighted.roll(Weighted.parse(_row()["Spread_Weight"]), rng)
    _budget -= 1
    _open_ts = now
    return drop

func skip_open(wallet: EnergyWallet, now: float) -> bool:
    var cost := int(_row().get("Spread_OpenSpeedUpCost", 0))
    if is_spent() or not wallet.spend_gems(cost):
        return false
    _open_ts = now - float(_row().get("Spread_OpenDuration", 0))
    return true

func to_dict() -> Dictionary:
    return {"type": type, "budget": _budget, "open_ts": _open_ts}

static func from_dict(d: Dictionary) -> ChestState:
    var cs := ChestState.new()
    cs.type = String(d["type"])
    cs._budget = int(d["budget"])
    cs._open_ts = float(d["open_ts"])
    return cs
