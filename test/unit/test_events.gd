extends GutTest
## Event lifecycle: auto-start when due + level 12 gate, 7-day duration,
## 2-day gap, dev controls bypass the gate, board is one row taller than
## the 13-row dogpark layout (open supply row at the bottom).

const NOW := 1000.0

func test_no_start_below_unlock_level() -> void:
    var g := Game.fresh(NOW, 42)
    g.tick_events(NOW)               # next_event_at 0 -> due, but level 1 < 12
    assert_false(g.events.is_active())

func test_auto_start_when_due_and_gated() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 12
    g.tick_events(NOW)
    assert_true(g.events.is_active())
    assert_eq(g.events.variant, "dogpark")
    assert_eq(g.events.ends_at, NOW + 604800.0)
    # board: 13 config rows + 1 open supply row
    assert_eq(g.events.board.height, 14)
    assert_eq(g.events.board.width, 7)
    assert_null(g.events.board.item_at(Vector2i(0, 13)))
    assert_eq(g.events.board.state_at(Vector2i(0, 13)), MergeBoard.CellState.OPEN)
    assert_eq(g.events.board.state_at(Vector2i(0, 0)), MergeBoard.CellState.BOXED)

func test_expiry_discards_board_and_schedules_next() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 12
    g.tick_events(NOW)
    g.tick_events(NOW + 604800.0)
    assert_false(g.events.is_active())
    assert_null(g.events.board)
    assert_eq(g.events.next_event_at, NOW + 604800.0 + 172800.0)
    g.tick_events(NOW + 604800.0 + 172800.0)   # next window opens
    assert_true(g.events.is_active())

func test_dev_controls_bypass_gate_and_timers() -> void:
    var g := Game.fresh(NOW, 42)          # level 1
    assert_true(g.dev_start_event(NOW))
    assert_true(g.events.is_active())
    assert_false(g.dev_start_event(NOW))  # idempotent while active
    g.dev_end_event(NOW + 5.0)
    assert_false(g.events.is_active())
    assert_eq(g.events.next_event_at, NOW + 5.0 + 172800.0)

func test_offline_expiry_reconciles_on_first_tick() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.events.is_active())
    g2.tick_events(NOW + 700000.0)        # loaded long after ends_at
    assert_false(g2.events.is_active())

func _walk_chain_from(id: String) -> Array:
    var out: Array = [id]
    while ConfigDB.items[out[-1]].has("MergedType"):
        out.append(String(ConfigDB.items[out[-1]]["MergedType"]))
    return out

func test_order_delivery_feeds_supply_row_only_while_active() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])          # IDLE: nothing fed
    g.dev_start_event(NOW)
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 0)
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 1)
    assert_eq(g.board.count_of("pb_dogpark_tar_1"), 0)  # main board untouched
    var fed_pos := Vector2i(-1, -1)
    for x in range(g.events.board.width):
        if g.events.board.item_at(Vector2i(x, g.events.board.height - 1)) != null:
            fed_pos = Vector2i(x, g.events.board.height - 1)
            break
    assert_ne(fed_pos, Vector2i(-1, -1))             # fed item lands on the supply row

func test_order_delivery_feeds_only_the_supply_row_never_mid_board() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 5
    g.dev_start_event(NOW)
    var b := g.events.board
    var row := b.height - 1
    # Fill every supply-row cell but the last with junk so a naive spread search
    # (radius expansion from (0, row)) would otherwise spill onto the row above.
    for x in range(b.width - 1):
        b.place(Vector2i(x, row), ItemInstance.make("pb_dogpark_tar_1"))
    # Snapshot every cell above the supply row before feeding.
    var before := {}
    for y in range(row):
        for x in range(b.width):
            var item := b.item_at(Vector2i(x, y))
            before[Vector2i(x, y)] = item.type if item != null else ""
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    var last := Vector2i(b.width - 1, row)
    assert_not_null(b.item_at(last))                 # fed into the last free supply cell
    # Nothing above the supply row changed - no spill from the feed.
    for y in range(row):
        for x in range(b.width):
            var item := b.item_at(Vector2i(x, y))
            var after_type := item.type if item != null else ""
            assert_eq(after_type, before[Vector2i(x, y)])

func test_merge_event_rejects_when_idle() -> void:
    var g := Game.fresh(NOW, 42)
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "no_event")

