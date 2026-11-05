extends GutTest
## Merges shock the target's
## orthogonal neighbors, shocked paperboxes collapse to veiled (cobwebbed)
## items and grant MainPaperboxExtraRewardConfig extras, and veiled items are
## cleared by merging a matching free item onto them. No gifted items needed.

const NOW := 1000.0

func test_paperbox_rewards_grid_loaded() -> void:
	assert_eq(ConfigDB.paperbox_rewards.size(), MergeBoard.HEIGHT)
	for row in ConfigDB.paperbox_rewards:
		assert_eq((row as Array).size(), MergeBoard.WIDTH)
	assert_eq(ConfigDB.paperbox_reward(Vector2i(0, 0)), "energy-20")
	assert_eq(ConfigDB.paperbox_reward(Vector2i(1, 0)), "")   # "0" means no extra
	assert_eq(ConfigDB.paperbox_reward(Vector2i(4, 7)), "energy-100")

func test_unboxing_a_reward_cell_grants_its_extra() -> void:
	var g := Game.fresh(NOW, 42)
	g.wallet.spend_energy(50, NOW)   # leave headroom below the cap
	var energy_before := g.wallet.energy(NOW)
	for pos in [Vector2i(1, 0), Vector2i(2, 0)]:
		g.board.remove(pos)
		g.board.set_state(pos, MergeBoard.CellState.OPEN)
		g.board.place(pos, ItemInstance.make("201"))
	assert_eq(g.merge(Vector2i(2, 0), Vector2i(1, 0), NOW), "")
	# Only the target's neighbors are shocked: (0,0) unboxes -> energy-20.
	assert_eq(g.board.state_at(Vector2i(0, 0)), MergeBoard.CellState.COVERED)
	assert_eq(g.board.state_at(Vector2i(3, 0)), MergeBoard.CellState.BOXED)   # source neighbor untouched
	assert_eq(g.wallet.energy(NOW), energy_before + 20)

func test_unboxing_a_zero_cell_grants_nothing() -> void:
	var g := Game.fresh(NOW, 42)
	g.wallet.spend_energy(50, NOW)
	var energy_before := g.wallet.energy(NOW)
	var coins_before := g.wallet.coins
	for pos in [Vector2i(5, 4), Vector2i(4, 4)]:   # target (4,4) neighbors are all "0" reward cells
		g.board.remove(pos)
		g.board.set_state(pos, MergeBoard.CellState.OPEN)
		g.board.place(pos, ItemInstance.make("201"))
	assert_eq(g.merge(Vector2i(5, 4), Vector2i(4, 4), NOW), "")
	assert_eq(g.wallet.energy(NOW), energy_before)
	assert_eq(g.wallet.coins, coins_before)

func test_failed_merge_grants_nothing() -> void:
	var g := Game.fresh(NOW, 42)
	g.wallet.spend_energy(50, NOW)
	var energy_before := g.wallet.energy(NOW)
	assert_ne(g.merge(Vector2i(0, 0), Vector2i(1, 0), NOW), "")   # boxed cells can't merge
	assert_eq(g.wallet.energy(NOW), energy_before)

func test_tutorial_playthrough_reaches_working_generator() -> void:
	var g := Game.fresh(NOW, 42)
	assert_eq(g.player.inventory.size(), 0)   # no gifted items: the board sustains itself
	# Move 1: merge the two open Empty Brown Bags (101) -> 102
	assert_eq(g.merge(Vector2i(1, 3), Vector2i(1, 4), NOW), "")
	assert_eq(g.board.state_at(Vector2i(2, 4)), MergeBoard.CellState.COVERED)   # the veiled 102
	# Move 2: free 102 onto the veiled 102 -> Shopping Bag (103), web cleared
	assert_eq(g.merge(Vector2i(1, 4), Vector2i(2, 4), NOW), "")
	assert_eq(g.board.item_at(Vector2i(2, 4)).type, "103")
	assert_eq(g.board.state_at(Vector2i(2, 4)), MergeBoard.CellState.OPEN)
	# That merge's shock unboxed the neighboring paperbox holding a veiled 103
	assert_eq(g.board.state_at(Vector2i(3, 4)), MergeBoard.CellState.COVERED)
	assert_eq(g.board.item_at(Vector2i(3, 4)).type, "103")
	# Move 3: free 103 onto the veiled 103 -> Overflowing Bag (104), the first generator
	assert_eq(g.merge(Vector2i(2, 4), Vector2i(3, 4), NOW), "")
	var bag := g.board.item_at(Vector2i(3, 4))
	assert_eq(bag.type, "104")
	assert_not_null(bag.gen)
	# Tapping it spawns an ingredient into a freed cell: play sustains from here
	var res: Dictionary = g.tap(Vector2i(3, 4), NOW)
	assert_true(res["ok"], "generator tap should spawn: %s" % str(res))
	assert_eq((res["spawned"] as Array).is_empty(), false)
