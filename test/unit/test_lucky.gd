extends GutTest

func test_roll_matches_config_row_for_105() -> void:
    # Config: generators 105/106, lucky_chance [60, 1], items 204/205/303/304/305.
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    var allowed := ["204", "205", "303", "304", "305"]
    var hits := 0
    for i in range(6000):
        var got := LuckyRoller.roll("105", 1, rng)
        if got != "":
            hits += 1
            assert_has(allowed, got)
    # Expected rate 1/60: 6000 rolls should land near 100 hits.
    assert_between(hits, 50, 200)

func test_unlisted_generator_never_rolls() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    for i in range(200):
        assert_eq(LuckyRoller.roll("101", 1, rng), "")

func test_level_bracket_respected() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    for i in range(200):
        assert_eq(LuckyRoller.roll("105", -5, rng), "")

func test_explicit_table_overrides_base() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    var table: Array = [{"generator": ["105"], "lucky_chance": [1, 1],
            "lucky_items": ["999-1"], "level_min": 1, "level_max": 999}]
    assert_eq(LuckyRoller.roll("105", 1, rng, table), "999")
    var base_got := LuckyRoller.roll("105", 1, rng)
    assert_true(base_got != "999")   # base table never yields 999
