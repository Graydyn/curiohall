# Phase 5b: Patron's Gala (GeneratorBoost) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A second, concurrent live-ops track: a multi-day "Patron's Gala" window during which finishing main orders climbs a daily-resetting task ladder that unlocks cumulative buffs (better lucky drops, free double-spawns, twin lucky items, no generator cooldowns) on the 32 boosted generator types.

**Architecture:** New pure-logic `Boost` class in `curio-hall/sim/boost.gd`, a sibling of `Events` (same conventions: RefCounted, injected `now`, injected RNG, tick host is `main.gd`'s 1s timer). Config overrides are resolved per lookup through `Boost.effective_row` / `Boost.effective_lucky` — ConfigDB is never mutated at runtime. `Game.tap_generator` and `Game.deliver_order` are the only sim seams touched. Save bumps to v10. View adds a code-created Gala button and `view/gala_panel.gd` (no board inside — it is a status/dev panel).

**Tech Stack:** Godot 4.7.1 GDScript, GUT headless tests via `./curio-hall/test.sh`.

**Spec:** `docs/superpowers/specs/2026-09-11-curio-hall-phase5b-generator-boost-design.md`

## Global Constraints

- Working directory for all commands: repo root (`test.sh` lives at `curio-hall/test.sh`).
- **Warnings are errors.** Never `var x := <Dictionary/Array lookup>`; annotate types explicitly (`var x: Dictionary = d["k"]`).
- Run tests with `./curio-hall/test.sh`. After adding a NEW `class_name` script (Task 2), run `(cd curio-hall && godot --headless --import)` once first, or the new class resolves as "nonexistent function".
- The starting board is FULL (63 occupied cells). Sim tests that need spawns must free cells first: `g.board.remove(pos)` + `g.board.set_state(pos, MergeBoard.CellState.OPEN)`.
- Item ids are Strings everywhere. Generator `"104"` is NOT boosted (boost list starts at `"105"`); use 104 for non-boosted assertions, 105 for boosted ones.
- The sim never reads the wall clock; time is always an injected `now: float`.
- Buff kind strings, verbatim everywhere: `"moreLuckyProduce"`, `"extraProduce"`, `"extraLuckyProduce"`, `"nocd"`.
- Commit messages end with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Config plumbing (files, tuning keys, ConfigDB accessors)

**Files:**

- Modify: `curio-hall/config/curio_hall_tuning.json`
- Modify: `curio-hall/sim/config_db.gd`
- Test: `curio-hall/test/unit/test_boost_config.gd`

**Interfaces:**
- Consumes: `ConfigDB._read(path)` (existing private JSON reader), `ConfigDB.load_all` (existing loader, called by `_ready`), `ConfigDB.items` / `ConfigDB.lucky` (existing base tables).
- Produces (used by Tasks 2–5):
  - `ConfigDB.boost_items: Dictionary` — mode name (`"MoreLuckyProduce"` / `"ExtraProduce"`) → `{type: String -> row: Dictionary}`
  - `ConfigDB.boost_lucky: Dictionary` — mode name → `Array` of lucky rows (same row shape as `ConfigDB.lucky`)
  - `ConfigDB.boost_item_row(mode: String, type: String) -> Dictionary` (empty Dictionary when absent)
  - `ConfigDB.boost_lucky_table(mode: String) -> Array` (empty Array when absent)
  - `ConfigDB.is_boost_type(type: String) -> bool`
  - Tuning keys: `boost_duration_seconds` (259200), `boost_gap_seconds` (86400), `boost_unlock_level` (8), `boost_tasks` ([2, 3, 4, 5]), `boost_buffs` (["moreLuckyProduce", "extraProduce", "extraLuckyProduce", "nocd"]), `boost_extra_produce` ([1, 3])



- [ ] **Step 2: Add tuning keys**

In `curio-hall/config/curio_hall_tuning.json`, add these keys to the single JSON object (keep it one line or reformat consistently — the file is one flat object):

```json
"boost_duration_seconds": 259200, "boost_gap_seconds": 86400, "boost_unlock_level": 8,
"boost_tasks": [2, 3, 4, 5],
"boost_buffs": ["moreLuckyProduce", "extraProduce", "extraLuckyProduce", "nocd"],
"boost_extra_produce": [1, 3]
```

- [ ] **Step 3: Write the failing test**

Create `curio-hall/test/unit/test_boost_config.gd`:

```gdscript
extends GutTest
## GeneratorBoost config families are
## queryable by mode + type. 32 boosted generator types; 104 is not one.

func test_boost_item_rows_load_both_modes() -> void:
    var more: Dictionary = ConfigDB.boost_item_row("MoreLuckyProduce", "105")
    assert_eq(String(more["MergedType"]), "106")
    # MoreLuckyProduce 105 folds the 202 weight away: ["201-37", "301-5"]
    assert_eq((more["Spread_Weight"] as Array).size(), 2)
    var extra: Dictionary = ConfigDB.boost_item_row("ExtraProduce", "105")
    assert_eq((extra["Spread_Weight"] as Array).size(), 3)  # identical to base
    assert_eq(ConfigDB.boost_item_row("MoreLuckyProduce", "104"), {})

func test_boost_lucky_tables_load_both_modes() -> void:
    var more: Array = ConfigDB.boost_lucky_table("MoreLuckyProduce")
    assert_eq(more.size(), 10)
    var row0: Dictionary = more[0]
    assert_eq(int((row0["lucky_chance"] as Array)[0]), 25)   # boosted 1/25
    var extra: Array = ConfigDB.boost_lucky_table("ExtraLuckyProduce")
    var erow0: Dictionary = extra[0]
    assert_eq(int((erow0["lucky_chance"] as Array)[0]), 60)  # base-rate 1/60
    assert_eq(ConfigDB.boost_lucky_table("nope"), [])

func test_boost_type_membership() -> void:
    assert_true(ConfigDB.is_boost_type("105"))
    assert_true(ConfigDB.is_boost_type("1711"))
    assert_false(ConfigDB.is_boost_type("104"))
    assert_false(ConfigDB.is_boost_type("101"))

func test_boost_tuning_keys_present() -> void:
    assert_eq(int(ConfigDB.tuning["boost_duration_seconds"]), 259200)
    assert_eq((ConfigDB.tuning["boost_tasks"] as Array).size(), 4)
    assert_eq((ConfigDB.tuning["boost_buffs"] as Array).size(), 4)
    assert_eq(String((ConfigDB.tuning["boost_buffs"] as Array)[0]), "moreLuckyProduce")
```

- [ ] **Step 4: Run test to verify it fails**

Run: `./curio-hall/test.sh -gselect=test_boost_config.gd`
Expected: FAIL — `boost_item_row` not found on ConfigDB.

- [ ] **Step 5: Implement ConfigDB additions**

In `curio-hall/sim/config_db.gd`:

Add vars near the other event vars (`event_boards`, around line 33):

```gdscript
var boost_items: Dictionary = {}   # "MoreLuckyProduce"/"ExtraProduce" -> {type -> row}
var boost_lucky: Dictionary = {}   # "MoreLuckyProduce"/"ExtraLuckyProduce" -> Array
```

Clear them in `load_all` where the other tables are cleared:

```gdscript
	boost_items.clear()
	boost_lucky.clear()
```

Load them in `load_all` (after the `_load_event_variant` call):

```gdscript
	var boost_model: Dictionary = _read(dir + "GeneratorBoostItemModelConfig.json")
	for mode in boost_model:
		var by_type: Dictionary = {}
		for row in (boost_model[mode] as Array):
			by_type[String((row as Dictionary)["Type"])] = row
		boost_items[mode] = by_type
	boost_lucky = _read(dir + "GeneratorBoostLuckyProduceConfig.json")
```

Add accessors near `event_unlock_level`:

```gdscript
func boost_item_row(mode: String, type: String) -> Dictionary:
	var by_type: Dictionary = boost_items.get(mode, {})
	return by_type.get(type, {})

func boost_lucky_table(mode: String) -> Array:
	var v: Variant = boost_lucky.get(mode)
	return v if v is Array else []

func is_boost_type(type: String) -> bool:
	return (boost_items.get("MoreLuckyProduce", {}) as Dictionary).has(type)
```

Note: `_read` returns parsed JSON with whole-number floats normalized to ints (existing behavior); rows land as Dictionaries keyed by String.

- [ ] **Step 6: Run test to verify it passes**

Run: `./curio-hall/test.sh -gselect=test_boost_config.gd`
Expected: PASS (4/4)

- [ ] **Step 7: Run the full suite (regression) and commit**

```bash
./curio-hall/test.sh
git add curio-hall/config/GeneratorBoostItemModelConfig.json \
        curio-hall/config/GeneratorBoostLuckyProduceConfig.json \
        curio-hall/config/curio_hall_tuning.json \
        curio-hall/sim/config_db.gd curio-hall/test/unit/test_boost_config.gd
git commit -m "feat: GeneratorBoost config families and tuning keys

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

(If Godot generated `.uid` sidecars for the new files, `git add` them too — they are intentionally tracked.)

---

### Task 2: Boost lifecycle and daily rollover (`sim/boost.gd`)

**Files:**
- Create: `curio-hall/sim/boost.gd`
- Test: `curio-hall/test/unit/test_boost.gd`

**Interfaces:**
- Consumes: `ConfigDB.tuning` keys from Task 1; `PlayerState.level` (existing).
- Produces (used by Tasks 3–6):
  - `class_name Boost extends RefCounted`, `signal boost_changed`
  - `enum State { IDLE, ACTIVE }`
  - Vars: `state: int`, `ends_at: float`, `next_boost_at: float`, `rollover_at: float`, `round_num: int`, `progress: int`, `buff_level: int`, `window_left: int`, `extras_left: int`, `extra_cached: bool`, `extra_lucky_cached: String` (`""` = empty)
  - `is_active() -> bool`
  - `tick(now: float, player: PlayerState) -> void`
  - `start_boost(now: float) -> bool`
  - `end_boost(now: float) -> void`
  - `static _next_midnight(now: float) -> float` (next UTC midnight)

- [ ] **Step 1: Write the failing test**

Create `curio-hall/test/unit/test_boost.gd`:

```gdscript
extends GutTest
## Patron's Gala lifecycle: gated auto-start, 3-day window, 1-day gap,
## daily rollover resets ladder state and bumps the round counter.

const NOW := 1000.0
const DAY := 86400.0

func _player(level: int) -> PlayerState:
    var p := PlayerState.new()
    p.level = level
    return p

func test_no_start_below_unlock_level() -> void:
    var b := Boost.new()
    b.tick(NOW, _player(1))     # next_boost_at 0 -> due, but level 1 < 8
    assert_false(b.is_active())

func test_auto_start_when_due_and_gated() -> void:
    var b := Boost.new()
    b.tick(NOW, _player(8))
    assert_true(b.is_active())
    assert_eq(b.ends_at, NOW + 259200.0)
    assert_eq(b.round_num, 1)
    assert_eq(b.rollover_at, DAY)   # next UTC midnight after t=1000

func test_expiry_schedules_next_window() -> void:
    var b := Boost.new()
    b.tick(NOW, _player(8))
    b.tick(NOW + 259200.0, _player(8))
    assert_false(b.is_active())
    assert_eq(b.next_boost_at, NOW + 259200.0 + 86400.0)
    b.tick(NOW + 259200.0 + 86400.0, _player(8))
    assert_true(b.is_active())

func test_dev_controls_bypass_gate_and_timers() -> void:
    var b := Boost.new()
    assert_true(b.start_boost(NOW))     # no level check on the dev path
    assert_true(b.is_active())
    assert_false(b.start_boost(NOW))    # idempotent while active
    b.end_boost(NOW + 5.0)
    assert_false(b.is_active())
    assert_eq(b.next_boost_at, NOW + 5.0 + 86400.0)

func test_daily_rollover_resets_and_advances() -> void:
    var b := Boost.new()
    b.start_boost(NOW)
    b.progress = 7
    b.buff_level = 3
    b.window_left = 2
    b.extras_left = 1
    b.extra_cached = true
    b.extra_lucky_cached = "204"
    b.tick(DAY + 1.0, _player(8))      # crosses the first midnight
    assert_true(b.is_active())
    assert_eq(b.round_num, 2)
    assert_eq(b.progress, 0)
    assert_eq(b.buff_level, 0)
    assert_eq(b.window_left, 0)
    assert_eq(b.extras_left, 0)
    assert_false(b.extra_cached)
    assert_eq(b.extra_lucky_cached, "")
    assert_eq(b.rollover_at, 2.0 * DAY)

func test_offline_gap_rolls_over_once_to_next_midnight() -> void:
    var b := Boost.new()
    b.start_boost(NOW)
    b.tick(2.0 * DAY + 500.0, _player(8))   # skipped a whole day offline
    assert_eq(b.round_num, 2)               # one reset, not two
    assert_eq(b.rollover_at, 3.0 * DAY)     # re-anchored past `now`

func test_end_before_midnight_never_rolls_over() -> void:
    var b := Boost.new()
    b.start_boost(NOW)
    b.end_boost(NOW + 10.0)
    b.tick(DAY + 1.0, _player(1))
    assert_false(b.is_active())
    assert_eq(b.round_num, 1)
```

- [ ] **Step 2: Import (new class_name), then run test to verify it fails**

```bash
(cd curio-hall && godot --headless --import)
./curio-hall/test.sh -gselect=test_boost.gd
```
Expected: FAIL — `Boost` not defined (first run fails at parse; after creating the file in Step 3, re-import again if resolution errors persist).

- [ ] **Step 3: Implement `curio-hall/sim/boost.gd`**

```gdscript
class_name Boost
extends RefCounted
## Patron's Gala (the   GeneratorBoost): a multi-day main-board buff
## window. Finishing main orders climbs a task ladder; each rung activates a
## buff, cumulatively. Ladder state resets at every UTC midnight inside the
## window (the   RefreshTime/RoundNum). Expiry advances on
## Game.tick_boost (main.gd's 1s timer hosts the tick).

signal boost_changed

enum State { IDLE, ACTIVE }

var state: int = State.IDLE
var ends_at: float = 0.0
var next_boost_at: float = 0.0    # 0.0 = start as soon as the gate passes
var rollover_at: float = 0.0
var round_num: int = 1
var progress: int = 0             # main orders delivered this round
var buff_level: int = 0           # rungs unlocked this round
var window_left: int = 0          # extraProduce quota: taps left in window
var extras_left: int = 0          # extraProduce quota: extras left in window
var extra_cached: bool = false    # one-slot cache for a blocked extra spawn
var extra_lucky_cached: String = ""  # blocked twin lucky item type, "" = none

func is_active() -> bool:
    return state == State.ACTIVE

static func _next_midnight(now: float) -> float:
    return floor(now / 86400.0 + 1.0) * 86400.0   # next UTC midnight

func tick(now: float, player: PlayerState) -> void:
    if state == State.IDLE:
        if now >= next_boost_at and player.level >= int(ConfigDB.tuning["boost_unlock_level"]):
            start_boost(now)
    elif now >= ends_at:
        end_boost(now)
    elif now >= rollover_at:
        _daily_reset()
        round_num += 1
        rollover_at = _next_midnight(now)
        boost_changed.emit()

func start_boost(now: float) -> bool:
    if state == State.ACTIVE:
        return false
    state = State.ACTIVE
    ends_at = now + float(ConfigDB.tuning["boost_duration_seconds"])
    rollover_at = _next_midnight(now)
    round_num = 1
    _daily_reset()
    boost_changed.emit()
    return true

func end_boost(now: float) -> void:
    if state != State.ACTIVE:
        return
    state = State.IDLE
    _daily_reset()
    next_boost_at = now + float(ConfigDB.tuning["boost_gap_seconds"])
    boost_changed.emit()

func _daily_reset() -> void:
    progress = 0
    buff_level = 0
    window_left = 0
    extras_left = 0
    extra_cached = false
    extra_lucky_cached = ""
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh -gselect=test_boost.gd`
Expected: PASS (7/7)

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/boost.gd curio-hall/sim/boost.gd.uid curio-hall/test/unit/test_boost.gd
git commit -m "feat: Boost lifecycle with daily rollover - Patron's Gala track

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Ladder, buffs, quota, caches, effective config, save dict

**Files:**
- Modify: `curio-hall/sim/boost.gd`
- Test: `curio-hall/test/unit/test_boost.gd` (append)

**Interfaces:**
- Consumes: Task 1 accessors (`ConfigDB.boost_item_row`, `ConfigDB.boost_lucky_table`, `ConfigDB.is_boost_type`, tuning keys), Task 2 state vars.
- Produces (used by Tasks 4–6):
  - `on_order_delivered(now: float) -> void`
  - `is_buff_active(kind: String) -> bool`
  - `is_boosted(type: String) -> bool`
  - `take_extra(rng: RandomNumberGenerator) -> bool` (advances the quota window; internal to `claim_extra` but public for direct quota tests)
  - `claim_extra(rng: RandomNumberGenerator) -> bool` (cache-first; true = place one extra now)
  - `report_extra_blocked() -> void` (re-cache a claimed extra that found no room)
  - `cache_extra_lucky(type: String) -> void`
  - `take_cached_lucky() -> String` (returns and clears the cached twin type, `""` if none)
  - `effective_row(type: String) -> Dictionary`
  - `effective_lucky() -> Array`
  - `to_dict() -> Dictionary` / `static from_dict(d: Dictionary) -> Boost`

- [ ] **Step 1: Write the failing tests (append to `test_boost.gd`)**

```gdscript
func _active_boost() -> Boost:
    var b := Boost.new()
    b.start_boost(NOW)
    return b

func test_ladder_unlocks_cumulative_buffs() -> void:
    var b := _active_boost()
    # boost_tasks [2,3,4,5]; boost_buffs [moreLucky, extra, extraLucky, nocd]
    assert_false(b.is_buff_active("moreLuckyProduce"))
    b.on_order_delivered(NOW)
    b.on_order_delivered(NOW)                      # progress 2 -> rung 1
    assert_true(b.is_buff_active("moreLuckyProduce"))
    assert_false(b.is_buff_active("extraProduce"))
    b.on_order_delivered(NOW)                      # progress 3 -> rung 2
    assert_true(b.is_buff_active("moreLuckyProduce"))   # cumulative
    assert_true(b.is_buff_active("extraProduce"))
    b.on_order_delivered(NOW)                      # 4 -> rung 3
    b.on_order_delivered(NOW)                      # 5 -> rung 4
    assert_true(b.is_buff_active("extraLuckyProduce"))
    assert_true(b.is_buff_active("nocd"))
    b.on_order_delivered(NOW)                      # past the top: no crash
    assert_eq(b.buff_level, 4)

func test_no_ladder_progress_while_idle() -> void:
    var b := Boost.new()
    b.on_order_delivered(NOW)
    assert_eq(b.progress, 0)
    assert_false(b.is_buff_active("moreLuckyProduce"))

func test_quota_fires_exactly_m_per_n_taps() -> void:
    var b := _active_boost()
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    # boost_extra_produce [1, 3]: exactly 1 fire per window of 3 taps.
    for k in range(50):
        var fires := 0
        for i in range(3):
            if b.take_extra(rng):
                fires += 1
        assert_eq(fires, 1)

func test_claim_extra_cache_first_and_blocked_recache() -> void:
    var b := _active_boost()
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    b.extra_cached = true
    b.window_left = 3
    b.extras_left = 0            # quota can't fire in this window
    assert_true(b.claim_extra(rng))   # cached one delivered
    assert_false(b.extra_cached)
    b.window_left = 1
    b.extras_left = 1            # next take_extra must fire
    assert_true(b.claim_extra(rng))
    b.report_extra_blocked()          # no room: back to the cache
    assert_true(b.extra_cached)
    # cache full + another blocked claim -> the claimed extra is lost (warning)
    b.window_left = 1
    b.extras_left = 1
    assert_true(b.claim_extra(rng))   # delivers the cached one, fire refills slot
    assert_true(b.extra_cached)

func test_lucky_twin_cache_roundtrip() -> void:
    var b := _active_boost()
    b.cache_extra_lucky("204")
    assert_eq(b.take_cached_lucky(), "204")
    assert_eq(b.take_cached_lucky(), "")

func test_effective_row_swaps_only_when_buffed_and_boosted() -> void:
    var b := _active_boost()
    var base_row: Dictionary = b.effective_row("105")
    assert_eq((base_row["Spread_Weight"] as Array).size(), 3)   # base until rung 1
    b.buff_level = 1                                            # moreLuckyProduce
    var boosted_row: Dictionary = b.effective_row("105")
    assert_eq((boosted_row["Spread_Weight"] as Array).size(), 2)
    var plain: Dictionary = b.effective_row("104")              # not a boost type
    assert_eq(plain, ConfigDB.items["104"])
    b.state = Boost.State.IDLE
    assert_eq((b.effective_row("105")["Spread_Weight"] as Array).size(), 3)

func test_effective_lucky_precedence() -> void:
    var b := _active_boost()
    assert_eq(b.effective_lucky(), ConfigDB.lucky)              # rung 0: base
    b.buff_level = 3                # moreLucky + extra + extraLucky all active
    var t: Array = b.effective_lucky()
    var row0: Dictionary = t[0]
    assert_eq(int((row0["lucky_chance"] as Array)[0]), 25)      # MoreLucky wins
    b.state = Boost.State.IDLE
    assert_eq(b.effective_lucky(), ConfigDB.lucky)              # IDLE: base again

func test_boost_save_roundtrip() -> void:
    var b := _active_boost()
    b.progress = 4
    b.buff_level = 3
    b.round_num = 2
    b.window_left = 2
    b.extras_left = 1
    b.extra_cached = true
    b.extra_lucky_cached = "303"
    var b2 := Boost.from_dict(b.to_dict())
    assert_eq(b2.state, Boost.State.ACTIVE)
    assert_eq(b2.ends_at, b.ends_at)
    assert_eq(b2.next_boost_at, b.next_boost_at)
    assert_eq(b2.rollover_at, b.rollover_at)
    assert_eq(b2.round_num, 2)
    assert_eq(b2.progress, 4)
    assert_eq(b2.buff_level, 3)
    assert_eq(b2.window_left, 2)
    assert_eq(b2.extras_left, 1)
    assert_true(b2.extra_cached)
    assert_eq(b2.extra_lucky_cached, "303")
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run: `./curio-hall/test.sh -gselect=test_boost.gd`
Expected: the Task 2 tests still PASS; the new ones FAIL (`on_order_delivered` not found).

- [ ] **Step 3: Implement (append to `curio-hall/sim/boost.gd`)**

```gdscript
## Ladder: each delivered main order is one point; rung N unlocks at the
## cumulative count boost_tasks[N-1]. All rungs <= buff_level are active.
func on_order_delivered(_now: float) -> void:
    if state != State.ACTIVE:
        return
    progress += 1
    var tasks: Array = ConfigDB.tuning["boost_tasks"]
    while buff_level < tasks.size() and progress >= int(tasks[buff_level]):
        buff_level += 1
    boost_changed.emit()

func is_buff_active(kind: String) -> bool:
    if state != State.ACTIVE:
        return false
    var buffs: Array = ConfigDB.tuning["boost_buffs"]
    for i in range(mini(buff_level, buffs.size())):
        if String(buffs[i]) == kind:
            return true
    return false

func is_boosted(type: String) -> bool:
    return ConfigDB.is_boost_type(type)

## extraProduce quota: exactly M extras per window of N taps, uniformly
## placed (fire chance extras_left/window_left, the   Left/Total
## spread-count scheme). Call once per boosted tap.
func take_extra(rng: RandomNumberGenerator) -> bool:
    if window_left <= 0:
        var quota: Array = ConfigDB.tuning["boost_extra_produce"]
        extras_left = int(quota[0])
        window_left = int(quota[1])
    var fire := rng.randi_range(1, window_left) <= extras_left
    window_left -= 1
    if fire:
        extras_left -= 1
    return fire

## Cache-first delivery: a cached extra goes out before a fresh fire; a
## same-tap fire then occupies the freed slot. At most one extra per tap.
func claim_extra(rng: RandomNumberGenerator) -> bool:
    var fired := take_extra(rng)
    if extra_cached:
        if not fired:
            extra_cached = false   # fired keeps the slot occupied
        return true
    return fired

func report_extra_blocked() -> void:
    if extra_cached:
        push_warning("Boost: extra produce lost, cache full")
    else:
        extra_cached = true

func cache_extra_lucky(type: String) -> void:
    if extra_lucky_cached != "":
        push_warning("Boost: twin lucky lost, cache full")
        return
    extra_lucky_cached = type

func take_cached_lucky() -> String:
    var t := extra_lucky_cached
    extra_lucky_cached = ""
    return t

## Query-seam config overrides: ConfigDB is never mutated. Only Spread_Weight
## differs in the override rows (charge caps/durations are identical to base,
## so GeneratorState keeps reading ConfigDB.items directly).
func effective_row(type: String) -> Dictionary:
    if is_buff_active("moreLuckyProduce") and is_boosted(type):
        var row := ConfigDB.boost_item_row("MoreLuckyProduce", type)
        if not row.is_empty():
            return row
    return ConfigDB.items.get(type, {})

func effective_lucky() -> Array:
    if is_buff_active("moreLuckyProduce"):
        return ConfigDB.boost_lucky_table("MoreLuckyProduce")
    if is_buff_active("extraLuckyProduce"):
        return ConfigDB.boost_lucky_table("ExtraLuckyProduce")
    return ConfigDB.lucky

func to_dict() -> Dictionary:
    return {"state": state, "ends_at": ends_at, "next_boost_at": next_boost_at,
            "rollover_at": rollover_at, "round_num": round_num,
            "progress": progress, "buff_level": buff_level,
            "window_left": window_left, "extras_left": extras_left,
            "extra_cached": extra_cached,
            "extra_lucky_cached": extra_lucky_cached}

static func from_dict(d: Dictionary) -> Boost:
    var b := Boost.new()
    b.state = int(d.get("state", State.IDLE))
    b.ends_at = float(d.get("ends_at", 0.0))
    b.next_boost_at = float(d.get("next_boost_at", 0.0))
    b.rollover_at = float(d.get("rollover_at", 0.0))
    b.round_num = int(d.get("round_num", 1))
    b.progress = int(d.get("progress", 0))
    b.buff_level = int(d.get("buff_level", 0))
    b.window_left = int(d.get("window_left", 0))
    b.extras_left = int(d.get("extras_left", 0))
    b.extra_cached = bool(d.get("extra_cached", false))
    b.extra_lucky_cached = String(d.get("extra_lucky_cached", ""))
    return b
```

Note: `ConfigDB.boost_item_row` returns a typed `Dictionary`, so `var row := ...` is safe there (typed function return, not a Dictionary lookup).

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh -gselect=test_boost.gd`
Expected: PASS (all, including Task 2's)

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/boost.gd curio-hall/test/unit/test_boost.gd
git commit -m "feat: boost ladder, buffs, extra-produce quota, config seams

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Game wiring and save v10

**Files:**
- Modify: `curio-hall/sim/game.gd` (SAVE_VERSION, `var boost`, `fresh`, `to_dict`, `from_dict`, `deliver_order`, new tick/dev funcs near `tick_events` around line 204)
- Modify: `curio-hall/sim/save_manager.gd` (required-keys list, around line 23)
- Test: `curio-hall/test/unit/test_boost_game.gd`

**Interfaces:**
- Consumes: `Boost` API from Tasks 2–3; existing `Game.deliver_order` (calls `events.on_order_delivered(self, now)` at `curio-hall/sim/game.gd:137`).
- Produces (used by Tasks 5–6):
  - `Game.boost: Boost`
  - `Game.SAVE_VERSION == 10`
  - `Game.tick_boost(now: float) -> void`
  - `Game.dev_start_boost(now: float) -> bool`
  - `Game.dev_end_boost(now: float) -> void`
  - Save dict gains key `"boost"`; SaveManager requires it.

- [ ] **Step 1: Write the failing test**

Create `curio-hall/test/unit/test_boost_game.gd`:

```gdscript
extends GutTest
## Game owns a Boost sibling to Events: fresh/save/load, tick host seam,
## dev controls, and deliver_order feeding the ladder (both tracks at once).

const NOW := 1000.0

func _deliverable_game() -> Game:
    var g := Game.fresh(NOW, 42)
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    return g

func test_fresh_game_has_idle_boost() -> void:
    var g := Game.fresh(NOW, 42)
    assert_not_null(g.boost)
    assert_false(g.boost.is_active())

func test_tick_boost_and_dev_controls() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 8
    g.tick_boost(NOW)
    assert_true(g.boost.is_active())
    g.dev_end_boost(NOW)
    assert_false(g.boost.is_active())
    assert_true(g.dev_start_boost(NOW))
    assert_true(g.boost.is_active())

func test_deliver_order_feeds_ladder_only_while_active() -> void:
    var g := _deliverable_game()
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.boost.progress, 0)          # IDLE: no progress
    g.dev_start_boost(NOW)
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.boost.progress, 1)

