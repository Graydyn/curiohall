# Curio Hall Phase 1 (Core Merge Board) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.



**Architecture:** Pure-logic simulation core (`sim/`, RefCounted classes, injected timestamps and RNG, no Nodes except the ConfigDB autoload) under a thin scene layer (`scenes/` + `view/`) that renders sim state and forwards input. Config JSON is loaded unmodified; the sim emits signals the view listens to.

**Tech Stack:** Godot 4.x (GDScript), GUT (Godot Unit Test) for the sim layer.

**Spec:** `docs/superpowers/specs/2026-09-02-curio-hall-phase1-design.md`

## Global Constraints

- Godot 4.x, GDScript only. Project lives at `curio-hall/` in this repo.
- Item ids are **Strings** everywhere (config uses `"101"`, `"1002"`). Tier = last 2 chars, chain = the prefix before them.
- Time enters the sim only as an injected `now: float` (unix seconds). Never call `Time.*` inside `sim/`.
- Randomness only via an injected `RandomNumberGenerator`.
- Energy tuning (confirmed): cap **100**, **+1 energy per 120 s**, stored in `config/curio_hall_tuning.json`.
- Board is **7 wide × 9 tall**. Portrait 720×1280.
- Run tests with: `godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://test/unit -ginclude_subdirs -gexit` from `curio-hall/` (a `test.sh` wrapper is created in Task 1).
- Commit after every green test cycle. No em dashes in any game text or docs.

## File Structure

```
curio-hall/
  project.godot                 # Task 1 (autoload ConfigDB, portrait window)
  test.sh                       # Task 1 test runner wrapper
  addons/gut/                   # Task 1 (vendored GUT)
  config/*.json                 # Task 1 (copied verbatim) + curio_hall_tuning.json
  sim/config_db.gd              # Task 1  ConfigDB autoload: load + validate + lookups
  sim/weighted.gd               # Task 1  "201-100" weighted-list parsing/rolling
  sim/item_instance.gd          # Task 2
  sim/merge_board.gd            # Task 2 board grid + merge/move/sell/spiral spawn
  sim/board_layout.gd           # Task 3 BoardModelConfig parsing + cell states
  sim/energy_wallet.gd          # Task 4 energy regen + coins + gems
  sim/generator_state.gd        # Task 5 charge/storage recharge pools
  sim/lucky_roller.gd           # Task 6
  sim/player_state.gd           # Task 7 XP/levels + inventory
  sim/order_book.gd             # Task 8
  sim/game.gd                   # Task 5+ orchestrator (tap_generator, deliver, ...)
  sim/save_manager.gd           # Task 9
  view/item_view.gd             # Task 10 placeholder rendering (the art seam)
  view/board_view.gd            # Task 10 grid + drag input
  view/hud.gd                   # Task 11
  view/order_bar.gd             # Task 11
  view/inventory_panel.gd       # Task 11
  scenes/main.tscn + main.gd    # Task 12 wiring + save debounce
  test/unit/test_*.gd           # per task
```

---

### Task 1: Project scaffold, GUT, config copy, ConfigDB

**Files:**
- Create: `curio-hall/project.godot`, `curio-hall/test.sh`, `curio-hall/addons/gut/` (vendored), `curio-hall/config/*.json`, `curio-hall/sim/config_db.gd`, `curio-hall/sim/weighted.gd`
- Test: `curio-hall/test/unit/test_config_db.gd`, `curio-hall/test/unit/test_weighted.gd`

**Interfaces:**
- Produces: autoload `ConfigDB` with `items: Dictionary` (String id → row Dictionary), `board_layout: Array`, `order_random: Array`, `order_items: Array`, `levels: Array`, `lucky: Array`, `inventory_cfg: Dictionary`, `tuning: Dictionary`, `properties: Dictionary` (String id → row), `scores: Dictionary` (String id → row), and `func validate() -> Array[String]` (empty = valid). Also `Weighted.parse(entries: Array) -> Array[Dictionary]` (`[{"id": "201", "weight": 100}]`) and `Weighted.roll(parsed: Array, rng: RandomNumberGenerator) -> String`.

- [ ] **Step 1: Create the Godot project skeleton**

Verify a Godot 4 binary exists first: `godot --version` (if the command is missing, stop and ask the user how Godot is installed rather than downloading one).

`curio-hall/project.godot`:

```ini
config_version=5

[application]
config/name="Curio Hall"
run/main_scene=""

[autoload]
ConfigDB="*res://sim/config_db.gd"

[display]
window/size/viewport_width=720
window/size/viewport_height=1280
window/handheld/orientation=1
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
```

- [ ] **Step 2: Vendor GUT**



Check the cloned GUT's README states Godot 4 support; if the default branch targets a different major version, check out the tag matching the installed Godot version.

`curio-hall/test.sh`:

```bash
#!/bin/sh
cd "$(dirname "$0")"
godot --headless -s res://addons/gut/gut_cmdln.gd -gdir=res://test/unit -ginclude_subdirs -gexit
```

