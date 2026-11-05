# Curio Hall Phase 4a: MainTask Campaign + Hall Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Coins earned from orders pay for the 4,107-task MainTask restoration campaign, presented on a pannable 2D floor-plan map of the 47 Hall wings, with save v4.

**Architecture:** A new time-free `Campaign` RefCounted sim class (current day + completed-task set) alongside the existing pure-logic sim; task costs spend through the existing atomic `EnergyWallet.spend_coins`; the `Rewards` grammar gains `exp`; the view adds a `MapPanel` CanvasLayer overlay (ShopPanel pattern) driven by a hand-authored `HallLayout` table.

**Tech Stack:** Godot 4.7.1 / GDScript, GUT headless tests

**Spec:** `docs/superpowers/specs/2026-09-03-curio-hall-phase4a-campaign-design.md` — note its **task-currency correction**: MainTask `cost` is paid in coins , NOT a new points currency; `OrderRandomConfig.Point` is an event currency deferred to phase 5.

## Global Constraints

- Warnings are errors: never `var x := <Dictionary/Array lookup>`; annotate types explicitly. Never bare integer division (`i / 6` on ints fails the build; use `int(i / 6.0)`).
- Run tests with `./curio-hall/test.sh` from the repo root. After creating any NEW `class_name` script, run `(cd curio-hall && godot --headless --import)` once or the class resolves as "nonexistent function".
- The starting board is FULL (all 63 cells). Sim tests that need an item placed must first free a cell: `g.board.remove(pos)` + `g.board.set_state(pos, MergeBoard.CellState.OPEN)`.
- All reward grants go through `Rewards.grant`/`grant_all`; all spends are check-then-spend with no partial mutation (`EnergyWallet.spend_coins` already is).
- The campaign is **time-free**: no timers, no tick host, nothing added to `main.gd`'s 1s timer.
- New files use 4-space indentation; edits to existing files match that file's style (`order_book.gd`, `rewards.gd`, `config_db.gd` use tabs).
- `SAVE_VERSION` becomes 4; a version/shape mismatch backs up to `save.corrupt.json` and resets (no migration).


---

### Task 1: `exp` reward token + `Game.grant_xp`

**Files:**
- Modify: `curio-hall/sim/rewards.gd` (tabs)
- Modify: `curio-hall/sim/game.gd`
- Test: `curio-hall/test/unit/test_rewards.gd` (append)

**Interfaces:**
- Consumes: `PlayerState.add_xp(n) -> Array[int]`, `Game._grant_level_rewards(gained, now)`.
- Produces: reward token `"exp-N"` grants XP through `Game.grant_xp(n: int, now: float) -> void` (public; also grants level-up rewards). `Rewards.parse("exp-15")` returns `{"kind": "xp", "id": "exp", "amount": 15}`.

- [ ] **Step 1: Write the failing test**

Append to `curio-hall/test/unit/test_rewards.gd` (match its existing indentation style):

```gdscript
func test_parse_exp_token() -> void:
	var r := Rewards.parse("exp-15")
	assert_eq(r["kind"], "xp")
	assert_eq(r["amount"], 15)

func test_grant_exp_adds_xp_and_level_rewards() -> void:
	var g := Game.fresh(1000.0, 42)
	var cost1 := int(ConfigDB.levels[0]["cost"])
	Rewards.grant("exp-%d" % (cost1 + 3), g, 1000.0)
	assert_eq(g.player.level, 2)   # leveled up, level-1 rewards granted via grant_xp
	assert_eq(g.player.xp, 3)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rewards.gd -gexit)`
Expected: FAIL — `parse("exp-15")["kind"]` is `"item"`, and grant warns "unknown item token".

- [ ] **Step 3: Implement**

In `curio-hall/sim/rewards.gd` (tabs): change the doc comment and `_CURRENCY`:

```gdscript
## "gold-N" = coins, "gem-N" = gems, "energy-N" = energy, "exp-N" = player XP,
## else item id + count.

const _CURRENCY := {"gold": "coins", "gem": "gems", "energy": "energy", "exp": "xp"}
```

and add a match arm in `grant` before `"item"`:

```gdscript
		"xp":
			game.grant_xp(int(r["amount"]), now)
```

In `curio-hall/sim/game.gd` add after `_grant_level_rewards`:

```gdscript
func grant_xp(n: int, now: float) -> void:
    _grant_level_rewards(player.add_xp(n), now)
```

and simplify `deliver_order`'s XP line to use it:

```gdscript
    grant_xp(int(res["xp"]), now)
```

(replacing `_grant_level_rewards(player.add_xp(int(res["xp"])), now)`).

- [ ] **Step 4: Run test to verify it passes**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_rewards.gd -gexit)` then `./curio-hall/test.sh`.
Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/rewards.gd curio-hall/sim/game.gd curio-hall/test/unit/test_rewards.gd
git commit -m "feat: exp reward token routes through Game.grant_xp"
```

---

### Task 2: ConfigDB loads MainTask + AreaUnlock

**Files:**
- Create: `curio-hall/config/MainTaskConfig.json`, `curio-hall/config/AreaUnlockConfig.json` 
- Modify: `curio-hall/sim/config_db.gd` (tabs)
- Test: `curio-hall/test/unit/test_config_db.gd` (append)