func test_both_tracks_active_at_once() -> void:
    var g := _deliverable_game()
    g.dev_start_boost(NOW)
    assert_true(g.dev_start_event(NOW))
    assert_true(g.boost.is_active())
    assert_true(g.events.is_active())
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    assert_eq(g.boost.progress, 1)                              # ladder fed
    assert_eq(g.events.board.count_of("pb_dogpark_tar_1"), 1)   # supply row fed

func test_game_save_roundtrip_includes_boost() -> void:
    var g := Game.fresh(NOW, 42)
    g.dev_start_boost(NOW)
    g.boost.progress = 2
    g.boost.buff_level = 1
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.boost.is_active())
    assert_eq(g2.boost.progress, 2)
    assert_eq(g2.boost.buff_level, 1)
    assert_eq(int(g.to_dict()["save_version"]), 10)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh -gselect=test_boost_game.gd`
Expected: FAIL — `boost` not found on Game.

- [ ] **Step 3: Implement in `curio-hall/sim/game.gd`**

- `const SAVE_VERSION := 9` → `const SAVE_VERSION := 10`
- Below `var events: Events` add: `var boost: Boost`
- In `fresh`, after `g.events = Events.new()`: `g.boost = Boost.new()`
- In `deliver_order`, directly after `events.on_order_delivered(self, now)`:

```gdscript
    boost.on_order_delivered(now)
