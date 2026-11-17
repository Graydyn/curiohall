class_name InventoryPanel
extends VBoxContainer

signal action_rejected(reason: String)

var game: Game
var board_view: BoardView
var _reward_btn := Button.new()
var _row := HBoxContainer.new()
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
    # Hint and inventory actions share one line to leave room for the stack.
    var header := HBoxContainer.new()
    _hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(_hint)
    var unlock := Button.new()
    unlock.text = "Unlock slot"
    unlock.pressed.connect(_on_unlock)
    header.add_child(unlock)
    var store_btn := Button.new()
    store_btn.text = "Store selected"
    store_btn.pressed.connect(_on_store_selected)
    header.add_child(store_btn)
    add_child(header)
    add_child(_row)
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
        # Show the id when the item has no art yet, like the inventory buttons do.
        var label := "" if _reward_btn.icon != null else next + "  "
        _reward_btn.text = "%sRewards (%d) - tap to place" % [label, n]

func _on_unlock() -> void:
    game.player.unlock_slot(game.wallet)
    refresh()

func _on_store_selected() -> void:
    var pos := board_view.selected
    if pos == Vector2i(-1, -1):
        return
    var item := game.board.item_at(pos)
    if item == null or item.gen != null or game.board.state_at(pos) != MergeBoard.CellState.OPEN:
        return
    var t := item.type
    if game.player.store(t):
        game.board.remove(pos)
    refresh()

func refresh() -> void:
    _refresh_reward_button()
    _hint.text = "Inventory %d/%d (next slot: %s gems)" % [
        game.player.inventory.size(), game.player.slots,
        str(game.player.next_slot_cost()) if game.player.next_slot_cost() >= 0 else "max"]
    for c in _row.get_children():
        c.queue_free()
    for i in range(game.player.inventory.size()):
        var btn := Button.new()
        btn.text = game.player.inventory[i]
        btn.pressed.connect(func():
            var t := game.player.withdraw(i)
            if t != "" and game.board.spawn(t, Vector2i(3, 4)) == Vector2i(-1, -1):
                game.player.store(t)   # board full: put it back
            refresh())
        _row.add_child(btn)