**Interfaces:**
- Produces: `ConfigDB.main_tasks: Dictionary` (`day:int -> Array[rows]`), `ConfigDB.main_task_by_key: Dictionary` (`"day_id" -> row`), `ConfigDB.area_tasks: Dictionary` (`area:int -> Array[rows]`), `ConfigDB.area_unlocks: Dictionary` (`area_id:int -> row`). Task key format is `"%d_%d" % [day, id]`. `validate()` warns (does NOT error) when an AreaUnlock `TaskCompleted-` condition references a missing task (the real config's `1_9` doesn't exist — spec erratum).

- [ ] **Step 1: Copy the config files**

```bash

```

- [ ] **Step 2: Write the failing test**

Append to `curio-hall/test/unit/test_config_db.gd` (match its indentation style):

```gdscript
func test_main_tasks_loaded_and_indexed() -> void:
	assert_eq((ConfigDB.main_tasks[1] as Array).size(), 7)   # day 1 has 7 tasks
	assert_eq(ConfigDB.main_tasks.size(), 282)               # 282 story days
	var row: Dictionary = ConfigDB.main_task_by_key["1_2"]
	assert_eq(int(row["cost"]), 16)
	assert_eq(int(row["area"]), 1)
	assert_true(ConfigDB.area_tasks.has(47))

func test_area_unlocks_loaded() -> void:
	var row: Dictionary = ConfigDB.area_unlocks[3]
	assert_eq(int(row["level"]), 5)
	assert_eq(String(row["condition"]), "TaskCompleted-1_9")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_config_db.gd -gexit)`
Expected: FAIL — `main_tasks` empty/nonexistent.

- [ ] **Step 4: Implement**

In `curio-hall/sim/config_db.gd` (tabs), add vars after `var bundles: Array = []`:

```gdscript
var main_tasks: Dictionary = {}       # day:int -> Array[rows]
var main_task_by_key: Dictionary = {} # "day_id" -> row
var area_tasks: Dictionary = {}       # area:int -> Array[rows]
var area_unlocks: Dictionary = {}     # area id -> row
```

In `load_all`, after the `bundles` line:

```gdscript
	for row in _read(dir + "MainTaskConfig.json"):
		if row == null:
			continue
		var task_day := int(row["day"])
		var task_area := int(row["area"])
		if not main_tasks.has(task_day):
			main_tasks[task_day] = []
		main_tasks[task_day].append(row)
		if not area_tasks.has(task_area):
			area_tasks[task_area] = []
		area_tasks[task_area].append(row)
		main_task_by_key["%d_%d" % [task_day, int(row["id"])]] = row
	for row in _read(dir + "AreaUnlockConfig.json"):
		if row != null:
			area_unlocks[int(row["id"])] = row
```

In `validate()`, before `return errors` add the warning (warning, not an error — see spec erratum):

```gdscript
	for area_id in area_unlocks:
		var cond := String(area_unlocks[area_id].get("condition", ""))
		if cond.begins_with("TaskCompleted-") and not main_task_by_key.has(cond.trim_prefix("TaskCompleted-")):
			push_warning("AreaUnlockConfig %s: condition task %s missing; treated as satisfied" % [area_id, cond])
```

- [ ] **Step 5: Run test to verify it passes**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_config_db.gd -gexit)` then `./curio-hall/test.sh`.
Expected: PASS (one pushed warning about `1_9` is fine), full suite green.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/config/MainTaskConfig.json curio-hall/config/AreaUnlockConfig.json curio-hall/sim/config_db.gd curio-hall/test/unit/test_config_db.gd
git commit -m "feat: load MainTask and AreaUnlock config"
```

---

### Task 3: `Campaign` sim

**Files:**
- Create: `curio-hall/sim/campaign.gd`
- Modify: `curio-hall/sim/game.gd`
- Test: `curio-hall/test/unit/test_campaign.gd` (create)

**Interfaces:**
- Consumes: `ConfigDB.main_tasks` / `main_task_by_key` / `area_tasks` / `area_unlocks` (Task 2), `EnergyWallet.spend_coins(n) -> bool`, `Rewards.grant_all` + `Game.grant_xp` (Task 1).
- Produces: `Campaign` (RefCounted) with `day: int`, `done: Dictionary`, `static task_key(d: int, id: int) -> String`, `tasks_today() -> Array`, `current_area() -> int`, `is_complete() -> bool`, `is_task_done(d: int, id: int) -> bool`, `is_area_unlocked(area: int, player: PlayerState) -> bool`, `area_state(area: int, player: PlayerState) -> AreaState` (enum `LOCKED/ACTIVE/RESTORED`), `wing_progress(area: int) -> Vector2i` (done, total), `complete_task(id: int, game, now: float) -> Dictionary` (`{ok, reason}`; reasons `not_today | already_done | area_locked | not_enough_coins`), signals `task_completed(day, id)`, `day_advanced(new_day)`, `area_restored(area)`, `to_dict()/from_dict()`. `Game` gains `campaign: Campaign` (in `fresh`) and `complete_task(id: int, now: float) -> Dictionary`.

