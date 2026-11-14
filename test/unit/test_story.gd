extends GutTest

const TEST_PATH := "user://test_save.json"
const TEST_CORRUPT_PATH := "user://test_save.corrupt.json"

var _scenes_backup: Dictionary
var _trig_backup: Dictionary

func before_all() -> void:
    SaveManager.path = TEST_PATH
    SaveManager.corrupt_path = TEST_CORRUPT_PATH

func after_all() -> void:
    _clean()
    SaveManager.path = "user://save.json"
    SaveManager.corrupt_path = "user://save.corrupt.json"

func _clean() -> void:
    for p in [TEST_PATH, TEST_CORRUPT_PATH]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(p)

func before_each() -> void:
    _clean()
    _scenes_backup = ConfigDB.story_scenes
    _trig_backup = ConfigDB.scenes_by_trigger
    ConfigDB.story_scenes = {}
    ConfigDB.scenes_by_trigger = {}

func after_each() -> void:
    ConfigDB.story_scenes = _scenes_backup
    ConfigDB.scenes_by_trigger = _trig_backup

func _add(id: String, trigger: String) -> void:
    ConfigDB.story_scenes[id] = {"id": id, "kind": "dialogue", "trigger": trigger, "lines": []}
    if not ConfigDB.scenes_by_trigger.has(trigger):
        ConfigDB.scenes_by_trigger[trigger] = []
    ConfigDB.scenes_by_trigger[trigger].append(id)

func _game() -> Game:
    var g := Game.fresh(1000.0, 42)
    g.wallet.coins = 1000
    return g

func test_task_then_element_order() -> void:
    _add("s_el", "element:01_001")
    _add("s_task", "task:1_4")
    var g := _game()
    for id in [1, 2, 3, 4]:
        g.complete_task(id, 1000.0)
    assert_eq(g.story.queue, ["s_task", "s_el"])

func test_element_day_area_order() -> void:
    _add("s_area", "area_opened:2")
    _add("s_day", "day:2")
    _add("s_el", "element:01_002")
    var g := _game()
    for id in [1, 2, 3, 4, 5, 6, 7]:
        g.complete_task(id, 1000.0)
    assert_eq(g.story.queue, ["s_el", "s_day", "s_area"])

func test_no_duplicate_enqueue() -> void:
    _add("a", "t")
    var s := Story.new()
    s.enqueue(["t"])
    s.enqueue(["t"])
    assert_eq(s.queue, ["a"])

func test_finish_marks_seen() -> void:
    _add("a", "t")
    _add("b", "u")
    var s := Story.new()
    watch_signals(s)
    s.enqueue(["t", "u"])
    assert_signal_emit_count(s, "scene_queued", 2)
    assert_true(s.has_pending())
    assert_eq(s.peek()["id"], "a")
    s.finish_current()
    assert_true(s.seen.has("a"))
    s.enqueue(["t"])
    assert_eq(s.queue, ["b"])
    s.finish_current()
    assert_false(s.has_pending())
    assert_eq(s.peek(), {})
    assert_eq(s.replayable().size(), 2)
    assert_eq(s.replayable()[0]["id"], "a")

func test_save_round_trip() -> void:
    _add("a", "t")
    _add("b", "u")
    var g := _game()
    g.story.enqueue(["t", "u"])
    g.story.finish_current()
    SaveManager.save(g)
    var g2 := SaveManager.load_game()
    assert_not_null(g2)
    assert_eq(g2.story.queue, ["b"])
    assert_true(g2.story.seen.has("a"))

func test_from_dict_prunes_unknown_seen_and_duplicates() -> void:
    _add("a", "t")
    _add("b", "u")
    var s := Story.from_dict({"seen": ["b"], "queue": ["ghost", "a", "a", "b"]})
    assert_eq(s.queue, ["a"])

func test_stale_scene_dropped_by_peek_and_has_pending() -> void:
    _add("a", "t")
    _add("b", "u")
    var s := Story.new()
    s.enqueue(["t", "u"])
    ConfigDB.story_scenes.erase("a")
    assert_eq(s.peek()["id"], "b")
    ConfigDB.story_scenes.erase("b")
    assert_false(s.has_pending())
    assert_eq(s.peek(), {})

func test_all_four_triggers_in_order() -> void:
    _add("s_area", "area_opened:2")
    _add("s_day", "day:2")
    _add("s_el", "element:01_002")
    _add("s_task", "task:1_7")
    var g := _game()
    for id in [1, 2, 3, 4, 5, 6, 7]:
        g.complete_task(id, 1000.0)
    assert_eq(g.story.queue, ["s_task", "s_el", "s_day", "s_area"])

func test_fresh_queues_area_one() -> void:
    _add("intro", "area_opened:1")
    var g := _game()
    assert_eq(g.story.queue, ["intro"])