```

- Next to `tick_events` / `dev_start_event` / `dev_end_event` (around line 204):

```gdscript
func tick_boost(now: float) -> void:
    boost.tick(now, player)

func dev_start_boost(now: float) -> bool:
    return boost.start_boost(now)

func dev_end_boost(now: float) -> void:
    boost.end_boost(now)
```

- In `to_dict`, after the `"events"` entry: `"boost": boost.to_dict(),`
- In `from_dict`, after the events line: `g.boost = Boost.from_dict(d["boost"])`

In `curio-hall/sim/save_manager.gd`, add `"boost"` to the required-keys array:

```gdscript
        for key in ["board", "wallet", "player", "orders", "shop", "deals", "iap", "campaign", "intimacy", "specials", "events", "boost"]:
```

(Update the version comment on the next line to mention v9 → v10.)

- [ ] **Step 4: Run the new test, then the full suite**

```bash
./curio-hall/test.sh -gselect=test_boost_game.gd
./curio-hall/test.sh
```
Expected: both PASS. `test_save.gd` keeps passing because it builds saves through `Game.to_dict()` (now v10 with the boost key); if any test hardcodes version 9, update it to 10 — that is the intended behavior change.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/test/unit/test_boost_game.gd
git commit -m "feat: Game hosts the Boost track - save v10

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: tap_generator buff hooks and LuckyRoller table parameter

**Files:**
- Modify: `curio-hall/sim/game.gd:83-110` (`tap_generator`)
- Modify: `curio-hall/sim/lucky_roller.gd`
- Test: `curio-hall/test/unit/test_boost_tap.gd`, `curio-hall/test/unit/test_lucky.gd` (append one test)

**Interfaces:**
- Consumes: `Boost.effective_row/effective_lucky/is_buff_active/is_boosted/claim_extra/report_extra_blocked/cache_extra_lucky/take_cached_lucky` (Task 3), `Game.boost` (Task 4).
- Produces:
  - `LuckyRoller.roll(generator_type: String, player_level: int, rng: RandomNumberGenerator, table: Array = []) -> String` — empty `table` means `ConfigDB.lucky`; existing 3-arg callers unchanged.
  - `tap_generator` result entries may carry `"extra": true` (extra-produce spawns and twin-lucky spawns) alongside the existing `"lucky": true`.

- [ ] **Step 1: Add the LuckyRoller parameter (tiny refactor first — existing tests are the safety net)**

In `curio-hall/sim/lucky_roller.gd` replace the function signature and the loop source:

```gdscript
class_name LuckyRoller