func test_merge_event_rejected_merge_does_not_mutate_state() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var b := g.events.board
    # Find a BOXED cell and place a matching free item on the supply row
    var boxed_pos := Vector2i(-1, -1)
    var boxed_type := ""
    for pos in b._items:
        if b.state_at(pos) == MergeBoard.CellState.BOXED:
            boxed_pos = pos
            boxed_type = b.item_at(pos).type
            break
    assert_ne(boxed_pos, Vector2i(-1, -1))  # Ensure we found a BOXED cell
    # Place a matching item on the supply row
    b.spawn(boxed_type, Vector2i(0, 13))
    var state_before := b.state_at(boxed_pos)
    # This merge should be rejected because target is BOXED
    var err := g.merge_event(Vector2i(0, 13), boxed_pos, NOW)
    assert_ne(err, "")  # Should get an error
    # BOXED cell should still be BOXED (no state mutation)
    assert_eq(b.state_at(boxed_pos), state_before)

func test_merge_event_onto_veiled_and_supply_row() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var b := g.events.board
    b.spawn("pb_dogpark_tar_1", Vector2i(0, 13))
    b.spawn("pb_dogpark_tar_1", Vector2i(1, 13))
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "")
    assert_eq(b.item_at(Vector2i(1, 13)).type, "pb_dogpark_tar_2")
    assert_eq(g.events.best_tier, 2)
    # merge shocks (1,12) from BOXED to COVERED; now find a covered cell that
    # has a mergeable item, spawn its matching type, and merge onto it.
    var covered_pos := Vector2i(-1, -1)
    var covered_type := ""
    for pos in b._items:
        if b.state_at(pos) == MergeBoard.CellState.COVERED:
            var item := b.item_at(pos)
            var row: Dictionary = ConfigDB.items.get(item.type, {})
            if row.has("MergedType") and row["MergedType"] != item.type:
                covered_pos = pos
                covered_type = item.type
                break
    if covered_pos != Vector2i(-1, -1):
        b.spawn(covered_type, Vector2i(2, 13))
        assert_eq(g.merge_event(Vector2i(2, 13), covered_pos, NOW), "")
        assert_eq(b.state_at(covered_pos), MergeBoard.CellState.OPEN)
        var merged_type := String(ConfigDB.items[covered_type]["MergedType"])
        assert_eq(b.item_at(covered_pos).type, merged_type)

func test_unboxing_event_cell_pays_event_grid_extra() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var b := g.events.board
    # find any cell whose 4-neighbourhood we can shock via a supply-row merge:
    # merge two tar_1 at (0,13),(1,13) -> target (1,13) shocks (1,12): a BOXED
    # layout cell -> becomes COVERED; the event grid's token for (1,12) (if any)
    # is granted. We assert the state transition and that no error occurs; the
    # reward amount is asserted only when the grid carries a token there.
    b.spawn("pb_dogpark_tar_1", Vector2i(0, 13))
    b.spawn("pb_dogpark_tar_1", Vector2i(1, 13))
    var energy_before := g.wallet.energy(NOW)
    g.wallet.spend_energy(50, NOW)
    energy_before = g.wallet.energy(NOW)
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "")
    assert_eq(b.state_at(Vector2i(1, 12)), MergeBoard.CellState.COVERED)
    var token := ConfigDB.event_paperbox_reward("dogpark", Vector2i(1, 12))
    if token.begins_with("energy-"):
        assert_eq(g.wallet.energy(NOW), energy_before + int(token.get_slice("-", 1)))

func test_completion_grants_end_rewards_once() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var chain := _walk_chain_from("pb_dogpark_tar_1")
    var penultimate := String(chain[chain.size() - 2])
    var b := g.events.board
    b.spawn(penultimate, Vector2i(0, 13))
    b.spawn(penultimate, Vector2i(1, 13))
    var gems_before := g.wallet.gems
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "")
    assert_true(g.events.completed)
    assert_eq(g.wallet.gems, gems_before + 30)
    assert_eq(g.events.best_tier, chain.size())
    # a second top merge cannot double-grant
    b.spawn(penultimate, Vector2i(2, 13))
    b.spawn(penultimate, Vector2i(3, 13))
    assert_eq(g.merge_event(Vector2i(2, 13), Vector2i(3, 13), NOW), "")
    assert_eq(g.wallet.gems, gems_before + 30)
