class_name ItemInstance
extends RefCounted

var type: String
var gen: Variant = null   # GeneratorState, attached in Task 5 for generator items
var chest: ChestState = null

static func make(item_type: String, now: float = 0.0) -> ItemInstance:
    var it := ItemInstance.new()
    it.type = item_type
    it.chest = ChestState.for_type(item_type, now)
    if it.chest == null:
        it.gen = GeneratorState.for_type(item_type, now)
    return it
