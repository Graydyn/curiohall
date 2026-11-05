class_name MergeBoard
extends RefCounted

const WIDTH := 7
const HEIGHT := 9
enum CellState { OPEN, COVERED, BOXED }

var width: int = WIDTH
var height: int = HEIGHT

signal item_placed(pos: Vector2i, type: String)
signal items_merged(pos: Vector2i, new_type: String)
signal item_removed(pos: Vector2i)
signal cell_opened(pos: Vector2i, new_state: int)

var _items := {}    # Vector2i -> ItemInstance
var _states := {}   # Vector2i -> CellState; absent means OPEN
var _unboxed: Array = []   # cells unboxed since take_unboxed(); transient, not saved

func in_bounds(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height

func item_at(pos: Vector2i) -> ItemInstance:
    return _items.get(pos)

func state_at(pos: Vector2i) -> int:
    return _states.get(pos, CellState.OPEN)

func set_state(pos: Vector2i, state: int) -> void:
    if state == CellState.OPEN:
        _states.erase(pos)
    else:
        _states[pos] = state

func place(pos: Vector2i, item: ItemInstance) -> bool:
    if not in_bounds(pos) or _items.has(pos):
        return false
    _items[pos] = item
    item_placed.emit(pos, item.type)
    return true

func remove(pos: Vector2i) -> ItemInstance:
    var item: ItemInstance = _items.get(pos)
    if item != null:
        _items.erase(pos)
        item_removed.emit(pos)
    return item

func can_merge(a: Vector2i, b: Vector2i) -> bool:
    return merge_error(a, b) == ""

func merge_error(a: Vector2i, b: Vector2i) -> String:
    if a == b:
        return "mismatch"
    var ia := item_at(a)
    var ib := item_at(b)
    if ia == null or ib == null:
        return "empty"
    # The source must be free; the target may be COVERED (a veiled item is a
    # legal merge target — merging a matching free item onto it clears the web).
    if state_at(a) != CellState.OPEN or state_at(b) == CellState.BOXED:
        return "not_open"
    if ia.type != ib.type:
        return "mismatch"
    var merged_type := String(ConfigDB.items[ia.type].get("MergedType", ""))
    if merged_type.is_empty() or "#" in merged_type:
        return "chain_top"
    return ""

func merge(a: Vector2i, b: Vector2i) -> String:
    var err := merge_error(a, b)
    if err != "":
        return err
    var new_type := String(ConfigDB.items[item_at(a).type]["MergedType"])
    remove(a)
    remove(b)
    place(b, ItemInstance.make(new_type))
    if state_at(b) == CellState.COVERED:
        set_state(b, CellState.OPEN)   # merging onto a veiled item clears its web
        cell_opened.emit(b, CellState.OPEN)
    _shock_neighbors(b)
    items_merged.emit(b, new_type)
    return ""

## A merge shocks the target's four orthogonal neighbors: a shocked paperbox
## collapses to its veiled contents. Cobwebs ignore shocks — they clear only
## when a matching free item is merged onto them (see merge/merge_error).
func _shock_neighbors(pos: Vector2i) -> void:
    for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
        var n: Vector2i = pos + d
        if state_at(n) == CellState.BOXED:
            set_state(n, CellState.COVERED)
            _unboxed.append(n)
            cell_opened.emit(n, CellState.COVERED)

func take_unboxed() -> Array:
    var out := _unboxed
    _unboxed = []
    return out

func move(from: Vector2i, to: Vector2i) -> String:
    if item_at(from) == null:
        return "empty"
    if state_at(from) != CellState.OPEN or state_at(to) != CellState.OPEN:
        return "not_open"
    if not in_bounds(to) or item_at(to) != null:
        return "occupied"
    place(to, remove(from))
    return ""

func sell(pos: Vector2i) -> Dictionary:
    var item := item_at(pos)
    if item == null or state_at(pos) != CellState.OPEN:
        return {"ok": false, "coins": 0, "reason": "not_open"}
    var price := int(ConfigDB.items[item.type].get("SellingPrice", 0))
    if price <= 0:
        return {"ok": false, "coins": 0, "reason": "unsellable"}
    remove(pos)
    return {"ok": true, "coins": price, "reason": ""}

func find_free_cell(near: Vector2i) -> Vector2i:
    for radius in range(0, width + height):
        for y in range(near.y - radius, near.y + radius + 1):
            for x in range(near.x - radius, near.x + radius + 1):
                var p := Vector2i(x, y)
                if in_bounds(p) and item_at(p) == null and state_at(p) == CellState.OPEN:
                    return p
    return Vector2i(-1, -1)

func spawn(type: String, near: Vector2i) -> Vector2i:
    var pos := find_free_cell(near)
    if pos != Vector2i(-1, -1):
        place(pos, ItemInstance.make(type))
    return pos

func count_of(type: String) -> int:
    var n := 0
    for pos in _items:
        if state_at(pos) == CellState.OPEN and _items[pos].type == type:
            n += 1
    return n

func remove_n_of(type: String, n: int) -> int:
    var removed := 0
    for pos in _items.keys():
        if removed == n:
            break
        if state_at(pos) == CellState.OPEN and _items[pos].type == type:
            remove(pos)
            removed += 1
    return removed

func to_dict() -> Dictionary:
    var cells := {}
    for pos in _items:
        var item: ItemInstance = _items[pos]
        cells["%d,%d" % [pos.x, pos.y]] = {
            "type": item.type,
            "state": state_at(pos),
            "gen": item.gen.to_dict() if item.gen != null else null,
            "chest": item.chest.to_dict() if item.chest != null else null,
        }
    return {"cells": cells, "width": width, "height": height}

static func from_dict(d: Dictionary) -> MergeBoard:
    var board := MergeBoard.new()
    board.width = int(d.get("width", WIDTH))
    board.height = int(d.get("height", HEIGHT))
    for key in d["cells"]:
        var parts: PackedStringArray = String(key).split(",")
        var pos := Vector2i(int(parts[0]), int(parts[1]))
        var c: Dictionary = d["cells"][key]
        var item := ItemInstance.new()
        item.type = String(c["type"])
        if c["gen"] != null:
            item.gen = GeneratorState.from_dict(c["gen"])
        if c.get("chest") != null:
            item.chest = ChestState.from_dict(c["chest"])
        board.place(pos, item)
        board.set_state(pos, int(c["state"]))
    return board
