extends GutTest

const TEST_PATH := "user://test_story_player.json"
const TEST_CORRUPT_PATH := "user://test_story_player.corrupt.json"

var _scenes_backup: Dictionary
var _trig_backup: Dictionary
var _old_base: String

func before_all() -> void:
    SaveManager.path = TEST_PATH
    SaveManager.corrupt_path = TEST_CORRUPT_PATH

func after_all() -> void:
    for p in [TEST_PATH, TEST_CORRUPT_PATH]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(p)
    SaveManager.path = "user://save.json"
    SaveManager.corrupt_path = "user://save.corrupt.json"

func before_each() -> void:
    _scenes_backup = ConfigDB.story_scenes
    _trig_backup = ConfigDB.scenes_by_trigger
    ConfigDB.story_scenes = {}
    ConfigDB.scenes_by_trigger = {}
    _old_base = HallArt.base_dir
    HallArt.base_dir = "res://nonexistent_art_dir/"
    HallArt.clear_cache()

func after_each() -> void:
    ConfigDB.story_scenes = _scenes_backup
    ConfigDB.scenes_by_trigger = _trig_backup
    HallArt.base_dir = _old_base
    HallArt.clear_cache()

func _beat(id: String, trigger: String) -> void:
    _add({"id": id, "kind": "beat", "trigger": trigger, "lines": [
        {"speaker": "cornelia", "expr": "happy", "text": "Hello."},
        {"speaker": "barnaby", "expr": "neutral", "text": "Welcome."},
        {"speaker": "nobody_known", "expr": "x", "text": "Hm."}]})

func _panel(id: String, trigger: String) -> void:
    _add({"id": id, "kind": "panel", "trigger": trigger, "panels": [{"caption": "One"}, {"caption": "Two"}]})

func _add(row: Dictionary) -> void:
    ConfigDB.story_scenes[row["id"]] = row
    if not ConfigDB.scenes_by_trigger.has(row["trigger"]):
        ConfigDB.scenes_by_trigger[row["trigger"]] = []
    ConfigDB.scenes_by_trigger[row["trigger"]].append(row["id"])

func _make() -> Array:
    var g := Game.fresh(0.0)
    g.story = Story.new()
    var p := StoryPlayer.new()
    add_child_autofree(p)
    p.setup(g)
    return [g, p]

func _boot(keep_save := false) -> Node:
    if not keep_save and FileAccess.file_exists(TEST_PATH):
        DirAccess.remove_absolute(TEST_PATH)
    var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
    add_child_autofree(main)
    await wait_process_frames(2)
    return main

func test_queue_plays_in_order_and_marks_seen() -> void:
    _beat("b1", "t:a")
    _panel("p1", "t:b")
    var gp := _make()
    var g: Game = gp[0]
    var p: StoryPlayer = gp[1]
    g.story.enqueue(["t:a", "t:b"])
    watch_signals(p)
    p.play_pending()
    assert_true(p.is_playing())
    assert_eq(p.current_scene()["id"], "b1")
    assert_false(g.story.seen.has("b1"))
    for i in 3:
        p.advance()
    assert_true(g.story.seen.has("b1"))
    assert_eq(p.current_scene()["id"], "p1")
    assert_signal_not_emitted(p, "finished")
    p.advance()
    p.advance()
    assert_true(g.story.seen.has("p1"))
    assert_false(p.is_playing())
    assert_true(g.story.queue.is_empty())
    assert_signal_emit_count(p, "finished", 1)

func test_skip_beat_marks_seen_and_continues() -> void:
    _beat("b1", "t:a")
    _panel("p1", "t:b")
    var gp := _make()
    var g: Game = gp[0]
    var p: StoryPlayer = gp[1]
    g.story.enqueue(["t:a", "t:b"])
    p.play_pending()
    (p.find_child("Skip", true, false) as Button).pressed.emit()
    assert_true(g.story.seen.has("b1"))
    assert_false(g.story.seen.has("p1"))
    assert_eq(p.current_scene()["id"], "p1")

