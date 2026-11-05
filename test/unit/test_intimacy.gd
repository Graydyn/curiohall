extends GutTest
## Config facts used here: Cornelia prefers chocolate (Intimacy 10 -> ceil(10*1.2)=12),
## Cornelia L1 costs 36 (three preferred chocolates) and rewards energy-30, L2 costs
## 60 (36+60=96 = eight chocolates total). Barnaby prefers flower (8 -> 10), L1 costs
## 48. Aldous unlocks at day_12 + intimacy_Barnaby_3. Ambrose is unreleased.

const NOW := 1000.0

func _rng() -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    return rng

func test_fresh_satchel_empty_and_tracks_at_zero() -> void:
    var g := Game.fresh(NOW, 42)
    for t in Intimacy.GIFT_TYPES:
        assert_eq(int(g.intimacy.satchel[t]), 0)
    assert_eq(g.intimacy.level_of("Cornelia"), 0)

func test_order_gifts_follow_coin_brackets() -> void:
    var im := Intimacy.new()
    var granted: Dictionary = im.grant_order_gifts(30, _rng())   # 26-45 -> 3..4 gifts
    var total := 0
    for t in granted:
        assert_has(Intimacy.GIFT_TYPES, String(t))
        total += int(granted[t])
    assert_between(total, 3, 4)
    var big: Dictionary = im.grant_order_gifts(200, _rng())      # 76+ -> 5..6
    var big_total := 0
    for t in big:
        big_total += int(big[t])
    assert_between(big_total, 5, 6)
    assert_eq(im.grant_order_gifts(0, _rng()).size(), 0)         # below every bracket

func test_deliver_order_grants_gifts() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 30, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    var total := 0
    for t in Intimacy.GIFT_TYPES:
        total += int(g.intimacy.satchel[t])
    assert_between(total, 3, 4)

func test_give_gift_spends_and_adds_points_with_preferred_bonus() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["chocolate"] = 3   # Cornelia's preferred type: ceil(10*1.2)=12 each
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(int(g.intimacy.satchel["chocolate"]), 2)
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 12)
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 24)
    assert_eq(g.intimacy.level_of("Cornelia"), 0)   # 24 < 36
    var energy_before := g.wallet.energy(NOW)
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])   # 36 -> level 1
    assert_eq(g.intimacy.level_of("Cornelia"), 1)
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 0)
    assert_eq(g.wallet.energy(NOW), energy_before + 30)          # L1 reward energy-30

func test_non_preferred_gift_counts_single() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["book"] = 1        # book Intimacy 10, not Cornelia's preference
    assert_true(g.give_gift("Cornelia", "book", NOW)["ok"])
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 10)

func test_level_two_records_story() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["chocolate"] = 8   # 8*12 = 96 = L1 (36) + L2 (60) exactly
    for i in range(8):
        assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(g.intimacy.level_of("Cornelia"), 2)
    assert_has(g.intimacy.story_unlocks, "character_story_cornelia_1")
    assert_has(g.intimacy.story_unlocks, "character_intimacy_background_cornelia")

func test_rejections() -> void:
    var g := Game.fresh(NOW, 42)
    assert_eq(g.give_gift("Cornelia", "chocolate", NOW)["reason"], "no_gift")
    g.intimacy.satchel["chocolate"] = 1
    assert_eq(g.give_gift("Aldous", "chocolate", NOW)["reason"], "locked")   # day 1 < 12
    assert_eq(g.give_gift("Ambrose", "chocolate", NOW)["reason"], "locked")     # unreleased
    assert_eq(g.give_gift("Cornelia", "pebbles", NOW)["reason"], "bad_type")
    assert_eq(int(g.intimacy.satchel["chocolate"]), 1)   # nothing consumed by rejections

func test_unlock_web_day_and_intimacy_gates() -> void:
    var g := Game.fresh(NOW, 42)
    assert_true(g.intimacy.is_unlocked("Cornelia", g.campaign))    # day_1
    assert_false(g.intimacy.is_unlocked("Aldous", g.campaign))
    g.campaign.day = 12
    assert_false(g.intimacy.is_unlocked("Aldous", g.campaign)) # still needs Barnaby 3
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 3
    assert_true(g.intimacy.is_unlocked("Aldous", g.campaign))
    assert_false(g.intimacy.is_unlocked("Ambrose", g.campaign))   # never
    assert_eq(g.intimacy.unlock_hint("Aldous"), ["day_12", "intimacy_Barnaby_3"])

func test_maxed_track_rejects() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Cornelia") as Dictionary)["level"] = 30
    g.intimacy.satchel["chocolate"] = 1
    assert_eq(g.give_gift("Cornelia", "chocolate", NOW)["reason"], "maxed")

func test_roundtrip() -> void:
    var im := Intimacy.new()
    im.satchel["flower"] = 3
    (im.track("Barnaby") as Dictionary)["level"] = 2
    (im.track("Barnaby") as Dictionary)["points"] = 15
    im.story_unlocks.append("character_story_barnaby_1")
    var im2 := Intimacy.from_dict(im.to_dict())
    assert_eq(int(im2.satchel["flower"]), 3)
    assert_eq(im2.level_of("Barnaby"), 2)
    assert_has(im2.story_unlocks, "character_story_barnaby_1")

func test_free_slot_claims_once_per_day() -> void:
    var im := Intimacy.new()
    var res: Dictionary = im.claim_free(_rng())
    assert_true(res["ok"])
    assert_has(Intimacy.GIFT_TYPES, String(res["type"]))
    assert_eq(im.claim_free(_rng())["reason"], "out_of_stock")