`chmod +x curio-hall/test.sh`. Run it once; expect "no tests found" style output, not a crash. (Godot's first headless run also imports the project; run `godot --headless --import` first if GUT scripts fail to load.)

- [ ] **Step 3: Copy config verbatim + write tuning file**

```bash


```

`curio-hall/config/curio_hall_tuning.json`:

```json
{ "energy_max": 100, "energy_regen_seconds": 120, "starting_energy": 100, "starting_coins": 0, "starting_gems": 0 }
```

- [ ] **Step 4: Write failing tests for Weighted and ConfigDB**

`curio-hall/test/unit/test_weighted.gd`:

```gdscript
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
```

`curio-hall/test/unit/test_config_db.gd`:

```gdscript
extends GutTest

func test_items_loaded_by_string_id() -> void:
    assert_true(ConfigDB.items.has("101"))
    assert_eq(ConfigDB.items["101"]["MergedType"], "102")

func test_worked_example_generator_104() -> void:
    var g: Dictionary = ConfigDB.items["104"]
    assert_eq(g["Spread_Weight"], ["201-100"])
    assert_eq(g["Spread_CostEnergy"], 1)
    assert_eq(g["Spread_ItemMaxNumber"], 80)
    assert_eq(g["Spread_StorageMaxNumber"], 240)

func test_board_layout_is_9_rows_of_7() -> void:
    assert_eq(ConfigDB.board_layout.size(), 9)
    for row in ConfigDB.board_layout:
        assert_eq((row as Array).size(), 7)

func test_tuning_loaded() -> void:
    assert_eq(ConfigDB.tuning["energy_max"], 100)

func test_validate_returns_no_errors() -> void:
    assert_eq(ConfigDB.validate(), [])
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL / script errors ("Weighted" not declared, ConfigDB missing members).

- [ ] **Step 6: Implement Weighted and ConfigDB**

`curio-hall/sim/weighted.gd`:

```gdscript
class_name Weighted

static func parse(entries: Array) -> Array[Dictionary]:
    var out: Array[Dictionary] = []
    for e in entries:
        var parts: PackedStringArray = String(e).rsplit("-", true, 1)
        out.append({"id": parts[0], "weight": int(parts[1])})
    return out

static func roll(parsed: Array, rng: RandomNumberGenerator) -> String:
    var total := 0
    for p in parsed:
        total += int(p["weight"])
    var pick := rng.randi_range(1, total)
    for p in parsed:
        pick -= int(p["weight"])
        if pick <= 0:
            return p["id"]
    return parsed[-1]["id"]
```

`curio-hall/sim/config_db.gd`:

```gdscript
extends Node
## Autoload. Loads all phase-1 config verbatim and validates cross-references.

var items: Dictionary = {}        # "101" -> row
var properties: Dictionary = {}   # "101" -> row
var scores: Dictionary = {}       # "101" -> row
var board_layout: Array = []
var order_random: Array = []
var order_items: Array = []
var levels: Array = []
var lucky: Array = []
var inventory_cfg: Dictionary = {}
var tuning: Dictionary = {}

func _ready() -> void:
    load_all()
    var errors := validate()
    if not errors.is_empty():
        push_error("Config validation failed:\n" + "\n".join(errors))
        assert(errors.is_empty())

func load_all(dir: String = "res://config/") -> void:
    for row in _read(dir + "ItemModelConfig.json"):
        if row != null: items[String(row["Type"])] = row
    for row in _read(dir + "ItemPropertyConfig.json"):
        if row != null: properties[String(row["Type"])] = row
    for row in _read(dir + "MergeItemScoreConfig.json"):
        if row != null: scores[String(row["item_id"])] = row
    board_layout = _read(dir + "BoardModelConfig.json")
    order_random = _read(dir + "OrderRandomConfig.json")
    order_items = _read(dir + "OrderItemConfig.json")
    levels = _read(dir + "LevelConfig.json")
    lucky = _read(dir + "LuckyProduceConfig.json")
    inventory_cfg = _read(dir + "InventorySlotConfig.json")
    tuning = _read(dir + "curio_hall_tuning.json")

func validate() -> Array[String]:
    var errors: Array[String] = []
    for id in items:
        var row: Dictionary = items[id]
        var merged := String(row.get("MergedType", ""))
        if merged != "" and not items.has(merged):
            errors.append("ItemModelConfig %s: MergedType %s missing" % [id, merged])
        for entry in row.get("Spread_Weight", []):
            var target: String = Weighted.parse([entry])[0]["id"]
            if not items.has(target):
                errors.append("ItemModelConfig %s: Spread_Weight target %s missing" % [id, target])
    for r in range(board_layout.size()):
        for cell in board_layout[r]:
            var id := String(cell).get_slice("#", String(cell).count("#"))
            if not items.has(id):
                errors.append("BoardModelConfig row %d: item %s missing" % [r, id])
    return errors

func _read(path: String) -> Variant:
    var f := FileAccess.open(path, FileAccess.READ)
    assert(f != null, "missing config file: " + path)
    var data: Variant = JSON.parse_string(f.get_as_text())
    assert(data != null, "bad JSON in " + path)
    return data
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add curio-hall
git commit -m "feat: scaffold Godot project with GUT, config pipeline, ConfigDB validation"
```

---

### Task 2: MergeBoard core (place, move, merge, sell, spiral spawn)

**Files:**
- Create: `curio-hall/sim/item_instance.gd`, `curio-hall/sim/merge_board.gd`
- Test: `curio-hall/test/unit/test_merge_board.gd`

**Interfaces:**
- Consumes: `ConfigDB.items`, `Weighted`.
- Produces: `ItemInstance` (`var type: String`, `var gen: Variant = null`, `static func make(type: String) -> ItemInstance`). `MergeBoard` (RefCounted): `const WIDTH := 7`, `const HEIGHT := 9`, `enum CellState { OPEN, COVERED, BOXED }`; signals `item_placed(pos: Vector2i, type: String)`, `items_merged(pos: Vector2i, new_type: String)`, `item_removed(pos: Vector2i)`, `cell_opened(pos: Vector2i, new_state: int)`; methods `item_at(pos) -> ItemInstance` (null if empty), `state_at(pos) -> int`, `set_state(pos, state)`, `place(pos, item) -> bool`, `remove(pos) -> ItemInstance`, `can_merge(a, b) -> bool`, `merge(a, b) -> String` ("" ok, else reason code `"mismatch"|"chain_top"|"not_open"|"empty"`), `move(from, to) -> String` ("" ok, else `"occupied"|"not_open"|"empty"`), `sell(pos) -> Dictionary` (`{"ok": bool, "coins": int, "reason": String}`), `find_free_cell(near: Vector2i) -> Vector2i` (`Vector2i(-1,-1)` if full), `spawn(type: String, near: Vector2i) -> Vector2i`, `count_of(type: String) -> int`, `remove_n_of(type: String, n: int) -> int`.

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_merge_board.gd`:

```gdscript
extends GutTest

var board: MergeBoard

func before_each() -> void:
    board = MergeBoard.new()

func test_merge_advances_tier() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("101"))
    assert_true(board.can_merge(Vector2i(0, 0), Vector2i(1, 0)))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "")
    assert_eq(board.item_at(Vector2i(1, 0)).type, "102")
    assert_null(board.item_at(Vector2i(0, 0)))

func test_merge_rejects_mismatch_and_chain_top() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("102"))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "mismatch")
    var top_id := ""
    for id in ConfigDB.items:
        if String(ConfigDB.items[id].get("MergedType", "")) == "":
            top_id = id
            break
    board.place(Vector2i(2, 0), ItemInstance.make(top_id))
    board.place(Vector2i(3, 0), ItemInstance.make(top_id))
    assert_eq(board.merge(Vector2i(2, 0), Vector2i(3, 0)), "chain_top")

func test_full_chain_walk_101_to_top() -> void:
    var id := "101"
    var steps := 0
    while String(ConfigDB.items[id].get("MergedType", "")) != "":
        board.place(Vector2i(0, 0), ItemInstance.make(id))
        board.place(Vector2i(1, 0), ItemInstance.make(id))
        assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "")
        id = board.item_at(Vector2i(1, 0)).type
        board.remove(Vector2i(1, 0))
        steps += 1
    assert_gt(steps, 5)

func test_move_and_occupied() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.place(Vector2i(1, 0), ItemInstance.make("102"))
    assert_eq(board.move(Vector2i(0, 0), Vector2i(2, 2)), "")
    assert_eq(board.item_at(Vector2i(2, 2)).type, "101")
    assert_eq(board.move(Vector2i(2, 2), Vector2i(1, 0)), "occupied")

func test_sell_uses_selling_price_and_rejects_zero() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("103"))
    var res := board.sell(Vector2i(0, 0))
    assert_true(res["ok"])
    assert_eq(res["coins"], 1)
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    assert_false(board.sell(Vector2i(0, 0))["ok"])

func test_spiral_spawn_prefers_near_cell() -> void:
    var pos := board.spawn("201", Vector2i(3, 4))
    assert_eq(pos, Vector2i(3, 4))
    var pos2 := board.spawn("201", Vector2i(3, 4))
    assert_true(pos2.distance_squared_to(Vector2i(3, 4)) <= 2)

func test_spawn_returns_minus_one_when_full() -> void:
    for x in range(MergeBoard.WIDTH):
        for y in range(MergeBoard.HEIGHT):
            board.place(Vector2i(x, y), ItemInstance.make("101"))
    assert_eq(board.spawn("201", Vector2i(0, 0)), Vector2i(-1, -1))

func test_covered_cells_reject_interaction() -> void:
    board.place(Vector2i(0, 0), ItemInstance.make("101"))
    board.set_state(Vector2i(0, 0), MergeBoard.CellState.COVERED)
    board.place(Vector2i(1, 0), ItemInstance.make("101"))
    assert_eq(board.merge(Vector2i(0, 0), Vector2i(1, 0)), "not_open")
    assert_eq(board.move(Vector2i(0, 0), Vector2i(2, 0)), "not_open")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL (MergeBoard/ItemInstance not declared).

- [ ] **Step 3: Implement ItemInstance and MergeBoard**

`curio-hall/sim/item_instance.gd`:

```gdscript
class_name ItemInstance
extends RefCounted

var type: String
var gen: Variant = null   # GeneratorState, attached in Task 5 for generator items

static func make(item_type: String) -> ItemInstance:
    var it := ItemInstance.new()
    it.type = item_type
    return it
```

`curio-hall/sim/merge_board.gd`:

```gdscript
class_name MergeBoard
extends RefCounted

const WIDTH := 7
const HEIGHT := 9
enum CellState { OPEN, COVERED, BOXED }

signal item_placed(pos: Vector2i, type: String)
signal items_merged(pos: Vector2i, new_type: String)
signal item_removed(pos: Vector2i)
signal cell_opened(pos: Vector2i, new_state: int)

var _items := {}    # Vector2i -> ItemInstance
var _states := {}   # Vector2i -> CellState; absent means OPEN

func in_bounds(pos: Vector2i) -> bool:
    return pos.x >= 0 and pos.x < WIDTH and pos.y >= 0 and pos.y < HEIGHT

func item_at(pos: Vector2i) -> ItemInstance:
    return _items.get(pos)

func state_at(pos: Vector2i) -> int:
    return _states.get(pos, CellState.OPEN)

func set_state(pos: Vector2i, state: int) -> void:
    if state == CellState.OPEN:
        _states.erase(pos)
    else:
        _states[pos] = state

func place(pos: Vector2i, item: ItemInstance) -> bool:
    if not in_bounds(pos) or _items.has(pos):
        return false
    _items[pos] = item
    item_placed.emit(pos, item.type)
    return true

func remove(pos: Vector2i) -> ItemInstance:
    var item: ItemInstance = _items.get(pos)
    if item != null:
        _items.erase(pos)
        item_removed.emit(pos)
    return item

func can_merge(a: Vector2i, b: Vector2i) -> bool:
    return merge_error(a, b) == ""

func merge_error(a: Vector2i, b: Vector2i) -> String:
    var ia := item_at(a)
    var ib := item_at(b)
    if ia == null or ib == null:
        return "empty"
    if state_at(a) != CellState.OPEN or state_at(b) != CellState.OPEN:
        return "not_open"
    if ia.type != ib.type:
        return "mismatch"
    if String(ConfigDB.items[ia.type].get("MergedType", "")) == "":
        return "chain_top"
    return ""

func merge(a: Vector2i, b: Vector2i) -> String:
    var err := merge_error(a, b)
    if err != "":
        return err
    var new_type := String(ConfigDB.items[item_at(a).type]["MergedType"])
    remove(a)
    remove(b)
    place(b, ItemInstance.make(new_type))
    _open_neighbors(a)
    _open_neighbors(b)
    items_merged.emit(b, new_type)
    return ""

func _open_neighbors(pos: Vector2i) -> void:
    for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
        var n: Vector2i = pos + d
        match state_at(n):
            CellState.COVERED:
                set_state(n, CellState.OPEN)
                cell_opened.emit(n, CellState.OPEN)
            CellState.BOXED:
                set_state(n, CellState.COVERED)
                cell_opened.emit(n, CellState.COVERED)

func move(from: Vector2i, to: Vector2i) -> String:
    if item_at(from) == null:
        return "empty"
    if state_at(from) != CellState.OPEN or state_at(to) != CellState.OPEN:
        return "not_open"
    if not in_bounds(to) or item_at(to) != null:
        return "occupied"
    place(to, remove(from))
    return ""

func sell(pos: Vector2i) -> Dictionary:
    var item := item_at(pos)
    if item == null or state_at(pos) != CellState.OPEN:
        return {"ok": false, "coins": 0, "reason": "not_open"}
    var price := int(ConfigDB.items[item.type].get("SellingPrice", 0))
    if price <= 0:
        return {"ok": false, "coins": 0, "reason": "unsellable"}
    remove(pos)
    return {"ok": true, "coins": price, "reason": ""}

func find_free_cell(near: Vector2i) -> Vector2i:
    for radius in range(0, WIDTH + HEIGHT):
        for y in range(near.y - radius, near.y + radius + 1):
            for x in range(near.x - radius, near.x + radius + 1):
                var p := Vector2i(x, y)
                if in_bounds(p) and item_at(p) == null and state_at(p) == CellState.OPEN:
                    return p
    return Vector2i(-1, -1)

func spawn(type: String, near: Vector2i) -> Vector2i:
    var pos := find_free_cell(near)
    if pos != Vector2i(-1, -1):
        place(pos, ItemInstance.make(type))
    return pos

func count_of(type: String) -> int:
    var n := 0
    for pos in _items:
        if state_at(pos) == CellState.OPEN and _items[pos].type == type:
            n += 1
    return n

func remove_n_of(type: String, n: int) -> int:
    var removed := 0
    for pos in _items.keys():
        if removed == n:
            break
        if state_at(pos) == CellState.OPEN and _items[pos].type == type:
            remove(pos)
            removed += 1
    return removed
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: all PASS. (The spiral in `find_free_cell` scans a growing square; the radius-0 pass returns `near` itself first, satisfying the nearness test.)

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: merge board core with config-driven merge/move/sell/spawn"
```

---

### Task 3: Board layout from BoardModelConfig

**Files:**
- Create: `curio-hall/sim/board_layout.gd`
- Test: `curio-hall/test/unit/test_board_layout.gd`

**Interfaces:**
- Consumes: `ConfigDB.board_layout`, `MergeBoard`, `ItemInstance`.
- Produces: `BoardLayout.apply(board: MergeBoard, layout: Array) -> void`. Cell string grammar: `"101"` = open item 101; `"c#102"` = COVERED item 102; `"pb#c#1002"` = BOXED item 1002. Design decision (documented assumption): a successful merge opens adjacent cells one stage (BOXED → COVERED → OPEN), implemented in Task 2's `_open_neighbors`.

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_board_layout.gd`:

```gdscript
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

func test_merging_the_two_starting_101s_uncovers_neighbor() -> void:
    var board := MergeBoard.new()
    BoardLayout.apply(board, ConfigDB.board_layout)
    # Starting layout has open "101" at (1,3) and (1,4).
    assert_eq(board.merge(Vector2i(1, 3), Vector2i(1, 4)), "")
    # The covered "c#102" at (2,4) is adjacent to (1,4)'s merge: now OPEN.
    assert_eq(board.state_at(Vector2i(2, 4)), MergeBoard.CellState.OPEN)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL (BoardLayout not declared).

- [ ] **Step 3: Implement BoardLayout**

`curio-hall/sim/board_layout.gd`:

```gdscript
class_name BoardLayout

static func apply(board: MergeBoard, layout: Array) -> void:
    for y in range(layout.size()):
        var row: Array = layout[y]
        for x in range(row.size()):
            var cell := String(row[x])
            var tokens := cell.split("#")
            var id: String = tokens[-1]
            var pos := Vector2i(x, y)
            board.place(pos, ItemInstance.make(id))
            if tokens.has("pb"):
                board.set_state(pos, MergeBoard.CellState.BOXED)
            elif tokens.has("c"):
                board.set_state(pos, MergeBoard.CellState.COVERED)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: PASS. If the position assertions fail, print the parsed layout and correct the test's expected coordinates against `config/BoardModelConfig.json` (row-major: `layout[y][x]`); the config is the source of truth, not this plan.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: starting board layout with covered/boxed cell states"
```

---

### Task 4: EnergyWallet

**Files:**
- Create: `curio-hall/sim/energy_wallet.gd`
- Test: `curio-hall/test/unit/test_energy_wallet.gd`

**Interfaces:**
- Consumes: `ConfigDB.tuning`.
- Produces: `EnergyWallet` (RefCounted): signal `changed`; `var coins: int`, `var gems: int`; `static func fresh(now: float) -> EnergyWallet`; `func energy(now: float) -> int`; `func spend_energy(n: int, now: float) -> bool`; `func add_energy(n: int, now: float) -> void`; `func add_coins(n: int) -> void`; `func spend_coins(n: int) -> bool`; `func add_gems(n: int) -> void`; `func spend_gems(n: int) -> bool`; `func seconds_to_next_energy(now: float) -> float`; `func to_dict() -> Dictionary`; `static func from_dict(d: Dictionary) -> EnergyWallet`.

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_energy_wallet.gd`:

```gdscript
extends GutTest

func test_starts_full_and_spends() -> void:
    var w := EnergyWallet.fresh(1000.0)
    assert_eq(w.energy(1000.0), 100)
    assert_true(w.spend_energy(30, 1000.0))
    assert_eq(w.energy(1000.0), 70)
    assert_false(w.spend_energy(999, 1000.0))

func test_regenerates_one_per_120s_capped() -> void:
    var w := EnergyWallet.fresh(1000.0)
    w.spend_energy(10, 1000.0)
    assert_eq(w.energy(1000.0 + 119.0), 90)
    assert_eq(w.energy(1000.0 + 120.0), 91)
    assert_eq(w.energy(1000.0 + 120.0 * 5), 95)
    assert_eq(w.energy(1000.0 + 120.0 * 100000), 100)

func test_coins_gems_atomic() -> void:
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10)
    assert_false(w.spend_coins(11))
    assert_eq(w.coins, 10)
    assert_true(w.spend_coins(10))
    assert_eq(w.coins, 0)

func test_round_trip() -> void:
    var w := EnergyWallet.fresh(1000.0)
    w.spend_energy(7, 1000.0)
    w.add_coins(5)
    var w2 := EnergyWallet.from_dict(w.to_dict())
    assert_eq(w2.energy(1000.0), 93)
    assert_eq(w2.coins, 5)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement EnergyWallet**

`curio-hall/sim/energy_wallet.gd`:

```gdscript
class_name EnergyWallet
extends RefCounted

signal changed

var coins: int = 0
var gems: int = 0
var _energy_base: int = 0     # energy at _energy_ts
var _energy_ts: float = 0.0

static func fresh(now: float) -> EnergyWallet:
    var w := EnergyWallet.new()
    w.coins = int(ConfigDB.tuning["starting_coins"])
    w.gems = int(ConfigDB.tuning["starting_gems"])
    w._energy_base = int(ConfigDB.tuning["starting_energy"])
    w._energy_ts = now
    return w

func _cap() -> int:
    return int(ConfigDB.tuning["energy_max"])

func _regen() -> float:
    return float(ConfigDB.tuning["energy_regen_seconds"])

func energy(now: float) -> int:
    return mini(_cap(), _energy_base + int(floor((now - _energy_ts) / _regen())))

func _settle(now: float) -> void:
    var e := energy(now)
    if e >= _cap():
        _energy_base = _cap()
        _energy_ts = now
    else:
        # keep the fractional progress toward the next point
        var accrued := int(floor((now - _energy_ts) / _regen()))
        _energy_base += accrued
        _energy_ts += accrued * _regen()

func spend_energy(n: int, now: float) -> bool:
    _settle(now)
    if energy(now) < n:
        return false
    _energy_base -= n
    changed.emit()
    return true

func add_energy(n: int, now: float) -> void:
    _settle(now)
    _energy_base = mini(_cap(), _energy_base + n)
    changed.emit()

func seconds_to_next_energy(now: float) -> float:
    if energy(now) >= _cap():
        return 0.0
    return _regen() - fmod(now - _energy_ts, _regen())

func add_coins(n: int) -> void:
    coins += n
    changed.emit()

func spend_coins(n: int) -> bool:
    if coins < n:
        return false
    coins -= n
    changed.emit()
    return true

func add_gems(n: int) -> void:
    gems += n
    changed.emit()

func spend_gems(n: int) -> bool:
    if gems < n:
        return false
    gems -= n
    changed.emit()
    return true

func to_dict() -> Dictionary:
    return {"coins": coins, "gems": gems, "energy_base": _energy_base, "energy_ts": _energy_ts}

static func from_dict(d: Dictionary) -> EnergyWallet:
    var w := EnergyWallet.new()
    w.coins = int(d["coins"])
    w.gems = int(d["gems"])
    w._energy_base = int(d["energy_base"])
    w._energy_ts = float(d["energy_ts"])
    return w
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: energy wallet with timestamp regen, coins, gems"
```

---

### Task 5: GeneratorState + Game orchestrator (tap to spawn)

**Files:**
- Create: `curio-hall/sim/generator_state.gd`, `curio-hall/sim/game.gd`
- Modify: `curio-hall/sim/item_instance.gd` (attach GeneratorState for generator types)
- Test: `curio-hall/test/unit/test_generator.gd`

**Interfaces:**
- Consumes: `ConfigDB.items` `Spread_*` fields, `EnergyWallet`, `MergeBoard`, `Weighted`.
- Produces: `GeneratorState` (RefCounted): `static func for_type(type: String, now: float) -> GeneratorState` (null for non-generators); `func charges(now: float) -> int`; `func storage(now: float) -> int`; `func consume(now: float) -> bool` (uses a charge first, then storage); `func to_dict() -> Dictionary` / `static func from_dict(d: Dictionary) -> GeneratorState`. `ItemInstance.make(type, now := 0.0)` now attaches `gen` when the type has `Spread_Weight`. `Game` (RefCounted): `var board: MergeBoard`, `var wallet: EnergyWallet`, `var rng: RandomNumberGenerator`; signal `spawned(pos: Vector2i, type: String)`; `static func fresh(now: float, seed_value: int = 0) -> Game` (applies BoardLayout); `func tap_generator(pos: Vector2i, now: float) -> Dictionary` (`{"ok": bool, "reason": String, "spawned": Array}` with reasons `"not_generator"|"no_energy"|"no_charge"|"board_full"`).

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_generator.gd`:

```gdscript
extends GutTest

func _game() -> Game:
    var g := Game.fresh(1000.0, 42)
    return g

func test_generator_state_charges_and_recovery() -> void:
    # Worked example from HANDOFF: generator 104, caps 80/240, recovery 2s/30s.
    var gs := GeneratorState.for_type("104", 1000.0)
    assert_eq(gs.charges(1000.0), 80)
    for i in range(80):
        assert_true(gs.consume(1000.0))
    assert_eq(gs.charges(1000.0), 0)
    assert_eq(gs.charges(1002.0), 1)   # 1 charge back after 2 s
    assert_eq(gs.charges(1000.0 + 2.0 * 80 * 10), 80)  # capped

func test_non_generator_has_no_state() -> void:
    assert_null(GeneratorState.for_type("101", 0.0))

func test_tap_spawns_weighted_item_and_spends_energy() -> void:
    var g := _game()
    var pos := g.board.spawn("104", Vector2i(6, 8))
    var before := g.wallet.energy(1000.0)
    var res := g.tap_generator(pos, 1000.0)
    assert_true(res["ok"])
    assert_eq(res["spawned"][0]["type"], "201")  # 104 only ever drops 201
    assert_eq(g.wallet.energy(1000.0), before - 1)  # Spread_CostEnergy 1

func test_tap_fails_without_energy() -> void:
    var g := _game()
    var pos := g.board.spawn("104", Vector2i(6, 8))
    g.wallet.spend_energy(g.wallet.energy(1000.0), 1000.0)
    var res := g.tap_generator(pos, 1000.0)
    assert_false(res["ok"])
    assert_eq(res["reason"], "no_energy")

func test_tap_on_normal_item_rejected() -> void:
    var g := _game()
    var pos := g.board.spawn("201", Vector2i(6, 8))
    assert_eq(g.tap_generator(pos, 1000.0)["reason"], "not_generator")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement GeneratorState, extend ItemInstance, implement Game**

`curio-hall/sim/generator_state.gd`:

```gdscript
class_name GeneratorState
extends RefCounted

var type: String
var _charge_used: int = 0      # charges consumed and not yet recovered
var _charge_ts: float = 0.0    # when recovery of the oldest missing charge began
var _storage_used: int = 0
var _storage_ts: float = 0.0

static func for_type(item_type: String, now: float) -> GeneratorState:
    var row: Dictionary = ConfigDB.items.get(item_type, {})
    if not row.has("Spread_Weight"):
        return null
    var gs := GeneratorState.new()
    gs.type = item_type
    gs._charge_ts = now
    gs._storage_ts = now
    return gs

func _row() -> Dictionary:
    return ConfigDB.items[type]

func _recovered(used: int, ts: float, duration: float, now: float) -> int:
    if used == 0 or duration <= 0.0:
        return used
    return mini(used, int(floor((now - ts) / duration)))

func charges(now: float) -> int:
    var cap := int(_row().get("Spread_ItemMaxNumber", 0))
    var dur := float(_row().get("Spread_ItemRecoveryDuration", 0))
    return cap - _charge_used + _recovered(_charge_used, _charge_ts, dur, now)

func storage(now: float) -> int:
    var cap := int(_row().get("Spread_StorageMaxNumber", 0))
    var dur := float(_row().get("Spread_StorageRecoveryDuration", 0))
    return cap - _storage_used + _recovered(_storage_used, _storage_ts, dur, now)

func _settle_pool(used: int, ts: float, duration: float, now: float) -> Array:
    var rec := _recovered(used, ts, duration, now)
    return [used - rec, (now if rec == used else ts + rec * duration)]

func consume(now: float) -> bool:
    var row := _row()
    var s := _settle_pool(_charge_used, _charge_ts, float(row.get("Spread_ItemRecoveryDuration", 0)), now)
    _charge_used = s[0]; _charge_ts = s[1]
    if charges(now) > 0:
        if _charge_used == 0:
            _charge_ts = now
        _charge_used += 1
        return true
    s = _settle_pool(_storage_used, _storage_ts, float(row.get("Spread_StorageRecoveryDuration", 0)), now)
    _storage_used = s[0]; _storage_ts = s[1]
    if storage(now) > 0:
        if _storage_used == 0:
            _storage_ts = now
        _storage_used += 1
        return true
    return false

func to_dict() -> Dictionary:
    return {"type": type, "charge_used": _charge_used, "charge_ts": _charge_ts,
            "storage_used": _storage_used, "storage_ts": _storage_ts}

static func from_dict(d: Dictionary) -> GeneratorState:
    var gs := GeneratorState.new()
    gs.type = String(d["type"])
    gs._charge_used = int(d["charge_used"])
    gs._charge_ts = float(d["charge_ts"])
    gs._storage_used = int(d["storage_used"])
    gs._storage_ts = float(d["storage_ts"])
    return gs
```

Modify `curio-hall/sim/item_instance.gd` (`make` gains a `now` parameter; existing call sites keep working via the default):

```gdscript
class_name ItemInstance
extends RefCounted

var type: String
var gen: GeneratorState = null

static func make(item_type: String, now: float = 0.0) -> ItemInstance:
    var it := ItemInstance.new()
    it.type = item_type
    it.gen = GeneratorState.for_type(item_type, now)
    return it
```

`curio-hall/sim/game.gd`:

```gdscript
class_name Game
extends RefCounted

signal spawned(pos: Vector2i, type: String)

var board: MergeBoard
var wallet: EnergyWallet
var rng := RandomNumberGenerator.new()

static func fresh(now: float, seed_value: int = 0) -> Game:
    var g := Game.new()
    g.board = MergeBoard.new()
    BoardLayout.apply(g.board, ConfigDB.board_layout)
    g.wallet = EnergyWallet.fresh(now)
    if seed_value != 0:
        g.rng.seed = seed_value
    else:
        g.rng.randomize()
    return g

func tap_generator(pos: Vector2i, now: float) -> Dictionary:
    var item := board.item_at(pos)
    if item == null or item.gen == null or board.state_at(pos) != MergeBoard.CellState.OPEN:
        return {"ok": false, "reason": "not_generator", "spawned": []}
    var row: Dictionary = ConfigDB.items[item.type]
    var cost := int(row.get("Spread_CostEnergy", 0))
    if wallet.energy(now) < cost:
        return {"ok": false, "reason": "no_energy", "spawned": []}
    if item.gen.charges(now) <= 0 and item.gen.storage(now) <= 0:
        return {"ok": false, "reason": "no_charge", "spawned": []}
    var drop := Weighted.roll(Weighted.parse(row["Spread_Weight"]), rng)
    var target := board.find_free_cell(pos)
    if target == Vector2i(-1, -1):
        return {"ok": false, "reason": "board_full", "spawned": []}
    wallet.spend_energy(cost, now)
    item.gen.consume(now)
    board.place(target, ItemInstance.make(drop, now))
    spawned.emit(target, drop)
    return {"ok": true, "reason": "", "spawned": [{"pos": target, "type": drop}]}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: PASS (including all earlier suites: `ItemInstance.make` stayed backward compatible).

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: generators with charge/storage recharge and tap-to-spawn"
```

---

### Task 6: LuckyRoller (bonus drops on generator taps)

**Files:**
- Create: `curio-hall/sim/lucky_roller.gd`
- Modify: `curio-hall/sim/game.gd` (`tap_generator` rolls lucky after the normal drop)
- Test: `curio-hall/test/unit/test_lucky.gd`

**Interfaces:**
- Consumes: `ConfigDB.lucky` rows (`generator: Array`, `lucky_chance: [den, num]`, `lucky_items: ["204-63", ...]`, `level_min`, `level_max`), `Weighted`.
- Produces: `LuckyRoller.roll(generator_type: String, player_level: int, rng: RandomNumberGenerator) -> String` (empty string = no bonus). `Game.tap_generator` result's `"spawned"` array may gain a second entry `{"pos": ..., "type": ..., "lucky": true}`. `Game` gains `var player_level: int = 1`.

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_lucky.gd`:

```gdscript
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement LuckyRoller and hook into Game**

`curio-hall/sim/lucky_roller.gd`:

```gdscript
class_name LuckyRoller

static func roll(generator_type: String, player_level: int, rng: RandomNumberGenerator) -> String:
    for row in ConfigDB.lucky:
        if row == null:
            continue
        if not (row["generator"] as Array).has(generator_type):
            continue
        if player_level < int(row["level_min"]) or player_level > int(row["level_max"]):
            continue
        var chance: Array = row["lucky_chance"]   # [denominator, numerator]
        if rng.randi_range(1, int(chance[0])) > int(chance[1]):
            return ""
        return Weighted.roll(Weighted.parse(row["lucky_items"]), rng)
    return ""
```

In `curio-hall/sim/game.gd`, add `var player_level: int = 1` and, inside `tap_generator` just before the `return {"ok": true, ...}` line, replace the return with:

```gdscript
    var result := [{"pos": target, "type": drop}]
    var lucky_type := LuckyRoller.roll(item.type, player_level, rng)
    if lucky_type != "":
        var lucky_pos := board.find_free_cell(pos)
        if lucky_pos != Vector2i(-1, -1):
            board.place(lucky_pos, ItemInstance.make(lucky_type, now))
            spawned.emit(lucky_pos, lucky_type)
            result.append({"pos": lucky_pos, "type": lucky_type, "lucky": true})
    return {"ok": true, "reason": "", "spawned": result}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: lucky bonus drops on generator taps"
```

---

### Task 7: PlayerState (XP/levels + inventory)

**Files:**
- Create: `curio-hall/sim/player_state.gd`
- Modify: `curio-hall/sim/game.gd` (owns a PlayerState; `player_level` reads from it)
- Test: `curio-hall/test/unit/test_player_state.gd`

**Interfaces:**
- Consumes: `ConfigDB.levels` (`{level, cost, rewards}`), `ConfigDB.inventory_cfg` (`DefaultNumber: 5`, `MaxNumber: 32`, `UnlockCost: Array`).
- Produces: `PlayerState` (RefCounted): signal `leveled_up(new_level: int, item_rewards: Array)`; `var level: int = 1`, `var xp: int = 0`, `var inventory: Array[String] = []`, `var slots: int`; `func add_xp(n: int) -> Array` (returns item-grant reward types like `["104"]` from level rewards; non-item reward codes such as `"main_e_chest_new_1-1"` are skipped in phase 1); `func store(type: String) -> bool`; `func withdraw(index: int) -> String` ("" if bad index); `func next_slot_cost() -> int` (-1 if maxed); `func unlock_slot(wallet: EnergyWallet) -> bool` (spends gems); `func to_dict()` / `static func from_dict(d)`. `Game` gains `var player: PlayerState`; `Game.player_level` becomes `func` reading `player.level` (Task 6's field is replaced; update `LuckyRoller` call site to `player.level`).

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_player_state.gd`:

```gdscript
extends GutTest

func test_levels_up_per_level_config() -> void:
    var p := PlayerState.new()
    var cost1 := int(ConfigDB.levels[0]["cost"])   # 30 xp for level 1
    var granted := p.add_xp(cost1)
    assert_eq(p.level, 2)
    assert_has(granted, "104")   # LevelConfig level-1 rewards include "104-1"

func test_xp_overflow_carries() -> void:
    var p := PlayerState.new()
    p.add_xp(int(ConfigDB.levels[0]["cost"]) + 5)
    assert_eq(p.level, 2)
    assert_eq(p.xp, 5)

func test_inventory_defaults_and_store_limit() -> void:
    var p := PlayerState.new()
    assert_eq(p.slots, 5)
    for i in range(5):
        assert_true(p.store("201"))
    assert_false(p.store("201"))

func test_slot_unlock_costs_gems() -> void:
    var p := PlayerState.new()
    assert_eq(p.next_slot_cost(), 0)   # UnlockCost[5] == 0? use config value
    var expected := int(ConfigDB.inventory_cfg["UnlockCost"][p.slots])
    assert_eq(p.next_slot_cost(), expected)
    var w := EnergyWallet.fresh(0.0)
    w.add_gems(100000)
    assert_true(p.unlock_slot(w))
    assert_eq(p.slots, 6)

func test_withdraw() -> void:
    var p := PlayerState.new()
    p.store("201")
    assert_eq(p.withdraw(0), "201")
    assert_eq(p.inventory.size(), 0)
    assert_eq(p.withdraw(5), "")
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement PlayerState and wire into Game**

`curio-hall/sim/player_state.gd`:

```gdscript
class_name PlayerState
extends RefCounted

signal leveled_up(new_level: int, item_rewards: Array)

var level: int = 1
var xp: int = 0
var inventory: Array[String] = []
var slots: int = 5

func _init() -> void:
    slots = int(ConfigDB.inventory_cfg["DefaultNumber"])

func _cost_for(lvl: int) -> int:
    if lvl > ConfigDB.levels.size():
        return -1   # max level
    return int(ConfigDB.levels[lvl - 1]["cost"])

func add_xp(n: int) -> Array:
    xp += n
    var granted: Array = []
    while _cost_for(level) > 0 and xp >= _cost_for(level):
        xp -= _cost_for(level)
        var rewards: Array = ConfigDB.levels[level - 1].get("rewards", [])
        level += 1
        for r in rewards:
            var parsed: Dictionary = Weighted.parse([r])[0]   # "104-1" -> id 104, count 1
            if ConfigDB.items.has(parsed["id"]):
                for i in range(int(parsed["weight"])):
                    granted.append(parsed["id"])
        leveled_up.emit(level, granted)
    return granted

func store(type: String) -> bool:
    if inventory.size() >= slots:
        return false
    inventory.append(type)
    return true

func withdraw(index: int) -> String:
    if index < 0 or index >= inventory.size():
        return ""
    return inventory.pop_at(index)

func next_slot_cost() -> int:
    var costs: Array = ConfigDB.inventory_cfg["UnlockCost"]
    if slots >= int(ConfigDB.inventory_cfg["MaxNumber"]):
        return -1
    return int(costs[slots])

func unlock_slot(wallet: EnergyWallet) -> bool:
    var cost := next_slot_cost()
    if cost < 0 or not wallet.spend_gems(cost):
        return false
    slots += 1
    return true

func to_dict() -> Dictionary:
    return {"level": level, "xp": xp, "inventory": inventory.duplicate(), "slots": slots}

static func from_dict(d: Dictionary) -> PlayerState:
    var p := PlayerState.new()
    p.level = int(d["level"])
    p.xp = int(d["xp"])
    p.slots = int(d["slots"])
    for t in d["inventory"]:
        p.inventory.append(String(t))
    return p
```

In `curio-hall/sim/game.gd`: add `var player: PlayerState`, set `g.player = PlayerState.new()` in `fresh()`, delete the `player_level` var from Task 6, and change the lucky call to `LuckyRoller.roll(item.type, player.level, rng)`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: PASS. If `test_slot_unlock_costs_gems`'s first assertion fails because `UnlockCost[5]` is not 0, delete that first `assert_eq(p.next_slot_cost(), 0)` line; the config-derived assertion below it is the real check.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: player XP/levels from LevelConfig and inventory slots"
```

---

### Task 8: OrderBook (minimal order loop)

**Files:**
- Create: `curio-hall/sim/order_book.gd`
- Modify: `curio-hall/sim/game.gd` (owns OrderBook; `deliver_order`)
- Test: `curio-hall/test/unit/test_order_book.gd`

**Interfaces:**
- Consumes: `ConfigDB.order_random` (uses the `Type: 1` row: `RefreshTime`, `UnlockLevel`, `Point`, `Filters` by player level, `ItemAmounts` weights), `ConfigDB.order_items` (`Code`, `UnlockLevel`, `Price`, `Weight`, `DiffScore`), `MergeBoard.count_of/remove_n_of`, `PlayerState.inventory`.
- Produces: `OrderBook` (RefCounted): `const SLOTS := 3`; signal `orders_changed`; `var orders: Array[Dictionary]` where an order is `{"items": {"203": 2}, "coins": int, "xp": int, "created_at": float}`; `func fill(player_level: int, rng: RandomNumberGenerator, now: float) -> void` (tops up empty slots; respects `UnlockLevel` of the Type-1 row, so below that level slots stay empty); `func can_deliver(i: int, board: MergeBoard) -> bool`; `func deliver(i: int, board: MergeBoard) -> Dictionary` (`{"ok": bool, "coins": int, "xp": int}`; removes items from board, clears slot); `func to_dict()` / `static func from_dict(d)`. `Game` gains `var orders: OrderBook` (filled in `fresh` and after each deliver) and `func deliver_order(i: int, now: float) -> Dictionary` which pays the wallet, grants XP via `player.add_xp`, and spawns any level-reward items near the board center.

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_order_book.gd`:

```gdscript
extends GutTest

func _rng() -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = 42
    return rng

func test_fill_respects_unlock_level() -> void:
    var ob := OrderBook.new()
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
    ob.orders = [{"items": {"203": 2}, "coins": 4, "xp": 4, "created_at": 0.0}, null, null]
    var board := MergeBoard.new()
    board.place(Vector2i(0, 0), ItemInstance.make("203"))
    assert_false(ob.can_deliver(0, board))
    board.place(Vector2i(1, 0), ItemInstance.make("203"))
    assert_true(ob.can_deliver(0, board))
    var res := ob.deliver(0, board)
    assert_true(res["ok"])
    assert_eq(res["coins"], 4)
    assert_eq(board.count_of("203"), 0)
    assert_null(ob.orders[0])

func test_game_deliver_pays_wallet_and_xp() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4, "created_at": 0.0}, null, null]
    g.board.spawn("203", Vector2i(3, 4))
    var coins_before := g.wallet.coins
    var res := g.deliver_order(0, 1000.0)
    assert_true(res["ok"])
    assert_eq(g.wallet.coins, coins_before + 4)
    assert_eq(g.player.xp, 4)
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement OrderBook and Game.deliver_order**

