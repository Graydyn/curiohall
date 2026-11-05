extends GutTest
## Patron's Gala lifecycle: gated auto-start, 3-day window, 1-day gap,
## daily rollover resets ladder state and bumps the round counter.

const NOW := 1000.0
const DAY := 86400.0

func _player(level: int) -> PlayerState:
    var p := PlayerState.new()
    p.level = level
    return p

func test_no_start_below_unlock_level() -> void:
    var b := Boost.new()
    b.tick(NOW, _player(1))     # next_boost_at 0 -> due, but level 1 < 8
    assert_false(b.is_active())

func test_auto_start_when_due_and_gated() -> void:
    var b := Boost.new()
    b.tick(NOW, _player(8))
    assert_true(b.is_active())
    assert_eq(b.ends_at, NOW + 259200.0)
    assert_eq(b.round_num, 1)
    assert_eq(b.rollover_at, DAY)   # next UTC midnight after t=1000

func test_expiry_schedules_next_window() -> void:
    var b := Boost.new()
    b.tick(NOW, _player(8))
    b.tick(NOW + 259200.0, _player(8))
    assert_false(b.is_active())
    assert_eq(b.next_boost_at, NOW + 259200.0 + 86400.0)
    b.tick(NOW + 259200.0 + 86400.0, _player(8))
    assert_true(b.is_active())

func test_dev_controls_bypass_gate_and_timers() -> void:
    var b := Boost.new()
    assert_true(b.start_boost(NOW))     # no level check on the dev path
    assert_true(b.is_active())
    assert_false(b.start_boost(NOW))    # idempotent while active
    b.end_boost(NOW + 5.0)
    assert_false(b.is_active())
    assert_eq(b.next_boost_at, NOW + 5.0 + 86400.0)

func test_daily_rollover_resets_and_advances() -> void:
    var b := Boost.new()
    b.start_boost(NOW)
    b.progress = 7
    b.buff_level = 3
    b.window_left = 2
    b.extras_left = 1
    b.extra_cached = true
    b.extra_lucky_cached = "204"
    b.tick(DAY + 1.0, _player(8))      # crosses the first midnight
    assert_true(b.is_active())
    assert_eq(b.round_num, 2)
    assert_eq(b.progress, 0)
    assert_eq(b.buff_level, 0)
    assert_eq(b.window_left, 0)
    assert_eq(b.extras_left, 0)
    assert_false(b.extra_cached)
    assert_eq(b.extra_lucky_cached, "")
    assert_eq(b.rollover_at, 2.0 * DAY)

func test_offline_gap_rolls_over_once_to_next_midnight() -> void:
    var b := Boost.new()
    b.start_boost(NOW)
    b.tick(2.0 * DAY + 500.0, _player(8))   # skipped a whole day offline
    assert_eq(b.round_num, 2)               # one reset, not two
    assert_eq(b.rollover_at, 3.0 * DAY)     # re-anchored past `now`

func test_end_before_midnight_never_rolls_over() -> void:
    var b := Boost.new()
    b.start_boost(NOW)
    b.end_boost(NOW + 10.0)
    b.tick(DAY + 1.0, _player(1))
    assert_false(b.is_active())
    assert_eq(b.round_num, 1)

func _active_boost() -> Boost:
    var b := Boost.new()
    b.start_boost(NOW)
    return b

func test_ladder_unlocks_cumulative_buffs() -> void:
    var b := _active_boost()
    # boost_tasks [2,3,4,5]; boost_buffs [moreLucky, extra, extraLucky, nocd]
    assert_false(b.is_buff_active("moreLuckyProduce"))
    b.on_order_delivered(NOW)
    b.on_order_delivered(NOW)                      # progress 2 -> rung 1
    assert_true(b.is_buff_active("moreLuckyProduce"))
    assert_false(b.is_buff_active("extraProduce"))
    b.on_order_delivered(NOW)                      # progress 3 -> rung 2
    assert_true(b.is_buff_active("moreLuckyProduce"))   # cumulative
    assert_true(b.is_buff_active("extraProduce"))
    b.on_order_delivered(NOW)                      # 4 -> rung 3
    b.on_order_delivered(NOW)                      # 5 -> rung 4
    assert_true(b.is_buff_active("extraLuckyProduce"))
    assert_true(b.is_buff_active("nocd"))
    b.on_order_delivered(NOW)                      # past the top: no crash
    assert_eq(b.buff_level, 4)