- [ ] **Step 1: Write the failing test**

Create `curio-hall/test/unit/test_campaign.gd`:

```gdscript
extends GutTest
## Day-1 tasks (from MainTaskConfig): ids 1-7, costs 26,16,24,46,25,24,24 (sum 185),
## every task rewards exp-15 (some also reward items). Day 2 is area 2, day 8 area 3.

func _game_with_coins(coins: int) -> Game:
    var g := Game.fresh(1000.0, 42)
    g.wallet.coins = coins   # deterministic regardless of tuning starting_coins
    return g

func test_fresh_campaign_starts_day_1_area_1() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_eq(g.campaign.day, 1)
    assert_eq(g.campaign.current_area(), 1)
    assert_eq(g.campaign.tasks_today().size(), 7)
    assert_false(g.campaign.is_complete())

func test_complete_task_spends_coins_and_grants_rewards() -> void:
    var g := _game_with_coins(100)
    var xp_before := g.player.xp
    var res: Dictionary = g.complete_task(1, 1000.0)   # cost 26, rewards exp-15
    assert_true(res["ok"])
    assert_eq(g.wallet.coins, 74)
    assert_eq(g.player.xp, xp_before + 15)
    assert_true(g.campaign.is_task_done(1, 1))

func test_rejections_leave_state_unchanged() -> void:
    var g := _game_with_coins(30)
    assert_eq(g.complete_task(99, 1000.0)["reason"], "not_today")
    var res: Dictionary = g.complete_task(4, 1000.0)   # costs 46 > 30
    assert_eq(res["reason"], "not_enough_coins")
    assert_eq(g.wallet.coins, 30)
    assert_true(g.complete_task(1, 1000.0)["ok"])      # cost 26
    assert_eq(g.complete_task(1, 1000.0)["reason"], "already_done")
    assert_eq(g.wallet.coins, 4)

func test_day_advances_when_all_tasks_done() -> void:
    var g := _game_with_coins(1000)
    watch_signals(g.campaign)
    for id in range(1, 8):
        assert_true(g.complete_task(id, 1000.0)["ok"])
    assert_eq(g.campaign.day, 2)
    assert_eq(g.campaign.current_area(), 2)
    assert_signal_emitted_with_parameters(g.campaign, "day_advanced", [2])
    assert_signal_emitted_with_parameters(g.campaign, "area_restored", [1])
    assert_eq(g.campaign.area_state(1, g.player), Campaign.AreaState.RESTORED)
    assert_eq(g.campaign.area_state(2, g.player), Campaign.AreaState.ACTIVE)
    assert_eq(g.campaign.area_state(3, g.player), Campaign.AreaState.LOCKED)

func test_area_gate_level_and_condition() -> void:
    var g := Game.fresh(1000.0, 42)
    # Area 3 gate: level 5 + TaskCompleted-1_9. 1_9 doesn't exist -> condition
    # treated as satisfied (spec erratum); only the level gate bites.
    g.player.level = 4
    assert_false(g.campaign.is_area_unlocked(3, g.player))
    g.player.level = 5
    assert_true(g.campaign.is_area_unlocked(3, g.player))
    assert_true(g.campaign.is_area_unlocked(2, g.player))   # no gate row

func test_area_locked_rejects_completion() -> void:
    var g := _game_with_coins(10000)
    g.player.level = 4                       # below area-3 gate
    g.campaign.day = 8                       # first area-3 day
    var first_id := int(g.campaign.tasks_today()[0]["id"])
    var res: Dictionary = g.complete_task(first_id, 1000.0)
    assert_eq(res["reason"], "area_locked")
    g.player.level = 5
    assert_true(g.complete_task(first_id, 1000.0)["ok"])

func test_wing_progress_counts_area_tasks() -> void:
    var g := _game_with_coins(1000)
    assert_eq(g.campaign.wing_progress(1), Vector2i(0, 7))   # area 1 == day 1 only
    g.complete_task(1, 1000.0)
    assert_eq(g.campaign.wing_progress(1), Vector2i(1, 7))

func test_campaign_roundtrip() -> void:
    var g := _game_with_coins(1000)
    g.complete_task(1, 1000.0)
    g.complete_task(2, 1000.0)
    var c := Campaign.from_dict(g.campaign.to_dict())
    assert_eq(c.day, 1)
    assert_true(c.is_task_done(1, 1))
    assert_true(c.is_task_done(1, 2))
    assert_false(c.is_task_done(1, 3))

func test_is_complete_past_last_day() -> void:
    var c := Campaign.new()
    c.day = 283   # config has days 1..282
    assert_true(c.is_complete())
    assert_eq(c.area_state(47, PlayerState.new()), Campaign.AreaState.RESTORED)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_campaign.gd -gexit)`
Expected: FAIL — `Campaign` / `g.campaign` nonexistent.

- [ ] **Step 3: Implement `Campaign`**

Create `curio-hall/sim/campaign.gd`:

