class_name InventoryPanel
extends VBoxContainer

signal action_rejected(reason: String)
signal storage_requested
signal info_requested

var game: Game
var board_view: BoardView
var _reward_btn := Button.new()
var _storage_btn := Button.new()
var _info_btn := Button.new()
var _hint := Label.new()

func setup(g: Game, bv: BoardView) -> void:
    game = g
    board_view = bv
    # Reward stack: item rewards wait here until the player taps to place one.
    _reward_btn.expand_icon = true
    _reward_btn.custom_minimum_size = Vector2(0, 48)
    _reward_btn.add_theme_constant_override("icon_max_width", 40)
    _reward_btn.pressed.connect(_on_place_reward)
    add_child(_reward_btn)
    game.player.rewards_changed.connect(refresh)
    # Store the selected item, or open the storage modal to take items out.
    var header := HBoxContainer.new()
    _hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _hint.text = "Select an item to store it"
    header.add_child(_hint)
    var store_btn := Button.new()
    store_btn.text = "Store selected"
    store_btn.pressed.connect(_on_store_selected)
    header.add_child(store_btn)
    # "?" opens the info panel for the selected item.
    _info_btn.text = "?"
    _info_btn.custom_minimum_size = Vector2(48, 0)
    _info_btn.pressed.connect(func(): info_requested.emit())
    header.add_child(_info_btn)
    board_view.selection_changed.connect(func(_pos): refresh())
    _storage_btn.pressed.connect(func(): storage_requested.emit())
    header.add_child(_storage_btn)
    add_child(header)
    refresh()

func _on_place_reward() -> void:
    var res := game.place_reward()
    if not res["ok"] and res["reason"] != "no_reward":
        action_rejected.emit(res["reason"])

func _refresh_reward_button() -> void:
    var n := game.player.reward_stack.size()
    var next := game.player.peek_reward()
    _reward_btn.disabled = n == 0
    _reward_btn.icon = ItemView.art_for(next) if next != "" else null
    if n == 0:
        _reward_btn.text = "No rewards waiting"
    else:
        # Show the id when the item has no art yet.
        var label := "" if _reward_btn.icon != null else next + "  "
        _reward_btn.text = "%sRewards (%d) - tap to place" % [label, n]

func _on_store_selected() -> void:
    var pos := board_view.selected
    if pos == Vector2i(-1, -1):
        return
    var item := game.board.item_at(pos)
    if item == null or item.gen != null or game.board.state_at(pos) != MergeBoard.CellState.OPEN:
        return
    if game.player.store(item.type):
        game.board.remove(pos)
    else:
        action_rejected.emit("storage_full")
    refresh()

func refresh() -> void:
    _refresh_reward_button()
    _storage_btn.text = "Storage %d/%d" % [game.player.inventory.size(), game.player.slots]
    _info_btn.disabled = board_view.selected == Vector2i(-1, -1)
