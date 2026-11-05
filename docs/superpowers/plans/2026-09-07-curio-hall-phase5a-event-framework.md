# Curio Hall Phase 5a: Event Framework + Pureboard Expedition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An auto-rotating live-ops event framework (with dev controls) proven on the Pureboard "dogpark" expedition: orders feed items onto a sealed second board's supply row, merges climb the event chain to completion, save v9.

**Architecture:** `MergeBoard` gains per-instance dimensions; a new `Events` sim owns lifecycle/scheduling/board/progress; ConfigDB loads event config bundles with items merged into the global item table; `BoardView` is parameterized to drive either board; a new `EventPanel` hosts the event board.

**Tech Stack:** Godot 4.7.1 / GDScript, GUT headless tests

**Spec:** `docs/superpowers/specs/2026-09-07-curio-hall-phase5a-event-framework-design.md`

## Global Constraints

- Warnings are errors: never `var x := <Dictionary/Array lookup>`; `v if v is Array else []` for nullable containers; no bare integer division; no multi-statement lambdas (use named methods).
- Tests: `./curio-hall/test.sh` from repo root; single file `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/<file> -gexit)`; run `(cd curio-hall && godot --headless --import)` after creating any NEW `class_name` script.
- **GUT swallows parse errors**: verify printed totals against the expected count stated per task and grep output for `Parse Error` / `SCRIPT ERROR`. Baseline at plan start: **200 tests**.
- Indentation: `config_db.gd` + `test_config_db.gd` TABS; `merge_board.gd`, `game.gd`, `save_manager.gd`, all `view/`, `test_merge_board.gd`, `test_save.gd`, `test_smoke.gd`, new files: 4 spaces. CHECK each test file before appending.
- All grants via `Rewards.grant/grant_all`; check-then-mutate; granted energy overfills past cap by design.
- `SAVE_VERSION` becomes 9; mismatch backs up and resets.
- Exact values: Pureboard layout 13 rows × 7 cols, every cell `pb#c#pb_dogpark_*`; scroll config `[{"level": 12, "scrollRows": 3}]`; tuning `event_duration_seconds` **604800**, `event_gap_seconds` **172800**, `event_feed_item` **"pb_dogpark_tar_1"**, `event_end_rewards` **["gem-30", "energy-100"]**. Event chain tops are NOT hardcoded in tests — walk `MergedType` from config.
- Commit ONLY on the phase worktree branch (verify `git branch --show-current` before each commit).
- Working directory: repo root unless stated.

---

### Task 1: `MergeBoard` per-instance dimensions

**Files:**
- Modify: `curio-hall/sim/merge_board.gd` (4 spaces)
- Test: `curio-hall/test/unit/test_merge_board.gd` (append; 4 spaces)

**Interfaces:**
- Produces: `MergeBoard.width: int` / `height: int` instance vars (defaulting to the `WIDTH`/`HEIGHT` consts), used by `in_bounds` and `find_free_cell`; `to_dict()` carries `"width"`/`"height"`; `from_dict` restores them (defaulting to the consts for old dicts). Everything else unchanged; the main board keeps its 7×9 behavior exactly.

- [ ] **Step 1: Write the failing test**

Append to `curio-hall/test/unit/test_merge_board.gd`:

```gdscript
func test_custom_dimensions_bounds_and_spawn() -> void:
    var board := MergeBoard.new()
    board.width = 7
    board.height = 14
    assert_true(board.in_bounds(Vector2i(6, 13)))
    assert_false(board.in_bounds(Vector2i(7, 13)))
    assert_false(board.in_bounds(Vector2i(6, 14)))
    # spawn near the bottom row of the taller board works
    assert_eq(board.spawn("201", Vector2i(0, 13)), Vector2i(0, 13))

func test_dimensions_roundtrip() -> void:
    var board := MergeBoard.new()
    board.width = 7
    board.height = 14
    board.place(Vector2i(3, 13), ItemInstance.make("201"))
    var b2 := MergeBoard.from_dict(board.to_dict())
    assert_eq(b2.width, 7)
    assert_eq(b2.height, 14)
    assert_eq(b2.item_at(Vector2i(3, 13)).type, "201")

func test_default_dimensions_unchanged() -> void:
    var board := MergeBoard.new()
    assert_eq(board.width, MergeBoard.WIDTH)
    assert_eq(board.height, MergeBoard.HEIGHT)
    assert_false(board.in_bounds(Vector2i(0, 9)))
```

- [ ] **Step 2: Run to verify it fails** — `width` nonexistent.

- [ ] **Step 3: Implement**

In `curio-hall/sim/merge_board.gd`:
- after the `enum CellState` line add:

```gdscript
var width: int = WIDTH
var height: int = HEIGHT
```

- `in_bounds` becomes:

```gdscript
func in_bounds(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < width and pos.y >= 0 and pos.y < height
```