`curio-hall/sim/order_book.gd`:

```gdscript
class_name OrderBook
extends RefCounted

const SLOTS := 3

signal orders_changed

var orders: Array = [null, null, null]

func _cfg() -> Dictionary:
    for row in ConfigDB.order_random:
        if int(row.get("Type", 0)) == 1:
            return row
    return {}

func pool_row(code: String) -> Dictionary:
    for row in ConfigDB.order_items:
        if String(row["Code"]) == code:
            return row
    return {}

func _pool_for_level(player_level: int) -> Array:
    var out: Array = []
    for row in ConfigDB.order_items:
        if row != null and int(row.get("UnlockLevel", 1)) <= player_level:
            out.append(row)
    return out

func fill(player_level: int, rng: RandomNumberGenerator, now: float) -> void:
    var cfg := _cfg()
    if player_level < int(cfg.get("UnlockLevel", 1)):
        return
    var pool := _pool_for_level(player_level)
    if pool.is_empty():
        return
    var amounts: Dictionary = cfg["ItemAmounts"]
    var kind_weights := Weighted.parse([
        "1-%d" % int(amounts.get("OneItemWeight", 100)),
        "2-%d" % int(amounts.get("TwoItemsWeight", 0)),
        "3-%d" % int(amounts.get("ThreeItemsWeight", 0)),
    ])
    var weighted_pool := Weighted.parse(pool.map(
        func(r: Dictionary) -> String: return "%s-%d" % [r["Code"], int(r.get("Weight", 1))]))
    for i in range(SLOTS):
        if orders[i] != null:
            continue
        var kinds := int(Weighted.roll(kind_weights, rng))
        var items := {}
        while items.size() < kinds:
            items[Weighted.roll(weighted_pool, rng)] = rng.randi_range(1, 2)
        var coins := 0
        var xp := 0
        for code in items:
            var row := pool_row(code)
            coins += int(row["Price"]) * int(items[code])
            xp += int(row.get("DiffScore", 1)) * int(items[code])
        orders[i] = {"items": items, "coins": coins, "xp": xp, "created_at": now}
    orders_changed.emit()

func can_deliver(i: int, board: MergeBoard) -> bool:
    var o: Variant = orders[i]
    if o == null:
        return false
    for code in o["items"]:
        if board.count_of(code) < int(o["items"][code]):
            return false
    return true

func deliver(i: int, board: MergeBoard) -> Dictionary:
    if not can_deliver(i, board):
        return {"ok": false, "coins": 0, "xp": 0}
    var o: Dictionary = orders[i]
    for code in o["items"]:
        board.remove_n_of(code, int(o["items"][code]))
    orders[i] = null
    orders_changed.emit()
    return {"ok": true, "coins": int(o["coins"]), "xp": int(o["xp"])}

func to_dict() -> Dictionary:
    return {"orders": orders.duplicate(true)}

static func from_dict(d: Dictionary) -> OrderBook:
    var ob := OrderBook.new()
    ob.orders = (d["orders"] as Array).duplicate(true)
    return ob
```

