extends GutTest
## Game owns a Boost sibling to Events: fresh/save/load, tick host seam,
## dev controls, and deliver_order feeding the ladder (both tracks at once).

const NOW := 1000.0

func _deliverable_game() -> Game:
    var g := Game.fresh(NOW, 42)
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    return g

func test_fresh_game_has_idle_boost() -> void:
    var g := Game.fresh(NOW, 42)
    assert_not_null(g.boost)
    assert_false(g.boost.is_active())

func test_tick_boost_and_dev_controls() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 8
    g.tick_boost(NOW)
    assert_true(g.boost.is_active())
    g.dev_end_boost(NOW)
    assert_false(g.boost.is_active())
    assert_true(g.dev_start_boost(NOW))
    assert_true(g.boost.is_active())

func test_deliver_order_feeds_ladder_only_while_active() -> void:
    var g := _deliverable_game()
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.boost.progress, 0)          # IDLE: no progress
    g.dev_start_boost(NOW)
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.boost.progress, 1)

func test_both_tracks_active_at_once() -> void:
    var g := _deliverable_game()
    g.dev_start_boost(NOW)
    assert_true(g.dev_start_event(NOW))
    assert_true(g.boost.is_active())
    assert_true(g.events.is_active())
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.boost.progress, 1)                              # ladder fed
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 1)   # supply row fed

func test_game_save_roundtrip_includes_boost() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_boost(NOW)
    g.boost.progress = 2
    g.boost.buff_level = 1
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.boost.is_active())
    assert_eq(g2.boost.progress, 2)
    assert_eq(g2.boost.buff_level, 1)
    assert_eq(int(g.to_dict()["save_version"]), 10)