- in `find_free_cell`, change `for radius in range(0, WIDTH + HEIGHT):` to `for radius in range(0, width + height):`
- `to_dict()` return becomes:

```gdscript
    return {"cells": cells, "width": width, "height": height}
```

- in `from_dict`, right after `var board := MergeBoard.new()`:

```gdscript
    board.width = int(d.get("width", WIDTH))
    board.height = int(d.get("height", HEIGHT))
```

- [ ] **Step 4: Run to verify green** — single file, then `./curio-hall/test.sh`: totals **203/203**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/merge_board.gd curio-hall/test/unit/test_merge_board.gd
git commit -m "feat: per-instance MergeBoard dimensions"
```

---

### Task 2: ConfigDB event bundle

**Files:**
- Create: `curio-hall/config/PureboardBoardModelConfig_dogpark.json`, `PureboardItemModelConfig_dogpark.json`, `PureboardBoardPaperRewardConfig_dogpark.json`, `PureboardBoardScrollConfig_dogpark.json` (copied verbatim)
- Modify: `curio-hall/sim/config_db.gd` (TABS)
- Test: `curio-hall/test/unit/test_config_db.gd` (append; TABS)

**Interfaces:**
- Produces: `ConfigDB.event_boards: Dictionary` (variant → layout Array), `event_paper_rewards: Dictionary` (variant → grid), `event_scroll: Dictionary` (variant → the single scroll row); event item rows merged into `ConfigDB.items` (load-time `push_error` + skip on id collision); helpers `event_board_layout(variant) -> Array`, `event_paperbox_reward(variant, pos: Vector2i) -> String`, `event_unlock_level(variant) -> int`. Existing `validate()` chain/`MergedType` checks cover event items automatically (they live in `items`); a new loop validates event layout cells.

- [ ] **Step 1: Copy the config files**

```bash

```

- [ ] **Step 2: Write the failing test**

Append to `curio-hall/test/unit/test_config_db.gd` (TABS):

```gdscript
func test_event_bundle_loaded() -> void:
	var layout: Array = ConfigDB.event_board_layout("dogpark")
	assert_eq(layout.size(), 13)
	assert_eq((layout[0] as Array).size(), 7)
	assert_true(ConfigDB.items.has("pb_dogpark_tar_1"))   # event items merged in
	assert_eq(ConfigDB.event_unlock_level("dogpark"), 12)
	assert_eq(ConfigDB.event_board_layout("nope"), [])

func test_event_paperbox_reward_lookup() -> void:
	# The grid is mostly "0"; find one non-zero cell from config and assert it,
	# plus a known-zero cell and out-of-bounds safety.
	var grid: Array = ConfigDB.event_paper_rewards["dogpark"]
	var found := Vector2i(-1, -1)
	var token := ""
	for y in range(grid.size()):
		for x in range((grid[y] as Array).size()):
			if String((grid[y] as Array)[x]) != "0":
				found = Vector2i(x, y)
				token = String((grid[y] as Array)[x])
	if found != Vector2i(-1, -1):
		assert_eq(ConfigDB.event_paperbox_reward("dogpark", found), token)
	assert_eq(ConfigDB.event_paperbox_reward("dogpark", Vector2i(0, 0)), "" if String((grid[0] as Array)[0]) == "0" else String((grid[0] as Array)[0]))
	assert_eq(ConfigDB.event_paperbox_reward("dogpark", Vector2i(-1, 99)), "")
```

- [ ] **Step 3: Run to verify it fails** — helpers nonexistent.

- [ ] **Step 4: Implement**

In `curio-hall/sim/config_db.gd` (TABS): vars after `story_recap`:

```gdscript
var event_boards: Dictionary = {}        # variant -> board layout Array
var event_paper_rewards: Dictionary = {} # variant -> [y][x] unbox-extra grid
var event_scroll: Dictionary = {}        # variant -> scroll row (level gate etc.)
```

Add `event_boards.clear()`, `event_paper_rewards.clear()`, `event_scroll.clear()` to the reload block. At the end of `load_all` (after the AreaUnlock loop):

```gdscript
	_load_event_variant(dir, "Pureboard", "dogpark")
```

New function after `load_all`:

```gdscript
## Loads one live-ops event variant: its items join the global item table
## (ids are family-prefixed and collision-checked), its board/reward/scroll
## tables are stored per variant.
func _load_event_variant(dir: String, family: String, variant: String) -> void:
	for row in _read(dir + family + "ItemModelConfig_" + variant + ".json"):
		if row == null:
			continue
		var id := String(row["Type"])
		if items.has(id):
			push_error("event item id collides with existing item: " + id)
			continue
		items[id] = row
	event_boards[variant] = _read(dir + family + "BoardModelConfig_" + variant + ".json")
	event_paper_rewards[variant] = _read(dir + family + "BoardPaperRewardConfig_" + variant + ".json")
	var scroll_rows: Array = _read(dir + family + "BoardScrollConfig_" + variant + ".json")
	event_scroll[variant] = scroll_rows[0] if scroll_rows.size() > 0 else {}
