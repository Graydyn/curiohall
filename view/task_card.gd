class_name TaskCard
extends Control
## Modal card for an element's next task: who asks, what it costs, Complete.

signal complete_pressed(key: String)
signal closed

var key := ""
var _asker: Label

func setup(g: Game, element_id: String, task_key: String) -> void:
    key = task_key
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP
    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.55)
    dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(dim)
    var row: Dictionary = ConfigDB.main_task_by_key.get(task_key, {})
    var cost := int(row.get("cost", 0))
    var icon := String(row.get("detail_icon", ""))
    var panel := PanelContainer.new()
    panel.theme_type_variation = "CardFrame"
    panel.position = Vector2(60, 400)
    panel.size = Vector2(600, 460)
    add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 14)
    panel.add_child(box)
    var title := Label.new()
    title.name = "ElementName"
    title.text = String(ConfigDB.hall_elements[element_id]["name"])
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    box.add_child(title)
    var who := HBoxContainer.new()
    who.alignment = BoxContainer.ALIGNMENT_CENTER
    who.add_theme_constant_override("separation", 14)
    box.add_child(who)
    var tex: Texture2D = null
    if Cast.is_cast(icon):
        tex = HallArt.portrait(icon, "neutral")
    else:
        tex = HallArt.ui("society_seal")
    if tex != null:
        var tr := TextureRect.new()
        tr.name = "Portrait"
        tr.texture = tex
        tr.custom_minimum_size = Vector2(120, 120)
        tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        who.add_child(tr)
    _asker = Label.new()
    _asker.name = "Asker"
    _asker.text = Cast.asker_name(icon)
    _asker.add_theme_font_size_override("font_size", 28)
    who.add_child(_asker)
    var cost_l := Label.new()
    cost_l.name = "Cost"
    cost_l.text = "Cost %d   (you have %d)" % [cost, g.wallet.coins]
    cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cost_l.add_theme_font_size_override("font_size", 26)
    box.add_child(cost_l)
    var done_b := Button.new()
    done_b.name = "Complete"
    done_b.text = "Complete"
    done_b.custom_minimum_size = Vector2(0, 96)
    done_b.disabled = g.wallet.coins < cost
    done_b.pressed.connect(func() -> void: complete_pressed.emit(key))
    box.add_child(done_b)
    var back_b := Button.new()
    back_b.name = "CardBack"
    back_b.text = "Back"
    back_b.custom_minimum_size = Vector2(0, 96)
    back_b.pressed.connect(close)
    box.add_child(back_b)

func asker_text() -> String:
    return _asker.text

func close() -> void:
    closed.emit()
