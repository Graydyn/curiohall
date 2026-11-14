extends GutTest

const TEST_PATH := "user://test_save.json"
const TEST_CORRUPT_PATH := "user://test_save.corrupt.json"
const DEFAULT_PATH := "user://save.json"
const DEFAULT_CORRUPT_PATH := "user://save.corrupt.json"

func before_all() -> void:
    SaveManager.path = TEST_PATH
    SaveManager.corrupt_path = TEST_CORRUPT_PATH

func before_each() -> void:
    _clean()

func after_all() -> void:
    _clean()
    SaveManager.path = DEFAULT_PATH
    SaveManager.corrupt_path = DEFAULT_CORRUPT_PATH

func _clean() -> void:
    for p in [SaveManager.path, SaveManager.corrupt_path]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(p)

func _game() -> Game:
    var g := Game.fresh(1000.0, 42)
    g.wallet.coins = 1000
    return g

func _finish_first(g: Game) -> Dictionary:
    var res := {}
    for id in [1, 2, 3, 4]:
        res = g.complete_task(id, 1000.0)
    return res

func test_stage_follows_campaign_done() -> void:
    var g := _game()
    assert_eq(HallElements.stage("01_001", g.campaign), HallElements.Stage.OUTLINE)
    g.complete_task(1, 1000.0)
    assert_eq(HallElements.stage("01_001", g.campaign), HallElements.Stage.IN_PROGRESS)
    assert_eq(HallElements.progress("01_001", g.campaign), Vector2i(1, 4))
    assert_eq(HallElements.next_task("01_001", g.campaign), "1_2")

func test_workable_of_task_and_in_area() -> void:
    var g := _game()
    assert_true(HallElements.is_workable("01_001", g.campaign))
    assert_eq(HallElements.of_task("1_5"), "01_002")
    assert_eq(HallElements.of_task("nope"), "")
    _finish_first(g)
    assert_eq(HallElements.next_task("01_001", g.campaign), "")
    assert_false(HallElements.is_workable("01_001", g.campaign))
    assert_true(HallElements.is_workable("01_002", g.campaign))
    assert_eq(HallElements.stage("01_001", g.campaign), HallElements.Stage.DONE)
    var ids := []
    for row in HallElements.in_area(1):
        ids.append(row["id"])
    assert_true(ids.has("01_001") and ids.has("01_002"))

func test_finishing_element_queues_mandatory_pick() -> void:
    var g := _game()
    watch_signals(g.hall)
    for id in [1, 2, 3]:
        var mid: Dictionary = g.complete_task(id, 1000.0)
        assert_false(mid.has("element"))
    var res: Dictionary = g.complete_task(4, 1000.0)
    assert_eq(res["element"], "01_001")
    assert_signal_emitted_with_parameters(g.hall, "element_finished", ["01_001"])
    assert_eq(g.hall.pending_pick, ["01_001"])
    assert_eq(g.hall.pending_in_area(1), ["01_001"])
    assert_eq(g.hall.look_of("01_001"), 0)

func test_pick_look_rules() -> void:
    var g := _game()
    assert_eq(g.pick_look("zz", 0)["reason"], "unknown_element")
    assert_eq(g.pick_look("01_002", 0)["reason"], "not_done")
    _finish_first(g)
    assert_eq(g.pick_look("01_001", 3)["reason"], "bad_look")
    assert_eq(g.pick_look("01_001", -1)["reason"], "bad_look")
    assert_eq(g.hall.pending_pick, ["01_001"])
    watch_signals(g.hall)
    assert_true(g.pick_look("01_001", 2)["ok"])
    assert_signal_emitted_with_parameters(g.hall, "look_changed", ["01_001", 2])
    assert_eq(g.hall.pending_pick, [])
    assert_eq(g.hall.look_of("01_001"), 2)
    assert_true(g.pick_look("01_001", 1)["ok"])
    assert_eq(g.hall.look_of("01_001"), 1)

func test_pending_pick_survives_save_round_trip() -> void:
    var g := _game()
    _finish_first(g)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.hall.pending_pick, ["01_001"])
    g2.pick_look("01_001", 2)
    var g3 := Game.from_dict(g2.to_dict())
    assert_eq(g3.hall.look_of("01_001"), 2)
    assert_eq(g3.hall.pending_pick, [])

func test_v10_save_resets() -> void:
    var d := Game.fresh(1000.0, 42).to_dict()
    d["save_version"] = 10
    var f := FileAccess.open(SaveManager.path, FileAccess.WRITE)
    f.store_string(JSON.stringify(d))
    f.close()
    assert_null(SaveManager.load_game())
    assert_true(FileAccess.file_exists(SaveManager.corrupt_path))