```

Helpers after `paperbox_reward`:

```gdscript
func event_board_layout(variant: String) -> Array:
	var v: Variant = event_boards.get(variant)
	return v if v is Array else []

func event_paperbox_reward(variant: String, pos: Vector2i) -> String:
	var grid_v: Variant = event_paper_rewards.get(variant)
	var grid: Array = grid_v if grid_v is Array else []
	if pos.y < 0 or pos.y >= grid.size():
		return ""
	var row: Array = grid[pos.y]
	if pos.x < 0 or pos.x >= row.size():
		return ""
	var token := String(row[pos.x])
	return "" if token == "0" else token

func event_unlock_level(variant: String) -> int:
	var row_v: Variant = event_scroll.get(variant)
	var row: Dictionary = row_v if row_v is Dictionary else {}
	return int(row.get("level", 1))
```

In `validate()`, before `return errors`:

```gdscript
	for variant in event_boards:
		var elayout: Array = event_boards[variant]
		for r in range(elayout.size()):
			for cell in elayout[r]:
				var id := String(cell).get_slice("#", String(cell).count("#"))
				if not items.has(id):
					errors.append("event %s layout row %d: item %s missing" % [variant, r, id])
```

- [ ] **Step 5: Run to verify green** — single file, then full suite: totals **205/205**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/config/Pureboard*_dogpark.json curio-hall/sim/config_db.gd curio-hall/test/unit/test_config_db.gd
git commit -m "feat: load pureboard event config bundle"
```

---

### Task 3: `Events` lifecycle, scheduling, dev controls, save v9

**Files:**
- Create: `curio-hall/sim/events.gd`
- Modify: `curio-hall/sim/game.gd`, `curio-hall/sim/save_manager.gd`, `curio-hall/config/curio_hall_tuning.json`
- Test: `curio-hall/test/unit/test_events.gd` (create), `curio-hall/test/unit/test_save.gd` (version bump + append; 4 spaces), `curio-hall/test/unit/test_shop_game.gd` (version literal)

**Interfaces:**
- Consumes: `ConfigDB.event_board_layout/event_unlock_level` (Task 2), `MergeBoard.width/height` (Task 1), `BoardLayout.apply`, `PlayerState.level`.
- Produces: `Events` (RefCounted): `enum State { IDLE, ACTIVE }`, `const VARIANT := "dogpark"`, fields `state/variant/ends_at/next_event_at/board/best_tier/completed`, `signal event_changed`, `is_active() -> bool`, `tick(now: float, player: PlayerState) -> void`, `start_event(now: float) -> bool`, `end_event(now: float) -> void`, `to_dict()/from_dict()`. `Game` gains `events: Events` (fresh), `tick_events(now)`, `dev_start_event(now)`, `dev_end_event(now)`, `SAVE_VERSION == 9`, `events` in the save + SaveManager key. Tuning gains `event_duration_seconds: 604800`, `event_gap_seconds: 172800` (feed/end-reward constants arrive in Task 4).

- [ ] **Step 1: Add tuning constants**

`curio-hall/config/curio_hall_tuning.json` gains `"event_duration_seconds": 604800, "event_gap_seconds": 172800`.

- [ ] **Step 2: Write the failing tests**

Create `curio-hall/test/unit/test_events.gd` (4 spaces):

```gdscript
extends GutTest
## Event lifecycle: auto-start when due + level 12 gate, 7-day duration,
## 2-day gap, dev controls bypass the gate, board is one row taller than
## the 13-row dogpark layout (open supply row at the bottom).

const NOW := 1000.0

func test_no_start_below_unlock_level() -> void:
    var g := Game.fresh(NOW, 42)
    g.tick_events(NOW)               # next_event_at 0 -> due, but level 1 < 12
    assert_false(g.events.is_active())

func test_auto_start_when_due_and_gated() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 12
    g.tick_events(NOW)
    assert_true(g.events.is_active())
    assert_eq(g.events.variant, "dogpark")
    assert_eq(g.events.ends_at, NOW + 604800.0)
    # board: 13 config rows + 1 open supply row
    assert_eq(g.events.board.height, 14)
    assert_eq(g.events.board.width, 7)
    assert_null(g.events.board.item_at(Vector2i(0, 13)))
    assert_eq(g.events.board.state_at(Vector2i(0, 13)), MergeBoard.CellState.OPEN)
    assert_eq(g.events.board.state_at(Vector2i(0, 0)), MergeBoard.CellState.BOXED)

func test_expiry_discards_board_and_schedules_next() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 12
    g.tick_events(NOW)
    g.tick_events(NOW + 604800.0)
    assert_false(g.events.is_active())
    assert_null(g.events.board)
    assert_eq(g.events.next_event_at, NOW + 604800.0 + 172800.0)
    g.tick_events(NOW + 604800.0 + 172800.0)   # next window opens
    assert_true(g.events.is_active())

func test_dev_controls_bypass_gate_and_timers() -> void:
    var g := Game.fresh(NOW, 42)          # level 1
    assert_true(g.dev_start_event(NOW))
    assert_true(g.events.is_active())
    assert_false(g.dev_start_event(NOW))  # idempotent while active
    g.dev_end_event(NOW + 5.0)
    assert_false(g.events.is_active())
    assert_eq(g.events.next_event_at, NOW + 5.0 + 172800.0)

func test_offline_expiry_reconciles_on_first_tick() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.events.is_active())
    g2.tick_events(NOW + 700000.0)        # loaded long after ends_at
    assert_false(g2.events.is_active())
```

