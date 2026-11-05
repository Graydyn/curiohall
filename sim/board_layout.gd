class_name BoardLayout

static func apply(board: MergeBoard, layout: Array) -> void:
	for y in range(layout.size()):
		var row: Array = layout[y]
		for x in range(row.size()):
			var cell := String(row[x])
			var tokens := cell.split("#")
			var id: String = tokens[-1]
			if id == "0":
				continue
			var pos := Vector2i(x, y)
			board.place(pos, ItemInstance.make(id))
			if tokens.has("pb"):
				board.set_state(pos, MergeBoard.CellState.BOXED)
			elif tokens.has("c"):
				board.set_state(pos, MergeBoard.CellState.COVERED)