func test_coin_price_escalates_every_four_buys() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10000)
    assert_eq(im.gift_coin_price("flower"), 40)
    for i in range(4):
        assert_true(im.buy_with_coins("flower", w)["ok"])
    assert_eq(im.gift_coin_price("flower"), 60)   # 40 + 1*20 after 4 buys
    assert_eq(im.gift_coin_price("watch"), 90)    # 60 + 1*30, escalation is shared
    assert_true(im.buy_with_coins("watch", w)["ok"])
    assert_true(im.buy_with_coins("watch", w)["ok"])   # 6th buy empties the slot
    assert_eq(im.buy_with_coins("flower", w)["reason"], "out_of_stock")
    assert_eq(int(im.satchel["flower"]), 4)
    assert_eq(int(im.satchel["watch"]), 2)

func test_coin_buy_rejects_without_spend_when_poor() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10)
    assert_eq(im.buy_with_coins("flower", w)["reason"], "not_enough_coins")
    assert_eq(w.coins, 10)
    assert_eq(int(im.satchel["flower"]), 0)

func test_gem_slots_sell_their_type_and_cap_at_three() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_gems(1000)
    var gems_before := w.gems
    for i in range(3):
        assert_true(im.buy_with_gems("chocolate", w)["ok"])   # slot 4, 12 gems each
    assert_eq(w.gems, gems_before - 36)
    assert_eq(im.buy_with_gems("chocolate", w)["reason"], "out_of_stock")
    assert_true(im.buy_with_gems("flower", w)["ok"])          # slot 3 unaffected
    assert_eq(im.buy_with_gems("pebbles", w)["reason"], "bad_type")

func test_tick_restocks_daily_and_resets_escalation() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10000)
    im.claim_free(_rng())
    for i in range(4):
        im.buy_with_coins("flower", w)
    im.tick(1000.0, _rng())                       # arms restock_at
    im.tick(1000.0 + 86400.0, _rng())             # a day later: restock
    assert_true(im.claim_free(_rng())["ok"])
    assert_eq(im.gift_coin_price("flower"), 40)

func test_shop_state_roundtrip() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10000)
    im.claim_free(_rng())
    for i in range(4):
        im.buy_with_coins("flower", w)
    im.tick(1000.0, _rng())
    var im2 := Intimacy.from_dict(im.to_dict())
    assert_eq(im2.claim_free(_rng())["reason"], "out_of_stock")
    assert_eq(im2.gift_coin_price("flower"), 60)
    assert_eq(im2.restock_at, im.restock_at)

func test_return_gift_needs_cooldown_and_a_leveled_friend() -> void:
    var g := Game.fresh(NOW, 42)
    assert_false(g.intimacy.maybe_refresh_return_gift(NOW, _rng()))     # 1000 < 86400
    assert_false(g.intimacy.maybe_refresh_return_gift(90000.0, _rng())) # nobody leveled
    assert_eq(g.intimacy.gift_refreshed_at, 0.0)                        # window NOT consumed
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    assert_true(g.intimacy.maybe_refresh_return_gift(90001.0, _rng()))
    assert_eq(g.intimacy.gift_source, "Barnaby")
    assert_eq(g.intimacy.gift_refreshed_at, 90001.0)

func test_return_gift_never_double_arms() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    assert_true(g.intimacy.maybe_refresh_return_gift(90000.0, _rng()))
    assert_false(g.intimacy.maybe_refresh_return_gift(900000.0, _rng()))
    assert_eq(g.intimacy.gift_source, "Barnaby")

func test_return_gift_sender_weighted_and_deterministic() -> void:
    var a := Intimacy.new()
    var b := Intimacy.new()
    for im in [a, b]:
        (im.track("Barnaby") as Dictionary)["level"] = 1
        (im.track("Cornelia") as Dictionary)["level"] = 5
    a.maybe_refresh_return_gift(90000.0, _rng())
    b.maybe_refresh_return_gift(90000.0, _rng())
    assert_eq(a.gift_source, b.gift_source)
    assert_has(["Barnaby", "Cornelia"], a.gift_source)

func test_claim_return_gift_grants_from_level_pool_and_clears() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.intimacy.gift_source = "Barnaby"
    var pool: Array = (ConfigDB.intimacy_levels["Barnaby"][0] as Dictionary)["Gifts"]
    var expected: Array = []
    for e in Weighted.parse(pool):
        expected.append(String(e["id"]))
    var res: Dictionary = g.claim_return_gift(NOW)
    assert_true(res["ok"])
    assert_eq(String(res["sender"]), "Barnaby")
    assert_has(expected, String(res["reward"]))
    assert_eq(g.intimacy.gift_source, "")
    assert_eq(g.claim_return_gift(NOW)["reason"], "no_gift")

func test_claim_with_maxed_sender_uses_last_row() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 30
    g.intimacy.gift_source = "Barnaby"
    var pool: Array = (ConfigDB.intimacy_levels["Barnaby"][29] as Dictionary)["Gifts"]
    var expected: Array = []
    for e in Weighted.parse(pool):
        expected.append(String(e["id"]))
    var res: Dictionary = g.claim_return_gift(NOW)
    assert_true(res["ok"])
    assert_has(expected, String(res["reward"]))

func test_deliver_order_checks_return_gift() -> void:
    var g := Game.fresh(90000.0, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, 90000.0)["ok"])
    assert_eq(g.intimacy.gift_source, "Barnaby")

func test_story_filter_records_only_character_tokens() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy._grant_level_rewards(
            {"Rewards": ["time_skip_5-1-1", "character_story_test_1", "character_moment_test_3a"]}, g, NOW)
    assert_has(g.intimacy.story_unlocks, "character_story_test_1")
    assert_has(g.intimacy.story_unlocks, "character_moment_test_3a")
    assert_false(g.intimacy.story_unlocks.has("time_skip_5-1-1"))
    assert_false(g.intimacy.story_unlocks.has("time_skip_5-1"))
