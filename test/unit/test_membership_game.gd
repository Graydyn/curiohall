extends GutTest
## Membership wired into Game: local-day clock, ticks, refill, save v11.

func test_fresh_game_has_membership_not_member() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_not_null(g.membership)
    assert_false(g.membership.is_member(1000.0))

func test_local_day_uses_offset() -> void:
    var g := Game.fresh(1000.0, 42)
    var t := 86400.0 * 100 + 3600.0          # 01:00 UTC on day 100
    assert_eq(g.local_day(t), 100)
    g.tz_offset_seconds = -2 * 3600           # UTC-2: still 23:00 on day 99
    assert_eq(g.local_day(t), 99)

func test_tick_across_midnight_pays_again() -> void:
    var g := Game.fresh(1000.0, 42)
    var t := 86400.0 * 100 + 86000.0         # 400s before midnight
    g.buy_pass(t)
    var gems := g.wallet.gems
    g.tick_membership(t)
    g.tick_membership(t + 500.0)               # next local day
    assert_eq(g.wallet.gems, gems + 40)
    assert_true(g.refill_available(t + 500.0))

func test_claim_refill_via_game() -> void:
    var g := Game.fresh(1000.0, 42)
    g.buy_pass(1000.0)
    assert_true(g.claim_refill(1000.0)["ok"])
    assert_eq(g.claim_refill(1000.0)["reason"], "already_claimed")

func test_save_round_trip_keeps_membership() -> void:
    var g := Game.fresh(1000.0, 42)
    g.buy_pass(1000.0)
    g.claim_refill(1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.membership.member_until, g.membership.member_until)
    assert_eq(g2.membership.last_refill_day, g.membership.last_refill_day)
    assert_eq(int(g.to_dict()["save_version"]), 11)
    assert_false(g.to_dict().has("iap"))

func test_reminder_counts_calendar_days_to_end() -> void:
    var g := Game.fresh(1000.0, 42)
    var start := 86400.0 * 100 + 10 * 3600.0     # day 100, 10:00 UTC (offset 0)
    g.buy_pass(start)                             # ends day 130 at 10:00
    var t := 86400.0 * 129 + 11 * 3600.0          # day 129, 11:00: < 24h left
    assert_eq(g.membership_end_days(t), 1)
    assert_eq(g.take_membership_reminder(t), "ending_soon")
    assert_eq(g.take_membership_reminder(86400.0 * 130 + 3600.0), "last_day")