In `curio-hall/sim/game.gd`: add `var orders: OrderBook`; in `fresh()` set `g.orders = OrderBook.new()` and call `g.orders.fill(g.player.level, g.rng, now)`; add:

```gdscript
func deliver_order(i: int, now: float) -> Dictionary:
    var res := orders.deliver(i, board)
    if not res["ok"]:
        return res
    wallet.add_coins(int(res["coins"]))
    for reward_type in player.add_xp(int(res["xp"])):
        board.spawn(reward_type, Vector2i(3, 4))
    orders.fill(player.level, rng, now)
    return res
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: minimal order loop with config-weighted requests"
```

---

### Task 9: Save/load with offline accrual

**Files:**
- Create: `curio-hall/sim/save_manager.gd`
- Modify: `curio-hall/sim/game.gd` (`to_dict`/`from_dict`), `curio-hall/sim/merge_board.gd` (`to_dict`/`from_dict`)
- Test: `curio-hall/test/unit/test_save.gd`

**Interfaces:**
- Consumes: `to_dict`/`from_dict` on EnergyWallet, PlayerState, OrderBook, GeneratorState.
- Produces: `MergeBoard.to_dict() -> Dictionary` / `static func from_dict(d) -> MergeBoard` (serializes items as `{"x,y": {"type": ..., "state": int, "gen": Dictionary|null}}`). `Game.to_dict() -> Dictionary` (includes `"save_version": 1`) / `static func from_dict(d: Dictionary) -> Game`. `SaveManager` (plain class, static funcs): `const PATH := "user://save.json"`; `static func save(game: Game) -> void`; `static func load_game() -> Game` (null if no save); on corrupt JSON: copies file to `user://save.corrupt.json`, returns null.