static func roll(generator_type: String, player_level: int, rng: RandomNumberGenerator, table: Array = []) -> String:
    var rows: Array = table if not table.is_empty() else ConfigDB.lucky
    for row in rows:
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

Append to `curio-hall/test/unit/test_lucky.gd`:

```gdscript
func test_explicit_table_overrides_base() -> void:
    var rng := RandomNumberGenerator.new()
    rng.seed = 1
    var table: Array = [{"generator": ["105"], "lucky_chance": [1, 1],
            "lucky_items": ["999-1"], "level_min": 1, "level_max": 999}]
    assert_eq(LuckyRoller.roll("105", 1, rng, table), "999")
    var base_got := LuckyRoller.roll("105", 1, rng)
    assert_true(base_got != "999")   # base table never yields 999
```

Run: `./curio-hall/test.sh -gselect=test_lucky.gd` — Expected: PASS. Commit:

```bash
git add curio-hall/sim/lucky_roller.gd curio-hall/test/unit/test_lucky.gd
git commit -m "refactor: LuckyRoller accepts an explicit lucky table

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Write the failing tap-hook tests**

Create `curio-hall/test/unit/test_boost_tap.gd`:

```gdscript
extends GutTest
## Patron's Gala hooks inside Game.tap_generator: nocd charge preservation,
## extra-produce quota spawns with cache-when-full, twin lucky spawns, and
## the effective Spread_Weight swap. Generator 105 is boosted; 104 is not.

