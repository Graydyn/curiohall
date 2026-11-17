extends GutTest
## Membership: 30-day pass (stacking, cap, Play Pass), daily gem allowance,
## claimable once-a-day energy refill, and calm once-a-day reminders.

const DAY := 86400.0
const NOW := 1000.0

var g: Game

func before_each() -> void:
    g = Game.fresh(NOW, 42)

func test_not_member_by_default() -> void:
    var m := Membership.new()
    assert_false(m.is_member(NOW))
    assert_eq(m.days_left(NOW), 0)

func test_buy_pass_gives_30_days() -> void:
    var m := Membership.new()
    assert_true(m.buy_pass(NOW)["ok"])
    assert_eq(m.member_until, NOW + 30 * DAY)
    assert_true(m.is_member(NOW + 30 * DAY - 1.0))
    assert_false(m.is_member(NOW + 30 * DAY))
    assert_eq(m.days_left(NOW), 30)

func test_buy_while_active_extends() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    assert_true(m.buy_pass(NOW + 10 * DAY)["ok"])
    assert_eq(m.member_until, NOW + 60 * DAY)

func test_stack_limit_60_days_ahead() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    m.buy_pass(NOW)                              # exactly 60 ahead: allowed
    assert_eq(m.buy_pass(NOW)["reason"], "stack_limit")
    assert_eq(m.member_until, NOW + 60 * DAY)    # unchanged on rejection

func test_buy_after_lapse_starts_from_now() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    var later := NOW + 45 * DAY
    m.buy_pass(later)
    assert_eq(m.member_until, later + 30 * DAY)

func test_play_pass_is_member_and_blocks_buying() -> void:
    var m := Membership.new()
    m.set_play_pass(true)
    assert_true(m.is_member(NOW))
    assert_eq(m.buy_pass(NOW)["reason"], "play_pass")
    assert_eq(m.member_until, 0.0)

func test_tick_pays_gem_allowance_once_per_day() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    var gems := g.wallet.gems
    m.tick(g, NOW, 5)
    m.tick(g, NOW + 60.0, 5)
    assert_eq(g.wallet.gems, gems + 20)
    m.tick(g, NOW + DAY, 6)
    assert_eq(g.wallet.gems, gems + 40)

func test_tick_does_not_back_pay_missed_days() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    var gems := g.wallet.gems
    m.tick(g, NOW, 5)
    m.tick(g, NOW + 3 * DAY, 8)
    assert_eq(g.wallet.gems, gems + 40)

func test_non_member_tick_pays_nothing_and_join_mid_day_pays() -> void:
    var m := Membership.new()
    var gems := g.wallet.gems
    m.tick(g, NOW, 5)
    assert_eq(g.wallet.gems, gems)
    m.buy_pass(NOW + 60.0)
    m.tick(g, NOW + 60.0, 5)
    assert_eq(g.wallet.gems, gems + 20)

func test_refill_adds_100_over_cap_once_per_day() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    assert_eq(g.wallet.energy(NOW), 100)
    assert_true(m.refill_available(NOW, 5))
    assert_true(m.claim_refill(g, NOW, 5)["ok"])
    assert_eq(g.wallet.energy(NOW), 200)
    assert_eq(m.claim_refill(g, NOW, 5)["reason"], "already_claimed")
    assert_false(m.refill_available(NOW, 5))
    assert_true(m.refill_available(NOW + DAY, 6))

func test_refill_rejected_for_non_member() -> void:
    var m := Membership.new()
    assert_false(m.refill_available(NOW, 5))
    assert_eq(m.claim_refill(g, NOW, 5)["reason"], "not_member")

func test_reminder_once_per_day() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    assert_eq(m.take_reminder(NOW, 0), "")
    var t := NOW + 27 * DAY + 1.0                # 3 days left (ceil)
    assert_eq(m.take_reminder(t, 27), "ending_soon")
    assert_eq(m.take_reminder(t, 27), "")
    var last := NOW + 30 * DAY - 3600.0          # < 1 day left
    assert_eq(m.take_reminder(last, 29), "last_day")

func test_no_reminder_on_play_pass() -> void:
    var m := Membership.new()
    m.set_play_pass(true)
    assert_eq(m.take_reminder(NOW, 0), "")

func test_round_trip() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    m.last_perk_day = 4
    m.last_refill_day = 3
    m.last_reminder_day = 2
    m.play_pass = true
    var m2 := Membership.from_dict(m.to_dict())
    assert_eq(m2.member_until, m.member_until)
    assert_eq([m2.last_perk_day, m2.last_refill_day, m2.last_reminder_day], [4, 3, 2])
    assert_true(m2.play_pass)
