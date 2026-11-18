class_name BoardView
extends Node2D

const CELL := 96
const HINT_DELAY := 4.0      # seconds of no input before a merge hint shows
const HINT_INTERVAL := 1.6   # seconds between hint bounces
const HINT_HOP := 12.0       # bounce height in pixels

signal selection_changed(pos: Vector2i)
signal action_rejected(reason: String)

var game: Game
var board: MergeBoard
var merge_fn: Callable
var tap_fn: Callable
var input_enabled := true
var selected := Vector2i(-1, -1)
var _views := {}          # Vector2i -> ItemView
var _drag_from := Vector2i(-1, -1)
var _dragging: ItemView = null
var hint_pair: Array = []   # [source, target] currently bouncing, or []
var _idle := 0.0
var _hint_tween: Tween = null

func setup(g: Game, b: MergeBoard = null, merge_cb: Callable = Callable(), tap_cb: Callable = Callable()) -> void:
    game = g
    board = b if b != null else g.board
    merge_fn = merge_cb if merge_cb.is_valid() else g.merge
    tap_fn = tap_cb if tap_cb.is_valid() else g.tap
    board.item_placed.connect(_on_placed)
    board.item_removed.connect(_on_removed)
    board.item_removed.connect(_on_removed_clears_selection)
    board.cell_opened.connect(_on_opened)
    for y in range(board.height):
        for x in range(board.width):
            var pos := Vector2i(x, y)
            if board.item_at(pos) != null:
                _on_placed(pos, board.item_at(pos).type)

func _cell_center(pos: Vector2i) -> Vector2:
    return Vector2(pos.x * CELL + CELL / 2.0, pos.y * CELL + CELL / 2.0)

func _pos_at(point: Vector2) -> Vector2i:
    var p := Vector2i(int(point.x / CELL), int(point.y / CELL))
    return p if board.in_bounds(p) else Vector2i(-1, -1)

func _on_placed(pos: Vector2i, _type: String) -> void:
    _reset_idle()
    var v: ItemView = _views.get(pos)
    if v == null:
        v = ItemView.new()
        add_child(v)
        _views[pos] = v
    v.position = _cell_center(pos)
    v.apply(board.item_at(pos).type, board.state_at(pos))

func _on_removed(pos: Vector2i) -> void:
    _reset_idle()
    var v: ItemView = _views.get(pos)
    if v != null:
        v.queue_free()
        _views.erase(pos)

func _on_removed_clears_selection(pos: Vector2i) -> void:
    if selected == pos:
        _select(Vector2i(-1, -1))

func _select(pos: Vector2i) -> void:
    selected = pos
    queue_redraw()
    selection_changed.emit(pos)

func clear_selection() -> void:
    _select(Vector2i(-1, -1))

func _on_opened(pos: Vector2i, _new_state: int) -> void:
    if _views.has(pos):
        _views[pos].apply(board.item_at(pos).type, board.state_at(pos))

func _draw() -> void:
    for y in range(board.height):
        for x in range(board.width):
            draw_rect(Rect2(x * CELL, y * CELL, CELL - 2, CELL - 2), Color(0, 0, 0, 0.15), true)
    if selected != Vector2i(-1, -1):
        draw_rect(Rect2(selected.x * CELL, selected.y * CELL, CELL - 2, CELL - 2), Color(1, 0.85, 0.3), false, 4.0)

## Any player input (anywhere on screen) restarts the idle timer and stops
## the merge hint; after HINT_DELAY idle seconds a legal merge pair bounces.
func _input(event: InputEvent) -> void:
    if event is InputEventMouseButton or event is InputEventScreenTouch \
            or event is InputEventKey or event is InputEventScreenDrag \
            or (event is InputEventMouseMotion and event.button_mask != 0):
        _reset_idle()

func _process(delta: float) -> void:
    if not input_enabled or not is_visible_in_tree() or _dragging != null:
        _reset_idle()
        return
    _idle += delta
    if hint_pair.is_empty() and _idle >= HINT_DELAY:
        _start_hint()

func _reset_idle() -> void:
    _idle = 0.0
    _stop_hint()

func _start_hint() -> void:
    var pair := board.find_merge_pair()
    if pair.is_empty() or not _views.has(pair[0]) or not _views.has(pair[1]):
        _idle = 0.0   # nothing to hint; check again after another delay
        return
    hint_pair = pair
    _hint_tween = create_tween().set_loops()
    _hint_tween.set_parallel(true)
    for pos in pair:
        var v: ItemView = _views[pos]
        var rest := _cell_center(pos)
        _hint_tween.tween_property(v, "position:y", rest.y - HINT_HOP, 0.15) \
                .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        _hint_tween.tween_property(v, "position:y", rest.y, 0.35).set_delay(0.15) \
                .set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
    _hint_tween.chain().tween_interval(HINT_INTERVAL - 0.5)

func _stop_hint() -> void:
    if _hint_tween != null:
        _hint_tween.kill()
        _hint_tween = null
    for pos in hint_pair:
        if _views.has(pos) and _views[pos] != _dragging:
            _views[pos].position = _cell_center(pos)
    hint_pair = []

func _unhandled_input(event: InputEvent) -> void:
    if not input_enabled: return
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        var pos := _pos_at(to_local(event.position))
        if event.pressed:
            _begin_drag(pos)
        else:
            _end_drag(pos)
    elif event is InputEventMouseMotion and _dragging != null:
        _dragging.position = to_local(event.position)

func _begin_drag(pos: Vector2i) -> void:
    if pos == Vector2i(-1, -1) or board.item_at(pos) == null:
        return
    _drag_from = pos
    _dragging = _views.get(pos)
    if _dragging != null:
        _dragging.z_index = 10

func _end_drag(pos: Vector2i) -> void:
    if _dragging == null:
        return
    _dragging.z_index = 0
    var from := _drag_from
    _dragging = null
    _drag_from = Vector2i(-1, -1)
    var now := Time.get_unix_time_from_system()
    if pos == from:
        var item := board.item_at(from)
        var open := item != null and board.state_at(from) == MergeBoard.CellState.OPEN
        # The first tap only selects an item; tapping the already-selected item
        # (or double-tapping) activates it: consume, open chest, or generate.
        var tappable: bool = open and (item.gen != null or item.chest != null \
                or ConfigDB.items.get(item.type, {}).has("CollectRewards"))
        if tappable and selected == from:
            var res: Dictionary = tap_fn.call(from, now)
            if not res["ok"] and res["reason"] != "" and res["reason"] != "not_tappable":
                action_rejected.emit(res["reason"])
            # Generators stay selected so repeat taps keep producing.
            if item.gen == null:
                _select(Vector2i(-1, -1))
        elif open:
            _select(from)
        _snap_back(from)
        return
    if pos == Vector2i(-1, -1):
        _snap_back(from)
        return
    var merge_err := String(merge_fn.call(from, pos, now))
    var err := merge_err
    if merge_err == "mismatch" or merge_err == "chain_top" or merge_err == "empty":
        err = board.move(from, pos)
        if err == "occupied":
            # The drop landed on an item, so the merge reason is the useful one.
            err = merge_err
    if err != "":
        action_rejected.emit(err)
        _snap_back(from)

func _snap_back(pos: Vector2i) -> void:
    var v: ItemView = _views.get(pos)
    if v != null:
        v.position = _cell_center(pos)