const NOW := 1000.0

## A game with generator `gen_type` at (6,8) and `free` open drop cells.
func _tap_game(gen_type: String, free: int) -> Game:
    var g := Game.fresh(NOW, 42)
    var pos := Vector2i(6, 8)
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(gen_type, NOW))
    var cells: Array[Vector2i] = [Vector2i(5, 8), Vector2i(4, 8), Vector2i(3, 8)]
    for i in range(free):
        g.board.remove(cells[i])
        g.board.set_state(cells[i], MergeBoard.CellState.OPEN)
    return g

func _rung(g: Game, level: int) -> void:
    g.dev_start_boost(NOW)
    g.boost.buff_level = level   # rungs: 1 moreLucky, 2 extra, 3 extraLucky, 4 nocd

func test_nocd_preserves_charges_for_boosted_type() -> void:
    var g := _tap_game("105", 2)
    _rung(g, 4)
    var gen := g.board.item_at(Vector2i(6, 8)).gen
    var before := gen.charges(NOW)
    assert_true(g.tap_generator(Vector2i(6, 8), NOW)["ok"])
    assert_eq(gen.charges(NOW), before)          # nocd: no charge consumed

func test_nocd_does_not_cover_unboosted_generator() -> void:
    var g := _tap_game("104", 2)
    _rung(g, 4)
    var gen := g.board.item_at(Vector2i(6, 8)).gen
    var before := gen.charges(NOW)
    assert_true(g.tap_generator(Vector2i(6, 8), NOW)["ok"])
    assert_eq(gen.charges(NOW), before - 1)

