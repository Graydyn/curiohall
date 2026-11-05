# Curio Hall Phase 4b3: Story Recap + Return Gifts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Daily return gifts from befriended characters (level-weighted sender, level-pool contents),  ×1.2-ceil preferred-gift bonus, and the five campaign-milestone Chronicle volumes readable from the map; save v8.

**Architecture:** Return gifts extend the existing `Intimacy` sim (two fields + two methods, `tick` gains an rng); the recap needs no sim state (a pure read over `campaign.done` + a new ConfigDB table) rendered by a new `ChroniclePanel`; `SocietyPanel` gains a claim row and a Memories list.

**Tech Stack:** Godot 4.7.1 / GDScript, GUT headless tests

**Spec:** `docs/superpowers/specs/2026-09-07-curio-hall-phase4b3-recap-return-gifts-design.md`

## Global Constraints

- Warnings are errors: never `var x := <Dictionary/Array lookup>`; GDScript `or` is boolean-only — use `var v: Variant = row.get("K")` then `var arr: Array = v if v is Array else []`; no bare integer division; multi-statement lambdas are invalid — use named methods.
- Run tests with `./curio-hall/test.sh` from repo root; single file `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/<file> -gexit)`. After creating any NEW `class_name` script run `(cd curio-hall && godot --headless --import)` once.
- **GUT swallows parse errors**: after every full-suite run verify the printed totals against the expected count stated in the task and grep output for `Parse Error` / `SCRIPT ERROR`. Baseline at plan start: **190 tests**.
- Indentation: `config_db.gd` TABS; `intimacy.gd`, `game.gd`, `save_manager.gd`, all `view/` files, `test_intimacy.gd`, `test_save.gd`, `test_smoke.gd` are 4 spaces; `test_config_db.gd` TABS. CHECK each test file before appending.
- The starting board is FULL; granted items fall back to `player.store` (inventory).
- Granted energy overfills past `energy_max` (4b ruling). All grants via `Rewards.grant`; check-then-mutate everywhere.
- `Weighted.parse` rsplits each token ONCE on `-`: a pool triplet `"1302-1-10"` parses to id `"1302-1"` (itself a valid reward token: item 1302 × 1) and weight 10; `"gold-15-5"` → id `"gold-15"` weight 5. The claim roll exploits this — do not re-split by hand.
- `SAVE_VERSION` becomes 8; mismatch backs up and resets (no migration).
- Exact values used in tests: gift Intimacy values flower 8 / chocolate 10 / book 10 / watch 12; Cornelia prefers chocolate, ceil(10×1.2)=12; Cornelia L1 cost 36 (=3×12), L1 rewards `["energy-30"]`, L2 cost 60 (36+60=96=8×12); Barnaby L1 cost 48; `story_recap` books 1-5 keyed to tasks `20_11`, `37_10`, `43_11`, `47_11`, `52_11`; book 1 has 112 rows, first row Type `title` Content `recap_title_1_1`; `return_gift_cooldown_seconds` 86400.
- Commit ONLY on the phase worktree branch (verify `git branch --show-current` before each commit; a prior phase once committed to main).
- Working directory: repo root unless stated.

---

### Task 1: Preferred-bonus correction (×1.2 ceil)

**Files:**
- Modify: `curio-hall/config/curio_hall_tuning.json`, `curio-hall/sim/intimacy.gd`
- Test: `curio-hall/test/unit/test_intimacy.gd` (modify existing tests; 4 spaces)

**Interfaces:**
- Produces: `give_gift` points become `ceili(float(gift_row["Intimacy"]) * mult)` with `mult = float(tuning.intimacy_preferred_multiplier)` (now **1.2**) for preferred types, `1.0` otherwise. Downstream numbers: preferred chocolate to Cornelia = 12/gift.

- [ ] **Step 1: Update the failing tests first (RED)**

In `curio-hall/test/unit/test_intimacy.gd`:

Replace the file's doc comment lines 2-5 with:

