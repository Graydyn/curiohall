class_name Workroom
extends Control
## The merge board, order bar and inventory: the Curator's workroom. A screen
## the home screen swaps in; it has no navigation of its own beyond Esc.

signal back_requested
## Storage or a sale changed state that no Game signal reports.
signal save_requested

var game: Game
var board_view: BoardView
var order_bar: OrderBar
var inventory: InventoryPanel
var storage_panel: StoragePanel
var info_panel: InfoPanel

func setup(g: Game, toast: Callable) -> void:
    game = g
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    board_view = BoardView.new()
    board_view.name = "BoardView"
    add_child(board_view)
    board_view.setup(game)
    board_view.position = Vector2((720 - MergeBoard.WIDTH * BoardView.CELL) / 2.0, 260)

    order_bar = OrderBar.new()
    order_bar.name = "OrderBar"
    _place(order_bar, 10.0, 120.0, 710.0, 240.0)
    add_child(order_bar)
    order_bar.setup(game)

    inventory = InventoryPanel.new()
    inventory.name = "InventoryPanel"
    _place(inventory, 10.0, 1140.0, 710.0, 1270.0)
    add_child(inventory)
    inventory.setup(game, board_view)

    board_view.action_rejected.connect(toast)
    order_bar.action_rejected.connect(toast)
    inventory.action_rejected.connect(toast)

    storage_panel = StoragePanel.new()
    add_child(storage_panel)
    storage_panel.setup(game)
    storage_panel.action_rejected.connect(toast)
    storage_panel.storage_changed.connect(inventory.refresh)
    storage_panel.storage_changed.connect(func(): save_requested.emit())
    storage_panel.visibility_changed.connect(inventory.refresh)
    inventory.storage_requested.connect(storage_panel.open)

    info_panel = InfoPanel.new()
    add_child(info_panel)
    info_panel.setup(game)
    info_panel.action_rejected.connect(toast)
    info_panel.sold.connect(func():
        board_view.clear_selection()
        save_requested.emit())
    inventory.info_requested.connect(func(): info_panel.open(board_view.selected))

func _place(c: Control, l: float, t: float, r: float, b: float) -> void:
    c.offset_left = l
    c.offset_top = t
    c.offset_right = r
    c.offset_bottom = b

func _unhandled_key_input(event: InputEvent) -> void:
    if visible and event.is_action_pressed("ui_cancel"):
        back_requested.emit()
        get_viewport().set_input_as_handled()