In `curio-hall/test/unit/test_save.gd` (4 spaces): rename `test_v8_roundtrip_campaign` → `test_v9_roundtrip_campaign`, `test_save_version_is_8_and_campaign_key_present` → `..._is_9_...`, literal `8` → `9`, and append:

```gdscript
func test_v9_roundtrip_event_board() -> void:
    var g := Game.fresh(1000.0, 42)
    g.dev_start_event(1000.0)
    g.events.board.spawn("pb_dogpark_tar_1", Vector2i(0, 13))
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.events.is_active())
    assert_eq(g2.events.board.height, 14)
    assert_eq(g2.events.board.count_of("pb_dogpark_tar_1"), 1)
```

`curio-hall/test/unit/test_shop_game.gd`: version literal `8` → `9`.

- [ ] **Step 3: Run to verify they fail** — `Events` nonexistent; version still 8.

- [ ] **Step 4: Implement**

Create `curio-hall/sim/events.gd` (4 spaces):

```gdscript
class_name Events
extends RefCounted
## Live-ops expedition lifecycle: auto-rotating schedule with dev overrides,
## a second merge board built from event config (one extra open supply row at
## the bottom stands in for the   cache queue), and tier progress.
## Expiry advances on Game.tick_events (main.gd's 1s timer hosts the tick).

signal event_changed

enum State { IDLE, ACTIVE }

const VARIANT := "dogpark"   # phase 5a ships a single archetype variant

var state: int = State.IDLE
var variant: String = ""
var ends_at: float = 0.0
var next_event_at: float = 0.0   # 0.0 = start as soon as the gate passes
var board: MergeBoard = null
var best_tier: int = 0
var completed: bool = false

func is_active() -> bool:
    return state == State.ACTIVE

func tick(now: float, player: PlayerState) -> void:
    if state == State.IDLE:
        if now >= next_event_at and player.level >= ConfigDB.event_unlock_level(VARIANT):
            start_event(now)
    elif now >= ends_at:
        end_event(now)

func start_event(now: float) -> bool:
    if state == State.ACTIVE:
        return false
    var layout: Array = ConfigDB.event_board_layout(VARIANT)
    if layout.is_empty():
        return false
    variant = VARIANT
    board = MergeBoard.new()
    board.width = (layout[0] as Array).size()
    board.height = layout.size() + 1   # +1: the open supply row at the bottom
    BoardLayout.apply(board, layout)
    ends_at = now + float(ConfigDB.tuning["event_duration_seconds"])
    best_tier = 0
    completed = false
    state = State.ACTIVE
    event_changed.emit()
    return true

func end_event(now: float) -> void:
    if state != State.ACTIVE:
        return
    state = State.IDLE
    board = null
    variant = ""
    next_event_at = now + float(ConfigDB.tuning["event_gap_seconds"])
    event_changed.emit()

func to_dict() -> Dictionary:
    return {"state": state, "variant": variant, "ends_at": ends_at,
            "next_event_at": next_event_at, "best_tier": best_tier,
            "completed": completed,
            "board": board.to_dict() if board != null else null}

static func from_dict(d: Dictionary) -> Events:
    var e := Events.new()
    e.state = int(d.get("state", State.IDLE))
    e.variant = String(d.get("variant", ""))
    e.ends_at = float(d.get("ends_at", 0.0))
    e.next_event_at = float(d.get("next_event_at", 0.0))
    e.best_tier = int(d.get("best_tier", 0))
    e.completed = bool(d.get("completed", false))
    var board_v: Variant = d.get("board")
    if board_v is Dictionary:
        e.board = MergeBoard.from_dict(board_v)
    return e
```

In `curio-hall/sim/game.gd`:
- `const SAVE_VERSION := 9`
- `var events: Events` after `var specials: SpecialOrders`; in `fresh`: `g.events = Events.new()` after the specials line.
- after `claim_return_gift`:

