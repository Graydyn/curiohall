extends GutTest

const TEST_PATH := "user://test_save.json"
const TEST_CORRUPT_PATH := "user://test_save.corrupt.json"
const DEFAULT_PATH := "user://save.json"
const DEFAULT_CORRUPT_PATH := "user://save.corrupt.json"

func before_all() -> void:
    SaveManager.path = TEST_PATH
    SaveManager.corrupt_path = TEST_CORRUPT_PATH

func before_each() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    if FileAccess.file_exists(SaveManager.corrupt_path):
        DirAccess.remove_absolute(SaveManager.corrupt_path)

func after_all() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    if FileAccess.file_exists(SaveManager.corrupt_path):
        DirAccess.remove_absolute(SaveManager.corrupt_path)
    SaveManager.path = DEFAULT_PATH
    SaveManager.corrupt_path = DEFAULT_CORRUPT_PATH

func test_game_round_trip_preserves_board_wallet_player() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.spend_energy(5, 1000.0)
    g.wallet.add_coins(7)
    g.player.add_xp(3)
    # Free cell at (3,4) and place "203" there
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203", 1000.0))
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.wallet.energy(1000.0), 95)
    assert_eq(g2.wallet.coins, 7)
    assert_eq(g2.player.xp, 3)
    assert_eq(g2.board.count_of("203"), g.board.count_of("203"))
    assert_eq(g2.board.state_at(Vector2i(0, 0)), MergeBoard.CellState.BOXED)

func test_offline_energy_accrual() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.spend_energy(50, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.wallet.energy(1000.0 + 120.0 * 10), 60)
    assert_eq(g2.wallet.energy(1000.0 + 120.0 * 10000), 100)

func test_generator_state_survives_save() -> void:
    var g := Game.fresh(1000.0, 42)
    # Free cell at (6,8) and an adjacent cell for the tap's drop
    var pos := Vector2i(6, 8)
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make("104", 1000.0))
    # Free an adjacent cell for the tap's drop
    var adjacent := pos + Vector2i.LEFT
    if g.board.item_at(adjacent) != null:
        g.board.remove(adjacent)
        g.board.set_state(adjacent, MergeBoard.CellState.OPEN)
    g.tap_generator(pos, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.board.item_at(pos).gen.charges(1000.0), 79)

func test_save_and_load_file() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.add_coins(9)
    SaveManager.save(g)
    var g2 := SaveManager.load_game()
    assert_not_null(g2)
    assert_eq(g2.wallet.coins, 9)

func test_corrupt_save_backed_up() -> void:
    var f := FileAccess.open(SaveManager.path, FileAccess.WRITE)
    f.store_string("{not json")
    f.close()
    assert_null(SaveManager.load_game())
    assert_true(FileAccess.file_exists(SaveManager.corrupt_path))

func test_structurally_invalid_save_backed_up() -> void:
    var f := FileAccess.open(SaveManager.path, FileAccess.WRITE)
    f.store_string('{"save_version":1}')
    f.close()
    assert_null(SaveManager.load_game())
    assert_true(FileAccess.file_exists(SaveManager.corrupt_path))

func test_v3_save_missing_shop_key_backed_up() -> void:
    var g := Game.fresh(1000.0, 42)
    var data := g.to_dict()
    data.erase("shop")
    var f := FileAccess.open(SaveManager.path, FileAccess.WRITE)
    f.store_string(JSON.stringify(data))
    f.close()
    assert_null(SaveManager.load_game())
    assert_true(FileAccess.file_exists(SaveManager.corrupt_path))

func test_v9_roundtrip_campaign() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.coins = 50
    g.complete_task(2, 1000.0)   # day-1 task 2, cost 16
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.wallet.coins, 34)
    assert_eq(g2.campaign.day, 1)
    assert_true(g2.campaign.is_task_done(1, 2))

func test_save_version_is_10_and_campaign_key_present() -> void:
    var g := Game.fresh(1000.0, 42)
    var d := g.to_dict()
    assert_eq(int(d["save_version"]), 10)
    assert_true(d.has("campaign"))

func test_v6_roundtrip_intimacy() -> void:
    var g := Game.fresh(1000.0, 42)
    g.intimacy.satchel["watch"] = 2
    g.give_gift("Cornelia", "watch", 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(int(g2.intimacy.satchel["watch"]), 1)
    assert_eq(int((g2.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 12)
    assert_true(g2.to_dict().has("intimacy"))

func test_v7_roundtrip_specials() -> void:
    var g := Game.fresh(1000.0, 42)
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.specials.active)
    assert_eq(g2.specials.next_id, 1)
    assert_true(g2.to_dict().has("specials"))

func test_v8_roundtrip_return_gift() -> void:
    var g := Game.fresh(1000.0, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.intimacy.maybe_refresh_return_gift(90000.0, g.rng)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.intimacy.gift_source, "Barnaby")
    assert_eq(g2.intimacy.gift_refreshed_at, 90000.0)

func test_v9_roundtrip_event_board() -> void:
    var g := Game.fresh(1000.0, 42)
    g.dev_start_event(1000.0)
    g.events.board.spawn("pb_dogpark_tar_1", Vector2i(0, 13))
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.events.is_active())
    assert_eq(g2.events.board.height, 14)
    assert_eq(g2.events.board.count_of("pb_dogpark_tar_1"), 1)
