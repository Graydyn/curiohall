extends GutTest
## Special order 1: trigger taskFinish-2_7, needs 1610, seeds chain 15 (-> 1501),
## rewards gem-15 + energy-100. Order 2: trigger 11_6, needs 2010, seeds 1901.
## Order 4 seeds BOTH sp4_1_1 and sp4_2_1 (Array GeneratorChain).

const NOW := 1000.0

func _plant(g: Game, type: String, pos: Vector2i) -> void:
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(type))

func test_seed_items_mapping() -> void:
    assert_eq(SpecialOrders.seed_items({"GeneratorChain": "15"}), ["1501"])
    assert_eq(SpecialOrders.seed_items({"GeneratorChain": "sp3_1"}), ["sp3_1_1"])
    assert_eq(SpecialOrders.seed_items({"GeneratorChain": ["sp4_1", "sp4_2"]}), ["sp4_1_1", "sp4_2_1"])

func test_inactive_until_trigger_task_done() -> void:
    var g := Game.fresh(NOW, 42)
    assert_false(g.specials.maybe_activate(g.campaign, g, NOW))
    assert_true(g.specials.current().is_empty())
    g.campaign.done["2_7"] = true
    assert_true(g.specials.maybe_activate(g.campaign, g, NOW))
    assert_true(g.specials.active)
    assert_eq(int(g.specials.current()["Id"]), 1)
    # seed granted; board is full so it lands in the inventory
    assert_has(g.player.inventory, "1501")

func test_sequential_gating_and_auto_advance() -> void:
    var g := Game.fresh(NOW, 42)
    g.campaign.done["2_7"] = true
    g.campaign.done["11_6"] = true    # order 2's trigger already satisfied
    g.specials.maybe_activate(g.campaign, g, NOW)
    assert_eq(int(g.specials.current()["Id"]), 1)   # order 2 must wait
    _plant(g, "1610", Vector2i(3, 4))
    var res: Dictionary = g.deliver_special(NOW)
    assert_true(res["ok"])
    # order 1 done -> order 2 activates immediately and seeds 1901
    assert_true(g.specials.active)
    assert_eq(int(g.specials.current()["Id"]), 2)
    assert_eq(g.board.count_of("1901"), 1)   # delivery freed a cell, so the seed spawned onto the board

func test_deliver_pays_rewards_and_consumes_item() -> void:
    var g := Game.fresh(NOW, 42)
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, NOW)
    _plant(g, "1610", Vector2i(3, 4))
    var gems_before := g.wallet.gems
    var energy_before := g.wallet.energy(NOW)
    assert_true(g.deliver_special(NOW)["ok"])
    assert_eq(g.wallet.gems, gems_before + 15)
    assert_eq(g.wallet.energy(NOW), energy_before + 100)   # overfill by design
    assert_eq(g.board.count_of("1610"), 0)

func test_deliver_rejections_change_nothing() -> void:
    var g := Game.fresh(NOW, 42)
    assert_eq(g.deliver_special(NOW)["reason"], "not_active")
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, NOW)
    var gems_before := g.wallet.gems
    assert_eq(g.deliver_special(NOW)["reason"], "no_item")
    assert_true(g.specials.active)
    assert_eq(g.wallet.gems, gems_before)

func test_full_walk_to_all_done() -> void:
    var g := Game.fresh(NOW, 42)
    for trig in ["2_7", "11_6", "18_7", "24_3", "29_8", "33_9"]:
        g.campaign.done[trig] = true
    g.specials.maybe_activate(g.campaign, g, NOW)
    var reqs := [["1610"], ["2010"], ["sp3_2_10", "sp3_3_6"], ["sp4_3_10"], ["sp5_2_10"], ["sp6_2_10"]]
    var cells := [Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)]
    var cell_idx := 0
    for req_set in reqs:
        assert_true(g.specials.active, "expected active before delivering order")
        # Plant all requirements for this order
        for req in req_set:
            _plant(g, req, cells[cell_idx])
            cell_idx += 1
        var order_num := g.specials.next_id if g.specials.active else g.specials.next_id - 1
        assert_true(g.deliver_special(NOW)["ok"], "deliver order %d" % order_num)
        if g.specials.active:
            for seed_id in SpecialOrders.seed_items(g.specials.current()):
                var on_board := g.board.count_of(String(seed_id))
                var in_inv := g.player.inventory.count(String(seed_id))
                assert_gt(on_board + in_inv, 0, "seed %s granted" % seed_id)
    assert_true(g.specials.is_all_done())
    assert_true(g.specials.current().is_empty())

func test_complete_task_hook_activates() -> void:
    var g := Game.fresh(NOW, 42)
    g.wallet.coins = 10000
    g.campaign.day = 2
    for i in range(1, 7):                      # day 2 has task ids 1..7
        g.campaign.done["2_%d" % i] = true
    assert_true(g.complete_task(7, NOW)["ok"]) # completes 2_7 -> hook fires
    assert_true(g.specials.active)
    assert_eq(int(g.specials.current()["Id"]), 1)

func test_requirements_helper() -> void:
    assert_eq(SpecialOrders.requirements({"Requirement1": "1610"}), ["1610"])
    assert_eq(SpecialOrders.requirements({"Requirement1": "sp3_2_10", "Requirement2": "sp3_3_6"}), ["sp3_2_10", "sp3_3_6"])

func test_order_three_requires_both_items() -> void:
    var g := Game.fresh(NOW, 42)
    g.specials.next_id = 3
    g.campaign.done["18_7"] = true
    g.specials.maybe_activate(g.campaign, g, NOW)
    assert_eq(int(g.specials.current()["Id"]), 3)
    # Try delivering with only first requirement on board
    _plant(g, "sp3_2_10", Vector2i(3, 4))
    var res: Dictionary = g.deliver_special(NOW)
    assert_eq(res["reason"], "no_item")
    assert_true(g.specials.active)  # still active, nothing consumed
    assert_eq(g.board.count_of("sp3_2_10"), 1)  # item still on board
    # Now plant second requirement too
    _plant(g, "sp3_3_6", Vector2i(2, 4))
    assert_true(g.deliver_special(NOW)["ok"])
    # Both items consumed
    assert_eq(g.board.count_of("sp3_2_10"), 0)
    assert_eq(g.board.count_of("sp3_3_6"), 0)

func test_roundtrip() -> void:
    var s := SpecialOrders.new()
    s.next_id = 3
    s.active = true
    var s2 := SpecialOrders.from_dict(s.to_dict())
    assert_eq(s2.next_id, 3)
    assert_true(s2.active)
