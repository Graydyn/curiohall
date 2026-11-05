extends GutTest

const TEST_PATH := "user://test_save.json"
const TEST_CORRUPT_PATH := "user://test_save.corrupt.json"
const DEFAULT_PATH := "user://save.json"
const DEFAULT_CORRUPT_PATH := "user://save.corrupt.json"

func before_all() -> void:
    SaveManager.path = TEST_PATH
    SaveManager.corrupt_path = TEST_CORRUPT_PATH

func after_all() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    if FileAccess.file_exists(SaveManager.corrupt_path):
        DirAccess.remove_absolute(SaveManager.corrupt_path)
    SaveManager.path = DEFAULT_PATH
    SaveManager.corrupt_path = DEFAULT_CORRUPT_PATH

func test_return_gift_and_recap_smoke() -> void:
    var g := Game.fresh(1000.0, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.tick_gifts(200000.0)                       # daily window long past: gift arms
    assert_eq(g.intimacy.gift_source, "Barnaby")
    var res: Dictionary = g.claim_return_gift(200000.0)
    assert_true(res["ok"])
    assert_eq(g.intimacy.gift_source, "")
    g.campaign.done["20_11"] = true              # unlocks Chronicle volume 1
    assert_true(g.campaign.done.has(String((ConfigDB.story_recap[1] as Dictionary)["task"])))
    var g2 := Game.from_dict(g.to_dict())        # quit/resume keeps the refresh clock
    assert_eq(g2.intimacy.gift_refreshed_at, g.intimacy.gift_refreshed_at)

func test_main_scene_loads_and_full_loop_runs() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    var scene: PackedScene = load("res://scenes/main.tscn")
    var main: Node = scene.instantiate()
    add_child_autofree(main)
    await wait_process_frames(2)
    var game: Game = main.game
    assert_not_null(game)
    # The Expedition button must be reachable even with no active event (the
    # DEV start control lives inside the panel it opens).
    assert_true((main.get_node("UI/ExpeditionButton") as Button).visible)
    # scripted loop: find a generator on the starting board, tap, merge two drops
    # (use the real clock, matching the epoch the freshly-created Game's wallet
    # and generator timers were stamped with in Main._ready)
    var now := Time.get_unix_time_from_system()
    var gen_pos := Vector2i(-1, -1)
    for y in range(MergeBoard.HEIGHT):
        for x in range(MergeBoard.WIDTH):
            var it := game.board.item_at(Vector2i(x, y))
            if it != null and it.gen != null and game.board.state_at(Vector2i(x, y)) == MergeBoard.CellState.OPEN:
                gen_pos = Vector2i(x, y)
    if gen_pos == Vector2i(-1, -1):
        # starting board is fully occupied (merge-game convention); no free cell
        # exists for spawn()/find_free_cell() to use, so free some directly:
        # one for the generator itself, two more nearby for its drops to land on.
        gen_pos = Vector2i(3, 4)
        for p in [gen_pos, Vector2i(2, 4), Vector2i(4, 4)]:
            game.board.remove(p)
            game.board.set_state(p, MergeBoard.CellState.OPEN)
        game.board.place(gen_pos, ItemInstance.make("104", now))
    var r1 := game.tap_generator(gen_pos, now)
    var r2 := game.tap_generator(gen_pos, now)
    assert_true(r1["ok"] and r2["ok"])
    var a: Vector2i = r1["spawned"][0]["pos"]
    var b: Vector2i = r2["spawned"][0]["pos"]
    if game.board.item_at(a).type == game.board.item_at(b).type:
        assert_eq(game.board.merge(a, b), "")
    SaveManager.save(game)
    assert_not_null(SaveManager.load_game())

    # store/withdraw round trip: pick any OPEN non-generator item and store it
    var store_pos := Vector2i(-1, -1)
    for y in range(MergeBoard.HEIGHT):
        for x in range(MergeBoard.WIDTH):
            var p := Vector2i(x, y)
            var item := game.board.item_at(p)
            if item != null and item.gen == null and game.board.state_at(p) == MergeBoard.CellState.OPEN:
                store_pos = p
    assert_true(store_pos != Vector2i(-1, -1))
    var inv_before := game.player.inventory.size()   # fresh games start with the gifted 103
    var stored_type := game.board.item_at(store_pos).type
    assert_true(game.player.store(stored_type))
    game.board.remove(store_pos)
    assert_eq(game.player.inventory.size(), inv_before + 1)
    var withdrawn := game.player.withdraw(inv_before)
    assert_eq(withdrawn, stored_type)
    if game.board.spawn(withdrawn, store_pos) == Vector2i(-1, -1):
        game.player.store(withdrawn)
        assert_eq(game.player.inventory.size(), inv_before + 1)
    else:
        assert_eq(game.player.inventory.size(), inv_before)

func test_economy_loop_chest_to_gems() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    var g := Game.fresh(1000.0, 42)
    # place a gem chest and free neighbors
    var cpos := Vector2i(1, 3)
    g.board.remove(cpos); g.board.set_state(cpos, MergeBoard.CellState.OPEN)
    g.board.place(cpos, ItemInstance.make("main_g_chest_new_1", 1000.0))
    for p in [Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4), Vector2i(0, 3), Vector2i(0, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    # tap chest -> dispenses a currency token; collect every dispensed token
    var gems0 := g.wallet.gems
    var coins0 := g.wallet.coins
    for i in range(5):
        var r := g.tap(cpos, 1000.0)
        if r["ok"] and r.get("spawned"):
            var tp: Vector2i = r["spawned"][0]["pos"]
            g.tap(tp, 1000.0)   # collect it
    # main_g_chest_new_1's Spread_Weight points at chain 24 (2401/2402), whose
    # CollectRewards are "gold-*" -> coins (verified against ItemModelConfig.json;
    # the "g" in the chest's name does not mean gems here).
    assert_true(g.wallet.coins > coins0)
    assert_eq(g.wallet.gems, gems0)

func test_shop_loop_buy_and_refresh() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    var g := Game.fresh(1000.0, 42)
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4), Vector2i(0, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    # buy an item-shop slot with coins
    var price := int(g.shop.slots[0]["price"])
    g.wallet.add_coins(price + 100)
    assert_true(g.buy_shop_slot(1, 1000.0)["ok"])
    assert_true(g.shop.slots[0]["sold_out"])
    # dev-stub an IAP pack -> gems, then buy a gem daily deal
    g.buy_iap_pack("getgem_1", 1000.0)   # +100 gems
    assert_true(g.buy_daily_deal(1, 1000.0)["ok"])   # 25 gems
    # save/load preserves it
    SaveManager.save(g)
    var g2 := SaveManager.load_game()
    assert_not_null(g2)
    assert_true(g2.shop.slots[0]["sold_out"])

func test_campaign_smoke_deliver_then_complete_task() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 5
    g.wallet.coins = 0
    g.orders.orders = [{"items": {"203": 1}, "coins": 20, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, 1000.0)["ok"])
    assert_eq(g.wallet.coins, 20)                     # order coins earned
    assert_true(g.complete_task(2, 1000.0)["ok"])     # day-1 task 2 costs 16
    assert_eq(g.wallet.coins, 4)
    assert_eq(g.campaign.wing_progress(1), Vector2i(1, 7))
    var g2 := Game.from_dict(g.to_dict())             # quit/resume preserves it
    assert_eq(g2.wallet.coins, 4)
    assert_true(g2.campaign.is_task_done(1, 2))

func test_intimacy_smoke_orders_to_friendship() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 80, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, 1000.0)["ok"])   # 76+ coins -> 5..6 gifts
    var total := 0
    for t in Intimacy.GIFT_TYPES:
        total += int(g.intimacy.satchel[t])
    assert_between(total, 5, 6)
    var given := 0
    for t in Intimacy.GIFT_TYPES:
        while int(g.intimacy.satchel[t]) > 0 and g.give_gift("Barnaby", t, 1000.0)["ok"]:
            given += 1
    assert_gt(given, 0)
    assert_gt(int((g.intimacy.tracks["Barnaby"] as Dictionary)["points"]) + g.intimacy.level_of("Barnaby") * 48, 0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(int((g2.intimacy.tracks["Barnaby"] as Dictionary)["points"]),
            int((g.intimacy.tracks["Barnaby"] as Dictionary)["points"]))

func test_special_order_smoke() -> void:
    var g := Game.fresh(1000.0, 42)
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, 1000.0)
    assert_eq(int(g.specials.current()["Id"]), 1)
    assert_has(g.player.inventory, "1501")          # the seeded generator chain
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("1610"))
    var gems_before := g.wallet.gems
    assert_true(g.deliver_special(1000.0)["ok"])
    assert_eq(g.wallet.gems, gems_before + 15)
    var g2 := Game.from_dict(g.to_dict())           # quit/resume preserves the sequence
    assert_eq(g2.specials.next_id, 2)

func test_event_smoke_feed_merge_persist_expire() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_true(g.dev_start_event(1000.0))
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, 1000.0)["ok"])
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 1)
    g.events.board.spawn("pb_dogpark_tar_1", Vector2i(1, 13))
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), 1000.0), "")
    assert_eq(g.events.best_tier, 2)
    var g2 := Game.from_dict(g.to_dict())          # mid-event quit/resume
    assert_true(g2.events.is_active())
    assert_eq(g2.events.best_tier, 2)
    g2.tick_events(1000.0 + 604800.0)              # clock runs out
    assert_false(g2.events.is_active())