- [ ] **Step 1: Write failing tests**

`curio-hall/test/unit/test_save.gd`:

```gdscript
extends GutTest

func before_each() -> void:
    if FileAccess.file_exists(SaveManager.PATH):
        DirAccess.remove_absolute(SaveManager.PATH)

func test_game_round_trip_preserves_board_wallet_player() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.spend_energy(5, 1000.0)
    g.wallet.add_coins(7)
    g.player.add_xp(3)
    g.board.spawn("203", Vector2i(3, 4))
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.wallet.energy(1000.0), 95)
    assert_eq(g2.wallet.coins, 7)
    assert_eq(g2.player.xp, 3)
    assert_eq(g2.board.count_of("203"), g.board.count_of("203"))
    assert_eq(g2.board.state_at(Vector2i(0, 0)), MergeBoard.CellState.BOXED)

func test_offline_energy_accrual() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.spend_energy(50, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.wallet.energy(1000.0 + 120.0 * 10), 60)
    assert_eq(g2.wallet.energy(1000.0 + 120.0 * 10000), 100)

func test_generator_state_survives_save() -> void:
    var g := Game.fresh(1000.0, 42)
    var pos := g.board.spawn("104", Vector2i(6, 8))
    g.tap_generator(pos, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.board.item_at(pos).gen.charges(1000.0), 79)

func test_save_and_load_file() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.add_coins(9)
    SaveManager.save(g)
    var g2 := SaveManager.load_game()
    assert_not_null(g2)
    assert_eq(g2.wallet.coins, 9)

func test_corrupt_save_backed_up() -> void:
    var f := FileAccess.open(SaveManager.PATH, FileAccess.WRITE)
    f.store_string("{not json")
    f.close()
    assert_null(SaveManager.load_game())
    assert_true(FileAccess.file_exists("user://save.corrupt.json"))
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement serialization**

Add to `curio-hall/sim/merge_board.gd`:

```gdscript
func to_dict() -> Dictionary:
    var cells := {}
    for pos in _items:
        var item: ItemInstance = _items[pos]
        cells["%d,%d" % [pos.x, pos.y]] = {
            "type": item.type,
            "state": state_at(pos),
            "gen": item.gen.to_dict() if item.gen != null else null,
        }
    return {"cells": cells}