```gdscript
## Config facts used here: Cornelia prefers chocolate (Intimacy 10 -> ceil(10*1.2)=12),
## Cornelia L1 costs 36 (three preferred chocolates) and rewards energy-30, L2 costs
## 60 (36+60=96 = eight chocolates total). Barnaby prefers flower (8 -> 10), L1 costs
## 48. Aldous unlocks at day_12 + intimacy_Barnaby_3. Ambrose is unreleased.
```

Replace `test_give_gift_spends_and_adds_points_with_preferred_double` entirely with:

```gdscript
func test_give_gift_spends_and_adds_points_with_preferred_bonus() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["chocolate"] = 3   # Cornelia's preferred type: ceil(10*1.2)=12 each
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(int(g.intimacy.satchel["chocolate"]), 2)
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 12)
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 24)
    assert_eq(g.intimacy.level_of("Cornelia"), 0)   # 24 < 36
    var energy_before := g.wallet.energy(NOW)
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])   # 36 -> level 1
    assert_eq(g.intimacy.level_of("Cornelia"), 1)
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 0)
    assert_eq(g.wallet.energy(NOW), energy_before + 30)          # L1 reward energy-30
```

Replace `test_level_two_records_story` entirely with:

```gdscript
func test_level_two_records_story() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["chocolate"] = 8   # 8*12 = 96 = L1 (36) + L2 (60) exactly
    for i in range(8):
        assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(g.intimacy.level_of("Cornelia"), 2)
    assert_has(g.intimacy.story_unlocks, "character_story_cornelia_1")
    assert_has(g.intimacy.story_unlocks, "character_intimacy_background_cornelia")
```

- [ ] **Step 2: Run to verify they fail** (points still ×2): `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_intimacy.gd -gexit)` — expect the two edited tests failing.

- [ ] **Step 3: Implement**

In `curio-hall/config/curio_hall_tuning.json`: `"intimacy_preferred_multiplier": 2` → `"intimacy_preferred_multiplier": 1.2`.

In `curio-hall/sim/intimacy.gd`, in `give_gift`, replace the two lines

```gdscript
    var mult := int(ConfigDB.tuning["intimacy_preferred_multiplier"]) if prefs.has(type) else 1
    t["points"] = int(t["points"]) + int(gift_row["Intimacy"]) * mult
```

with

```gdscript
    var mult := float(ConfigDB.tuning["intimacy_preferred_multiplier"]) if prefs.has(type) else 1.0
    t["points"] = int(t["points"]) + ceili(float(gift_row["Intimacy"]) * mult)
```

- [ ] **Step 4: Run to verify green**: single file, then `./curio-hall/test.sh` — totals **190/190**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/config/curio_hall_tuning.json curio-hall/sim/intimacy.gd curio-hall/test/unit/test_intimacy.gd
```

---

### Task 2: Return gifts in `Intimacy`, story-token filter, save v8

**Files:**
- Modify: `curio-hall/sim/intimacy.gd`, `curio-hall/sim/game.gd`, `curio-hall/sim/save_manager.gd`, `curio-hall/config/curio_hall_tuning.json`
- Test: `curio-hall/test/unit/test_intimacy.gd` (append), `curio-hall/test/unit/test_save.gd` (version bump + append; 4 spaces), `curio-hall/test/unit/test_shop_game.gd` (version literal)

**Interfaces:**
- Consumes: `Weighted.parse/roll` (rsplit-once behavior per Global Constraints), `ConfigDB.intimacy_list/intimacy_levels`, `Rewards.grant`, `Game.rng`.
- Produces: `Intimacy.gift_source: String` (`""` = none), `gift_refreshed_at: float`, `maybe_refresh_return_gift(now: float, rng: RandomNumberGenerator) -> bool`, `claim_return_gift(game, now: float) -> {ok, reason, sender, reward}` (reason `no_gift`); `Intimacy.tick(now: float, rng: RandomNumberGenerator)` (signature change); `_is_story_token` becomes prefix-based (`character_` only). `Game.tick_gifts(now)` passes `rng`; `Game.deliver_order` calls `maybe_refresh_return_gift`; `Game.claim_return_gift(now: float) -> Dictionary`; `SAVE_VERSION == 8`; tuning `return_gift_cooldown_seconds: 86400`.

- [ ] **Step 1: Add the tuning constant**

`curio-hall/config/curio_hall_tuning.json` gains `"return_gift_cooldown_seconds": 86400`.

- [ ] **Step 2: Write the failing tests**

Append to `curio-hall/test/unit/test_intimacy.gd` (4 spaces):

```gdscript
func test_return_gift_needs_cooldown_and_a_leveled_friend() -> void:
    var g := Game.fresh(NOW, 42)
    assert_false(g.intimacy.maybe_refresh_return_gift(NOW, _rng()))     # 1000 < 86400
    assert_false(g.intimacy.maybe_refresh_return_gift(90000.0, _rng())) # nobody leveled
    assert_eq(g.intimacy.gift_refreshed_at, 0.0)                        # window NOT consumed
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    assert_true(g.intimacy.maybe_refresh_return_gift(90001.0, _rng()))
    assert_eq(g.intimacy.gift_source, "Barnaby")
    assert_eq(g.intimacy.gift_refreshed_at, 90001.0)

