extends GutTest
## Expedition prize ladder (one prize per feed-chain tier, growing, final
## prize the biggest but <= 25% of the total) and the member edge (member
## orders drop a tier-2 feed item). Supply-row merges shock row 12, whose
## paperbox grid carries no tokens, so prize totals below are exact.

const NOW := 1000.0
const SUPPLY_Y := 13

func _tier_value(i: int) -> float:
    var v := 0.0
    for t in ConfigDB.tuning["event_tier_rewards"][i]:
        v += Rewards.value(String(t))
    return v

func _started(member: bool) -> Game:
    var g := Game.fresh(NOW, 42)
    if member:
        g.buy_pass(NOW)
    g.dev_start_event(NOW)
    g.wallet.spend_energy(90, NOW)   # read energy grants from below the cap
    return g

func test_ladder_has_one_entry_per_chain_tier() -> void:
    assert_eq((ConfigDB.tuning["event_tier_rewards"] as Array).size(), 12)

func test_prizes_never_decrease() -> void:
    var prev := 0.0
    for i in range(12):
        var v := _tier_value(i)
        if v > 0.0:
            assert_true(v >= prev, "tier %d" % (i + 1))
            prev = v

func test_final_prize_is_largest_and_at_most_quarter() -> void:
    var total := 0.0
    var biggest := 0.0
    for i in range(12):
        total += _tier_value(i)
        biggest = maxf(biggest, _tier_value(i))
    assert_eq(_tier_value(11), biggest)
    assert_true(_tier_value(11) <= 0.25 * total)

func test_member_order_drops_tier_2_feed() -> void:
    var g := _started(true)
    g.events.on_order_delivered(g, NOW)
    assert_eq(g.events.board.item_at(Vector2i(0, SUPPLY_Y)).type, "pb_dogpark_tar_2")

func test_free_order_drops_tier_1_feed() -> void:
    var g := _started(false)
    g.events.on_order_delivered(g, NOW)
    assert_eq(g.events.board.item_at(Vector2i(0, SUPPLY_Y)).type, "pb_dogpark_tar_1")

func test_merge_to_tier_2_pays_tier_2_prize() -> void:
    var g := _started(false)
    var b := g.events.board
    b.spawn("pb_dogpark_tar_1", Vector2i(0, SUPPLY_Y))
    b.spawn("pb_dogpark_tar_1", Vector2i(1, SUPPLY_Y))
    var e := g.wallet.energy(NOW)
    assert_eq(g.merge_event(Vector2i(0, SUPPLY_Y), Vector2i(1, SUPPLY_Y), NOW), "")
    assert_eq(g.wallet.energy(NOW), e + 20)
    assert_eq(g.events.paid_tier, 2)

func test_member_first_merge_pays_skipped_tiers() -> void:
    var g := _started(true)
    var b := g.events.board
    b.spawn("pb_dogpark_tar_2", Vector2i(0, SUPPLY_Y))
    b.spawn("pb_dogpark_tar_2", Vector2i(1, SUPPLY_Y))
    var e := g.wallet.energy(NOW)
    var gems := g.wallet.gems
    assert_eq(g.merge_event(Vector2i(0, SUPPLY_Y), Vector2i(1, SUPPLY_Y), NOW), "")
    assert_eq(g.wallet.energy(NOW), e + 20)     # tier 2 prize, never merged into
    assert_eq(g.wallet.gems, gems + 8)          # tier 3 prize
    assert_eq(g.events.paid_tier, 3)

func test_prizes_survive_round_trip_without_repaying() -> void:
    var g := _started(false)
    var b := g.events.board
    b.spawn("pb_dogpark_tar_1", Vector2i(0, SUPPLY_Y))
    b.spawn("pb_dogpark_tar_1", Vector2i(1, SUPPLY_Y))
    g.merge_event(Vector2i(0, SUPPLY_Y), Vector2i(1, SUPPLY_Y), NOW)
    g.events = Events.from_dict(g.events.to_dict())
    assert_eq(g.events.paid_tier, 2)
    b = g.events.board
    b.spawn("pb_dogpark_tar_1", Vector2i(2, SUPPLY_Y))
    b.spawn("pb_dogpark_tar_1", Vector2i(3, SUPPLY_Y))
    var e := g.wallet.energy(NOW)
    assert_eq(g.merge_event(Vector2i(2, SUPPLY_Y), Vector2i(3, SUPPLY_Y), NOW), "")
    assert_eq(g.wallet.energy(NOW), e)

func test_new_event_resets_paid_tier() -> void:
    var g := _started(false)
    g.events.paid_tier = 5
    g.dev_end_event(NOW)
    g.dev_start_event(NOW)
    assert_eq(g.events.paid_tier, 0)