```gdscript
class_name Campaign
extends RefCounted
## MainTask restoration campaign. Story days (1..282) advance as their tasks
## complete; each day maps to exactly one of the 47 areas, monotonically.
## Task costs are paid in coins (see the spec's task-currency correction).
## Time-free by design: no timers, so no runtime tick host is needed.

signal task_completed(day: int, id: int)
signal day_advanced(new_day: int)
signal area_restored(area: int)

enum AreaState { LOCKED, ACTIVE, RESTORED }

var day: int = 1
var done: Dictionary = {}   # "day_id" -> true

static func task_key(d: int, id: int) -> String:
    return "%d_%d" % [d, id]

func tasks_today() -> Array:
    var rows: Array = ConfigDB.main_tasks.get(day, [])
    return rows

func is_complete() -> bool:
    return not ConfigDB.main_tasks.has(day)

func current_area() -> int:
    var rows := tasks_today()
    if rows.is_empty():
        return -1
    return int(rows[0]["area"])

func is_task_done(d: int, id: int) -> bool:
    return done.has(task_key(d, id))

func is_area_unlocked(area: int, player: PlayerState) -> bool:
    var row: Dictionary = ConfigDB.area_unlocks.get(area, {})
    if row.is_empty():
        return true
    if player.level < int(row.get("level", 1)):
        return false
    var cond := String(row.get("condition", ""))
    if cond.begins_with("TaskCompleted-"):
        var key := cond.trim_prefix("TaskCompleted-")
        # A condition naming a task that doesn't exist (the real config's 1_9)
        # is treated as satisfied — see the spec erratum.
        if ConfigDB.main_task_by_key.has(key):
            return done.has(key)
    return true

func area_state(area: int, player: PlayerState) -> AreaState:
    if is_complete():
        return AreaState.RESTORED
    var cur := current_area()
    if area < cur:
        return AreaState.RESTORED
    if area > cur:
        return AreaState.LOCKED
    return AreaState.ACTIVE if is_area_unlocked(area, player) else AreaState.LOCKED

func wing_progress(area: int) -> Vector2i:
    var finished := 0
    var rows: Array = ConfigDB.area_tasks.get(area, [])
    for row in rows:
        if done.has(task_key(int(row["day"]), int(row["id"]))):
            finished += 1
    return Vector2i(finished, rows.size())

func complete_task(id: int, game, now: float) -> Dictionary:
    var key := task_key(day, id)
    var row: Dictionary = ConfigDB.main_task_by_key.get(key, {})
    if row.is_empty():
        return {"ok": false, "reason": "not_today"}
    if done.has(key):
        return {"ok": false, "reason": "already_done"}
    if not is_area_unlocked(int(row["area"]), game.player):
        return {"ok": false, "reason": "area_locked"}
    if not game.wallet.spend_coins(int(row["cost"])):
        return {"ok": false, "reason": "not_enough_coins"}
    done[key] = true
    var rewards: Array = row.get("rewards", [])
    Rewards.grant_all(rewards, game, now)
    task_completed.emit(day, id)
    _advance_if_day_done()
    return {"ok": true, "reason": ""}

func _advance_if_day_done() -> void:
    for row in tasks_today():
        if not done.has(task_key(day, int(row["id"]))):
            return
    var finished_area := current_area()
    day += 1
    day_advanced.emit(day)
    if current_area() != finished_area:
        area_restored.emit(finished_area)

func to_dict() -> Dictionary:
    return {"day": day, "done": done.keys()}

static func from_dict(d: Dictionary) -> Campaign:
    var c := Campaign.new()
    c.day = int(d["day"])
    for k in d.get("done", []):
        c.done[String(k)] = true
    return c
```

In `curio-hall/sim/game.gd`: add `var campaign: Campaign` after `var iap: Iap`; in `fresh`, after `g.iap = Iap.new()`:

```gdscript
    g.campaign = Campaign.new()
```

and add after `buy_bundle`:

```gdscript
func complete_task(id: int, now: float) -> Dictionary:
    return campaign.complete_task(id, self, now)
```

(Save wiring — `to_dict`/`from_dict`/version — is Task 4; `Game.from_dict` does not touch campaign yet.)

- [ ] **Step 4: Run test to verify it passes**

Run: `(cd curio-hall && godot --headless --import)` (new class_name!) then `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_campaign.gd -gexit)` then `./curio-hall/test.sh`.
Expected: PASS. Note: day-1 rewards include item tokens (e.g. `2701-1`); if an id is missing from `ItemModelConfig`, `Rewards` warn-and-skips — a warning, not a failure.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/campaign.gd curio-hall/sim/game.gd curio-hall/test/unit/test_campaign.gd
git commit -m "feat: Campaign sim - coin-paid tasks, day advancement, area gating"
```

---

### Task 4: Save v4

**Files:**
- Modify: `curio-hall/sim/game.gd`
- Modify: `curio-hall/sim/save_manager.gd`
- Test: `curio-hall/test/unit/test_save.gd` (append)

**Interfaces:**
- Consumes: `Campaign.to_dict()/from_dict()` (Task 3).
- Produces: `Game.SAVE_VERSION == 4`; `Game.to_dict()` carries `"campaign"`; `Game.from_dict` restores it; `SaveManager.load_game()` requires the `campaign` key and rejects version != 4 (backing up to `save.corrupt.json`).

- [ ] **Step 1: Write the failing test**

Append to `curio-hall/test/unit/test_save.gd` (match its indentation and any existing helper/save-path conventions in that file):

```gdscript
func test_v4_roundtrip_campaign() -> void:
	var g := Game.fresh(1000.0, 42)
	g.wallet.coins = 50
	g.complete_task(2, 1000.0)   # day-1 task 2, cost 16
	var g2 := Game.from_dict(g.to_dict())
	assert_eq(g2.wallet.coins, 34)
	assert_eq(g2.campaign.day, 1)
	assert_true(g2.campaign.is_task_done(1, 2))