static func from_dict(d: Dictionary) -> MergeBoard:
    var board := MergeBoard.new()
    for key in d["cells"]:
        var parts: PackedStringArray = String(key).split(",")
        var pos := Vector2i(int(parts[0]), int(parts[1]))
        var c: Dictionary = d["cells"][key]
        var item := ItemInstance.new()
        item.type = String(c["type"])
        if c["gen"] != null:
            item.gen = GeneratorState.from_dict(c["gen"])
        board.place(pos, item)
        board.set_state(pos, int(c["state"]))
    return board
```

Add to `curio-hall/sim/game.gd`:

```gdscript
const SAVE_VERSION := 1

func to_dict() -> Dictionary:
    return {
        "save_version": SAVE_VERSION,
        "board": board.to_dict(),
        "wallet": wallet.to_dict(),
        "player": player.to_dict(),
        "orders": orders.to_dict(),
    }

static func from_dict(d: Dictionary) -> Game:
    if int(d.get("save_version", 0)) != SAVE_VERSION:
        push_warning("save_version %s: no migration needed yet" % d.get("save_version"))
    var g := Game.new()
    g.board = MergeBoard.from_dict(d["board"])
    g.wallet = EnergyWallet.from_dict(d["wallet"])
    g.player = PlayerState.from_dict(d["player"])
    g.orders = OrderBook.from_dict(d["orders"])
    g.rng.randomize()
    return g
```

`curio-hall/sim/save_manager.gd`:

```gdscript
class_name SaveManager

const PATH := "user://save.json"
const CORRUPT_PATH := "user://save.corrupt.json"

static func save(game: Game) -> void:
    var f := FileAccess.open(PATH, FileAccess.WRITE)
    f.store_string(JSON.stringify(game.to_dict()))