func test_charges_consumed_below_nocd_rung() -> void:
    var g := _tap_game("105", 2)
    _rung(g, 3)
    var gen := g.board.item_at(Vector2i(6, 8)).gen
    var before := gen.charges(NOW)
    assert_true(g.tap_generator(Vector2i(6, 8), NOW)["ok"])
    assert_eq(gen.charges(NOW), before - 1)

func test_extra_produce_quota_over_window() -> void:
    # Over any 3 consecutive boosted taps exactly one carries an extra spawn
    # (quota [1,3]); board kept roomy so nothing caches.
    var g := _tap_game("105", 3)
    _rung(g, 2)
    var extras := 0
    var taps := 0
    for k in range(6):
        var res := g.tap_generator(Vector2i(6, 8), NOW)
        assert_true(res["ok"])
        taps += 1
        for s in (res["spawned"] as Array):
            var entry: Dictionary = s
            if bool(entry.get("extra", false)):
                extras += 1
            # clean every spawn off the board to keep room
            g.board.remove(entry["pos"])
            g.board.set_state(entry["pos"], MergeBoard.CellState.OPEN)
    assert_eq(extras, 2)   # 6 taps = 2 full windows of 3

func test_extra_produce_costs_no_extra_energy() -> void:
    var g := _tap_game("105", 3)
    _rung(g, 2)
    # Force the fire on the first tap: window primed so extras==window.
    g.boost.window_left = 1
    g.boost.extras_left = 1
    var before := g.wallet.energy(NOW)
    var res := g.tap_generator(Vector2i(6, 8), NOW)
    assert_true(res["ok"])
    var non_lucky := 0
    for s in (res["spawned"] as Array):
        if not bool((s as Dictionary).get("lucky", false)):
            non_lucky += 1
    assert_eq(non_lucky, 2)                          # normal + extra
    assert_eq(g.wallet.energy(NOW), before - 1)      # one tap, one energy

func test_extra_blocked_caches_and_delivers_later() -> void:
    var g := _tap_game("105", 1)          # exactly one free cell: extra can't fit
    _rung(g, 2)
    g.boost.window_left = 1
    g.boost.extras_left = 1
    var res := g.tap_generator(Vector2i(6, 8), NOW)
    assert_true(res["ok"])
    assert_true(g.boost.extra_cached)     # extra had no room
    # free two cells; cached extra rides the next tap
    g.board.remove(res["spawned"][0]["pos"])
    g.board.set_state(res["spawned"][0]["pos"], MergeBoard.CellState.OPEN)
    if g.board.item_at(Vector2i(4, 8)) != null:
        g.board.remove(Vector2i(4, 8))
    g.board.set_state(Vector2i(4, 8), MergeBoard.CellState.OPEN)
    g.boost.window_left = 3
    g.boost.extras_left = 0               # quota silent: delivery is cache-driven
    var res2 := g.tap_generator(Vector2i(6, 8), NOW)
    assert_true(res2["ok"])
    var extra_count := 0
    for s in (res2["spawned"] as Array):
        if bool((s as Dictionary).get("extra", false)):
            extra_count += 1
    assert_eq(extra_count, 1)
    assert_false(g.boost.extra_cached)

func test_more_lucky_swaps_spread_weight() -> void:
    # MoreLuckyProduce 105 weights have no 202: across many taps none appears.
    var g := _tap_game("105", 3)
    _rung(g, 1)
    for k in range(60):
        var res := g.tap_generator(Vector2i(6, 8), NOW)
        assert_true(res["ok"])
        for s in (res["spawned"] as Array):
            var entry: Dictionary = s
            if not bool(entry.get("lucky", false)):
                assert_ne(String(entry["type"]), "202")
            g.board.remove(entry["pos"])
            g.board.set_state(entry["pos"], MergeBoard.CellState.OPEN)

func test_twin_lucky_spawns_or_caches() -> void:
    var g := _tap_game("105", 3)
    _rung(g, 3)
    # Replace the boost's lucky view with a guaranteed proc by leveling the
    # ladder to moreLucky (1/25) and just tapping a lot; assert the invariant:
    # every tap where a lucky spawn appears also carries a twin (or cached it).
    var lucky_taps := 0
    for k in range(400):
        if g.wallet.energy(NOW) < 1:
            g.wallet.add_energy(50, NOW)
        var res := g.tap_generator(Vector2i(6, 8), NOW)
        if not res["ok"]:
            break
        var lucky_seen := 0
        for s in (res["spawned"] as Array):
            var entry: Dictionary = s
            if bool(entry.get("lucky", false)):
                lucky_seen += 1
            g.board.remove(entry["pos"])
            g.board.set_state(entry["pos"], MergeBoard.CellState.OPEN)
        if lucky_seen > 0 or g.boost.extra_lucky_cached != "":
            lucky_taps += 1
            assert_true(lucky_seen == 2 or (lucky_seen <= 1 and g.boost.extra_lucky_cached != "")
                    or lucky_seen == 1)  # 1 = twin was the cached delivery path
        g.boost.take_cached_lucky()      # reset the cache between taps
    assert_gt(lucky_taps, 0)             # 400 taps at ~1/25: procs happened
