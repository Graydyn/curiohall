extends GutTest

func _rng() -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new(); r.seed = 7; return r

func test_delivered_slot_enters_cooldown_then_refreshes() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = ConfigDB.order_fixed.size()   # isolate random-order cooldowns from tutorial orders
	ob.fill(5, _rng(), 1000.0)
	assert_not_null(ob.orders[0])
	var rt := int(ob.orders[0]["refresh_time"])
	assert_gt(rt, 0)
	var board := MergeBoard.new()
	for code in ob.orders[0]["items"]:
		for i in range(int(ob.orders[0]["items"][code])):
			board.place(Vector2i(i, 0), ItemInstance.make(code))
		# ensure enough copies
	# deliver slot 0
	ob.deliver(0, board)
	ob.set_cooldown(0, rt, 1000.0)
	assert_true(ob.is_cooling(0, 1000.0))
	ob.fill(5, _rng(), 1000.0)                 # too soon: stays empty
	assert_null(ob.orders[0])
	ob.fill(5, _rng(), 1000.0 + rt)            # cooldown elapsed: refills
	assert_not_null(ob.orders[0])

func test_skip_refresh_spends_gems_and_refills() -> void:
	var ob := OrderBook.new()
	ob.refresh_at = [1000.0 + 9999.0, 0.0, 0.0]  # slot 0 cooling far out
	ob.orders = [null, null, null]
	var w := EnergyWallet.fresh(1000.0); w.add_gems(100)
	assert_true(ob.skip_refresh(0, w, 1000.0))
	assert_eq(w.gems, 100 - int(ConfigDB.tuning["order_skip_gems"]))
	ob.fill(5, _rng(), 1000.0)
	assert_not_null(ob.orders[0])

func test_eligible_types_respect_level_and_refresh_floor() -> void:
	var ob := OrderBook.new()
	var elig: Array = ob._eligible_types(3)   # level 3: types 1,2 unlock (refresh>=60)
	var nums: Array = elig.map(func(r): return int(r["Type"]))
	assert_true(nums.has(1) and nums.has(2))
	assert_false(nums.has(15))          # refresh 1 -> excluded
	assert_false(nums.has(4))           # unlock 5 -> not yet at level 3

func test_order_item_tiers_respect_filter_caps() -> void:
	var ob := OrderBook.new()
	ob.fill(3, _rng(), 1000.0)
	# Type-1/2 filters cap tiers; every requested item's tier must be <= 8 here
	for slot in ob.orders:
		if slot == null: continue
		for code in slot["items"]:
			assert_lte(int(String(code).substr(String(code).length() - 2)), 8)

func test_game_skip_order_refresh_deducts_gems_and_refills_slot() -> void:
	var g := Game.fresh(1000.0, 42)
	g.player.level = 5
	g.orders.orders = [null, null, null]
	g.orders.refresh_at = [1000.0 + 9999.0, 0.0, 0.0]
	g.wallet.add_gems(100)
	var gems_before: int = g.wallet.gems
	var res: Dictionary = g.skip_order_refresh(0, 1000.0)
	assert_true(res["ok"])
	assert_eq(res["reason"], "")
	assert_eq(g.wallet.gems, gems_before - int(ConfigDB.tuning["order_skip_gems"]))
	assert_not_null(g.orders.orders[0])

func test_game_skip_order_refresh_insufficient_gems_fails_without_side_effects() -> void:
	var g := Game.fresh(1000.0, 42)
	g.player.level = 5
	g.orders.orders = [null, null, null]
	g.orders.refresh_at = [1000.0 + 9999.0, 0.0, 0.0]
	g.wallet.gems = 0
	var res: Dictionary = g.skip_order_refresh(0, 1000.0)
	assert_false(res["ok"])
	assert_eq(res["reason"], "not_enough_gems")
	assert_eq(g.wallet.gems, 0)
	assert_null(g.orders.orders[0])

func test_game_tick_orders_refills_slot_after_cooldown_elapses() -> void:
	var g := Game.fresh(1000.0, 42)
	g.player.level = 5
	g.orders.orders = [null, null, null]
	g.orders.refresh_at = [500.0, 0.0, 0.0]   # already elapsed relative to now=1000.0
	g.tick_orders(1000.0)
	assert_not_null(g.orders.orders[0])

func test_fill_returns_false_and_skips_signal_when_no_slot_eligible() -> void:
	var ob := OrderBook.new()
	ob.fill(5, _rng(), 1000.0)
	for i in range(OrderBook.SLOTS):
		assert_not_null(ob.orders[i])
	var signaled := false
	ob.orders_changed.connect(func(): signaled = true)
	var refilled: bool = ob.fill(5, _rng(), 1000.0)   # all slots already full
	assert_false(refilled)
	assert_false(signaled)
