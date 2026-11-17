class_name TaskCard
extends Control
## Modal card for an element's next task: element, step, who asks, reward,
## what it costs, Complete. No portrait: the asker is a name line only.

signal complete_pressed(key: String)
signal closed

var key := ""
var _asker_name := ""

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
    panel.position = Vector2(40, 350)
    panel.size = Vector2(640, 580)
    add_child(panel)
    var box := VBoxContainer.new()
    box.add_theme_constant_override("separation", 14)
    panel.add_child(box)
    var title := Label.new()
    title.name = "ElementName"
    title.text = String(ConfigDB.hall_elements[element_id]["name"])
    title.theme_type_variation = "CardLabel"
    title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    title.add_theme_font_size_override("font_size", 34)
    box.add_child(title)
    var p := HallElements.progress(element_id, g.campaign)
    var step := _card_label("Step %d of %d" % [mini(p.x + 1, p.y), p.y], 24)
    step.name = "Step"
    box.add_child(step)
    _asker_name = Cast.asker_name(icon)
    var asker := _card_label(("Requested by " + _asker_name) if Cast.is_cast(icon) else _asker_name, 22)
    asker.name = "Asker"
    box.add_child(asker)
    box.add_child(_reward_row(row.get("rewards", [])))
    var cost_l := Label.new()
    cost_l.name = "Cost"
    cost_l.text = "Cost %d   (you have %d)" % [cost, g.wallet.coins]
    cost_l.theme_type_variation = "CardLabel"
    cost_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    cost_l.add_theme_font_size_override("font_size", 26)
    box.add_child(cost_l)
    var done_b := Button.new()
    done_b.name = "Complete"
    done_b.text = "Complete"
    done_b.custom_minimum_size = Vector2(0, 80)
    done_b.disabled = g.wallet.coins < cost
    done_b.pressed.connect(func() -> void: complete_pressed.emit(key))
    box.add_child(done_b)
    var back_b := Button.new()
    back_b.name = "CardBack"
    back_b.text = "Back"
    back_b.custom_minimum_size = Vector2(0, 80)
    back_b.pressed.connect(close)
    box.add_child(back_b)

func _card_label(text: String, font_size: int) -> Label:
    var l := Label.new()
    l.text = text
    l.theme_type_variation = "CardLabel"
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.add_theme_font_size_override("font_size", font_size)
    return l

## "Reward: 15 XP" plus an icon per item reward (items have art, not names).
func _reward_row(tokens: Array) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.name = "Reward"
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.add_theme_constant_override("separation", 8)
    var parts: PackedStringArray = []
    var items: Array = []
    for t in tokens:
        var r := Rewards.parse(String(t))
        match r["kind"]:
            "xp":
                parts.append("%d XP" % r["amount"])
            "coins", "gems", "energy":
                parts.append("%d %s" % [r["amount"], r["kind"]])
            _:
                items.append(r)
    var text := "Reward: " + ", ".join(parts)
    if items.size() > 0 and parts.size() > 0:
        text += " +"
    row.add_child(_card_label(text, 24))
    for r in items:
        var tex := ItemView.art_for(String(r["id"]))
        if tex == null:
            row.add_child(_card_label("an item", 24))
            continue
        var tr := TextureRect.new()
        tr.texture = tex
        tr.custom_minimum_size = Vector2(44, 44)
        tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
        row.add_child(tr)
        if int(r["amount"]) > 1:
            row.add_child(_card_label("x%d" % r["amount"], 24))
    return row

func asker_text() -> String:
    return _asker_name

func close() -> void:
    closed.emit()
