extends GutTest

func test_layout_fills_full_board_with_states() -> void:
	var board := MergeBoard.new()
	BoardLayout.apply(board, ConfigDB.board_layout)
	# Known cells from BoardModelConfig: (1,3) is bare "101", (2,4) is "c#102",
	# (0,0) is "pb#c#1002".
	assert_eq(board.item_at(Vector2i(1, 3)).type, "101")
	assert_eq(board.state_at(Vector2i(1, 3)), MergeBoard.CellState.OPEN)
	assert_eq(board.item_at(Vector2i(2, 4)).type, "102")
	assert_eq(board.state_at(Vector2i(2, 4)), MergeBoard.CellState.COVERED)
	assert_eq(board.item_at(Vector2i(0, 0)).type, "1002")
	assert_eq(board.state_at(Vector2i(0, 0)), MergeBoard.CellState.BOXED)

func test_merging_the_two_starting_101s_leaves_veiled_neighbor_mergeable() -> void:
	var board := MergeBoard.new()
	BoardLayout.apply(board, ConfigDB.board_layout)
	# Starting layout has open "101" at (1,3) and (1,4).
	assert_eq(board.merge(Vector2i(1, 3), Vector2i(1, 4)), "")
	# Cobwebs ignore shocks: the veiled "c#102" at (2,4) stays COVERED, but the
	# free 102 merges onto it, clearing the web (the   tutorial move 2).
	assert_eq(board.state_at(Vector2i(2, 4)), MergeBoard.CellState.COVERED)
	assert_eq(board.merge(Vector2i(1, 4), Vector2i(2, 4)), "")
	assert_eq(board.item_at(Vector2i(2, 4)).type, "103")
	assert_eq(board.state_at(Vector2i(2, 4)), MergeBoard.CellState.OPEN)