```gdscript
func tick_events(now: float) -> void:
    events.tick(now, player)

func dev_start_event(now: float) -> bool:
    return events.start_event(now)

func dev_end_event(now: float) -> void:
    events.end_event(now)
```

- `to_dict()`: `"events": events.to_dict(),` after `"specials"`; `from_dict()`: `g.events = Events.from_dict(d["events"])` after the specials line.

`curio-hall/sim/save_manager.gd`: required keys gain `"events"`; comment → "v8 saves reset on upgrade to v9".

- [ ] **Step 5: Run to verify green** — `--import` first (new class_name); test_events.gd, test_save.gd, then full suite: totals **211/211**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/sim/events.gd curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/config/curio_hall_tuning.json curio-hall/test/unit/test_events.gd curio-hall/test/unit/test_save.gd curio-hall/test/unit/test_shop_game.gd
git commit -m "feat: live-ops event lifecycle with auto-rotation and dev controls, save v9"
```

---

### Task 4: Feeding, `merge_event`, progress and completion

**Files:**
- Modify: `curio-hall/sim/events.gd`, `curio-hall/sim/game.gd`, `curio-hall/config/curio_hall_tuning.json`
- Test: `curio-hall/test/unit/test_events.gd` (append)

**Interfaces:**
- Consumes: Task 3's `Events`, `ConfigDB.event_paperbox_reward`, `Rewards.grant/grant_all`, `Game.deliver_order`.
- Produces: `Events.on_order_delivered(game, now)`; `Events.record_merge(new_type: String, game, now: float)`; `Events.feed_chain_prefix() -> String` (static); `Game.merge_event(a: Vector2i, b: Vector2i, now: float) -> String` (returns `"no_event"` when idle, else `MergeBoard.merge`'s error string); tuning `event_feed_item: "pb_dogpark_tar_1"`, `event_end_rewards: ["gem-30", "energy-100"]`. `Game.deliver_order` calls `events.on_order_delivered(self, now)`.

- [ ] **Step 1: Add tuning constants**

`curio-hall/config/curio_hall_tuning.json` gains `"event_feed_item": "pb_dogpark_tar_1", "event_end_rewards": ["gem-30", "energy-100"]`.

- [ ] **Step 2: Write the failing tests**

Append to `curio-hall/test/unit/test_events.gd`:

```gdscript
func _walk_chain_from(id: String) -> Array:
    var out: Array = [id]
    while ConfigDB.items[out[-1]].has("MergedType"):
        out.append(String(ConfigDB.items[out[-1]]["MergedType"]))
    return out

func test_order_delivery_feeds_supply_row_only_while_active() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])          # IDLE: nothing fed
    g.dev_start_event(NOW)
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 0)
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 1)
    assert_eq(g.board.count_of("pb_dogpark_tar_1"), 0)  # main board untouched

func test_merge_event_rejects_when_idle() -> void:
    var g := Game.fresh(NOW, 42)
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "no_event")

func test_merge_event_onto_veiled_and_supply_row() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var b := g.events.board
    b.spawn("pb_dogpark_tar_1", Vector2i(0, 13))
    b.spawn("pb_dogpark_tar_1", Vector2i(1, 13))
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "")
    assert_eq(b.item_at(Vector2i(1, 13)).type, "pb_dogpark_tar_2")
    assert_eq(g.events.best_tier, 2)
    # merging onto a veiled matching event cell clears the veil (find one tar_8
    # cell in the top layout row per config: layout row 0 col 1 is tar_8)
    # 8 needs a free tar_8: build one is long, so verify the veil rule directly:
    b.place(Vector2i(2, 13), ItemInstance.make("pb_dogpark_tar_8"))
    assert_eq(g.merge_event(Vector2i(2, 13), Vector2i(1, 0), NOW), "")
    assert_eq(b.item_at(Vector2i(1, 0)).type, "pb_dogpark_tar_9")
    assert_eq(b.state_at(Vector2i(1, 0)), MergeBoard.CellState.OPEN)

func test_unboxing_event_cell_pays_event_grid_extra() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var b := g.events.board
    # find any cell whose 4-neighbourhood we can shock via a supply-row merge:
    # merge two tar_1 at (0,13),(1,13) -> target (1,13) shocks (1,12): a BOXED
    # layout cell -> becomes COVERED; the event grid's token for (1,12) (if any)
    # is granted. We assert the state transition and that no error occurs; the
    # reward amount is asserted only when the grid carries a token there.
    b.spawn("pb_dogpark_tar_1", Vector2i(0, 13))
    b.spawn("pb_dogpark_tar_1", Vector2i(1, 13))
    var energy_before := g.wallet.energy(NOW)
    g.wallet.spend_energy(50, NOW)
    energy_before = g.wallet.energy(NOW)
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "")
    assert_eq(b.state_at(Vector2i(1, 12)), MergeBoard.CellState.COVERED)
    var token := ConfigDB.event_paperbox_reward("dogpark", Vector2i(1, 12))
    if token.begins_with("energy-"):
        assert_eq(g.wallet.energy(NOW), energy_before + int(token.get_slice("-", 1)))

