extends GutTest

func test_parse_entries() -> void:
	var parsed := Weighted.parse(["201-100", "202-2"])
	assert_eq(parsed.size(), 2)
	assert_eq(parsed[0]["id"], "201")
	assert_eq(parsed[0]["weight"], 100)

func test_roll_is_deterministic_with_seed() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var parsed := Weighted.parse(["201-100"])
	assert_eq(Weighted.roll(parsed, rng), "201")

func test_roll_distribution_respects_weights() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var parsed := Weighted.parse(["a-90", "b-10"])
	var counts := {"a": 0, "b": 0}
	for i in range(1000):
		counts[Weighted.roll(parsed, rng)] += 1
	assert_gt(counts["a"], 700)
	assert_gt(counts["b"], 20)
