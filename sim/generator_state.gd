class_name GeneratorState
extends RefCounted

var type: String
var _charge_used: int = 0      # charges consumed and not yet recovered
var _charge_ts: float = 0.0    # when recovery of the oldest missing charge began
var _storage_used: int = 0
var _storage_ts: float = 0.0

static func for_type(item_type: String, now: float) -> GeneratorState:
    var row: Dictionary = ConfigDB.items.get(item_type, {})
    if not row.has("Spread_Weight"):
        return null
    var gs := GeneratorState.new()
    gs.type = item_type
    gs._charge_ts = now
    gs._storage_ts = now
    return gs

func _row() -> Dictionary:
    return ConfigDB.items[type]

func _recovered(used: int, ts: float, duration: float, now: float) -> int:
    if used == 0 or duration <= 0.0:
        return used
    return mini(used, int(floor((now - ts) / duration)))

func charges(now: float) -> int:
    var cap := int(_row().get("Spread_ItemMaxNumber", 0))
    var dur := float(_row().get("Spread_ItemRecoveryDuration", 0))
    return cap - _charge_used + _recovered(_charge_used, _charge_ts, dur, now)

func storage(now: float) -> int:
    var cap := int(_row().get("Spread_StorageMaxNumber", 0))
    var dur := float(_row().get("Spread_StorageRecoveryDuration", 0))
    return cap - _storage_used + _recovered(_storage_used, _storage_ts, dur, now)

func _settle_pool(used: int, ts: float, duration: float, now: float) -> Array:
    var rec := _recovered(used, ts, duration, now)
    return [used - rec, (now if rec == used else ts + rec * duration)]

func consume(now: float) -> bool:
    var row := _row()
    var s := _settle_pool(_charge_used, _charge_ts, float(row.get("Spread_ItemRecoveryDuration", 0)), now)
    _charge_used = s[0]; _charge_ts = s[1]
    if charges(now) > 0:
        if _charge_used == 0:
            _charge_ts = now
        _charge_used += 1
        return true
    s = _settle_pool(_storage_used, _storage_ts, float(row.get("Spread_StorageRecoveryDuration", 0)), now)
    _storage_used = s[0]; _storage_ts = s[1]
    if storage(now) > 0:
        if _storage_used == 0:
            _storage_ts = now
        _storage_used += 1
        return true
    return false

func to_dict() -> Dictionary:
    return {"type": type, "charge_used": _charge_used, "charge_ts": _charge_ts,
            "storage_used": _storage_used, "storage_ts": _storage_ts}

static func from_dict(d: Dictionary) -> GeneratorState:
    var gs := GeneratorState.new()
    gs.type = String(d["type"])
    gs._charge_used = int(d["charge_used"])
    gs._charge_ts = float(d["charge_ts"])
    gs._storage_used = int(d["storage_used"])
    gs._storage_ts = float(d["storage_ts"])
    return gs
