class_name EventPanel
extends CanvasLayer
## The Society Presents: the live event's board, countdown, progress, and
## clearly-labeled DEV lifecycle controls. Placeholder styling.

signal action_rejected(reason: String)
signal visibility_changed_to(open: bool)

const BOARD_SCALE := 0.55

var game: Game
var _header: Label
var _board_holder: Node2D
var _board_view: BoardView = null

func setup(g: Game) -> void:
    game = g
    layer = 12
    visible = false
    var bg := ColorRect.new()
    bg.color = Color(0.07, 0.09, 0.11, 0.97)
    bg.anchor_right = 1.0
    bg.anchor_bottom = 1.0
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let drags reach the board
    add_child(bg)
    _header = Label.new()
    _header.position = Vector2(10, 8)
    add_child(_header)
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.position = Vector2(600, 8)
    close_b.pressed.connect(close)
    add_child(close_b)
    var dev_start := Button.new()
    dev_start.text = "DEV: Start event"
    dev_start.position = Vector2(10, 40)
    dev_start.pressed.connect(_dev_start)
    add_child(dev_start)
    var dev_end := Button.new()
    dev_end.text = "DEV: End event"
    dev_end.position = Vector2(160, 40)
    dev_end.pressed.connect(_dev_end)
    add_child(dev_end)
    _board_holder = Node2D.new()
    _board_holder.position = Vector2(80, 90)
    _board_holder.scale = Vector2(BOARD_SCALE, BOARD_SCALE)
    add_child(_board_holder)
    game.events.event_changed.connect(_on_event_changed)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_refresh_header)
    add_child(t)

func open() -> void:
    visible = true
    _rebuild_board_view()
    _refresh_header()
    visibility_changed_to.emit(true)

func close() -> void:
    visible = false
    if _board_view != null:
        _board_view.input_enabled = false
        _board_view.queue_free()
        _board_view = null
    visibility_changed_to.emit(false)

func _dev_start() -> void:
    if not game.dev_start_event(Time.get_unix_time_from_system()):
        action_rejected.emit("event_already_active")

func _dev_end() -> void:
    game.dev_end_event(Time.get_unix_time_from_system())

func _on_event_changed() -> void:
    if visible:
        _rebuild_board_view()
        _refresh_header()

func _rebuild_board_view() -> void:
    if _board_view != null:
        _board_view.input_enabled = false
        _board_view.queue_free()
        _board_view = null
    if not game.events.is_active():
        return
    _board_view = BoardView.new()
    _board_holder.add_child(_board_view)
    _board_view.setup(game, game.events.board, game.merge_event, _event_tap)
    _board_view.action_rejected.connect(func(reason: String) -> void: action_rejected.emit(reason))

func _event_tap(_pos: Vector2i, _now: float) -> Dictionary:
    return {"ok": false, "kind": "none", "reason": ""}

func _refresh_header() -> void:
    if not visible:
        return
    if not game.events.is_active():
        _header.text = "No expedition underway   (next departs when the clock allows)"
        return
    var now := Time.get_unix_time_from_system()
    var left := maxf(0.0, game.events.ends_at - now)
    var chain_len := _chain_length()
    var progress := "Best find: tier %d / %d%s" % [game.events.best_tier, chain_len,
            "   EXPEDITION COMPLETE!" if game.events.completed else ""]
    _header.text = "The Society Presents: %s\nends in %dh %dm   %s" % [
            game.events.variant, int(left / 3600.0), int(fmod(left, 3600.0) / 60.0), progress]

func _chain_length() -> int:
    var id := String(ConfigDB.tuning["event_feed_item"])
    var n := 1
    while ConfigDB.items.get(id, {}).has("MergedType"):
        id = String(ConfigDB.items[id]["MergedType"])
        n += 1
    return n