func test_save_version_is_4_and_campaign_key_present() -> void:
	var g := Game.fresh(1000.0, 42)
	var d := g.to_dict()
	assert_eq(int(d["save_version"]), 4)
	assert_true(d.has("campaign"))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_save.gd -gexit)`
Expected: FAIL — version is 3, no `campaign` key, `Game.from_dict` leaves `campaign` null.

- [ ] **Step 3: Implement**

In `curio-hall/sim/game.gd`:
- `const SAVE_VERSION := 4`
- `to_dict()`: add `"campaign": campaign.to_dict(),` after the `"iap"` entry.
- `from_dict()`: add `g.campaign = Campaign.from_dict(d["campaign"])` after the `g.iap` line.

In `curio-hall/sim/save_manager.gd`: extend the required-keys list:

```gdscript
        for key in ["board", "wallet", "player", "orders", "shop", "deals", "iap", "campaign"]:
```

(The existing version check already resets old saves once SAVE_VERSION is 4 — update its comment to say v3 saves reset on upgrade to v4.)

- [ ] **Step 4: Run test to verify it passes**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_save.gd -gexit)` then `./curio-hall/test.sh`.
Expected: PASS, full suite green.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/test/unit/test_save.gd
git commit -m "feat: save v4 with campaign state"
```

---

### Task 5: `HallLayout` floor plan

**Files:**
- Create: `curio-hall/view/hall_layout.gd`
- Test: `curio-hall/test/unit/test_hall_layout.gd` (create)

**Interfaces:**
- Produces: `HallLayout.wings() -> Array` of `{"area": int, "name": String, "rect": Rect2}` for areas 1..47 (canvas coordinates), and `HallLayout.canvas_size() -> Vector2`. Pure data + geometry; no game state.

- [ ] **Step 1: Write the failing test**

Create `curio-hall/test/unit/test_hall_layout.gd`:

```gdscript
extends GutTest

func test_47_wings_all_areas_once() -> void:
    var wings := HallLayout.wings()
    assert_eq(wings.size(), 47)
    var seen := {}
    for w in wings:
        seen[int(w["area"])] = true
    for area in range(1, 48):
        assert_true(seen.has(area), "area %d missing" % area)

func test_no_overlaps_and_inside_canvas() -> void:
    var wings := HallLayout.wings()
    var canvas := Rect2(Vector2.ZERO, HallLayout.canvas_size())
    for i in range(wings.size()):
        var a: Rect2 = wings[i]["rect"]
        assert_true(canvas.encloses(a), "wing %d outside canvas" % i)
        for j in range(i + 1, wings.size()):
            var b: Rect2 = wings[j]["rect"]
            assert_false(a.intersects(b), "wings %d and %d overlap" % [i, j])

func test_names_match_creative_direction() -> void:
    var by_area := {}
    for w in HallLayout.wings():
        by_area[int(w["area"])] = String(w["name"])
    assert_eq(by_area[1], "The Front Gates")
    assert_eq(by_area[2], "The Grand Atrium")
    assert_eq(by_area[47], "The Attic of Marvels")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless --import && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_hall_layout.gd -gexit)`
Expected: FAIL — `HallLayout` nonexistent.

- [ ] **Step 3: Implement**

Create `curio-hall/view/hall_layout.gd`:

```gdscript
class_name HallLayout
## Hand-authored floor plan of the 47 Hall wings (docs/creative-direction.md),
## laid out top-to-bottom in restoration order on one scrollable canvas.
## Pure data + geometry; no game state.

const CELL := Vector2(400.0, 230.0)
const GAP := 20.0
const COLS := 4