func test_return_gift_never_double_arms() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    assert_true(g.intimacy.maybe_refresh_return_gift(90000.0, _rng()))
    assert_false(g.intimacy.maybe_refresh_return_gift(900000.0, _rng()))
    assert_eq(g.intimacy.gift_source, "Barnaby")

func test_return_gift_sender_weighted_and_deterministic() -> void:
    var a := Intimacy.new()
    var b := Intimacy.new()
    for im in [a, b]:
        (im.track("Barnaby") as Dictionary)["level"] = 1
        (im.track("Cornelia") as Dictionary)["level"] = 5
    a.maybe_refresh_return_gift(90000.0, _rng())
    b.maybe_refresh_return_gift(90000.0, _rng())
    assert_eq(a.gift_source, b.gift_source)
    assert_has(["Barnaby", "Cornelia"], a.gift_source)

func test_claim_return_gift_grants_from_level_pool_and_clears() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.intimacy.gift_source = "Barnaby"
    var pool: Array = (ConfigDB.intimacy_levels["Barnaby"][0] as Dictionary)["Gifts"]
    var expected: Array = []
    for e in Weighted.parse(pool):
        expected.append(String(e["id"]))
    var res: Dictionary = g.claim_return_gift(NOW)
    assert_true(res["ok"])
    assert_eq(String(res["sender"]), "Barnaby")
    assert_has(expected, String(res["reward"]))
    assert_eq(g.intimacy.gift_source, "")
    assert_eq(g.claim_return_gift(NOW)["reason"], "no_gift")

func test_claim_with_maxed_sender_uses_last_row() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 30
    g.intimacy.gift_source = "Barnaby"
    var pool: Array = (ConfigDB.intimacy_levels["Barnaby"][29] as Dictionary)["Gifts"]
    var expected: Array = []
    for e in Weighted.parse(pool):
        expected.append(String(e["id"]))
    var res: Dictionary = g.claim_return_gift(NOW)
    assert_true(res["ok"])
    assert_has(expected, String(res["reward"]))

func test_deliver_order_checks_return_gift() -> void:
    var g := Game.fresh(90000.0, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 4, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, 90000.0)["ok"])
    assert_eq(g.intimacy.gift_source, "Barnaby")

func test_story_filter_records_only_character_tokens() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy._grant_level_rewards(
            {"Rewards": ["time_skip_5-1-1", "character_story_test_1"]}, g, NOW)
    assert_has(g.intimacy.story_unlocks, "character_story_test_1")
    assert_false(g.intimacy.story_unlocks.has("time_skip_5-1-1"))
    assert_false(g.intimacy.story_unlocks.has("time_skip_5-1"))
```

Also in `test_intimacy.gd`: the existing `test_tick_restocks_daily_and_resets_escalation` and `test_shop_state_roundtrip` call `im.tick(<now>)` — update every such call to `im.tick(<now>, _rng())` (the signature gains an rng in this task).

In `curio-hall/test/unit/test_save.gd` (4 spaces): rename `test_v7_roundtrip_campaign` → `test_v8_roundtrip_campaign`, `test_save_version_is_7_and_campaign_key_present` → `..._is_8_...`, `assert_eq(int(d["save_version"]), 7)` → `8`, and append:

```gdscript
func test_v8_roundtrip_return_gift() -> void:
    var g := Game.fresh(1000.0, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.intimacy.maybe_refresh_return_gift(90000.0, g.rng)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.intimacy.gift_source, "Barnaby")
    assert_eq(g2.intimacy.gift_refreshed_at, 90000.0)
