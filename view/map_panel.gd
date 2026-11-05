class_name MapPanel
extends CanvasLayer
## Pannable floor-plan map of the Hall: wing states, the current day's task
## pins, and a task card for paying coins. Placeholder styling.

signal action_rejected(reason: String)
signal chronicle_requested

const WING_COLORS := {
    Campaign.AreaState.LOCKED: Color(0.13, 0.15, 0.18),
    Campaign.AreaState.ACTIVE: Color(0.16, 0.32, 0.34),    # deep teal
    Campaign.AreaState.RESTORED: Color(0.42, 0.30, 0.14),  # warm brass
}

var game: Game
var _root: PanelContainer
var _scroll: ScrollContainer
var _canvas: Control
var _header: Label
var _card: PanelContainer
var _selected_task := -1

func setup(g: Game) -> void:
    game = g
    layer = 10
    visible = false
    _root = PanelContainer.new()
    _root.anchor_right = 1.0
    _root.anchor_bottom = 1.0
    add_child(_root)
    var vbox := VBoxContainer.new()
    _root.add_child(vbox)
    var top := HBoxContainer.new()
    vbox.add_child(top)
    _header = Label.new()
    _header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(_header)
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.pressed.connect(close)
    top.add_child(close_b)
    var chron_b := Button.new()
    chron_b.text = "Chronicle"
    chron_b.pressed.connect(func() -> void: chronicle_requested.emit())
    top.add_child(chron_b)
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(_scroll)
    _canvas = Control.new()
    _canvas.custom_minimum_size = HallLayout.canvas_size()
    _scroll.add_child(_canvas)
    _card = PanelContainer.new()   # task card overlay, above the scroll
    _card.anchor_left = 0.08
    _card.anchor_right = 0.92
    _card.anchor_top = 0.35
    _card.anchor_bottom = 0.62
    _card.visible = false
    add_child(_card)
    game.campaign.task_completed.connect(func(_d: int, _i: int) -> void: refresh())
    game.campaign.day_advanced.connect(func(_d: int) -> void: refresh())
    game.wallet.changed.connect(refresh)

func open() -> void:
    visible = true
    _selected_task = -1
    refresh()
    call_deferred("_scroll_to_active")

func close() -> void:
    visible = false

func refresh() -> void:
    if not visible:
        return
    _header.text = "CURIO HALL   Day %d   Coins: %d" % [game.campaign.day, game.wallet.coins]
    for c in _canvas.get_children():
        c.queue_free()
    for wing in HallLayout.wings():
        _draw_wing(wing)
    _refresh_card()

func _draw_wing(wing: Dictionary) -> void:
    var rect: Rect2 = wing["rect"]
    var area := int(wing["area"])
    var state := game.campaign.area_state(area, game.player)
    var bg := ColorRect.new()
    bg.color = WING_COLORS[state]
    bg.position = rect.position
    bg.size = rect.size
    _canvas.add_child(bg)
    var name_l := Label.new()
    var suffix := ""
    match state:
        Campaign.AreaState.LOCKED:
            suffix = "  (locked)"
        Campaign.AreaState.ACTIVE:
            var prog := game.campaign.wing_progress(area)
            suffix = "  %d/%d" % [prog.x, prog.y]
        Campaign.AreaState.RESTORED:
            suffix = "  * restored"
    name_l.text = String(wing["name"]) + suffix
    name_l.position = rect.position + Vector2(10.0, 6.0)
    _canvas.add_child(name_l)
    if area == game.campaign.current_area():
        _draw_pins(rect)

func _draw_pins(rect: Rect2) -> void:
    var rows: Array = game.campaign.tasks_today()
    for i in range(rows.size()):
        var row: Dictionary = rows[i]
        var id := int(row["id"])
        var is_done := game.campaign.is_task_done(game.campaign.day, id)
        var b := Button.new()
        b.text = "OK" if is_done else "%dc" % int(row["cost"])
        b.disabled = is_done
        b.position = rect.position + Vector2(10.0 + (i % 6) * 63.0, 40.0 + int(i / 6.0) * 46.0)
        b.size = Vector2(58.0, 40.0)
        b.pressed.connect(_select_task.bind(id))
        _canvas.add_child(b)

func _select_task(id: int) -> void:
    _selected_task = id
    _refresh_card()

func _dismiss_card() -> void:
    _selected_task = -1
    _refresh_card()

func _refresh_card() -> void:
    for c in _card.get_children():
        c.queue_free()
    if _selected_task < 0:
        _card.visible = false
        return
    var key := Campaign.task_key(game.campaign.day, _selected_task)
    var row: Dictionary = ConfigDB.main_task_by_key.get(key, {})
    if row.is_empty() or game.campaign.is_task_done(game.campaign.day, _selected_task):
        _card.visible = false
        _selected_task = -1
        return
    _card.visible = true
    var v := VBoxContainer.new()
    _card.add_child(v)
    v.add_child(_mk_label(_wing_name(int(row["area"]))))
    var icon := String(row.get("detail_icon", "")).to_lower()
    v.add_child(_mk_label("Requested by: " + Cast.display_name(icon)))
    var cost := int(row["cost"])
    v.add_child(_mk_label("Cost: %d coins   (you have %d)" % [cost, game.wallet.coins]))
    var complete_b := Button.new()
    complete_b.text = "Complete"
    complete_b.disabled = game.wallet.coins < cost
    complete_b.pressed.connect(_complete_selected)
    v.add_child(complete_b)
    var back_b := Button.new()
    back_b.text = "Back"
    back_b.pressed.connect(_dismiss_card)
    v.add_child(back_b)

func _complete_selected() -> void:
    var res: Dictionary = game.complete_task(_selected_task, Time.get_unix_time_from_system())
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    else:
        _selected_task = -1
    refresh()

func _mk_label(text: String) -> Label:
    var l := Label.new()
    l.text = text
    return l

func _wing_name(area: int) -> String:
    for wing in HallLayout.wings():
        if int(wing["area"]) == area:
            return String(wing["name"])
    return "Wing %d" % area

func _scroll_to_active() -> void:
    var cur := game.campaign.current_area()
    for wing in HallLayout.wings():
        if int(wing["area"]) == cur:
            var rect: Rect2 = wing["rect"]
            _scroll.scroll_vertical = int(maxf(0.0, rect.position.y - 200.0))
            _scroll.scroll_horizontal = int(maxf(0.0, rect.position.x - 100.0))
            return