# One array per floor-plan row: [area, display name, column span].
const _ROWS: Array = [
    [[1, "The Front Gates", 4]],
    [[2, "The Grand Atrium", 2], [3, "The Cloakroom & Vestibule", 1], [4, "The Curator's Office", 1]],
    [[5, "The Tea Room", 1], [6, "The Hall of Feathers", 1], [7, "The Butterfly House", 1], [8, "The Conservatory", 1]],
    [[9, "The Fossil Gallery", 1], [10, "The Mineral Vault", 1], [11, "The Shell & Coral Room", 1], [12, "The Aquarium Grotto", 1]],
    [[13, "The Map Room", 1], [14, "The Library of Expeditions", 1], [15, "The Archives", 1], [16, "The Clockwork Workshop", 1]],
    [[17, "The Hall of Instruments", 1], [18, "The Astronomy Dome", 1], [19, "The Orrery Landing", 1], [20, "The Gaslight Gallery", 1]],
    [[21, "The Sculpture Court", 1], [22, "The Hall of Giants", 1], [23, "The Insectarium", 1], [24, "The Herbarium", 1]],
    [[25, "The Apothecary Annex", 1], [26, "The Gemstone Salon", 1], [27, "The Meteorite Chamber", 1], [28, "The Cabinet of Whispers", 1]],
    [[29, "The Portrait Stair", 1], [30, "The Founders' Gallery", 1], [31, "The Music Box Parlor", 1], [32, "The Print & Poster Room", 1]],
    [[33, "The Model Ship Hall", 1], [34, "The Balloon Loft", 1], [35, "The Observatory Walk", 1], [36, "The Moonlit Courtyard", 1]],
    [[37, "The Reflecting Pool", 1], [38, "The Glasshouse Menagerie", 1], [39, "The Night Garden", 1], [40, "The Deep Vaults", 1]],
    [[41, "The Forgotten Wing", 1], [42, "The Founder's Study", 1], [43, "The Hidden Passage", 1], [44, "The Chart Room of Lost Lands", 1]],
    [[45, "The Grand Ballroom", 2], [46, "The Clock Tower", 1], [47, "The Attic of Marvels", 1]],
]

static func wings() -> Array:
    var out: Array = []
    for r in range(_ROWS.size()):
        var x := GAP
        var row: Array = _ROWS[r]
        for entry in row:
            var e: Array = entry
            var span := int(e[2])
            var w := CELL.x * span + GAP * (span - 1)
            out.append({
                "area": int(e[0]),
                "name": String(e[1]),
                "rect": Rect2(x, GAP + r * (CELL.y + GAP), w, CELL.y),
            })
            x += w + GAP
    return out

static func canvas_size() -> Vector2:
    return Vector2(GAP + COLS * (CELL.x + GAP), GAP + _ROWS.size() * (CELL.y + GAP))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_hall_layout.gd -gexit)` then `./curio-hall/test.sh`.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/view/hall_layout.gd curio-hall/test/unit/test_hall_layout.gd
git commit -m "feat: HallLayout hand-authored 47-wing floor plan"
```

---

### Task 6: `MapPanel` overlay + main wiring + smoke test

**Files:**
- Create: `curio-hall/view/map_panel.gd`
- Modify: `curio-hall/scenes/main.gd`
- Modify: `curio-hall/scenes/main.tscn`
- Test: `curio-hall/test/unit/test_smoke.gd` (append)

**Interfaces:**
- Consumes: `Game.campaign` / `Game.complete_task(id, now)` (Tasks 3-4), `EnergyWallet.coins` + `wallet.changed`, `HallLayout.wings()/canvas_size()` (Task 5), `Campaign.AreaState`, `ConfigDB.main_task_by_key`.
- Produces: `MapPanel` (CanvasLayer) with `setup(g: Game)`, `open()`, `close()`, `signal action_rejected(reason: String)`. Main scene gets a Map button, three new `REJECT_MESSAGES` (`not_enough_coins` already exists), and save-pending wiring for task completion.

- [ ] **Step 1: Write the failing smoke test**

Append to `curio-hall/test/unit/test_smoke.gd` (match its indentation and helper conventions — it drives the sim, not the scene):

```gdscript
func test_campaign_smoke_deliver_then_complete_task() -> void:
	var g := Game.fresh(1000.0, 42)
	g.player.level = 5
	g.wallet.coins = 0
	g.orders.orders = [{"items": {"203": 1}, "coins": 20, "xp": 4,
			"created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
	g.board.remove(Vector2i(3, 4))
	g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
	g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
	assert_true(g.deliver_order(0, 1000.0)["ok"])
	assert_eq(g.wallet.coins, 20)                     # order coins earned
	assert_true(g.complete_task(2, 1000.0)["ok"])     # day-1 task 2 costs 16
	assert_eq(g.wallet.coins, 4)
	assert_eq(g.campaign.wing_progress(1), Vector2i(1, 7))
	var g2 := Game.from_dict(g.to_dict())             # quit/resume preserves it
	assert_eq(g2.wallet.coins, 4)
	assert_true(g2.campaign.is_task_done(1, 2))
```

- [ ] **Step 2: Run test to verify it passes already**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_smoke.gd -gexit)`
Expected: PASS (it exercises Tasks 1-4) — it guards the loop end to end. If it fails, an earlier task regressed; fix that first.

- [ ] **Step 3: Implement `MapPanel`**

Create `curio-hall/view/map_panel.gd`:

```gdscript
class_name MapPanel
extends CanvasLayer
## Pannable floor-plan map of the Hall: wing states, the current day's task
## pins, and a task card for paying coins. Placeholder styling.

signal action_rejected(reason: String)

# Original detail_icon name -> Curio Hall cast (docs/creative-direction.md).
# Icons outside the 11 cast slots fall back to a capitalized placeholder.
const CHARACTER_NAMES := {
    "cornelia": "Cornelia Wren", "barnaby": "Barnaby Pluck",
    "aldous": "Prof. Aldous Finch", "sam": "Jasper Vane",
    "mark": "Tobias Bloom", "anjali": "Anjali Bose",
    "hugo": "Hugo Pemberton", "prudence": "Prudence Quill",
    "zephyrine": "Zephyrine \"Zeph\" Blackwood", "rosalind": "Rosalind Thorne",
    "ambrose": "Ambrose Hall",
}