static func load_game() -> Game:
    if not FileAccess.file_exists(PATH):
        return null
    var text := FileAccess.open(PATH, FileAccess.READ).get_as_text()
    var data: Variant = JSON.parse_string(text)
    if data == null or typeof(data) != TYPE_DICTIONARY:
        DirAccess.copy_absolute(PATH, CORRUPT_PATH)
        push_error("Corrupt save backed up to " + CORRUPT_PATH)
        return null
    return Game.from_dict(data)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: PASS. Note JSON round-trips ints as floats; the `int(...)` casts in every `from_dict` are what make this safe. If a test fails on a type mismatch, fix the cast, not the test.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test
git commit -m "feat: save/load with versioning, offline accrual, corrupt-save backup"
```

---

### Task 10: BoardView + ItemView placeholders + drag input

**Files:**
- Create: `curio-hall/view/item_view.gd`, `curio-hall/view/board_view.gd`
- Test: manual (headless smoke test comes in Task 12)

**Interfaces:**
- Consumes: `Game`, `MergeBoard` signals, `ConfigDB.items`.
- Produces: `ItemView` (Node2D): `func apply(item_type: String, cell_state: int) -> void` — THE art seam; everything visual about an item goes through this one function. `BoardView` (Node2D): `const CELL := 96`; `func setup(game: Game) -> void`; signal `sell_requested(pos: Vector2i)`; converts input to `game.tap_generator`, `game.board.merge/move`. Positions: cell (x, y) at pixel `(x * CELL + CELL/2, y * CELL + CELL/2)` inside the BoardView, which Task 12 centers on screen.

- [ ] **Step 1: Implement ItemView**

`curio-hall/view/item_view.gd`:

```gdscript
class_name ItemView
extends Node2D
## Placeholder rendering. When real art arrives, only apply() changes.

const SIZE := 88.0

var _type := ""
var _state := MergeBoard.CellState.OPEN
var _is_generator := false

func apply(item_type: String, cell_state: int) -> void:
    _type = item_type
    _state = cell_state
    _is_generator = ConfigDB.items.get(item_type, {}).has("Spread_Weight")
    queue_redraw()

static func chain_of(item_type: String) -> String:
    return item_type.substr(0, item_type.length() - 2)

static func tier_of(item_type: String) -> int:
    return int(item_type.substr(item_type.length() - 2))

func _draw() -> void:
    var chain := chain_of(_type)
    var tier := tier_of(_type)
    var hue := fmod(hash(chain) * 0.6180339887, 1.0)
    var col := Color.from_hsv(hue, 0.55, clampf(0.95 - tier * 0.04, 0.4, 0.95))
    match _state:
        MergeBoard.CellState.COVERED:
            col = col.darkened(0.6)
        MergeBoard.CellState.BOXED:
            col = Color(0.35, 0.28, 0.2)
    var rect := Rect2(-SIZE / 2, -SIZE / 2, SIZE, SIZE)
    draw_rect(rect, col, true)
    if _is_generator:
        draw_rect(rect, Color.GOLD, false, 4.0)
    var font := ThemeDB.fallback_font
    if _state == MergeBoard.CellState.BOXED:
        draw_string(font, Vector2(-SIZE / 2 + 6, 6), "?", HORIZONTAL_ALIGNMENT_CENTER, SIZE - 12, 28)
    else:
        draw_string(font, Vector2(-SIZE / 2 + 6, -8), chain, HORIZONTAL_ALIGNMENT_CENTER, SIZE - 12, 18)
        draw_string(font, Vector2(-SIZE / 2 + 6, 22), "T%d" % tier, HORIZONTAL_ALIGNMENT_CENTER, SIZE - 12, 22, Color.WHITE)
```

- [ ] **Step 2: Implement BoardView**

`curio-hall/view/board_view.gd`:

```gdscript
class_name BoardView
extends Node2D

const CELL := 96

signal sell_requested(pos: Vector2i)
signal action_rejected(reason: String)

var game: Game
var _views := {}          # Vector2i -> ItemView
var _drag_from := Vector2i(-1, -1)
var _dragging: ItemView = null

func setup(g: Game) -> void:
    game = g
    game.board.item_placed.connect(_on_placed)
    game.board.item_removed.connect(_on_removed)
    game.board.cell_opened.connect(_on_opened)
    for y in range(MergeBoard.HEIGHT):
        for x in range(MergeBoard.WIDTH):
            var pos := Vector2i(x, y)
            if game.board.item_at(pos) != null:
                _on_placed(pos, game.board.item_at(pos).type)

func _cell_center(pos: Vector2i) -> Vector2:
    return Vector2(pos.x * CELL + CELL / 2.0, pos.y * CELL + CELL / 2.0)

func _pos_at(point: Vector2) -> Vector2i:
    var p := Vector2i(int(point.x / CELL), int(point.y / CELL))
    return p if game.board.in_bounds(p) else Vector2i(-1, -1)

func _on_placed(pos: Vector2i, _type: String) -> void:
    var v: ItemView = _views.get(pos)
    if v == null:
        v = ItemView.new()
        add_child(v)
        _views[pos] = v
    v.position = _cell_center(pos)
    v.apply(game.board.item_at(pos).type, game.board.state_at(pos))

func _on_removed(pos: Vector2i) -> void:
    var v: ItemView = _views.get(pos)
    if v != null:
        v.queue_free()
        _views.erase(pos)

func _on_opened(pos: Vector2i, _new_state: int) -> void:
    if _views.has(pos):
        _views[pos].apply(game.board.item_at(pos).type, game.board.state_at(pos))

func _draw() -> void:
    for y in range(MergeBoard.HEIGHT):
        for x in range(MergeBoard.WIDTH):
            draw_rect(Rect2(x * CELL, y * CELL, CELL - 2, CELL - 2), Color(0, 0, 0, 0.15), true)

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        var pos := _pos_at(to_local(event.position))
        if event.pressed:
            _begin_drag(pos)
        else:
            _end_drag(pos)
    elif event is InputEventMouseMotion and _dragging != null:
        _dragging.position = to_local(event.position)

func _begin_drag(pos: Vector2i) -> void:
    if pos == Vector2i(-1, -1) or game.board.item_at(pos) == null:
        return
    _drag_from = pos
    _dragging = _views.get(pos)
    if _dragging != null:
        _dragging.z_index = 10

func _end_drag(pos: Vector2i) -> void:
    if _dragging == null:
        return
    _dragging.z_index = 0
    var from := _drag_from
    _dragging = null
    _drag_from = Vector2i(-1, -1)
    var now := Time.get_unix_time_from_system()
    if pos == from:
        var res := game.tap_generator(from, now)
        if not res["ok"] and res["reason"] != "not_generator":
            action_rejected.emit(res["reason"])
        _snap_back(from)
        return
    if pos == Vector2i(-1, -1):
        _snap_back(from)
        return
    var err := game.board.merge(from, pos)
    if err == "mismatch" or err == "chain_top" or err == "empty":
        err = game.board.move(from, pos)
    if err != "":
        action_rejected.emit(err)
        _snap_back(from)

func _snap_back(pos: Vector2i) -> void:
    var v: ItemView = _views.get(pos)
    if v != null:
        v.position = _cell_center(pos)
```

Note for the implementer: after a successful `merge` or `move`, the board's `item_removed`/`item_placed` signals fire and the `_views` bookkeeping in `_on_placed`/`_on_removed` repositions everything; `_snap_back` is only for rejected actions.

- [ ] **Step 3: Manual verification (deferred run)**

No standalone scene exists until Task 12; visually verifying drag/merge happens there. Verify now only that scripts parse: run `curio-hall/test.sh` — Expected: existing suites still PASS, no script errors in output.

- [ ] **Step 4: Commit**

```bash
git add curio-hall/view
git commit -m "feat: board view and placeholder item rendering with drag input"
```

---

### Task 11: HUD, OrderBar, InventoryPanel

**Files:**
- Create: `curio-hall/view/hud.gd`, `curio-hall/view/order_bar.gd`, `curio-hall/view/inventory_panel.gd`
- Test: manual in Task 12; script-parse check via test run

**Interfaces:**
- Consumes: `Game`, `EnergyWallet.changed`, `OrderBook.orders_changed`, `PlayerState`.
- Produces: `Hud` (VBoxContainer): `func setup(game: Game) -> void`, refreshes on a 1 s timer plus wallet signal. `OrderBar` (HBoxContainer): `func setup(game: Game) -> void`; deliver buttons call `game.deliver_order(i, now)`. `InventoryPanel` (VBoxContainer): `func setup(game: Game, board_view: BoardView) -> void`; a Store mode: `sell_requested` unused; instead a "Store" button stores the last-tapped item — phase 1 keeps it simple: one "Store item" button per inventory row and a grid of withdraw buttons.

- [ ] **Step 1: Implement the three controls**

`curio-hall/view/hud.gd`:

```gdscript
class_name Hud
extends VBoxContainer

var game: Game
var _energy := Label.new()
var _coins := Label.new()
var _level := Label.new()

func setup(g: Game) -> void:
    game = g
    for l in [_energy, _coins, _level]:
        add_child(l)
    game.wallet.changed.connect(refresh)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(refresh)
    add_child(t)
    refresh()

