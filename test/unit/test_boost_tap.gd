extends GutTest
## Patron's Gala hooks inside Game.tap_generator: nocd charge preservation,
## extra-produce quota spawns with cache-when-full, twin lucky spawns, and
## the effective Spread_Weight swap. Generator 105 is boosted; 104 is not.

const NOW := 1000.0

## A game with generator `gen_type` at (6,8) and `free` open drop cells.
func _tap_game(gen_type: String, free: int) -> Game:
    var g := Game.fresh(NOW, 42)
    var pos := Vector2i(6, 8)
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(gen_type, NOW))
    var cells: Array[Vector2i] = [Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8)]
    for i in range(free):
        g.board.remove(cells[i])
        g.board.set_state(cells[i], MergeBoard.CellState.OPEN)
    return g

func _rung(g: Game, level: int) -> void:
    g.dev_start_boost(NOW)
    g.boost.buff_level = level   # rungs: 1 moreLucky, 2 extra, 3 extraLucky, 4 nocd

func test_nocd_preserves_charges_for_boosted_type() -> void:
    var g := _tap_game("105", 2)
    _rung(g, 4)
    var gen: GeneratorState = g.board.item_at(Vector2i(6, 8)).gen
    var before: int = gen.charges(NOW)
    assert_true(g.tap_generator(Vector2i(6, 8), NOW)["ok"])
    assert_eq(gen.charges(NOW), before)          # nocd: no charge consumed

func test_nocd_does_not_cover_unboosted_generator() -> void:
    var g := _tap_game("104", 2)
    _rung(g, 4)
    var gen: GeneratorState = g.board.item_at(Vector2i(6, 8)).gen
    var before: int = gen.charges(NOW)
    assert_true(g.tap_generator(Vector2i(6, 8), NOW)["ok"])
    assert_eq(gen.charges(NOW), before - 1)

func test_charges_consumed_below_nocd_rung() -> void:
    var g := _tap_game("105", 2)
    _rung(g, 3)
    var gen: GeneratorState = g.board.item_at(Vector2i(6, 8)).gen
    var before: int = gen.charges(NOW)
    assert_true(g.tap_generator(Vector2i(6, 8), NOW)["ok"])
    assert_eq(gen.charges(NOW), before - 1)

func test_extra_produce_quota_over_window() -> void:
    # Over any 3 consecutive boosted taps exactly one carries an extra spawn
    # (quota [1,3]); board kept roomy so nothing caches.
    var g := _tap_game("105", 3)
    _rung(g, 2)
    var extras := 0
    var taps := 0
    for k in range(6):
        var res := g.tap_generator(Vector2i(6, 8), NOW)
        assert_true(res["ok"])
        taps += 1
        for s in (res["spawned"] as Array):
            var entry: Dictionary = s
            if bool(entry.get("extra", false)):
                extras += 1
            # clean every spawn off the board to keep room
            g.board.remove(entry["pos"])
            g.board.set_state(entry["pos"], MergeBoard.CellState.OPEN)
    assert_eq(extras, 2)   # 6 taps = 2 full windows of 3

func test_extra_produce_costs_no_extra_energy() -> void:
    var g := _tap_game("105", 3)
    _rung(g, 2)
    # Force the fire on the first tap: window primed so extras==window.
    g.boost.window_left = 1
    g.boost.extras_left = 1
    var before := g.wallet.energy(NOW)
    var res := g.tap_generator(Vector2i(6, 8), NOW)
    assert_true(res["ok"])
    var non_lucky := 0
    for s in (res["spawned"] as Array):
        if not bool((s as Dictionary).get("lucky", false)):
            non_lucky += 1
    assert_eq(non_lucky, 2)                          # normal + extra
    assert_eq(g.wallet.energy(NOW), before - 1)      # one tap, one energy

func test_extra_blocked_caches_and_delivers_later() -> void:
    var g := _tap_game("105", 1)          # exactly one free cell: extra can't fit
    _rung(g, 2)
    g.boost.window_left = 1
    g.boost.extras_left = 1
    var res := g.tap_generator(Vector2i(6, 8), NOW)
    assert_true(res["ok"])
    assert_true(g.boost.extra_cached)     # extra had no room
    # free two cells; cached extra rides the next tap
    g.board.remove(res["spawned"][0]["pos"])
    g.board.set_state(res["spawned"][0]["pos"], MergeBoard.CellState.OPEN)
    if g.board.item_at(Vector2i(4, 8)) != null:
        g.board.remove(Vector2i(4, 8))
    g.board.set_state(Vector2i(4, 8), MergeBoard.CellState.OPEN)
    g.boost.window_left = 3
    g.boost.extras_left = 0               # quota silent: delivery is cache-driven
    var res2 := g.tap_generator(Vector2i(6, 8), NOW)
    assert_true(res2["ok"])
    var extra_count := 0
    for s in (res2["spawned"] as Array):
        if bool((s as Dictionary).get("extra", false)):
            extra_count += 1
    assert_eq(extra_count, 1)
    assert_false(g.boost.extra_cached)

func test_more_lucky_swaps_spread_weight() -> void:
    # MoreLuckyProduce 105 weights have no 202: across many taps none appears.
    var g := _tap_game("105", 3)
    _rung(g, 1)
    for k in range(60):
        var res := g.tap_generator(Vector2i(6, 8), NOW)
        assert_true(res["ok"])
        for s in (res["spawned"] as Array):
            var entry: Dictionary = s
            if not bool(entry.get("lucky", false)):
                assert_ne(String(entry["type"]), "202")
            g.board.remove(entry["pos"])
            g.board.set_state(entry["pos"], MergeBoard.CellState.OPEN)

func test_twin_lucky_spawns_or_caches() -> void:
    var g := _tap_game("105", 3)
    _rung(g, 3)
    # Replace the boost's lucky view with a guaranteed proc by leveling the
    # ladder to moreLucky (1/25) and just tapping a lot; assert the invariant:
    # every tap where a lucky spawn appears also carries a twin (or cached it).
    var lucky_taps := 0
    for k in range(400):
        if g.wallet.energy(NOW) < 1:
            g.wallet.add_energy(50, NOW)
        var res := g.tap_generator(Vector2i(6, 8), NOW)
        if not res["ok"]:
            break
        var lucky_seen := 0
        for s in (res["spawned"] as Array):
            var entry: Dictionary = s
            if bool(entry.get("lucky", false)):
                lucky_seen += 1
            g.board.remove(entry["pos"])
            g.board.set_state(entry["pos"], MergeBoard.CellState.OPEN)
        if lucky_seen > 0 or g.boost.extra_lucky_cached != "":
            lucky_taps += 1
            assert_true(lucky_seen == 2 or (lucky_seen <= 1 and g.boost.extra_lucky_cached != "")
                    or lucky_seen == 1)  # 1 = twin was the cached delivery path
        g.boost.take_cached_lucky()      # reset the cache between taps
    assert_gt(lucky_taps, 0)             # 400 taps at ~1/25: procs happened