func test_replay_leaves_queue_and_seen_alone() -> void:
    _beat("b1", "t:a")
    var gp := _make()
    var g: Game = gp[0]
    var p: StoryPlayer = gp[1]
    g.story.seen["b1"] = true
    g.story.queue.append("b1")
    watch_signals(p)
    p.play(ConfigDB.story_scenes["b1"])
    p.skip()
    assert_false(p.is_playing())
    assert_eq(g.story.queue, ["b1"])
    assert_eq(g.story.seen.keys(), ["b1"])
    assert_signal_emitted(p, "finished")

func test_missing_art_still_plays() -> void:
    _beat("b1", "t:a")
    _panel("p1", "t:b")
    var gp := _make()
    var p: StoryPlayer = gp[1]
    p.play(ConfigDB.story_scenes["b1"])
    assert_eq((p.find_child("Name", true, false) as Label).text, "Cornelia Wren")
    assert_eq((p.find_child("Text", true, false) as Label).text, "Hello.")
    assert_null(p.find_child("Portrait_cornelia", true, false))
    p.advance()
    assert_eq((p.find_child("Name", true, false) as Label).text, "Barnaby Pluck")
    p.skip()
    p.play(ConfigDB.story_scenes["p1"])
    assert_not_null(p.find_child("PanelCard", true, false))
    assert_eq((p.find_child("Text", true, false) as Label).text, "One")
    p.advance()
    assert_eq((p.find_child("Text", true, false) as Label).text, "Two")

func test_swallows_input_while_playing() -> void:
    var p: StoryPlayer = _make()[1]
    assert_false(p.visible)
    assert_eq((p.find_child("Root", true, false) as Control).mouse_filter, Control.MOUSE_FILTER_STOP)
    assert_gt(p.layer, 11)

func test_pending_pick_blocks_until_picks_done() -> void:
    _beat("b1", "t:a")
    var main := await _boot()
    var home: HomeScreen = main.home
    var g: Game = main.game
    g.story = Story.new()
    g.wallet.add_coins(1000)
    home.open_wing(1)
    var w := home.wing_view
    for i in 4:
        w.tap_element("01_001")
        (w.task_card.find_child("Complete", true, false) as Button).pressed.emit()
    assert_not_null(w.picker)
    g.story.enqueue(["t:a"])
    home.play_story()
    assert_false(home.story_player.is_playing())
    w.picker.pick(1)
    assert_true(home.story_player.is_playing())
    assert_eq(home.story_player.current_scene()["id"], "b1")

func test_back_skips_current_scene() -> void:
    _beat("b1", "t:a")
    _panel("p1", "t:b")
    var main := await _boot()
    var home: HomeScreen = main.home
    var g: Game = main.game
    g.story = Story.new()
    g.story.enqueue(["t:a", "t:b"])
    home.play_story()
    assert_true(home.go_back())
    assert_true(g.story.seen.has("b1"))
    assert_true(home.story_player.is_playing())
    assert_eq(home.current_screen(), "home")
    assert_true(home.go_back())
    assert_false(home.story_player.is_playing())
    assert_eq(home.current_screen(), "home")

func test_chronicle_lists_and_replays_seen_scenes() -> void:
    _beat("b1", "t:a")
    _panel("p1", "t:b")
    var main := await _boot()
    var home: HomeScreen = main.home
    var g: Game = main.game
    g.story = Story.new()
    g.story.seen["b1"] = true
    home.chronicle_panel.open()
    await wait_process_frames(2)
    assert_not_null(home.chronicle_panel.find_child("Scene_b1", true, false))
    assert_null(home.chronicle_panel.find_child("Scene_p1", true, false))
    (home.chronicle_panel.find_child("Scene_b1", true, false) as Button).pressed.emit()
    assert_true(home.story_player.is_playing())
    home.story_player.skip()
    assert_eq(g.story.seen.keys(), ["b1"])
    assert_true(g.story.queue.is_empty())

func _play_all(home: HomeScreen) -> Array:
    var order: Array = []
    var guard := 0
    while home.story_player.is_playing() and guard < 50:
        guard += 1
        var id := String(home.story_player.current_scene()["id"])
        if order.is_empty() or order[-1] != id:
            order.append(id)
        home.story_player.advance()
    return order

