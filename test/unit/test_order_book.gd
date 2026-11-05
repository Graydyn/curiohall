extends GutTest

func _rng() -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	return rng

func test_fill_respects_unlock_level() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = ConfigDB.order_fixed.size()   # isolate random-order gating from tutorial orders
	ob.fill(1, _rng(), 0.0)   # Type-1 row unlocks at level 3
	for o in ob.orders:
		assert_null(o)

func test_fill_generates_valid_orders_at_level_5() -> void:
	var ob := OrderBook.new()
	ob.fill(5, _rng(), 0.0)
	for o in ob.orders:
		assert_not_null(o)
		assert_between((o["items"] as Dictionary).size(), 1, 3)
		for code in o["items"]:
			var row: Dictionary = ob.pool_row(code)
			assert_true(int(row["UnlockLevel"]) <= 5)
		assert_gt(int(o["coins"]), 0)

func test_deliver_removes_items_and_pays() -> void:
	var ob := OrderBook.new()
	ob.orders = [{"items": {"203": 2}, "coins": 4, "xp": 4, "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
	var board := MergeBoard.new()
	board.place(Vector2i(0, 0), ItemInstance.make("203"))
	assert_false(ob.can_deliver(0, board))
	board.place(Vector2i(1, 0), ItemInstance.make("203"))
	assert_true(ob.can_deliver(0, board))
	var res: Dictionary = ob.deliver(0, board)
	assert_true(res["ok"])
	assert_eq(res["coins"], 4)
	assert_eq(board.count_of("203"), 0)
	assert_null(ob.orders[0])

func test_game_deliver_pays_wallet_and_xp() -> void:
	var g := Game.fresh(1000.0, 42)
	g.player.level = 5
	g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4, "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
	# Free a cell first since board starts FULL from the layout
	g.board.remove(Vector2i(3, 4))
	g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
	g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
	var coins_before := g.wallet.coins
	var res: Dictionary = g.deliver_order(0, 1000.0)
	assert_true(res["ok"])
	assert_eq(g.wallet.coins, coins_before + 4)
	assert_eq(g.player.xp, 4)
