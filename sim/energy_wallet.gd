class_name EnergyWallet
extends RefCounted

signal changed

var coins: int = 0
var gems: int = 0
var _energy_base: int = 0     # energy at _energy_ts
var _energy_ts: float = 0.0

static func fresh(now: float) -> EnergyWallet:
    var w := EnergyWallet.new()
    w.coins = int(ConfigDB.tuning["starting_coins"])
    w.gems = int(ConfigDB.tuning["starting_gems"])
    w._energy_base = int(ConfigDB.tuning["starting_energy"])
    w._energy_ts = now
    return w

func _cap() -> int:
    return int(ConfigDB.tuning["energy_max"])

func _regen() -> float:
    return float(ConfigDB.tuning["energy_regen_seconds"])

func energy(now: float) -> int:
    var accrued_regen := 0
    if _energy_base < _cap():
        accrued_regen = int(floor((now - _energy_ts) / _regen()))
        accrued_regen = mini(accrued_regen, _cap() - _energy_base)
    return _energy_base + accrued_regen

func _settle(now: float) -> void:
    if _energy_base < _cap():
        var accrued := int(floor((now - _energy_ts) / _regen()))
        accrued = mini(accrued, _cap() - _energy_base)
        _energy_base += accrued
        _energy_ts += accrued * _regen()
    else:
        # If overfilled, advance timestamp to prevent retroactive regen when spending brings energy below cap
        _energy_ts = now

func spend_energy(n: int, now: float) -> bool:
    _settle(now)
    if energy(now) < n:
        return false
    _energy_base -= n
    changed.emit()
    return true

func add_energy(n: int, now: float) -> void:
    _settle(now)
    _energy_base += n
    changed.emit()

func seconds_to_next_energy(now: float) -> float:
    if energy(now) >= _cap():
        return 0.0
    return _regen() - fmod(now - _energy_ts, _regen())

func add_coins(n: int) -> void:
    coins += n
    changed.emit()

func spend_coins(n: int) -> bool:
    if coins < n:
        return false
    coins -= n
    changed.emit()
    return true

func add_gems(n: int) -> void:
    gems += n
    changed.emit()

func spend_gems(n: int) -> bool:
    if gems < n:
        return false
    gems -= n
    changed.emit()
    return true

func to_dict() -> Dictionary:
    return {"coins": coins, "gems": gems, "energy_base": _energy_base, "energy_ts": _energy_ts}

static func from_dict(d: Dictionary) -> EnergyWallet:
    var w := EnergyWallet.new()
    w.coins = int(d["coins"])
    w.gems = int(d["gems"])
    w._energy_base = int(d["energy_base"])
    w._energy_ts = float(d["energy_ts"])
    return w