```

In `curio-hall/test/unit/test_shop_game.gd`: version literal `7` → `8`.

- [ ] **Step 3: Run to verify they fail** — new methods/fields nonexistent; version still 7.

- [ ] **Step 4: Implement**

In `curio-hall/sim/intimacy.gd`:

Add state after `var restock_at: float = 0.0`:

```gdscript
var gift_source: String = ""        # return-gift sender (original name); "" = none waiting
var gift_refreshed_at: float = 0.0  # when the last return gift was armed
```

Change `tick` to:

```gdscript
func tick(now: float, rng: RandomNumberGenerator) -> void:
    if restock_at <= 0.0:
        restock_at = now + float(ConfigDB.tuning["gift_shop_restock_seconds"])
    elif now >= restock_at:
        restock()
        restock_at = now + float(ConfigDB.tuning["gift_shop_restock_seconds"])
        satchel_changed.emit()
    maybe_refresh_return_gift(now, rng)
```

Add after `grant_order_gifts`:

```gdscript
## Once per cooldown window a befriended character (weight = intimacy level)
## sends a return gift. An empty pool of friends does NOT consume the window.
func maybe_refresh_return_gift(now: float, rng: RandomNumberGenerator) -> bool:
    if gift_source != "":
        return false
    if now - gift_refreshed_at < float(ConfigDB.tuning["return_gift_cooldown_seconds"]):
        return false
    var weighted: Array = []
    for row in ConfigDB.intimacy_list:
        var lvl := level_of(String(row["Name"]))
        if lvl > 0:
            weighted.append("%s-%d" % [String(row["Name"]), lvl])
    if weighted.is_empty():
        return false
    gift_source = String(Weighted.roll(Weighted.parse(weighted), rng))
    gift_refreshed_at = now
    satchel_changed.emit()
    return true

## The gift contents are one weighted roll from the sender's CURRENT level
## row's Gifts pool ("item-count-weight" triplets; Weighted's rsplit-once
## leaves "item-count", which is already a valid reward token).
func claim_return_gift(game, now: float) -> Dictionary:
    if gift_source == "":
        return {"ok": false, "reason": "no_gift"}
    var rows: Array = ConfigDB.intimacy_levels.get(gift_source, [])
    var lvl := clampi(level_of(gift_source), 1, maxi(1, rows.size()))
    if rows.is_empty():
        gift_source = ""
        return {"ok": false, "reason": "no_gift"}
    var row: Dictionary = rows[lvl - 1]
    var pool_v: Variant = row.get("Gifts")
    var pool: Array = pool_v if pool_v is Array else []
    if pool.is_empty():
        gift_source = ""
        satchel_changed.emit()
        return {"ok": false, "reason": "no_gift"}
    var picked := String(Weighted.roll(Weighted.parse(pool), game.rng))
    Rewards.grant(picked, game, now)
    var sender := gift_source
    gift_source = ""
    satchel_changed.emit()
    return {"ok": true, "reason": "", "sender": sender, "reward": picked}
```

Replace `_is_story_token` with:

```gdscript
## Only character story/background/portrait keys are memories; any other
## unknown token (e.g. booster ids) falls through to Rewards' warn-and-skip.
func _is_story_token(token: String) -> bool:
    return token.begins_with("character_")
```

Extend `to_dict()`'s dictionary with `"gift_source": gift_source, "gift_refreshed_at": gift_refreshed_at,` and `from_dict` (before `return im`):

```gdscript
    im.gift_source = String(d.get("gift_source", ""))
    im.gift_refreshed_at = float(d.get("gift_refreshed_at", 0.0))
```

In `curio-hall/sim/game.gd`:
- `const SAVE_VERSION := 8`
- `tick_gifts` becomes:

```gdscript
func tick_gifts(now: float) -> void:
    intimacy.tick(now, rng)