func test_pending_pick_survives_save_and_blocks_boot() -> void:
    _beat("b1", "t:a")
    var g := Game.fresh(0.0)
    g.wallet.add_coins(1000)
    for id in [1, 2, 3, 4]:
        g.complete_task(id, 0.0)
    assert_eq(g.hall.pending_pick, ["01_001"])
    g.story = Story.new()
    g.story.enqueue(["t:a"])
    SaveManager.save(g)
    var main := await _boot(true)
    var home: HomeScreen = main.home
    await wait_process_frames(2)
    assert_eq(home.game.hall.pending_pick, ["01_001"])
    assert_false(home.story_player.is_playing())
    home.open_wing(1)
    assert_not_null(home.wing_view.picker)
    assert_false(home.story_player.is_playing())
    home.wing_view.picker.pick(0)
    assert_true(home.story_player.is_playing())
    assert_eq(home.story_player.current_scene()["id"], "b1")

func test_day_one_finale_plays_after_pick_in_order() -> void:
    _beat("s_task", "task:1_7")
    _beat("s_el", "element:01_002")
    _beat("s_day", "day:2")
    _beat("s_area", "area_opened:2")
    var main := await _boot()
    var home: HomeScreen = main.home
    var g: Game = main.game
    g.story = Story.new()
    g.wallet.add_coins(5000)
    for id in [1, 2, 3, 4]:
        g.complete_task(id, 0.0)
    g.pick_look("01_001", 0)
    for id in [5, 6]:
        g.complete_task(id, 0.0)
    assert_true(g.story.queue.is_empty())
    var res := g.complete_task(7, 0.0)
    assert_true(res["ok"])
    assert_eq(g.story.queue, ["s_task", "s_el", "s_day", "s_area"])
    home.open_wing(1)
    await wait_process_frames(2)
    assert_not_null(home.wing_view.picker)
    assert_false(home.story_player.is_playing())
    home.wing_view.picker.pick(1)
    assert_eq(_play_all(home), ["s_task", "s_el", "s_day", "s_area"])
    assert_true(g.story.queue.is_empty())
    assert_eq(g.story.seen.size(), 4)

func test_task_without_element_plays_after_completion() -> void:
    _beat("s_task", "task:1_1")
    var main := await _boot()
    var home: HomeScreen = main.home
    var g: Game = main.game
    g.story = Story.new()
    g.wallet.add_coins(1000)
    home.open_wing(1)
    var w := home.wing_view
    w.tap_element("01_001")
    (w.task_card.find_child("Complete", true, false) as Button).pressed.emit()
    await wait_process_frames(2)
    assert_true(home.story_player.is_playing())
    assert_eq(home.story_player.current_scene()["id"], "s_task")
    assert_eq(_play_all(home), ["s_task"])
    assert_eq(g.story.seen.keys(), ["s_task"])

func test_boot_with_pending_pick_in_old_wing_opens_it() -> void:
    _beat("s_day", "day:2")
    var g := Game.fresh(0.0)
    g.wallet.add_coins(5000)
    for id in [1, 2, 3, 4]:
        g.complete_task(id, 0.0)
    g.pick_look("01_001", 0)
    for id in [5, 6, 7]:
        g.complete_task(id, 0.0)
    assert_eq(g.hall.pending_pick, ["01_002"])
    assert_ne(g.campaign.current_area(), 1)
    g.story = Story.new()
    g.story.enqueue(["day:2"])
    SaveManager.save(g)
    var main := await _boot(true)
    var home: HomeScreen = main.home
    await wait_process_frames(2)
    assert_eq(home.current_screen(), "wing")
    assert_eq(home.wing_area, 1)
    assert_not_null(home.wing_view.picker)
    assert_false(home.story_player.is_playing())
    home.wing_view.picker.pick(0)
    assert_true(home.story_player.is_playing())
    assert_eq(home.story_player.current_scene()["id"], "s_day")
