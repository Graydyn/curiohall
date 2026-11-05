class_name PlayerState
extends RefCounted

signal leveled_up(new_level: int)

var level: int = 1
var xp: int = 0
var inventory: Array[String] = []
var slots: int = 5

func _init() -> void:
    slots = int(ConfigDB.inventory_cfg["DefaultNumber"])

func _cost_for(lvl: int) -> int:
    if lvl > ConfigDB.levels.size():
        return -1   # max level
    return int(ConfigDB.levels[lvl - 1]["cost"])

func add_xp(n: int) -> Array[int]:
    xp += n
    var gained: Array[int] = []
    while _cost_for(level) > 0 and xp >= _cost_for(level):
        xp -= _cost_for(level)
        gained.append(level)   # the level just completed
        level += 1
        leveled_up.emit(level)
    return gained

func store(type: String) -> bool:
    if inventory.size() >= slots:
        return false
    inventory.append(type)
    return true

func withdraw(index: int) -> String:
    if index < 0 or index >= inventory.size():
        return ""
    return inventory.pop_at(index)

func next_slot_cost() -> int:
    var costs: Array = ConfigDB.inventory_cfg["UnlockCost"]
    if slots >= int(ConfigDB.inventory_cfg["MaxNumber"]):
        return -1
    return int(costs[slots])

func unlock_slot(wallet: EnergyWallet) -> bool:
    var cost := next_slot_cost()
    if cost < 0 or not wallet.spend_gems(cost):
        return false
    slots += 1
    return true

func to_dict() -> Dictionary:
    return {"level": level, "xp": xp, "inventory": inventory.duplicate(), "slots": slots}

static func from_dict(d: Dictionary) -> PlayerState:
    var p := PlayerState.new()
    p.level = int(d["level"])
    p.xp = int(d["xp"])
    p.slots = int(d["slots"])
    for t in d["inventory"]:
        p.inventory.append(String(t))
    return p
