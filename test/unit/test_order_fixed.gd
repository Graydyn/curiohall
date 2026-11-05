extends GutTest
## Fixed tutorial orders (OrderFixedConfig): the   early-game bootstrap.
## Ids 1-4 unlock at level 1 in slot 1 only; 5+ open up more slots/levels.
## Item 203 has Price 2 / DiffScore 2 in OrderItemConfig.

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng

func test_order_fixed_config_loaded_in_id_order() -> void:
	assert_eq(ConfigDB.order_fixed.size(), 16)
	for i in range(ConfigDB.order_fixed.size()):
		assert_eq(int(ConfigDB.order_fixed[i]["Id"]), i + 1)

func test_fill_at_level_1_places_first_fixed_order_only() -> void:
	var ob := OrderBook.new()
	ob.fill(1, _rng(), 0.0)
	var o: Variant = ob.orders[0]
	assert_not_null(o)
	assert_eq(o["items"], {"203": 1})
	assert_true(bool(o["fixed"]))
	assert_null(ob.orders[1])   # ids 1-4 allow slot 1 only; randoms locked below level 3
	assert_null(ob.orders[2])
	assert_eq(ob.next_fixed, 1)

func test_fill_is_idempotent_while_fixed_order_pending() -> void:
	var ob := OrderBook.new()
	ob.fill(1, _rng(), 0.0)
	ob.fill(1, _rng(), 0.0)
	assert_eq(ob.next_fixed, 1)
	assert_eq(ob.orders[0]["items"], {"203": 1})

func test_deliver_fixed_pays_config_price_and_next_fills() -> void:
	var ob := OrderBook.new()
	ob.fill(1, _rng(), 0.0)
	var board := MergeBoard.new()
	board.place(Vector2i(0, 0), ItemInstance.make("203"))
	var res: Dictionary = ob.deliver(0, board)
	assert_true(res["ok"])
	assert_eq(int(res["coins"]), 2)
	assert_eq(int(res["xp"]), 2)
	assert_eq(int(res["refresh_time"]), 0)   # fixed orders have no cooldown
	ob.fill(1, _rng(), 0.0)
	assert_eq(ob.orders[0]["items"], {"208": 1})   # id 2 takes the slot
	assert_eq(ob.next_fixed, 2)

func test_fixed_orders_gate_on_unlock_level() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = 4   # id 5 is next; it unlocks at level 2
	ob.fill(1, _rng(), 0.0)
	assert_null(ob.orders[0])
	assert_eq(ob.next_fixed, 4)
	ob.fill(2, _rng(), 0.0)
	assert_eq(ob.orders[0]["items"], {"304": 1})
	assert_eq(ob.next_fixed, 6)   # ids 5 AND 6 both unlock at level 2 (slots 1-2)

func test_duplicate_requirements_accumulate() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = 10   # id 11: Requirement1 and Requirement2 both "504"
	ob.fill(3, _rng(), 0.0)
	assert_eq(ob.orders[0]["items"], {"504": 2})

func test_two_fixed_orders_at_level_2_use_both_slots() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = 4   # ids 5 and 6 both allow slots [1, 2] at level 2
	ob.fill(2, _rng(), 0.0)
	assert_eq(ob.orders[0]["items"], {"304": 1})
	assert_eq(ob.orders[1]["items"], {"303": 1})
	assert_eq(ob.next_fixed, 6)

func test_random_orders_fill_remaining_slots_after_fixed() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = 15   # id 16 unlocks at level 4, slots [1, 2]
	ob.fill(5, _rng(), 0.0)
	assert_true(bool(ob.orders[0].get("fixed", false)))
	assert_eq(ob.next_fixed, 16)
	assert_not_null(ob.orders[1])   # randoms are eligible at level 5
	assert_false(bool(ob.orders[1].get("fixed", false)))
	assert_not_null(ob.orders[2])

func test_next_fixed_survives_roundtrip() -> void:
	var ob := OrderBook.new()
	ob.fill(1, _rng(), 0.0)
	var ob2 := OrderBook.from_dict(ob.to_dict())
	assert_eq(ob2.next_fixed, 1)
	assert_eq(ob2.orders[0]["items"], {"203": 1})

func test_level_1_reward_grants_the_104_generator() -> void:
	var g := Game.fresh(1000.0, 42)
	var rewards: Array = ConfigDB.levels[0].get("rewards", [])
	assert_has(rewards, "104-1")
	g.grant_xp(int(ConfigDB.levels[0]["cost"]), 1000.0)   # complete level 1
	assert_eq(g.player.level, 2)
	var got_104 := g.player.inventory.has("104")
	for y in range(MergeBoard.HEIGHT):
		for x in range(MergeBoard.WIDTH):
			var item := g.board.item_at(Vector2i(x, y))
			if item != null and item.type == "104":
				got_104 = true
				assert_not_null(item.gen)   # 104 is a working generator
	assert_true(got_104, "level-1 reward should place a 104 generator on board or inventory")

func _allowed_avatars(level: int) -> Array:
	var normals_v: Variant = ConfigDB.order_avatars.get("NormalAvatars")
	var normals: Array = normals_v if normals_v is Array else []
	var out: Array = []
	for row in normals:
		if level >= int(row.get("UnlockLevel", 1)):
			out.append(String(row["Avatar"]))
	return out

func test_fixed_orders_carry_level_gated_avatar() -> void:
	var ob := OrderBook.new()
	ob.fill(1, _rng(), 0.0)
	var o: Dictionary = ob.orders[0]
	assert_true(o.has("avatar"))
	assert_has(_allowed_avatars(1), String(o["avatar"]))

func test_random_orders_carry_level_gated_avatar() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = ConfigDB.order_fixed.size()
	ob.fill(5, _rng(), 0.0)
	for o in ob.orders:
		assert_not_null(o)
		assert_has(_allowed_avatars(5), String(o["avatar"]))

func test_avatar_roll_is_deterministic_under_seed() -> void:
	var a := OrderBook.new()
	var b := OrderBook.new()
	a.fill(1, _rng(), 0.0)
	b.fill(1, _rng(), 0.0)
	assert_eq(String(a.orders[0]["avatar"]), String(b.orders[0]["avatar"]))
