class_name StoragePanel
extends CanvasLayer
## Modal storage overlay: shows every stored item and empty slot. Tapping an
## item puts it back on the board; the unlock button buys another slot.

signal action_rejected(reason: String)
signal storage_changed

const COLUMNS := 5
const SLOT_SIZE := Vector2(120, 120)

var game: Game
var _root: PanelContainer
var _title := Label.new()
var _grid := GridContainer.new()
var _unlock_btn := Button.new()

func setup(g: Game) -> void:
    game = g
    layer = 10
    visible = false
    _root = PanelContainer.new()
    _root.anchor_right = 1.0
    _root.anchor_bottom = 1.0
    add_child(_root)
    var col := VBoxContainer.new()
    col.add_theme_constant_override("separation", 12)
    _root.add_child(col)
    var header := HBoxContainer.new()
    _title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _title.add_theme_font_size_override("font_size", 28)
    header.add_child(_title)
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.pressed.connect(close)
    header.add_child(close_b)
    col.add_child(header)
    var hint := Label.new()
    hint.text = "Tap an item to put it back on the board."
    col.add_child(hint)
    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    col.add_child(scroll)
    _grid.columns = COLUMNS
    _grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_grid)
    _unlock_btn.custom_minimum_size = Vector2(0, 64)
    _unlock_btn.pressed.connect(_on_unlock)
    col.add_child(_unlock_btn)
    game.wallet.changed.connect(refresh)

func open() -> void:
    visible = true
    refresh()

func close() -> void:
    visible = false

func _do(res: Dictionary) -> void:
    if not res["ok"]:
        action_rejected.emit(res["reason"])
    else:
        storage_changed.emit()
    refresh()

func _on_unlock() -> void:
    _do(game.unlock_storage_slot())

func _on_withdraw(i: int) -> void:
    _do(game.withdraw_stored(i))

func refresh() -> void:
    if not visible:
        return
    var p := game.player
    _title.text = "Storage  %d/%d" % [p.inventory.size(), p.slots]
    for c in _grid.get_children():
        _grid.remove_child(c)
        c.queue_free()
    for i in range(p.slots):
        var b := Button.new()
        b.custom_minimum_size = SLOT_SIZE
        b.expand_icon = true
        b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
        if i < p.inventory.size():
            var t := p.inventory[i]
            b.icon = ItemView.art_for(t)
            if b.icon == null:
                b.text = t   # no art yet: show the id
            b.tooltip_text = t
            b.pressed.connect(_on_withdraw.bind(i))
        else:
            b.disabled = true
        _grid.add_child(b)
    var cost := p.next_slot_cost()
    if cost < 0:
        _unlock_btn.text = "All slots unlocked"
        _unlock_btn.disabled = true
    else:
        _unlock_btn.text = "Unlock slot - %d gems  (you have %d)" % [cost, game.wallet.gems]
        _unlock_btn.disabled = game.wallet.gems < cost