func test_completion_grants_end_rewards_once() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_event(NOW)
    var chain := _walk_chain_from("pb_dogpark_tar_1")
    var penultimate := String(chain[chain.size() - 2])
    var b := g.events.board
    b.spawn(penultimate, Vector2i(0, 13))
    b.spawn(penultimate, Vector2i(1, 13))
    var gems_before := g.wallet.gems
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), NOW), "")
    assert_true(g.events.completed)
    assert_eq(g.wallet.gems, gems_before + 30)
    assert_eq(g.events.best_tier, chain.size())
    # a second top merge cannot double-grant
    b.spawn(penultimate, Vector2i(2, 13))
    b.spawn(penultimate, Vector2i(3, 13))
    assert_eq(g.merge_event(Vector2i(2, 13), Vector2i(3, 13), NOW), "")
    assert_eq(g.wallet.gems, gems_before + 30)
```

- [ ] **Step 3: Run to verify they fail** — `merge_event`/`on_order_delivered` nonexistent.

- [ ] **Step 4: Implement**

In `curio-hall/sim/events.gd`, add after `end_event`:

```gdscript
static func feed_chain_prefix() -> String:
    return String(ConfigDB.tuning["event_feed_item"]).rsplit("_", true, 1)[0] + "_"

## Stand-in for the   order->item cache delivery: each finished main
## order drops one feed item onto the supply row (lost with a warning if full).
func on_order_delivered(game, now: float) -> void:
    if state != State.ACTIVE:
        return
    var item := String(ConfigDB.tuning["event_feed_item"])
    if board.spawn(item, Vector2i(0, board.height - 1)) == Vector2i(-1, -1):
        push_warning("Events: supply row full, feed item lost")
    else:
        event_changed.emit()

static func _tier_of(id: String) -> int:
    return int(String(id).rsplit("_", true, 1)[1])

## Progress tracks the feed chain only; producing its top completes the
## expedition and grants the (placeholder) end rewards exactly once.
func record_merge(new_type: String, game, now: float) -> void:
    if not new_type.begins_with(feed_chain_prefix()):
        return
    var t := _tier_of(new_type)
    if t > best_tier:
        best_tier = t
        event_changed.emit()
    if not completed and not ConfigDB.items.get(new_type, {}).has("MergedType"):
        completed = true
        var rewards_v: Variant = ConfigDB.tuning["event_end_rewards"]
        var rewards: Array = rewards_v if rewards_v is Array else []
        Rewards.grant_all(rewards, game, now)
        event_changed.emit()
```

In `curio-hall/sim/game.gd`:
- in `deliver_order`, after `intimacy.maybe_refresh_return_gift(now, rng)`:

```gdscript
    events.on_order_delivered(self, now)
```

- after `dev_end_event`:

```gdscript
func merge_event(a: Vector2i, b: Vector2i, now: float) -> String:
    if not events.is_active():
        return "no_event"
    var err := events.board.merge(a, b)
    if err != "":
        return err
    for pos in events.board.take_unboxed():
        var token := ConfigDB.event_paperbox_reward(events.variant, pos)
        if token != "":
            Rewards.grant(token, self, now)
    events.record_merge(events.board.item_at(b).type, self, now)
    return ""
```

- [ ] **Step 5: Run to verify green** — test_events.gd, then full suite: totals **216/216**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/sim/events.gd curio-hall/sim/game.gd curio-hall/config/curio_hall_tuning.json curio-hall/test/unit/test_events.gd
git commit -m "feat: order feeding, event merges and expedition completion"
```

---

### Task 5: `BoardView` parameterization, `EventPanel`, wiring, smoke, roadmap

**Files:**
- Create: `curio-hall/view/event_panel.gd`
- Modify: `curio-hall/view/board_view.gd`, `curio-hall/scenes/main.gd`, `curio-hall/scenes/main.tscn`, `docs/curio-hall-roadmap.md`
- Test: `curio-hall/test/unit/test_smoke.gd` (append; 4 spaces)