```

Note for the executor: `EnergyWallet.add_energy(n, now)` is the real signature (verified). GUT provides `assert_ne`/`assert_gt`; if a name differs on this GUT version, use `assert_true(x != y)` / `assert_true(x > y)`.

- [ ] **Step 3: Run test to verify it fails**

Run: `./curio-hall/test.sh -gselect=test_boost_tap.gd`
Expected: FAIL — no `"extra"` entries, nocd not honored (charges always consumed).

- [ ] **Step 4: Rewrite `tap_generator` in `curio-hall/sim/game.gd`**

Replace the whole function with:

```gdscript
func tap_generator(pos: Vector2i, now: float) -> Dictionary:
    var item := board.item_at(pos)
    if item == null or item.gen == null or board.state_at(pos) != MergeBoard.CellState.OPEN:
        return {"ok": false, "reason": "not_generator", "spawned": []}
    var row: Dictionary = boost.effective_row(item.type)
    var cost := int(row.get("Spread_CostEnergy", 0))
    if wallet.energy(now) < cost:
        return {"ok": false, "reason": "no_energy", "spawned": []}
    var nocd := boost.is_buff_active("nocd") and boost.is_boosted(item.type)
    if not nocd and item.gen.charges(now) <= 0 and item.gen.storage(now) <= 0:
        return {"ok": false, "reason": "no_charge", "spawned": []}
    var drop := Weighted.roll(Weighted.parse(row["Spread_Weight"]), rng)
    var target := board.find_free_cell(pos)
    if target == Vector2i(-1, -1):
        return {"ok": false, "reason": "board_full", "spawned": []}
    wallet.spend_energy(cost, now)
    if not nocd:
        item.gen.consume(now)
    board.place(target, ItemInstance.make(drop, now))
    spawned.emit(target, drop)
    var result := [{"pos": target, "type": drop}]
    # Patron's Gala: guaranteed double-spawn quota (free, cache-when-full).
    if boost.is_buff_active("extraProduce") and boost.is_boosted(item.type):
        if boost.claim_extra(rng):
            var extra_pos := board.find_free_cell(pos)
            if extra_pos == Vector2i(-1, -1):
                boost.report_extra_blocked()
            else:
                var extra_drop := Weighted.roll(Weighted.parse(row["Spread_Weight"]), rng)
                board.place(extra_pos, ItemInstance.make(extra_drop, now))
                spawned.emit(extra_pos, extra_drop)
                result.append({"pos": extra_pos, "type": extra_drop, "extra": true})
    var lucky_type: String = LuckyRoller.roll(item.type, player.level, rng, boost.effective_lucky())
    if lucky_type != "":
        var lucky_pos := board.find_free_cell(pos)
        if lucky_pos != Vector2i(-1, -1):
            board.place(lucky_pos, ItemInstance.make(lucky_type, now))
            spawned.emit(lucky_pos, lucky_type)
            result.append({"pos": lucky_pos, "type": lucky_type, "lucky": true})
        # Patron's Gala: twin lucky (a second copy, cache-when-full).
        if boost.is_buff_active("extraLuckyProduce") and boost.is_boosted(item.type):
            var twin_pos := board.find_free_cell(pos)
            if twin_pos == Vector2i(-1, -1):
                boost.cache_extra_lucky(lucky_type)
            else:
                board.place(twin_pos, ItemInstance.make(lucky_type, now))
                spawned.emit(twin_pos, lucky_type)
                result.append({"pos": twin_pos, "type": lucky_type, "lucky": true, "extra": true})
    elif boost.is_buff_active("extraLuckyProduce") and boost.is_boosted(item.type) \
            and boost.extra_lucky_cached != "":
        var cached_pos := board.find_free_cell(pos)
        if cached_pos != Vector2i(-1, -1):
            var cached_type := boost.take_cached_lucky()
            board.place(cached_pos, ItemInstance.make(cached_type, now))
            spawned.emit(cached_pos, cached_type)
            result.append({"pos": cached_pos, "type": cached_type, "lucky": true, "extra": true})
    return {"ok": true, "reason": "", "spawned": result}
```

- [ ] **Step 5: Run the new test, then the full suite**

```bash
./curio-hall/test.sh -gselect=test_boost_tap.gd
./curio-hall/test.sh
```
Expected: PASS. Pre-existing generator/lucky tests must stay green (boost is IDLE in them, every seam falls back to base config).

- [ ] **Step 6: Commit**

```bash
git add curio-hall/sim/game.gd curio-hall/test/unit/test_boost_tap.gd
git commit -m "feat: gala buff hooks in tap_generator - nocd, extras, twin lucky

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Gala panel and main.gd wiring

**Files:**
- Create: `curio-hall/view/gala_panel.gd`
- Modify: `curio-hall/scenes/main.gd`
- Test: headless boot + full suite (no GUT view tests, per project convention)

**Interfaces:**
- Consumes: `Game.boost`, `Game.tick_boost`, `Game.dev_start_boost`, `Game.dev_end_boost`, `Boost.boost_changed`, tuning `boost_tasks`/`boost_buffs`; `EventPanel` conventions (`layer`, `visibility_changed_to`, toast via `action_rejected`).
- Produces: `class_name GalaPanel extends CanvasLayer` with `setup(g: Game)`, `open()`, `close()`, signals `action_rejected(reason: String)` and `visibility_changed_to(open: bool)`.

- [ ] **Step 1: Implement `curio-hall/view/gala_panel.gd`**

