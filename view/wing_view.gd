class_name WingView
extends Control
## Interior of one wing: a vertically scrolling subroom scene with its Hall
## elements, subroom tabs, an Arrange toggle, the task card and look picker.

signal back_requested
signal picks_done
signal toast(reason: String)

const TAP_SLOP := 12.0

var game: Game
var area := 0
var subroom := 0
var task_card: TaskCard
var picker: LookPicker
var arrange_toggle: Button

var _clip: Control
var _scene: Control
var _tabs: HBoxContainer
var _sprites: Dictionary = {}   # element id -> ElementSprite
var _scroll := 0.0
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragged := false

func setup(g: Game, a: int, focus_element: String = "") -> void:
    game = g
    area = a
    subroom = 0
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    for c in get_children():
        remove_child(c)
        c.free()
    _sprites.clear()
    task_card = null
    picker = null
    _clip = Control.new()
    _clip.name = "Clip"
    _clip.clip_contents = true
    _clip.set_anchors_preset(Control.PRESET_FULL_RECT)
    _clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(_clip)
    _build_chrome()
    if focus_element != "" and ConfigDB.hall_elements.has(focus_element):
        subroom = int(ConfigDB.hall_elements[focus_element]["subroom"])
    _build_scene()
    if focus_element != "" and _sprites.has(focus_element):
        var s: ElementSprite = _sprites[focus_element]
        _scroll = s.position.y + s.size.y * 0.5 - size.y * 0.5
        _apply_scroll()
    _open_next_pending()

func _subrooms() -> Array:
    return ConfigDB.hall_wings.get(area, {}).get("subrooms", [])

func _build_chrome() -> void:
    arrange_toggle = Button.new()
    arrange_toggle.name = "ArrangeToggle"
    arrange_toggle.text = "Arrange"
    arrange_toggle.toggle_mode = true
    arrange_toggle.offset_left = 540.0
    arrange_toggle.offset_right = 710.0
    arrange_toggle.offset_top = 64.0
    arrange_toggle.offset_bottom = 152.0
    add_child(arrange_toggle)
    var rooms := _subrooms()
    _tabs = HBoxContainer.new()
    _tabs.name = "Tabs"
    _tabs.offset_left = 10.0
    _tabs.offset_right = 710.0
    _tabs.offset_top = 160.0
    _tabs.offset_bottom = 248.0
    _tabs.add_theme_constant_override("separation", 8)
    _tabs.visible = rooms.size() > 1
    add_child(_tabs)
    for i in rooms.size():
        var b := Button.new()
        b.name = "Tab%d" % i
        b.text = String(rooms[i]["name"])
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        b.custom_minimum_size = Vector2(0, 88)
        b.pressed.connect(show_subroom.bind(i))
        _tabs.add_child(b)

func has_tabs() -> bool:
    return _tabs.visible

func show_subroom(i: int) -> void:
    if i == subroom or i < 0 or i >= _subrooms().size():
        return
    subroom = i
    _scroll = 0.0
    _build_scene()

func _build_scene() -> void:
    if _scene != null:
        _clip.remove_child(_scene)
        _scene.free()
    _sprites.clear()
    var rooms := _subrooms()
    var sz := Vector2(720, 1280)
    if subroom < rooms.size():
        var arr: Array = rooms[subroom]["size"]
        sz = Vector2(float(arr[0]), float(arr[1]))
    _scene = Control.new()
    _scene.name = "Scene"
    _scene.size = sz
    _scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _clip.add_child(_scene)
    var tex := HallArt.wing_scene(area, subroom)
    if tex != null:
        var tr := TextureRect.new()
        tr.texture = tex
        tr.size = sz
        tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tr.stretch_mode = TextureRect.STRETCH_SCALE
        tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _scene.add_child(tr)
    else:
        var bg := Panel.new()
        bg.size = sz
        bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
        var sb := StyleBoxFlat.new()
        sb.bg_color = CurioTheme.TEAL.darkened(0.3)
        bg.add_theme_stylebox_override("panel", sb)
        _scene.add_child(bg)
    for row in HallElements.in_area(area):
        if int(row["subroom"]) != subroom:
            continue
        var s := ElementSprite.new()
        s.name = "El_" + String(row["id"])
        _scene.add_child(s)
        s.setup(row, game)
        s.tapped.connect(tap_element)
        _sprites[String(row["id"])] = s
    _apply_scroll()

func sprite_count() -> int:
    return _sprites.size()

