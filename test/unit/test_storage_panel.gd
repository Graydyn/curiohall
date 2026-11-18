extends GutTest
## Storage modal: take stored items back out and unlock slots.

func _panel(g: Game) -> StoragePanel:
    var p := StoragePanel.new()
    add_child_autofree(p)
    p.setup(g)
    p.open()
    return p

func _free_centre(g: Game) -> void:
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)

func test_withdraw_stored_places_item_on_board() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_centre(g)
    g.player.store("201")
    var res := g.withdraw_stored(0)
    assert_true(res["ok"])
    assert_eq(g.board.item_at(Vector2i(3, 4)).type, "201")
    assert_eq(g.player.inventory.size(), 0)

func test_withdraw_stored_board_full_keeps_item() -> void:
    var g := Game.fresh(1000.0, 42)   # board full
    g.player.store("201")
    var res := g.withdraw_stored(0)
    assert_eq(res["reason"], "board_full")
    assert_eq(g.player.inventory, ["201"] as Array[String])

func test_unlock_storage_slot_reasons() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.gems = 0
    assert_eq(g.unlock_storage_slot()["reason"], "not_enough_gems")
    g.wallet.gems = 1000000
    var before := g.player.slots
    assert_true(g.unlock_storage_slot()["ok"])
    assert_eq(g.player.slots, before + 1)
    g.player.slots = int(ConfigDB.inventory_cfg["MaxNumber"])
    assert_eq(g.unlock_storage_slot()["reason"], "storage_maxed")

func test_panel_shows_one_button_per_slot() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.store("201")
    var p := _panel(g)
    assert_eq(p._grid.get_child_count(), g.player.slots)
    assert_false(p._grid.get_child(0).disabled)
    assert_true(p._grid.get_child(1).disabled)
    assert_string_contains(p._title.text, "1/%d" % g.player.slots)

func test_panel_tap_withdraws_and_rejects_when_full() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.store("201")
    var p := _panel(g)
    watch_signals(p)
    p._grid.get_child(0).pressed.emit()
    assert_signal_emitted_with_parameters(p, "action_rejected", ["board_full"])
    _free_centre(g)
    p._grid.get_child(0).pressed.emit()
    assert_eq(g.board.item_at(Vector2i(3, 4)).type, "201")
    assert_signal_emitted(p, "storage_changed")
    assert_eq(g.player.inventory.size(), 0)

func test_panel_unlock_button() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.gems = 1000000
    var p := _panel(g)
    var before := g.player.slots
    p._unlock_btn.pressed.emit()
    assert_eq(g.player.slots, before + 1)
    assert_eq(p._grid.get_child_count(), before + 1)
