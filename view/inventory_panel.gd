class_name InventoryPanel
extends VBoxContainer

var game: Game
var board_view: BoardView
var _row := HBoxContainer.new()
var _hint := Label.new()

func setup(g: Game, bv: BoardView) -> void:
    game = g
    board_view = bv
    add_child(_hint)
    add_child(_row)
    var unlock := Button.new()
    unlock.text = "Unlock slot"
    unlock.pressed.connect(_on_unlock)
    add_child(unlock)
    var store_btn := Button.new()
    store_btn.text = "Store selected"
    store_btn.pressed.connect(_on_store_selected)
    add_child(store_btn)
    refresh()

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