**Interfaces:**
- Consumes: `Game.events`/`merge_event`/`dev_start_event`/`dev_end_event`/`tick_events` (Tasks 3-4).
- Produces: `BoardView.setup(g: Game, b: MergeBoard = null, merge_cb: Callable = Callable(), tap_cb: Callable = Callable())` (board defaults to `g.board`, callbacks default to `g.merge`/`g.tap`; dimensions come from the board's `width`/`height`); `BoardView.input_enabled: bool` (main scene disables it while the event panel is open); `EventPanel` (CanvasLayer) with `setup(g: Game)`, `open()`, `close()`, `signal action_rejected(reason: String)`; an Expedition HUD button visible only while an event is active; `REJECT_MESSAGES` gains `no_event`.

- [ ] **Step 1: Write the smoke test**

Append to `curio-hall/test/unit/test_smoke.gd` (4 spaces):

```gdscript
func test_event_smoke_feed_merge_persist_expire() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_true(g.dev_start_event(1000.0))
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, 1000.0)["ok"])
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 1)
    g.events.board.spawn("pb_dogpark_tar_1", Vector2i(1, 13))
    assert_eq(g.merge_event(Vector2i(0, 13), Vector2i(1, 13), 1000.0), "")
    assert_eq(g.events.best_tier, 2)
    var g2 := Game.from_dict(g.to_dict())          # mid-event quit/resume
    assert_true(g2.events.is_active())
    assert_eq(g2.events.best_tier, 2)
    g2.tick_events(1000.0 + 604800.0)              # clock runs out
    assert_false(g2.events.is_active())
```

- [ ] **Step 2: Run it — expected to PASS already** (exercises Tasks 1-4; guards the wiring). Suite totals become **217**.

- [ ] **Step 3: Parameterize `BoardView`**

In `curio-hall/view/board_view.gd`:
- add fields after `var game: Game`:

```gdscript
var board: MergeBoard
var merge_fn: Callable
var tap_fn: Callable
var input_enabled := true
```

- `setup` becomes:

```gdscript
func setup(g: Game, b: MergeBoard = null, merge_cb: Callable = Callable(), tap_cb: Callable = Callable()) -> void:
    game = g
    board = b if b != null else g.board
    merge_fn = merge_cb if merge_cb.is_valid() else g.merge
    tap_fn = tap_cb if tap_cb.is_valid() else g.tap
    board.item_placed.connect(_on_placed)
    board.item_removed.connect(_on_removed)
    board.item_removed.connect(_on_removed_clears_selection)
    board.cell_opened.connect(_on_opened)
    for y in range(board.height):
        for x in range(board.width):
            var pos := Vector2i(x, y)
            if board.item_at(pos) != null:
                _on_placed(pos, board.item_at(pos).type)
```

- replace every remaining `game.board.` with `board.` (`_pos_at`, `_on_placed`, `_on_opened`, `_begin_drag`, `_end_drag`'s tap/select/move paths).
- `_draw` loops become `for y in range(board.height): for x in range(board.width):`.
- `_unhandled_input` gains a first line: `if not input_enabled: return`.
- in `_end_drag`: `game.tap(from, now)` → `tap_fn.call(from, now)`; `game.merge(from, pos, now)` → `String(merge_fn.call(from, pos, now))`; `game.board.move(from, pos)` → `board.move(from, pos)`.

The main scene's `board_view.setup(game)` call keeps working via the defaults — do not change it.

- [ ] **Step 4: Implement `EventPanel`**

Create `curio-hall/view/event_panel.gd` (4 spaces):

```gdscript
class_name EventPanel
extends CanvasLayer
## The Society Presents: the live event's board, countdown, progress, and
## clearly-labeled DEV lifecycle controls. Placeholder styling.

signal action_rejected(reason: String)
signal visibility_changed_to(open: bool)

const BOARD_SCALE := 0.55

var game: Game
var _header: Label
var _board_holder: Node2D
var _board_view: BoardView = null

func setup(g: Game) -> void:
    game = g
    layer = 12
    visible = false
    var bg := ColorRect.new()
    bg.color = Color(0.07, 0.09, 0.11, 0.97)
    bg.anchor_right = 1.0
    bg.anchor_bottom = 1.0
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # let drags reach the board
    add_child(bg)
    _header = Label.new()
    _header.position = Vector2(10, 8)
    add_child(_header)
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.position = Vector2(600, 8)
    close_b.pressed.connect(close)
    add_child(close_b)
    var dev_start := Button.new()
    dev_start.text = "DEV: Start event"
    dev_start.position = Vector2(10, 40)
    dev_start.pressed.connect(_dev_start)
    add_child(dev_start)
    var dev_end := Button.new()
    dev_end.text = "DEV: End event"
    dev_end.position = Vector2(160, 40)
    dev_end.pressed.connect(_dev_end)
    add_child(dev_end)
    _board_holder = Node2D.new()
    _board_holder.position = Vector2(80, 90)
    _board_holder.scale = Vector2(BOARD_SCALE, BOARD_SCALE)
    add_child(_board_holder)
    game.events.event_changed.connect(_on_event_changed)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_refresh_header)
    add_child(t)

func open() -> void:
    visible = true
    _rebuild_board_view()
    _refresh_header()
    visibility_changed_to.emit(true)

func close() -> void:
    visible = false
    visibility_changed_to.emit(false)

func _dev_start() -> void:
    if not game.dev_start_event(Time.get_unix_time_from_system()):
        action_rejected.emit("unknown")

func _dev_end() -> void:
    game.dev_end_event(Time.get_unix_time_from_system())

func _on_event_changed() -> void:
    if visible:
        _rebuild_board_view()
        _refresh_header()

func _rebuild_board_view() -> void:
    if _board_view != null:
        _board_view.queue_free()
        _board_view = null
    if not game.events.is_active():
        return
    _board_view = BoardView.new()
    _board_holder.add_child(_board_view)
    _board_view.setup(game, game.events.board, game.merge_event, Callable())
    _board_view.action_rejected.connect(func(reason: String) -> void: action_rejected.emit(reason))

func _refresh_header() -> void:
    if not visible:
        return
    if not game.events.is_active():
        _header.text = "No expedition underway   (next departs when the clock allows)"
        return
    var now := Time.get_unix_time_from_system()
    var left := maxf(0.0, game.events.ends_at - now)
    var chain_len := _chain_length()
    var progress := "Best find: tier %d / %d%s" % [game.events.best_tier, chain_len,
            "   EXPEDITION COMPLETE!" if game.events.completed else ""]
    _header.text = "The Society Presents: %s\nends in %dh %dm   %s" % [
            game.events.variant, int(left / 3600.0), int(fmod(left, 3600.0) / 60.0), progress]

func _chain_length() -> int:
    var id := String(ConfigDB.tuning["event_feed_item"])
    var n := 1
    while ConfigDB.items.get(id, {}).has("MergedType"):
        id = String(ConfigDB.items[id]["MergedType"])
        n += 1
    return n
```

Note: taps on the event board pass `Callable()` so `tap_fn` defaults to `g.tap` — which operates on the MAIN board; that's wrong for the event board. Instead pass a rejecting tap: add to `event_panel.gd`:

```gdscript
func _event_tap(_pos: Vector2i, _now: float) -> Dictionary:
    return {"ok": false, "kind": "none", "reason": ""}
```

and call `_board_view.setup(game, game.events.board, game.merge_event, _event_tap)`.

- [ ] **Step 5: Wire the main scene**

`curio-hall/scenes/main.tscn`: `load_steps` 10 → 11; ext_resource after chronicle_panel:

```
[ext_resource type="Script" path="res://view/event_panel.gd" id="10"]
```

nodes: after SocietyButton:

```
[node name="ExpeditionButton" type="Button" parent="UI"]
offset_left = 600.0
offset_top = 60.0
offset_right = 710.0
offset_bottom = 100.0
text = "Expedition"
visible = false
```

after ChroniclePanel:

```
[node name="EventPanel" type="CanvasLayer" parent="."]
script = ExtResource("10")
```

`curio-hall/scenes/main.gd`:
- `REJECT_MESSAGES` gains `"no_event": "No expedition is underway",`
- `@onready var event_panel: EventPanel = $EventPanel` and `@onready var expedition_button: Button = $UI/ExpeditionButton`
- in `_ready`, after the chronicle wiring:

```gdscript
    event_panel.setup(game)
    expedition_button.pressed.connect(event_panel.open)
    event_panel.action_rejected.connect(_show_toast)
    event_panel.visibility_changed_to.connect(func(open: bool) -> void: board_view.input_enabled = not open)
    game.events.event_changed.connect(_refresh_expedition_button)
    _refresh_expedition_button()
```

- new method:

```gdscript
func _refresh_expedition_button() -> void:
    expedition_button.visible = game.events.is_active()
```

- save-pending list gains `game.events.event_changed`; `_flush_save` gains `game.tick_events(Time.get_unix_time_from_system())` next to the other ticks.

- [ ] **Step 6: Verify** — `--import`, full suite (totals **217/217**, no Parse Error/SCRIPT ERROR), then the ~8s backgrounded headless boot (zero SCRIPT ERROR lines).

- [ ] **Step 7: Update the roadmap**

Mark a new "## Phase 5a: Event framework and Pureboard expedition ✅" section (colon header, no em dashes in new text) before the Phase 5 section, describing: auto-rotating lifecycle with dev controls, per-instance board dimensions, event config bundles, order feeding onto the supply row (cache-queue stand-in), tier progress and placeholder end rewards, BoardView parameterization, EventPanel, save v9. Spec + plan links. Deferred: event points/decoration shop, scrolling-window presentation, event orders, remaining archetypes, real end rewards (bytecode). Reword the Phase 5 intro to note 5a is done and the remaining archetypes queue behind it.

- [ ] **Step 8: Commit**

```bash
git add curio-hall/view/event_panel.gd curio-hall/view/board_view.gd curio-hall/scenes/main.gd curio-hall/scenes/main.tscn curio-hall/test/unit/test_smoke.gd docs/curio-hall-roadmap.md
git commit -m "feat: EventPanel and parameterized BoardView - phase 5a playable"
```