```

- in `deliver_order`, after `intimacy.grant_order_gifts(int(res["coins"]), rng)`:

```gdscript
    intimacy.maybe_refresh_return_gift(now, rng)
```

- add after `buy_gift_gems`:

```gdscript
func claim_return_gift(now: float) -> Dictionary:
    return intimacy.claim_return_gift(self, now)
```

In `curio-hall/sim/save_manager.gd`: version comment → "v7 saves reset on upgrade to v8" (the required-keys list already has `intimacy`; no key change).

- [ ] **Step 5: Run to verify green**: test_intimacy.gd, test_save.gd, then `./curio-hall/test.sh` — totals **198/198**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/sim/intimacy.gd curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/config/curio_hall_tuning.json curio-hall/test/unit/test_intimacy.gd curio-hall/test/unit/test_save.gd curio-hall/test/unit/test_shop_game.gd
git commit -m "feat: daily return gifts from befriended characters, save v8"
```

---

### Task 3: ConfigDB `story_recap`

**Files:**
- Create: `curio-hall/config/StoryRecapConfig.json` (copied verbatim)
- Modify: `curio-hall/sim/config_db.gd` (TABS)
- Test: `curio-hall/test/unit/test_config_db.gd` (append; TABS)

**Interfaces:**
- Produces: `ConfigDB.story_recap: Dictionary` — `{book:int -> {"task": String, "rows": Array}}`, rows in file order; `validate()` warns when a book's task key is missing from `main_task_by_key`.

- [ ] **Step 1: Copy the config**


- [ ] **Step 2: Write the failing test**

Append to `curio-hall/test/unit/test_config_db.gd` (TABS):

```gdscript
func test_story_recap_grouped_by_book() -> void:
	assert_eq(ConfigDB.story_recap.size(), 5)
	var b1: Dictionary = ConfigDB.story_recap[1]
	assert_eq(String(b1["task"]), "20_11")
	assert_eq((b1["rows"] as Array).size(), 112)
	var first: Dictionary = (b1["rows"] as Array)[0]
	assert_eq(String(first["Type"]), "title")
	assert_eq(String(first["Content"]), "recap_title_1_1")
	assert_eq(String((ConfigDB.story_recap[5] as Dictionary)["task"]), "52_11")
```

- [ ] **Step 3: Run to verify it fails** — `story_recap` nonexistent.

- [ ] **Step 4: Implement**

In `curio-hall/sim/config_db.gd` (TABS): add `var story_recap: Dictionary = {}   # book:int -> {"task": String, "rows": Array}` after `order_avatars`; add `story_recap.clear()` to the reload-clear block; in `load_all` after the `order_avatars` line:

```gdscript
	for row in _read(dir + "StoryRecapConfig.json"):
		if row == null:
			continue
		var book := int(row["Book"])
		if not story_recap.has(book):
			story_recap[book] = {"task": String(row["Task"]), "rows": []}
		(story_recap[book]["rows"] as Array).append(row)
```

In `validate()`, before `return errors`:

```gdscript
	for book in story_recap:
		var task_key := String(story_recap[book]["task"])
		if not main_task_by_key.has(task_key):
			push_warning("StoryRecapConfig book %s: task %s missing" % [book, task_key])
```