const WING_COLORS := {
    Campaign.AreaState.LOCKED: Color(0.13, 0.15, 0.18),
    Campaign.AreaState.ACTIVE: Color(0.16, 0.32, 0.34),    # deep teal
    Campaign.AreaState.RESTORED: Color(0.42, 0.30, 0.14),  # warm brass
}

var game: Game
var _root: PanelContainer
var _scroll: ScrollContainer
var _canvas: Control
var _header: Label
var _card: PanelContainer
var _selected_task := -1

func setup(g: Game) -> void:
    game = g
    layer = 10
    visible = false
    _root = PanelContainer.new()
    _root.anchor_right = 1.0
    _root.anchor_bottom = 1.0
    add_child(_root)
    var vbox := VBoxContainer.new()
    _root.add_child(vbox)
    var top := HBoxContainer.new()
    vbox.add_child(top)
    _header = Label.new()
    _header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    top.add_child(_header)
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.pressed.connect(close)
    top.add_child(close_b)
    _scroll = ScrollContainer.new()
    _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    vbox.add_child(_scroll)
    _canvas = Control.new()
    _canvas.custom_minimum_size = HallLayout.canvas_size()
    _scroll.add_child(_canvas)
    _card = PanelContainer.new()   # task card overlay, above the scroll
    _card.anchor_left = 0.08
    _card.anchor_right = 0.92
    _card.anchor_top = 0.35
    _card.anchor_bottom = 0.62
    _card.visible = false
    add_child(_card)
    game.campaign.task_completed.connect(func(_d: int, _i: int) -> void: refresh())
    game.campaign.day_advanced.connect(func(_d: int) -> void: refresh())
    game.wallet.changed.connect(refresh)

func open() -> void:
    visible = true
    _selected_task = -1
    refresh()
    call_deferred("_scroll_to_active")

func close() -> void:
    visible = false

func refresh() -> void:
    if not visible:
        return
    _header.text = "CURIO HALL — Day %d   Coins: %d" % [game.campaign.day, game.wallet.coins]
    for c in _canvas.get_children():
        c.queue_free()
    for wing in HallLayout.wings():
        _draw_wing(wing)
    _refresh_card()

func _draw_wing(wing: Dictionary) -> void:
    var rect: Rect2 = wing["rect"]
    var area := int(wing["area"])
    var state := game.campaign.area_state(area, game.player)
    var bg := ColorRect.new()
    bg.color = WING_COLORS[state]
    bg.position = rect.position
    bg.size = rect.size
    _canvas.add_child(bg)
    var name_l := Label.new()
    var suffix := ""
    match state:
        Campaign.AreaState.LOCKED:
            suffix = "  (locked)"
        Campaign.AreaState.ACTIVE:
            var prog := game.campaign.wing_progress(area)
            suffix = "  %d/%d" % [prog.x, prog.y]
        Campaign.AreaState.RESTORED:
            suffix = "  * restored"
    name_l.text = String(wing["name"]) + suffix
    name_l.position = rect.position + Vector2(10.0, 6.0)
    _canvas.add_child(name_l)
    if area == game.campaign.current_area():
        _draw_pins(rect)

func _draw_pins(rect: Rect2) -> void:
    var rows: Array = game.campaign.tasks_today()
    for i in range(rows.size()):
        var row: Dictionary = rows[i]
        var id := int(row["id"])
        var is_done := game.campaign.is_task_done(game.campaign.day, id)
        var b := Button.new()
        b.text = "OK" if is_done else "%dc" % int(row["cost"])
        b.disabled = is_done
        b.position = rect.position + Vector2(10.0 + (i % 6) * 63.0, 40.0 + int(i / 6.0) * 46.0)
        b.size = Vector2(58.0, 40.0)
        b.pressed.connect(_select_task.bind(id))
        _canvas.add_child(b)

func _select_task(id: int) -> void:
    _selected_task = id
    _refresh_card()

func _dismiss_card() -> void:
    _selected_task = -1
    _refresh_card()

func _refresh_card() -> void:
    for c in _card.get_children():
        c.queue_free()
    if _selected_task < 0:
        _card.visible = false
        return
    var key := Campaign.task_key(game.campaign.day, _selected_task)
    var row: Dictionary = ConfigDB.main_task_by_key.get(key, {})
    if row.is_empty() or game.campaign.is_task_done(game.campaign.day, _selected_task):
        _card.visible = false
        _selected_task = -1
        return
    _card.visible = true
    var v := VBoxContainer.new()
    _card.add_child(v)
    v.add_child(_mk_label(_wing_name(int(row["area"]))))
    var icon := String(row.get("detail_icon", "")).to_lower()
    v.add_child(_mk_label("Requested by: " + String(CHARACTER_NAMES.get(icon, icon.capitalize()))))
    var cost := int(row["cost"])
    v.add_child(_mk_label("Cost: %d coins   (you have %d)" % [cost, game.wallet.coins]))
    var complete_b := Button.new()
    complete_b.text = "Complete"
    complete_b.disabled = game.wallet.coins < cost
    complete_b.pressed.connect(_complete_selected)
    v.add_child(complete_b)
    var back_b := Button.new()
    back_b.text = "Back"
    back_b.pressed.connect(_dismiss_card)
    v.add_child(back_b)