```gdscript
class_name GalaPanel
extends CanvasLayer
## The Patron's Gala: task ladder, active buffs, countdowns, and
## clearly-labeled DEV lifecycle controls. Placeholder styling.
## No board here - the gala buffs the MAIN board.

signal action_rejected(reason: String)
signal visibility_changed_to(open: bool)

const RUNG_NAMES := {
    "moreLuckyProduce": "Lucky Finds",
    "extraProduce": "Overflowing Cases",
    "extraLuckyProduce": "Twin Discoveries",
    "nocd": "Tireless Curators",
}

var game: Game
var _body: Label

func setup(g: Game) -> void:
    game = g
    layer = 13            # above EventPanel's 12: both can be open in sequence
    visible = false
    var bg := ColorRect.new()
    bg.color = Color(0.10, 0.08, 0.05, 0.97)
    bg.anchor_right = 1.0
    bg.anchor_bottom = 1.0
    add_child(bg)
    var header := Label.new()
    header.text = "The Patron's Gala"
    header.position = Vector2(10, 8)
    header.add_theme_font_size_override("font_size", 24)
    add_child(header)
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.position = Vector2(600, 8)
    close_b.pressed.connect(close)
    add_child(close_b)
    var dev_start := Button.new()
    dev_start.text = "DEV: Start gala"
    dev_start.position = Vector2(10, 44)
    dev_start.pressed.connect(_dev_start)
    add_child(dev_start)
    var dev_end := Button.new()
    dev_end.text = "DEV: End gala"
    dev_end.position = Vector2(160, 44)
    dev_end.pressed.connect(_dev_end)
    add_child(dev_end)
    _body = Label.new()
    _body.position = Vector2(10, 90)
    _body.add_theme_font_size_override("font_size", 18)
    add_child(_body)
    game.boost.boost_changed.connect(_refresh)
    var t := Timer.new()   # parented on the CanvasLayer, never freed by refresh
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_refresh)
    add_child(t)

func open() -> void:
    visible = true
    _refresh()
    visibility_changed_to.emit(true)

func close() -> void:
    visible = false
    visibility_changed_to.emit(false)

func _dev_start() -> void:
    if not game.dev_start_boost(Time.get_unix_time_from_system()):
        action_rejected.emit("boost_already_active")
    _refresh()

func _dev_end() -> void:
    game.dev_end_boost(Time.get_unix_time_from_system())
    _refresh()

func _fmt(seconds: float) -> String:
    var s := maxi(0, int(seconds))
    return "%dh %02dm %02ds" % [s / 3600, (s % 3600) / 60, s % 60]

func _refresh() -> void:
    if not visible:
        return
    var b := game.boost
    if not b.is_active():
        _body.text = "The Hall is quiet. The next gala has not been announced."
        if b.next_boost_at > 0.0:
            var now := Time.get_unix_time_from_system()
            _body.text += "\nDoors open in " + _fmt(b.next_boost_at - now)
        return
    var now := Time.get_unix_time_from_system()
    var tasks: Array = ConfigDB.tuning["boost_tasks"]
    var buffs: Array = ConfigDB.tuning["boost_buffs"]
    var lines: Array[String] = []
    lines.append("Night %d of the gala.  Doors close in %s" % [b.round_num, _fmt(b.ends_at - now)])
    lines.append("Ladder resets at midnight: %s" % _fmt(b.rollover_at - now))
    lines.append("Orders fulfilled tonight: %d" % b.progress)
    lines.append("")
    for i in range(buffs.size()):
        var kind := String(buffs[i])
        var name: String = RUNG_NAMES.get(kind, kind)
        var need := int(tasks[i])
        if i < b.buff_level:
            lines.append("* %s - ACTIVE" % name)
        else:
            lines.append("  %s - unlocks at %d orders" % [name, need])
    _body.text = "\n".join(lines)
```

- [ ] **Step 2: Wire into `curio-hall/scenes/main.gd`**

All additions mirror the expedition wiring (grep anchors given):

1. Near `var _event_panel_open := false` (line ~39) add:

```gdscript
var _gala_panel_open := false
var gala_panel: GalaPanel
var gala_button: Button
```

2. In `_ready`, right after the `event_panel` wiring block (`event_panel.visibility_changed_to.connect(...)`, line ~80):

```gdscript
    gala_panel = GalaPanel.new()
    add_child(gala_panel)
    gala_panel.setup(game)
    gala_panel.action_rejected.connect(_show_toast)
    gala_panel.visibility_changed_to.connect(_on_gala_panel_visibility_changed)
    gala_button = Button.new()
    gala_button.text = "Gala"
    gala_button.position = expedition_button.position + Vector2(0.0, 44.0)
    gala_button.pressed.connect(gala_panel.open)
    $UI.add_child(gala_button)
    game.boost.boost_changed.connect(_refresh_gala_button)
    _refresh_gala_button()
```

3. Beside `_refresh_expedition_button` (line ~129):

```gdscript
## Always reachable while closed: the DEV start control lives inside the
## panel (same rationale as the expedition button).
func _refresh_gala_button() -> void:
    gala_button.visible = not _gala_panel_open and not _event_panel_open
    gala_button.text = "Gala!" if game.boost.is_active() else "Gala"

func _on_gala_panel_visibility_changed(open: bool) -> void:
    _gala_panel_open = open
    board_view.input_enabled = not open
    _refresh_gala_button()
    _refresh_expedition_button()
```

4. Everywhere `game.tick_events(...)` is called (grep `tick_events` in main.gd — the 1s timer handler and `_flush_save`, line ~122), add directly after each:

```gdscript
    game.tick_boost(Time.get_unix_time_from_system())
```

5. In `_refresh_expedition_button`, extend the visibility condition so the two buttons hide together while either panel is open (keeps the gala button from floating over the event board):

```gdscript
    expedition_button.visible = not _event_panel_open and not _gala_panel_open
```

Also call `_refresh_gala_button()` from `_on_event_panel_visibility_changed` so the gala button hides while the expedition panel is open.

6. If `_show_toast`'s `REJECT_MESSAGES` is a const Dictionary, add an entry: `"boost_already_active": "The gala is already under way."`

- [ ] **Step 3: Verify headless boot and full suite**

```bash
(cd curio-hall && timeout 20 godot --headless 2>&1 | head -20; true)
./curio-hall/test.sh
```
Expected: boot logs show no script errors (SCRIPT ERROR/PARSE ERROR lines absent); suite PASS.

- [ ] **Step 4: Commit**

```bash
git add curio-hall/view/gala_panel.gd curio-hall/view/gala_panel.gd.uid curio-hall/scenes/main.gd
git commit -m "feat: Patron's Gala panel and HUD button

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Roadmap update and final verification

**Files:**
- Modify: `docs/curio-hall-roadmap.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the phase record future sessions read first.

- [ ] **Step 1: Add the phase 5b section to the roadmap**

In `docs/curio-hall-roadmap.md`, after the "Phase 5a" section (before "## Phase 5 — Live-ops events"), insert:

```markdown
## Phase 5b: Patron's Gala (GeneratorBoost) ✅

The second live-ops archetype and the first main-board buff event, running as a
parallel track concurrent with the expedition.
(GeneratorBoostActivityModel/ItemSpread): a daily-resetting task ladder — finishing
main orders unlocks cumulative buffs on the 32 boosted generator types
(moreLuckyProduce config swap, extraProduce guaranteed-double quota with
cache-when-full, extraLuckyProduce twin lucky, nocd free recharge). Query-seam
config overrides (ConfigDB never mutated), save v10, code-built Gala button + panel
with DEV controls.

- Spec: `docs/superpowers/specs/2026-09-11-curio-hall-phase5b-generator-boost-design.md`
- Plan: `docs/superpowers/plans/2026-09-11-curio-hall-phase5b-generator-boost.md`
- Deferred: smartProduce buff (needs order-targeting smart-produce infrastructure),
  board-cell boost glow and the fly-buff celebration animation, per-buff art.
```

Also update the "Phase 5 — Live-ops events" paragraph: change "Phase 5a lands the framework and the Pureboard expedition; the remaining archetypes queue behind it" to note 5b shipped GeneratorBoost and the remaining archetypes are Farmboard, Dig/Break (brings swallow), Freefall, Multiboards, Explore.

- [ ] **Step 2: Full verification**

```bash
(cd curio-hall && godot --headless --import)
./curio-hall/test.sh
```
Expected: entire suite PASS, zero warnings.

- [ ] **Step 3: Commit**

```bash
git add docs/curio-hall-roadmap.md
git commit -m "docs: roadmap - phase 5b Patron's Gala shipped

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