func sprite(id: String) -> ElementSprite:
    return _sprites.get(id)

func refresh_sprites() -> void:
    for id in _sprites:
        (_sprites[id] as ElementSprite).refresh()

func _max_scroll() -> float:
    return maxf(0.0, _scene.size.y - size.y)

func _apply_scroll() -> void:
    if _scene == null:
        return
    _scroll = clampf(_scroll, 0.0, _max_scroll())
    _scene.position = Vector2(0.0, -_scroll)

## Test hook and tap handler for one element.
func tap_element(id: String) -> void:
    if task_card != null or picker != null or not _sprites.has(id):
        return
    var c := game.campaign
    if arrange_toggle.button_pressed and HallElements.stage(id, c) == HallElements.Stage.DONE:
        _open_picker(id, true)
    elif HallElements.is_workable(id, c):
        _open_card(id)
    elif HallElements.stage(id, c) != HallElements.Stage.DONE:
        var key := HallElements.next_task(id, c)
        if key != "" and int(key.get_slice("_", 0)) > c.day:
            toast.emit("not_today")

func _open_card(id: String) -> void:
    task_card = TaskCard.new()
    task_card.name = "TaskCard"
    add_child(task_card)
    task_card.setup(game, id, HallElements.next_task(id, game.campaign))
    task_card.complete_pressed.connect(_on_complete)
    task_card.closed.connect(_close_card)

func _close_card() -> void:
    if task_card != null:
        task_card.hide()
        task_card.queue_free()
        task_card = null

func _on_complete(key: String) -> void:
    var res: Dictionary = game.complete_task(int(key.get_slice("_", 1)), Time.get_unix_time_from_system())
    _close_card()
    if not res["ok"]:
        toast.emit(String(res["reason"]))
        return
    refresh_sprites()
    _open_next_pending()

func _open_next_pending() -> void:
    if picker != null:
        return
    var pending := game.hall.pending_in_area(area)
    if not pending.is_empty():
        _open_picker(String(pending[0]), false)

func _open_picker(id: String, closable: bool) -> void:
    picker = LookPicker.new()
    picker.name = "LookPicker"
    add_child(picker)
    picker.setup(game, id, closable)
    picker.picked.connect(_on_picked)
    picker.closed.connect(_close_picker)

func _on_picked(_id: String, _look: int) -> void:
    _close_picker()

func _close_picker() -> void:
    if picker != null:
        picker.hide()
        picker.queue_free()
        picker = null
    refresh_sprites()
    _open_next_pending()
    if picker == null and game.hall.pending_in_area(area).is_empty():
        picks_done.emit()

func _sprite_at(pos: Vector2) -> ElementSprite:
    var local := pos - _scene.position
    for id in _sprites:
        var s: ElementSprite = _sprites[id]
        if s.hit_rect().has_point(local):
            return s
    return null

func _finish_tap(pos: Vector2) -> void:
    if task_card != null or picker != null:
        return
    var s := _sprite_at(pos)
    if s != null:
        s.tap()

func _gui_input(event: InputEvent) -> void:
    if _scene == null:
        return
    if event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.device == InputEvent.DEVICE_ID_EMULATION:
            return
        if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
            _scroll -= 80.0
            _apply_scroll()
        elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
            _scroll += 80.0
            _apply_scroll()
        elif mb.button_index == MOUSE_BUTTON_LEFT:
            if mb.pressed:
                _pressing = true
                _dragged = false
                _press_pos = mb.position
            else:
                if _pressing and not _dragged:
                    _finish_tap(mb.position)
                _pressing = false
    elif event is InputEventMouseMotion:
        var mm := event as InputEventMouseMotion
        if mm.device == InputEvent.DEVICE_ID_EMULATION:
            return
        if _pressing and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
            if _dragged or mm.position.distance_to(_press_pos) > TAP_SLOP:
                _dragged = true
                _scroll -= mm.relative.y
                _apply_scroll()
    elif event is InputEventScreenTouch:
        var st := event as InputEventScreenTouch
        if st.pressed:
            _pressing = true
            _dragged = false
            _press_pos = st.position
        else:
            if _pressing and not _dragged:
                _finish_tap(st.position)
            _pressing = false
    elif event is InputEventScreenDrag:
        var sd := event as InputEventScreenDrag
        if _pressing and (_dragged or sd.position.distance_to(_press_pos) > TAP_SLOP):
            _dragged = true
            _scroll -= sd.relative.y
            _apply_scroll()
