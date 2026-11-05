extends GutTest
## Day-1 tasks (from MainTaskConfig): ids 1-7, costs 26,16,24,46,25,24,24 (sum 185),
## every task rewards exp-15 (some also reward items). Day 2 is area 2, day 8 area 3.

func _game_with_coins(coins: int) -> Game:
    var g := Game.fresh(1000.0, 42)
    g.wallet.coins = coins   # deterministic regardless of tuning starting_coins
    return g

func test_fresh_campaign_starts_day_1_area_1() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_eq(g.campaign.day, 1)
    assert_eq(g.campaign.current_area(), 1)
    assert_eq(g.campaign.tasks_today().size(), 7)
    assert_false(g.campaign.is_complete())

func test_complete_task_spends_coins_and_grants_rewards() -> void:
    var g := _game_with_coins(100)
    var xp_before := g.player.xp
    var res: Dictionary = g.complete_task(1, 1000.0)   # cost 26, rewards exp-15
    assert_true(res["ok"])
    assert_eq(g.wallet.coins, 74)
    assert_eq(g.player.xp, xp_before + 15)
    assert_true(g.campaign.is_task_done(1, 1))

func test_rejections_leave_state_unchanged() -> void:
    var g := _game_with_coins(30)
    assert_eq(g.complete_task(99, 1000.0)["reason"], "not_today")
    var res: Dictionary = g.complete_task(4, 1000.0)   # costs 46 > 30
    assert_eq(res["reason"], "not_enough_coins")
    assert_eq(g.wallet.coins, 30)
    assert_true(g.complete_task(1, 1000.0)["ok"])      # cost 26
    assert_eq(g.complete_task(1, 1000.0)["reason"], "already_done")
    assert_eq(g.wallet.coins, 4)

func test_day_advances_when_all_tasks_done() -> void:
    var g := _game_with_coins(1000)
    watch_signals(g.campaign)
    for id in range(1, 8):
        assert_true(g.complete_task(id, 1000.0)["ok"])
    assert_eq(g.campaign.day, 2)
    assert_eq(g.campaign.current_area(), 2)
    assert_signal_emitted_with_parameters(g.campaign, "day_advanced", [2])
    assert_signal_emitted_with_parameters(g.campaign, "area_restored", [1])
    assert_eq(g.campaign.area_state(1, g.player), Campaign.AreaState.RESTORED)
    assert_eq(g.campaign.area_state(2, g.player), Campaign.AreaState.ACTIVE)
    assert_eq(g.campaign.area_state(3, g.player), Campaign.AreaState.LOCKED)

func test_area_gate_level_and_condition() -> void:
    var g := Game.fresh(1000.0, 42)
    # Area 3 gate: level 5 + TaskCompleted-1_9. 1_9 doesn't exist -> condition
    # treated as satisfied (spec erratum); only the level gate bites.
    g.player.level = 4
    assert_false(g.campaign.is_area_unlocked(3, g.player))
    g.player.level = 5
    assert_true(g.campaign.is_area_unlocked(3, g.player))
    assert_true(g.campaign.is_area_unlocked(2, g.player))   # no gate row

func test_area_locked_rejects_completion() -> void:
    var g := _game_with_coins(10000)
    g.player.level = 4                       # below area-3 gate
    g.campaign.day = 8                       # first area-3 day
    var first_id := int(g.campaign.tasks_today()[0]["id"])
    var res: Dictionary = g.complete_task(first_id, 1000.0)
    assert_eq(res["reason"], "area_locked")
    g.player.level = 5
    assert_true(g.complete_task(first_id, 1000.0)["ok"])

func test_wing_progress_counts_area_tasks() -> void:
    var g := _game_with_coins(1000)
    assert_eq(g.campaign.wing_progress(1), Vector2i(0, 7))   # area 1 == day 1 only
    g.complete_task(1, 1000.0)
    assert_eq(g.campaign.wing_progress(1), Vector2i(1, 7))

func test_campaign_roundtrip() -> void:
    var g := _game_with_coins(1000)
    g.complete_task(1, 1000.0)
    g.complete_task(2, 1000.0)
    var c := Campaign.from_dict(g.campaign.to_dict())
    assert_eq(c.day, 1)
    assert_true(c.is_task_done(1, 1))
    assert_true(c.is_task_done(1, 2))
    assert_false(c.is_task_done(1, 3))

func test_is_complete_past_last_day() -> void:
    var c := Campaign.new()
    c.day = 283   # config has days 1..282
    assert_true(c.is_complete())
    assert_eq(c.area_state(47, PlayerState.new()), Campaign.AreaState.RESTORED)