func _complete_selected() -> void:
    var res: Dictionary = game.complete_task(_selected_task, Time.get_unix_time_from_system())
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    else:
        _selected_task = -1
    refresh()

func _mk_label(text: String) -> Label:
    var l := Label.new()
    l.text = text
    return l

func _wing_name(area: int) -> String:
    for wing in HallLayout.wings():
        if int(wing["area"]) == area:
            return String(wing["name"])
    return "Wing %d" % area

func _scroll_to_active() -> void:
    var cur := game.campaign.current_area()
    for wing in HallLayout.wings():
        if int(wing["area"]) == cur:
            var rect: Rect2 = wing["rect"]
            _scroll.scroll_vertical = int(maxf(0.0, rect.position.y - 200.0))
            _scroll.scroll_horizontal = int(maxf(0.0, rect.position.x - 100.0))
            return
```

(Note: `refresh()` rebuilds only `_canvas`/`_card` children; the panel owns no Timer, so the phase-2 self-freeing-timer trap can't occur here. `wallet.changed` may fire with args — if `connect(refresh)` arity-errors at runtime, wrap as `func(..._args) -> void: refresh()` like `main.gd` does.)

- [ ] **Step 4: Wire the main scene**

In `curio-hall/scenes/main.tscn`:
- Header: bump `load_steps=7` to `load_steps=8`.
- Add after the shop_panel ext_resource line:

```
[ext_resource type="Script" path="res://view/map_panel.gd" id="7"]
```

- Add after the ShopButton node:

```
[node name="MapButton" type="Button" parent="UI"]
offset_left = 480.0
offset_top = 10.0
offset_right = 590.0
offset_bottom = 50.0
text = "Map"
```

- Add after the ShopPanel node:

```
[node name="MapPanel" type="CanvasLayer" parent="."]
script = ExtResource("7")
```

In `curio-hall/scenes/main.gd`:
- Extend `REJECT_MESSAGES` with (`not_enough_coins` already exists):

```gdscript
    "not_today": "That task isn't on today's docket",
    "already_done": "Already completed",
    "area_locked": "That wing is still locked",
```

- Add `@onready` vars after `shop_button`:

```gdscript
@onready var map_panel: MapPanel = $MapPanel
@onready var map_button: Button = $UI/MapButton
```

- In `_ready`, after `shop_panel.action_rejected.connect(_show_toast)`:

```gdscript
    map_panel.setup(game)
    map_button.pressed.connect(map_panel.open)
    map_panel.action_rejected.connect(_show_toast)
```

- Extend the save-pending signal list to include task completion:

```gdscript
    for sig in [game.board.item_placed, game.board.item_removed, game.wallet.changed, game.shop.shop_changed, game.deals.deals_changed, game.campaign.task_completed]:
```

- [ ] **Step 5: Verify headless boot + full suite**

Run: `(cd curio-hall && godot --headless --import)` then `./curio-hall/test.sh`
Expected: full suite green, no script errors.
Then boot the scene headless for a few seconds to catch scene wiring errors:
`(cd curio-hall && timeout 10 godot --headless 2>&1 | head -40)` — expect no `SCRIPT ERROR` lines (the run being killed by timeout is fine). A hands-on windowed click-through is left to the user per convention.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/view/map_panel.gd curio-hall/scenes/main.gd curio-hall/scenes/main.tscn curio-hall/test/unit/test_smoke.gd
git commit -m "feat: MapPanel floor-plan overlay with task pins - phase 4a playable"
```

---

### Task 7: Roadmap update

**Files:**
- Modify: `docs/curio-hall-roadmap.md`

- [ ] **Step 1: Update the roadmap**

In `docs/curio-hall-roadmap.md`, replace the Phase 4 section with a split entry:

- **Phase 4a ✅** — MainTask campaign (282 story days — the old "290 chapters" figure was wrong — 4,107 coin-paid tasks), AreaUnlock gating, `exp` reward token, Hall floor-plan map with task pins, save v4. Spec: `docs/superpowers/specs/2026-09-03-curio-hall-phase4a-campaign-design.md`. Plan: `docs/superpowers/plans/2026-09-03-curio-hall-phase4a-campaign.md`. Notes: task costs are coins 
AreaUnlock's `TaskCompleted-1_9` references a nonexistent task and is treated as satisfied (level gate still applies); map pin positions are our own (only 93 config `edit_pos` rows exist); the `_fire` alternate campaign is ignored; task text awaits the text-rewrite track.
- **Phase 4b ⏳** — characters/intimacy (`CharacterIntimacy*`), special/branch/avatar orders, story recap.
- **Phase 4c ⏳** — `Skin` decoration of the wings.

- [ ] **Step 2: Commit**

```bash
git add docs/curio-hall-roadmap.md
git commit -m "docs: mark phase 4a complete, split phase 4 into 4a/4b/4c"
```