- [ ] **Step 5: Run to verify green**: single file then full suite — totals **199/199** (198 + 1), no Parse Error/SCRIPT ERROR.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/config/StoryRecapConfig.json curio-hall/sim/config_db.gd curio-hall/test/unit/test_config_db.gd
git commit -m "feat: load story recap config grouped by book"
```

---

### Task 4: `ChroniclePanel`, Society claim row + Memories, smoke, roadmap

**Files:**
- Create: `curio-hall/view/chronicle_panel.gd`
- Modify: `curio-hall/view/map_panel.gd`, `curio-hall/view/society_panel.gd`, `curio-hall/scenes/main.gd`, `curio-hall/scenes/main.tscn`, `docs/curio-hall-roadmap.md`
- Test: `curio-hall/test/unit/test_smoke.gd` (append; 4 spaces)

**Interfaces:**
- Consumes: `ConfigDB.story_recap`, `Campaign.done`, `Intimacy.gift_source`, `Game.claim_return_gift(now)`, `Intimacy.story_unlocks`, `Cast.display_name`.
- Produces: `ChroniclePanel` (CanvasLayer) with `setup(g: Game)`, `open()`, `close()`; `MapPanel` gains `signal chronicle_requested` and a header Chronicle button; main scene wires them.

- [ ] **Step 1: Write the smoke test**

Append to `curio-hall/test/unit/test_smoke.gd` (4 spaces):

```gdscript
func test_return_gift_and_recap_smoke() -> void:
    var g := Game.fresh(1000.0, 42)
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 1
    g.tick_gifts(200000.0)                       # daily window long past: gift arms
    assert_eq(g.intimacy.gift_source, "Barnaby")
    var res: Dictionary = g.claim_return_gift(200000.0)
    assert_true(res["ok"])
    assert_eq(g.intimacy.gift_source, "")
    g.campaign.done["20_11"] = true              # unlocks Chronicle volume 1
    assert_true(g.campaign.done.has(String((ConfigDB.story_recap[1] as Dictionary)["task"])))
    var g2 := Game.from_dict(g.to_dict())        # quit/resume keeps the refresh clock
    assert_eq(g2.intimacy.gift_refreshed_at, g.intimacy.gift_refreshed_at)
```

- [ ] **Step 2: Run it — expected to PASS already** (exercises Tasks 2-3). Suite totals become **200**.

- [ ] **Step 3: Implement `ChroniclePanel`**

Create `curio-hall/view/chronicle_panel.gd` (4 spaces):

```gdscript
class_name ChroniclePanel
extends CanvasLayer
## The five Chronicle volumes: campaign-milestone story recaps rendered from
## StoryRecapConfig loc keys. Placeholder text until the rewrite track.

var game: Game
var _root: PanelContainer
var _list: VBoxContainer
var _book := -1   # -1 = the volume list
var _page := 1

func setup(g: Game) -> void:
    game = g
    layer = 11
    visible = false
    _root = PanelContainer.new()
    _root.anchor_right = 1.0
    _root.anchor_bottom = 1.0
    add_child(_root)
    var scroll := ScrollContainer.new()
    _root.add_child(scroll)
    _list = VBoxContainer.new()
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list)

func open() -> void:
    visible = true
    _book = -1
    refresh()

func close() -> void:
    visible = false

func _label(text: String) -> void:
    var l := Label.new()
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.text = text
    _list.add_child(l)

func _button(text: String, disabled: bool, cb: Callable) -> void:
    var b := Button.new()
    b.text = text
    b.disabled = disabled
    b.pressed.connect(cb)
    _list.add_child(b)

func refresh() -> void:
    if not visible:
        return
    for c in _list.get_children():
        c.queue_free()
    if _book < 0:
        _draw_books()
    else:
        _draw_pages()

func _draw_books() -> void:
    _label("THE CURIO HALL CHRONICLE")
    _button("X Close", false, close)
    var books: Array = ConfigDB.story_recap.keys()
    books.sort()
    for b in books:
        var entry: Dictionary = ConfigDB.story_recap[b]
        if game.campaign.done.has(String(entry["task"])):
            _button("Volume %d" % int(b), false, _open_book.bind(int(b)))
        else:
            _label("Volume %d   (sealed until the restoration reaches further)" % int(b))

func _open_book(b: int) -> void:
    _book = b
    _page = 1
    refresh()

func _back_to_books() -> void:
    _book = -1
    refresh()

func _pages() -> Array:
    var entry: Dictionary = ConfigDB.story_recap.get(_book, {})
    var rows_v: Variant = entry.get("rows")
    var rows: Array = rows_v if rows_v is Array else []
    var out: Array = []
    for row in rows:
        var p := int(row["Page"])
        while out.size() < p:
            out.append([])
        (out[p - 1] as Array).append(row)
    return out

func _prev_page() -> void:
    _page -= 1
    refresh()

func _next_page() -> void:
    _page += 1
    refresh()