func test_no_ladder_progress_while_idle() -> void:
    var b := Boost.new()
    b.on_order_delivered(NOW)
    assert_eq(b.progress, 0)
    assert_false(b.is_buff_active("moreLuckyProduce"))

func test_quota_fires_exactly_m_per_n_taps() -> void:
    var b := _active_boost()
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    # boost_extra_produce [1, 3]: exactly 1 fire per window of 3 taps.
    for k in range(50):
        var fires := 0
        for i in range(3):
            if b.take_extra(rng):
                fires += 1
        assert_eq(fires, 1)

func test_claim_extra_cache_first_and_blocked_recache() -> void:
    var b := _active_boost()
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    b.extra_cached = true
    b.window_left = 3
    b.extras_left = 0            # quota can't fire in this window
    assert_true(b.claim_extra(rng))   # cached one delivered
    assert_false(b.extra_cached)
    b.window_left = 1
    b.extras_left = 1            # next take_extra must fire
    assert_true(b.claim_extra(rng))
    b.report_extra_blocked()          # no room: back to the cache
    assert_true(b.extra_cached)
    # cache full + another blocked claim -> the claimed extra is lost (warning)
    b.window_left = 1
    b.extras_left = 1
    assert_true(b.claim_extra(rng))   # delivers the cached one, fire refills slot
    assert_true(b.extra_cached)

func test_lucky_twin_cache_roundtrip() -> void:
    var b := _active_boost()
    b.cache_extra_lucky("204")
    assert_eq(b.take_cached_lucky(), "204")
    assert_eq(b.take_cached_lucky(), "")

func test_effective_row_swaps_only_when_buffed_and_boosted() -> void:
    var b := _active_boost()
    var base_row: Dictionary = b.effective_row("105")
    assert_eq((base_row["Spread_Weight"] as Array).size(), 3)   # base until rung 1
    b.buff_level = 1                                            # moreLuckyProduce
    var boosted_row: Dictionary = b.effective_row("105")
    assert_eq((boosted_row["Spread_Weight"] as Array).size(), 2)
    var plain: Dictionary = b.effective_row("104")              # not a boost type
    assert_eq(plain, ConfigDB.items["104"])
    b.state = Boost.State.IDLE
    assert_eq((b.effective_row("105")["Spread_Weight"] as Array).size(), 3)

func test_effective_lucky_precedence() -> void:
    var b := _active_boost()
    assert_eq(b.effective_lucky(), ConfigDB.lucky)              # rung 0: base
    b.buff_level = 3                # moreLucky + extra + extraLucky all active
    var t: Array = b.effective_lucky()
    var row0: Dictionary = t[0]
    assert_eq(int((row0["lucky_chance"] as Array)[0]), 25)      # MoreLucky wins
    b.state = Boost.State.IDLE
    assert_eq(b.effective_lucky(), ConfigDB.lucky)              # IDLE: base again

func test_boost_save_roundtrip() -> void:
    var b := _active_boost()
    b.progress = 4
    b.buff_level = 3
    b.round_num = 2
    b.window_left = 2
    b.extras_left = 1
    b.extra_cached = true
    b.extra_lucky_cached = "303"
    var b2: Boost = Boost.from_dict(b.to_dict())
    assert_eq(b2.state, Boost.State.ACTIVE)
    assert_eq(b2.ends_at, b.ends_at)
    assert_eq(b2.next_boost_at, b.next_boost_at)
    assert_eq(b2.rollover_at, b.rollover_at)
    assert_eq(b2.round_num, 2)
    assert_eq(b2.progress, 4)
    assert_eq(b2.buff_level, 3)
    assert_eq(b2.window_left, 2)
    assert_eq(b2.extras_left, 1)
    assert_true(b2.extra_cached)
    assert_eq(b2.extra_lucky_cached, "303")