func refresh() -> void:
    var now := Time.get_unix_time_from_system()
    var e := game.wallet.energy(now)
    var suffix := "" if e >= int(ConfigDB.tuning["energy_max"]) else " (+1 in %ds)" % int(game.wallet.seconds_to_next_energy(now))
    _energy.text = "Energy: %d%s" % [e, suffix]
    _coins.text = "Coins: %d   Gems: %d" % [game.wallet.coins, game.wallet.gems]
    _level.text = "Level %d   XP %d" % [game.player.level, game.player.xp]
```

`curio-hall/view/order_bar.gd`:

```gdscript
class_name OrderBar
extends HBoxContainer

var game: Game

func setup(g: Game) -> void:
    game = g
    game.orders.orders_changed.connect(refresh)
    game.board.item_placed.connect(func(_p, _t): refresh())
    game.board.item_removed.connect(func(_p): refresh())
    refresh()

func refresh() -> void:
    for c in get_children():
        c.queue_free()
    for i in range(OrderBook.SLOTS):
        var o: Variant = game.orders.orders[i]
        var btn := Button.new()
        if o == null:
            btn.text = "-"
            btn.disabled = true
        else:
            var parts: Array[String] = []
            for code in o["items"]:
                parts.append("%s x%d (have %d)" % [code, o["items"][code], game.board.count_of(code)])
            btn.text = "%s\n%d coins" % [", ".join(parts), o["coins"]]
            btn.disabled = not game.orders.can_deliver(i, game.board)
            btn.pressed.connect(func(): game.deliver_order(i, Time.get_unix_time_from_system()))
        add_child(btn)
```

`curio-hall/view/inventory_panel.gd`:

```gdscript
class_name InventoryPanel
extends VBoxContainer

var game: Game
var board_view: BoardView
var _row := HBoxContainer.new()
var _hint := Label.new()

func setup(g: Game, bv: BoardView) -> void:
    game = g
    board_view = bv
    add_child(_hint)
    add_child(_row)
    var unlock := Button.new()
    unlock.text = "Unlock slot"
    unlock.pressed.connect(_on_unlock)
    add_child(unlock)
    refresh()

func _on_unlock() -> void:
    game.player.unlock_slot(game.wallet)
    refresh()

func refresh() -> void:
    _hint.text = "Inventory %d/%d (next slot: %s gems)" % [
        game.player.inventory.size(), game.player.slots,
        str(game.player.next_slot_cost()) if game.player.next_slot_cost() >= 0 else "max"]
    for c in _row.get_children():
        c.queue_free()
    for i in range(game.player.inventory.size()):
        var btn := Button.new()
        btn.text = game.player.inventory[i]
        btn.pressed.connect(func():
            var t := game.player.withdraw(i)
            if t != "" and game.board.spawn(t, Vector2i(3, 4)) == Vector2i(-1, -1):
                game.player.store(t)   # board full: put it back
            refresh())
        _row.add_child(btn)
```

- [ ] **Step 2: Verify scripts parse**

Run: `curio-hall/test.sh` — Expected: existing suites PASS, no parse errors.

- [ ] **Step 3: Commit**

```bash
git add curio-hall/view
git commit -m "feat: HUD, order bar, and inventory panel controls"
```

---

### Task 12: Main scene integration, save debounce, smoke test

**Files:**
- Create: `curio-hall/scenes/main.gd`, `curio-hall/scenes/main.tscn`
- Modify: `curio-hall/project.godot` (set main scene)
- Test: `curio-hall/test/unit/test_smoke.gd`

**Interfaces:**
- Consumes: everything above.
- Produces: a runnable game (`godot --path curio-hall`).

- [ ] **Step 1: Write the failing smoke test**

`curio-hall/test/unit/test_smoke.gd`:

```gdscript
extends GutTest

func test_main_scene_loads_and_full_loop_runs() -> void:
    if FileAccess.file_exists(SaveManager.PATH):
        DirAccess.remove_absolute(SaveManager.PATH)
    var scene: PackedScene = load("res://scenes/main.tscn")
    var main: Node = scene.instantiate()
    add_child_autofree(main)
    await wait_frames(2)
    var game: Game = main.game
    assert_not_null(game)
    # scripted loop: find a generator on the starting board, tap, merge two drops
    var now := 1000.0
    var gen_pos := Vector2i(-1, -1)
    for y in range(MergeBoard.HEIGHT):
        for x in range(MergeBoard.WIDTH):
            var it := game.board.item_at(Vector2i(x, y))
            if it != null and it.gen != null and game.board.state_at(Vector2i(x, y)) == MergeBoard.CellState.OPEN:
                gen_pos = Vector2i(x, y)
    if gen_pos == Vector2i(-1, -1):
        gen_pos = game.board.spawn("104", Vector2i(3, 4))
    var r1 := game.tap_generator(gen_pos, now)
    var r2 := game.tap_generator(gen_pos, now)
    assert_true(r1["ok"] and r2["ok"])
    var a: Vector2i = r1["spawned"][0]["pos"]
    var b: Vector2i = r2["spawned"][0]["pos"]
    if game.board.item_at(a).type == game.board.item_at(b).type:
        assert_eq(game.board.merge(a, b), "")
    SaveManager.save(game)
    assert_not_null(SaveManager.load_game())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `curio-hall/test.sh` — Expected: FAIL (main.tscn missing).

- [ ] **Step 3: Implement main scene**

`curio-hall/scenes/main.gd`:

```gdscript
extends Node

var game: Game
var _save_pending := false

@onready var board_view: BoardView = $BoardView
@onready var hud: Hud = $UI/Hud
@onready var order_bar: OrderBar = $UI/OrderBar
@onready var inventory: InventoryPanel = $UI/InventoryPanel

func _ready() -> void:
    var now := Time.get_unix_time_from_system()
    game = SaveManager.load_game()
    if game == null:
        game = Game.fresh(now)
    game.orders.fill(game.player.level, game.rng, now)
    board_view.setup(game)
    board_view.position = Vector2((720 - MergeBoard.WIDTH * BoardView.CELL) / 2.0, 260)
    hud.setup(game)
    order_bar.setup(game)
    inventory.setup(game, board_view)
    for sig in [game.board.item_placed, game.board.item_removed, game.wallet.changed]:
        sig.connect(func(..._args): _save_pending = true)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_flush_save)
    add_child(t)

func _flush_save() -> void:
    if _save_pending:
        _save_pending = false
        SaveManager.save(game)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        SaveManager.save(game)
```

`curio-hall/scenes/main.tscn` (text scene file):

```ini
[gd_scene load_steps=6 format=3]

[ext_resource type="Script" path="res://scenes/main.gd" id="1"]
[ext_resource type="Script" path="res://view/board_view.gd" id="2"]
[ext_resource type="Script" path="res://view/hud.gd" id="3"]
[ext_resource type="Script" path="res://view/order_bar.gd" id="4"]
[ext_resource type="Script" path="res://view/inventory_panel.gd" id="5"]

[node name="Main" type="Node"]
script = ExtResource("1")

[node name="BoardView" type="Node2D" parent="."]
script = ExtResource("2")

[node name="UI" type="CanvasLayer" parent="."]

[node name="Hud" type="VBoxContainer" parent="UI"]
offset_left = 10.0
offset_top = 10.0
offset_right = 350.0
offset_bottom = 110.0
script = ExtResource("3")

[node name="OrderBar" type="HBoxContainer" parent="UI"]
offset_left = 10.0
offset_top = 120.0
offset_right = 710.0
offset_bottom = 240.0
script = ExtResource("4")

[node name="InventoryPanel" type="VBoxContainer" parent="UI"]
offset_left = 10.0
offset_top = 1140.0
offset_right = 710.0
offset_bottom = 1270.0
script = ExtResource("5")
```

In `curio-hall/project.godot`, set `run/main_scene="res://scenes/main.tscn"`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `curio-hall/test.sh` — Expected: all suites PASS including smoke.

- [ ] **Step 5: Manual playtest (definition of done)**

Run: `godot --path curio-hall`. Verify by playing: tap the starting generators (gold border), merge spawned items, deliver an order once level 3+ (grind two orders' worth of merges), watch energy tick down and the +1 countdown, store/withdraw an item, quit and relaunch to confirm resume. Take a screenshot for the record if running in an environment that allows it.

- [ ] **Step 6: Commit**

```bash
git add curio-hall
git commit -m "feat: main scene wiring, debounced saves, smoke test - phase 1 playable"
```

---

## Self-review notes (already applied)

- Spec coverage: every §2 sim component has a task (Board T2, layout T3, wallet T4, generators T5, lucky T6, player/inventory T7, orders T8, saves T9); §3 views T10-T11; §4 persistence T9+T12; §5 tests distributed per task; §6 milestones map to task order.
- Known deliberate simplifications (documented in the spec): `ProtectLevel` sell-confirmation is view-only and deferred; `EnergyBoostItemConfig` is not consumed in phase 1; non-item level rewards (chests) are skipped; `pb#`/`c#` open-one-stage-per-adjacent-merge is an assumption to tune during playtest.
- Type consistency: item ids String everywhere; `now: float` threaded through all sim mutations; `ItemInstance.make(type, now := 0.0)` keeps Task 2 call sites valid after Task 5.
```