func _draw_pages() -> void:
    var pages := _pages()
    _button("< Volumes", false, _back_to_books)
    _label("Volume %d   page %d / %d" % [_book, _page, pages.size()])
    if _page >= 1 and _page <= pages.size():
        for row in pages[_page - 1]:
            match String(row["Type"]):
                "title":
                    _label("== %s ==" % String(row["Content"]))
                "subtitle":
                    _label("-- %s --" % String(row["Content"]))
                "img":
                    _label("[illustration: %s]" % String(row["Content"]))
                _:
                    _label(String(row["Content"]))
    _button("< Back", _page <= 1, _prev_page)
    _button("Next >", _page >= pages.size(), _next_page)
```

- [ ] **Step 4: Wire map, society, and main scene**

`curio-hall/view/map_panel.gd`: add `signal chronicle_requested` under the existing `action_rejected` signal; in `setup`, after `top.add_child(close_b)`:

```gdscript
    var chron_b := Button.new()
    chron_b.text = "Chronicle"
    chron_b.pressed.connect(func() -> void: chronicle_requested.emit())
    top.add_child(chron_b)
```

`curio-hall/view/society_panel.gd`:
- In `_draw_roster`, after the `_button("X Close", ...)` line:

```gdscript
    if game.intimacy.gift_source != "":
        _label("%s sent you a gift!" % Cast.display_name(game.intimacy.gift_source))
        _button("Claim gift", false, _claim_return_gift)
```

- Add the handler near the other `_claim`/`_buy` methods:

```gdscript
func _claim_return_gift() -> void:
    var res: Dictionary = game.claim_return_gift(Time.get_unix_time_from_system())
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()
```

- In `_draw_detail`, before `_draw_gift_shop()`:

```gdscript
    _label("--- MEMORIES ---")
    var orig := name.to_lower()
    var mems: Array = []
    for s in game.intimacy.story_unlocks:
        if String(s).begins_with("character_story_" + orig) \
                or String(s).begins_with("character_intimacy_background_" + orig) \
                or String(s).begins_with("character_" + orig):
            if not mems.has(String(s)):
                mems.append(String(s))
    if mems.is_empty():
        _label("No memories yet")
    for m in mems:
        _label(String(m))
```

`curio-hall/scenes/main.tscn`: bump `load_steps` by 1 (9 → 10); add after the society_panel ext_resource:

```
[ext_resource type="Script" path="res://view/chronicle_panel.gd" id="9"]
```

and after the SocietyPanel node:

```
[node name="ChroniclePanel" type="CanvasLayer" parent="."]
script = ExtResource("9")
```

`curio-hall/scenes/main.gd`: `@onready var chronicle_panel: ChroniclePanel = $ChroniclePanel` after `society_button`; in `_ready` after the society wiring:

```gdscript
    chronicle_panel.setup(game)
    map_panel.chronicle_requested.connect(chronicle_panel.open)
```

(No new REJECT_MESSAGES: `no_gift` already exists.)

- [ ] **Step 5: Verify** — `(cd curio-hall && godot --headless --import)`, `./curio-hall/test.sh` (totals **200/200**, no Parse Error/SCRIPT ERROR), then the ~8s backgrounded headless boot (zero SCRIPT ERROR lines).

- [ ] **Step 6: Update the roadmap**

Mark Phase 4b3 ✅ in `docs/curio-hall-roadmap.md` (colon header style, no em dashes in new text): Chronicle reader (five volumes gated by campaign milestones), daily return gifts (level-weighted sender, level-pool contents, preferred bonus corrected to 1.2x ceil, memories list, save v8. Spec + plan links. Deferred: return gifts as openable board items via a cache queue (direct grant stand-in), recap art/text (rewrite track).

- [ ] **Step 7: Commit**

```bash
git add curio-hall/view/chronicle_panel.gd curio-hall/view/map_panel.gd curio-hall/view/society_panel.gd curio-hall/scenes/main.gd curio-hall/scenes/main.tscn curio-hall/test/unit/test_smoke.gd docs/curio-hall-roadmap.md
git commit -m "feat: Chronicle reader, return-gift claim and memories - phase 4b3 playable"
```
