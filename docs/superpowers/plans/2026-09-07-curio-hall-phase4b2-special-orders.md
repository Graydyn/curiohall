# Curio Hall Phase 4b2: Special Orders + Order Avatars Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The six sequential `OrderSpecial` requests activate as campaign tasks complete (granting their generator seed items), deliverable from a new special slot on the order bar, and regular orders gain rotating customer avatars; save v7.

**Architecture:** A small time-free `SpecialOrders` RefCounted sim (sequential `next_id` + `active`), hooked into `Game.complete_task`; avatar names rolled at order-build time in `OrderBook`; view work confined to `OrderBar`. Follows the Campaign/Intimacy patterns.

**Tech Stack:** Godot 4.7.1 / GDScript, GUT headless tests

**Spec:** `docs/superpowers/specs/2026-09-07-curio-hall-phase4b2-special-orders-design.md`

## Global Constraints

- Warnings are errors: never `var x := <Dictionary/Array lookup>`; GDScript `or` is boolean-only — use `var v: Variant = row.get("K")` then `var arr: Array = v if v is Array else []`; no bare integer division.
- Run tests with `./curio-hall/test.sh` from repo root; single file `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/<file> -gexit)`. After creating any NEW `class_name` script run `(cd curio-hall && godot --headless --import)` once.
- **GUT swallows parse errors** (a prior phase lost 10 tests to a silent parse failure): after every full-suite run, check the printed totals against the expected count stated in the task and grep the output for `Parse Error` / `SCRIPT ERROR`. Baseline at this plan's start: **173 tests**.
- Indentation: `config_db.gd` and `order_book.gd` use TABS; `game.gd`, `save_manager.gd`, and all `view/` and new `sim/` files use 4 spaces; before appending to any test file, CHECK its existing indentation and match it (do not trust labels).
- The starting board is FULL: tests that place items must first `g.board.remove(pos)` + `g.board.set_state(pos, MergeBoard.CellState.OPEN)`.
- Granted energy overfills past `energy_max` by design (4b ruling); expect that in reward assertions.
- All grants via `Rewards.grant/grant_all`; deliveries are check-then-mutate with no state change on rejection.
- `SAVE_VERSION` becomes 7; version/shape mismatch backs up to `save.corrupt.json` and resets (no migration).
- Exact config values used in tests: special order 1 `{Trigger taskFinish-2_7, Requirement1 "1610", GeneratorChain "15", Rewards ["gem-15","energy-100"], AvatarId 101}`; order 2 `{taskFinish-11_6, "2010", "19", ["gem-20","energy-100"], 102}`; order 4's GeneratorChain is the Array `["sp4_1","sp4_2"]`; triggers 3-6 are `18_7`, `24_3`, `29_8`, `33_9` with requirements `sp3_2_10`, `sp4_3_10`, `sp5_2_10`, `sp6_2_10`. Seed mapping: numeric chain `"15"` → `"1501"`; `sp` chain `"sp3_1"` → `"sp3_1_1"`. `SpecialAvatars` keys are STRINGS (`"101"` → `"Sam"`). `NormalAvatars` rows: `{Id, Avatar, UnlockLevel?}` (UnlockLevel defaults to 1; Lily is 2, Lucy is 5).

---

### Task 1: ConfigDB loads special orders and avatars

**Files:**
- Create: `curio-hall/config/OrderSpecialConfig.json`, `curio-hall/config/OrderAvatarConfig.json` 
- Modify: `curio-hall/sim/config_db.gd` (TABS)
- Test: `curio-hall/test/unit/test_config_db.gd` (append; TABS)

**Interfaces:**
- Produces: `ConfigDB.order_special: Array` (6 rows sorted by Id), `ConfigDB.order_avatars: Dictionary` (groups incl. `NormalAvatars` Array and `SpecialAvatars` Dictionary with string keys). `validate()` warns (never errors) when a special's `Requirement1` or a derived seed item id is missing from `items`.

- [ ] **Step 1: Copy the config files**



- [ ] **Step 2: Write the failing test**

Append to `curio-hall/test/unit/test_config_db.gd` (TABS):

```gdscript
func test_order_special_loaded_sorted() -> void:
	assert_eq(ConfigDB.order_special.size(), 6)
	for i in range(6):
		assert_eq(int(ConfigDB.order_special[i]["Id"]), i + 1)
	assert_eq(String(ConfigDB.order_special[0]["Requirement1"]), "1610")
	assert_eq(String(ConfigDB.order_special[0]["Trigger"]), "taskFinish-2_7")

func test_order_avatars_loaded() -> void:
	var normals_v: Variant = ConfigDB.order_avatars.get("NormalAvatars")
	assert_true(normals_v is Array and (normals_v as Array).size() > 0)
	var specials_v: Variant = ConfigDB.order_avatars.get("SpecialAvatars")
	assert_true(specials_v is Dictionary)
	assert_eq(String((specials_v as Dictionary)["101"]), "Sam")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_config_db.gd -gexit)`
Expected: FAIL — `order_special` nonexistent.

- [ ] **Step 4: Implement**

In `curio-hall/sim/config_db.gd` (TABS), add vars after `var intimacy_dialogs: Array = []`:

```gdscript
var order_special: Array = []      # 6 sequential special orders, sorted by Id
var order_avatars: Dictionary = {} # OrderAvatarConfig groups (NormalAvatars, SpecialAvatars, ...)
```

In `load_all`, after the `intimacy_dialogs` line:

```gdscript
	order_special = _read(dir + "OrderSpecialConfig.json")
	order_special.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["Id"]) < int(b["Id"]))
	order_avatars = _read(dir + "OrderAvatarConfig.json")
```

In `validate()`, before `return errors`:

```gdscript
	for row in order_special:
		if not items.has(String(row.get("Requirement1", ""))):
			push_warning("OrderSpecialConfig %s: Requirement1 %s missing" % [row.get("Id"), row.get("Requirement1")])
		var chains_v: Variant = row.get("GeneratorChain")
		var chains: Array = chains_v if chains_v is Array else [chains_v]
		for c in chains:
			var chain := String(c)
			var seed_id := (chain + "_1") if chain.begins_with("sp") else (chain + "01")
			if not items.has(seed_id):
				push_warning("OrderSpecialConfig %s: seed item %s missing" % [row.get("Id"), seed_id])
```

- [ ] **Step 5: Run test to verify it passes**

Single file, then `./curio-hall/test.sh`. Expected: PASS; suite totals **175 tests / 175 passing**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/config/OrderSpecialConfig.json curio-hall/config/OrderAvatarConfig.json curio-hall/sim/config_db.gd curio-hall/test/unit/test_config_db.gd
git commit -m "feat: load special order and order avatar config"
```

---

### Task 2: `SpecialOrders` sim, Game wiring, save v7

**Files:**
- Create: `curio-hall/sim/special_orders.gd`
- Modify: `curio-hall/sim/game.gd`, `curio-hall/sim/save_manager.gd`
- Test: `curio-hall/test/unit/test_special_orders.gd` (create), `curio-hall/test/unit/test_save.gd` (version bump; 4-SPACE file), `curio-hall/test/unit/test_shop_game.gd` (version literal)

**Interfaces:**
- Consumes: `ConfigDB.order_special` (Task 1), `Campaign.done`/`Campaign.day`, `Rewards.grant/grant_all`, `MergeBoard.count_of/remove_n_of`.
- Produces: `SpecialOrders` (RefCounted): `next_id: int`, `active: bool`, `signal special_changed`, `static seed_items(row: Dictionary) -> Array`, `current() -> Dictionary` (`{}` when inactive), `is_all_done() -> bool`, `maybe_activate(campaign: Campaign, game, now: float) -> bool`, `deliver(board: MergeBoard, game, now: float) -> {ok, reason}` (reasons `not_active | no_item`), `to_dict()/from_dict()`. `Game` gains `specials: SpecialOrders` (in `fresh`), `deliver_special(now: float) -> Dictionary`, a `maybe_activate` hook inside `complete_task`, `SAVE_VERSION == 7`, and `specials` in the save.

- [ ] **Step 1: Write the failing tests**

Create `curio-hall/test/unit/test_special_orders.gd` (4 spaces):

```gdscript
extends GutTest
## Special order 1: trigger taskFinish-2_7, needs 1610, seeds chain 15 (-> 1501),
## rewards gem-15 + energy-100. Order 2: trigger 11_6, needs 2010, seeds 1901.
## Order 4 seeds BOTH sp4_1_1 and sp4_2_1 (Array GeneratorChain).

const NOW := 1000.0

func _plant(g: Game, type: String, pos: Vector2i) -> void:
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(type))

func test_seed_items_mapping() -> void:
    assert_eq(SpecialOrders.seed_items({"GeneratorChain": "15"}), ["1501"])
    assert_eq(SpecialOrders.seed_items({"GeneratorChain": "sp3_1"}), ["sp3_1_1"])
    assert_eq(SpecialOrders.seed_items({"GeneratorChain": ["sp4_1", "sp4_2"]}), ["sp4_1_1", "sp4_2_1"])

func test_inactive_until_trigger_task_done() -> void:
    var g := Game.fresh(NOW, 42)
    assert_false(g.specials.maybe_activate(g.campaign, g, NOW))
    assert_true(g.specials.current().is_empty())
    g.campaign.done["2_7"] = true
    assert_true(g.specials.maybe_activate(g.campaign, g, NOW))
    assert_true(g.specials.active)
    assert_eq(int(g.specials.current()["Id"]), 1)
    # seed granted; board is full so it lands in the inventory
    assert_has(g.player.inventory, "1501")

func test_sequential_gating_and_auto_advance() -> void:
    var g := Game.fresh(NOW, 42)
    g.campaign.done["2_7"] = true
    g.campaign.done["11_6"] = true    # order 2's trigger already satisfied
    g.specials.maybe_activate(g.campaign, g, NOW)
    assert_eq(int(g.specials.current()["Id"]), 1)   # order 2 must wait
    _plant(g, "1610", Vector2i(3, 4))
    var res: Dictionary = g.deliver_special(NOW)
    assert_true(res["ok"])
    # order 1 done -> order 2 activates immediately and seeds 1901
    assert_true(g.specials.active)
    assert_eq(int(g.specials.current()["Id"]), 2)
    assert_has(g.player.inventory, "1901")

func test_deliver_pays_rewards_and_consumes_item() -> void:
    var g := Game.fresh(NOW, 42)
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, NOW)
    _plant(g, "1610", Vector2i(3, 4))
    var gems_before := g.wallet.gems
    var energy_before := g.wallet.energy(NOW)
    assert_true(g.deliver_special(NOW)["ok"])
    assert_eq(g.wallet.gems, gems_before + 15)
    assert_eq(g.wallet.energy(NOW), energy_before + 100)   # overfill by design
    assert_eq(g.board.count_of("1610"), 0)

func test_deliver_rejections_change_nothing() -> void:
    var g := Game.fresh(NOW, 42)
    assert_eq(g.deliver_special(NOW)["reason"], "not_active")
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, NOW)
    var gems_before := g.wallet.gems
    assert_eq(g.deliver_special(NOW)["reason"], "no_item")
    assert_true(g.specials.active)
    assert_eq(g.wallet.gems, gems_before)

func test_full_walk_to_all_done() -> void:
    var g := Game.fresh(NOW, 42)
    for trig in ["2_7", "11_6", "18_7", "24_3", "29_8", "33_9"]:
        g.campaign.done[trig] = true
    g.specials.maybe_activate(g.campaign, g, NOW)
    var reqs := ["1610", "2010", "sp3_2_10", "sp4_3_10", "sp5_2_10", "sp6_2_10"]
    for req in reqs:
        assert_true(g.specials.active, "expected active before delivering %s" % req)
        _plant(g, req, Vector2i(3, 4))
        assert_true(g.deliver_special(NOW)["ok"], "deliver %s" % req)
    assert_true(g.specials.is_all_done())
    assert_true(g.specials.current().is_empty())

func test_complete_task_hook_activates() -> void:
    var g := Game.fresh(NOW, 42)
    g.wallet.coins = 10000
    g.campaign.day = 2
    for i in range(1, 7):                      # day 2 has task ids 1..7
        g.campaign.done["2_%d" % i] = true
    assert_true(g.complete_task(7, NOW)["ok"]) # completes 2_7 -> hook fires
    assert_true(g.specials.active)
    assert_eq(int(g.specials.current()["Id"]), 1)

func test_roundtrip() -> void:
    var s := SpecialOrders.new()
    s.next_id = 3
    s.active = true
    var s2 := SpecialOrders.from_dict(s.to_dict())
    assert_eq(s2.next_id, 3)
    assert_true(s2.active)
```

In `curio-hall/test/unit/test_save.gd` (4 SPACES — check first), rename `test_v6_roundtrip_campaign` → `test_v7_roundtrip_campaign`, `test_save_version_is_6_and_campaign_key_present` → `..._is_7_...`, change `assert_eq(int(d["save_version"]), 6)` to `7`, and append:

```gdscript
func test_v7_roundtrip_specials() -> void:
    var g := Game.fresh(1000.0, 42)
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_true(g2.specials.active)
    assert_eq(g2.specials.next_id, 1)
    assert_true(g2.to_dict().has("specials"))
```

In `curio-hall/test/unit/test_shop_game.gd`: `assert_eq(g2.to_dict()["save_version"], 6)` → `7`.

- [ ] **Step 2: Run tests to verify they fail**

test_special_orders.gd: FAIL (`SpecialOrders` nonexistent). test_save.gd: FAIL (version 6).

- [ ] **Step 3: Implement**

Create `curio-hall/sim/special_orders.gd` (4 spaces):

```gdscript
class_name SpecialOrders
extends RefCounted
## The six sequential OrderSpecial requests: each activates when its campaign
## task completes, seeds the player with its generator chain's tier-1 item
, and pays gem/energy
## rewards when its single required item is delivered from the board.
## Time-free by design: no timers, no tick host.

signal special_changed

var next_id: int = 1
var active: bool = false

static func seed_items(row: Dictionary) -> Array:
    var chains_v: Variant = row.get("GeneratorChain")
    var chains: Array = chains_v if chains_v is Array else [chains_v]
    var out: Array = []
    for c in chains:
        var chain := String(c)
        out.append((chain + "_1") if chain.begins_with("sp") else (chain + "01"))
    return out

func _row(id: int) -> Dictionary:
    for row in ConfigDB.order_special:
        if int(row["Id"]) == id:
            return row
    return {}

func current() -> Dictionary:
    return _row(next_id) if active else {}

func is_all_done() -> bool:
    return not active and next_id > ConfigDB.order_special.size()

func maybe_activate(campaign: Campaign, game, now: float) -> bool:
    if active or next_id > ConfigDB.order_special.size():
        return false
    var row := _row(next_id)
    var trigger := String(row.get("Trigger", ""))
    if not trigger.begins_with("taskFinish-"):
        return false
    if not campaign.done.has(trigger.trim_prefix("taskFinish-")):
        return false
    active = true
    for seed_id in seed_items(row):
        Rewards.grant(String(seed_id), game, now)
    special_changed.emit()
    return true

func deliver(board: MergeBoard, game, now: float) -> Dictionary:
    if not active:
        return {"ok": false, "reason": "not_active"}
    var row := _row(next_id)
    var req := String(row["Requirement1"])
    if board.count_of(req) < 1:
        return {"ok": false, "reason": "no_item"}
    board.remove_n_of(req, 1)
    var rewards_v: Variant = row.get("Rewards")
    var rewards: Array = rewards_v if rewards_v is Array else []
    Rewards.grant_all(rewards, game, now)
    active = false
    next_id += 1
    maybe_activate(game.campaign, game, now)
    special_changed.emit()
    return {"ok": true, "reason": ""}

func to_dict() -> Dictionary:
    return {"next_id": next_id, "active": active}

static func from_dict(d: Dictionary) -> SpecialOrders:
    var s := SpecialOrders.new()
    s.next_id = int(d.get("next_id", 1))
    s.active = bool(d.get("active", false))
    return s
```

In `curio-hall/sim/game.gd`:
- `const SAVE_VERSION := 7`
- add `var specials: SpecialOrders` after `var intimacy: Intimacy`
- in `fresh`, after `g.intimacy = Intimacy.new()`: `g.specials = SpecialOrders.new()`
- replace `complete_task` with:

```gdscript
func complete_task(id: int, now: float) -> Dictionary:
    var res := campaign.complete_task(id, self, now)
    if res["ok"]:
        specials.maybe_activate(campaign, self, now)
    return res
```

- add after `complete_task`:

```gdscript
func deliver_special(now: float) -> Dictionary:
    return specials.deliver(board, self, now)
```

- `to_dict()`: add `"specials": specials.to_dict(),` after `"intimacy"`; `from_dict()`: `g.specials = SpecialOrders.from_dict(d["specials"])` after the intimacy line.

In `curio-hall/sim/save_manager.gd`: required-keys list gains `"specials"`; version comment updated to "v6 saves reset on upgrade to v7".

- [ ] **Step 4: Run tests to verify they pass**

`(cd curio-hall && godot --headless --import)` (new class_name), test_special_orders.gd, test_save.gd, then `./curio-hall/test.sh`. Expected: PASS; suite totals **184 tests / 184 passing** (175 + 8 new special tests + 1 new save test), no Parse Error/SCRIPT ERROR.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/special_orders.gd curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/test/unit/test_special_orders.gd curio-hall/test/unit/test_save.gd curio-hall/test/unit/test_shop_game.gd
git commit -m "feat: sequential special orders with seed grants, save v7"
```

---

### Task 3: Customer avatars on regular and fixed orders

**Files:**
- Modify: `curio-hall/sim/order_book.gd` (TABS)
- Test: `curio-hall/test/unit/test_order_fixed.gd` (append; TABS — check first)

**Interfaces:**
- Consumes: `ConfigDB.order_avatars` (Task 1).
- Produces: every order dict from `_build_order` and `_build_fixed` carries `"avatar": String` (possibly `""`); `_build_fixed(row, player_level, rng, now)` gains the two new parameters; `_fill_fixed(player_level, rng, now)` gains `rng`; `fill` threads it through. `OrderBook._roll_avatar(player_level: int, rng: RandomNumberGenerator) -> String` rolls uniformly from `NormalAvatars` rows with `UnlockLevel` (default 1) ≤ player level.

- [ ] **Step 1: Write the failing test**

Append to `curio-hall/test/unit/test_order_fixed.gd` (TABS — verify by reading the file first):

```gdscript
func _allowed_avatars(level: int) -> Array:
	var normals_v: Variant = ConfigDB.order_avatars.get("NormalAvatars")
	var normals: Array = normals_v if normals_v is Array else []
	var out: Array = []
	for row in normals:
		if level >= int(row.get("UnlockLevel", 1)):
			out.append(String(row["Avatar"]))
	return out

func test_fixed_orders_carry_level_gated_avatar() -> void:
	var ob := OrderBook.new()
	ob.fill(1, _rng(), 0.0)
	var o: Dictionary = ob.orders[0]
	assert_true(o.has("avatar"))
	assert_has(_allowed_avatars(1), String(o["avatar"]))

func test_random_orders_carry_level_gated_avatar() -> void:
	var ob := OrderBook.new()
	ob.next_fixed = ConfigDB.order_fixed.size()
	ob.fill(5, _rng(), 0.0)
	for o in ob.orders:
		assert_not_null(o)
		assert_has(_allowed_avatars(5), String(o["avatar"]))

func test_avatar_roll_is_deterministic_under_seed() -> void:
	var a := OrderBook.new()
	var b := OrderBook.new()
	a.fill(1, _rng(), 0.0)
	b.fill(1, _rng(), 0.0)
	assert_eq(String(a.orders[0]["avatar"]), String(b.orders[0]["avatar"]))
```

- [ ] **Step 2: Run test to verify it fails**

test_order_fixed.gd: FAIL — no `avatar` key.

- [ ] **Step 3: Implement**

In `curio-hall/sim/order_book.gd` (TABS):

Add after `pool_row`:

```gdscript
func _roll_avatar(player_level: int, rng: RandomNumberGenerator) -> String:
	var normals_v: Variant = ConfigDB.order_avatars.get("NormalAvatars")
	var normals: Array = normals_v if normals_v is Array else []
	var pool: Array = []
	for row in normals:
		if player_level >= int(row.get("UnlockLevel", 1)):
			pool.append(String(row["Avatar"]))
	if pool.is_empty():
		return ""
	return String(pool[rng.randi_range(0, pool.size() - 1)])
```

In `_build_order`'s return dict, add `"avatar": _roll_avatar(player_level, rng),` (before `"points"`).

Change `_build_fixed(row: Dictionary, now: float)` to `_build_fixed(row: Dictionary, player_level: int, rng: RandomNumberGenerator, now: float)` and add `"avatar": _roll_avatar(player_level, rng),` to its return dict.

Change `_fill_fixed(player_level: int, now: float)` to `_fill_fixed(player_level: int, rng: RandomNumberGenerator, now: float)`, update its `_build_fixed(row, now)` call to `_build_fixed(row, player_level, rng, now)`, and update `fill`'s call to `_fill_fixed(player_level, rng, now)`.

- [ ] **Step 4: Run tests to verify they pass**

test_order_fixed.gd, then `./curio-hall/test.sh`. Expected: PASS; suite totals **187 tests / 187 passing**, no Parse Error/SCRIPT ERROR.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/order_book.gd curio-hall/test/unit/test_order_fixed.gd
git commit -m "feat: level-gated customer avatars on regular and fixed orders"
```

---

### Task 4: Order bar special slot + avatar labels, smoke test, roadmap

**Files:**
- Modify: `curio-hall/view/order_bar.gd`, `curio-hall/scenes/main.gd`, `docs/curio-hall-roadmap.md`
- Test: `curio-hall/test/unit/test_smoke.gd` (append; check indentation first — it is 4 spaces)

**Interfaces:**
- Consumes: `Game.specials.current()/special_changed`, `Game.deliver_special(now)`, order dicts' `avatar` (Task 3), `Cast.display_name`, `ConfigDB.order_avatars["SpecialAvatars"]` (string keys), `SpecialOrders.seed_items`.
- Produces: order bar UI only; `REJECT_MESSAGES` gains `not_active`, `no_item`.

- [ ] **Step 1: Write the failing smoke test**

Append to `curio-hall/test/unit/test_smoke.gd` (4 spaces):

```gdscript
func test_special_order_smoke() -> void:
    var g := Game.fresh(1000.0, 42)
    g.campaign.done["2_7"] = true
    g.specials.maybe_activate(g.campaign, g, 1000.0)
    assert_eq(int(g.specials.current()["Id"]), 1)
    assert_has(g.player.inventory, "1501")          # the seeded generator chain
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("1610"))
    var gems_before := g.wallet.gems
    assert_true(g.deliver_special(1000.0)["ok"])
    assert_eq(g.wallet.gems, gems_before + 15)
    var g2 := Game.from_dict(g.to_dict())           # quit/resume preserves the sequence
    assert_eq(g2.specials.next_id, 2)
```

- [ ] **Step 2: Run it — expected to PASS already** (it exercises Tasks 1-2 and guards the wiring). If it fails, fix the earlier task first. Suite totals become **188**.

- [ ] **Step 3: Implement the order bar changes**

In `curio-hall/view/order_bar.gd` (4 spaces):

In `setup`, after the `orders_changed` connect:

```gdscript
    game.specials.special_changed.connect(refresh)
```

In `refresh`, inside the `else` branch that renders a filled order, change the `btn.text` assignment to include the avatar line:

```gdscript
            var avatar_line := ""
            var avatar_v: Variant = o.get("avatar")
            if avatar_v != null and String(avatar_v) != "":
                avatar_line = Cast.display_name(String(avatar_v)) + "\n"
            btn.text = "%s%s\n%d coins" % [avatar_line, ", ".join(parts), o["coins"]]
```

At the end of `refresh` (after the SLOTS loop), append the special slot:

```gdscript
    var sp: Dictionary = game.specials.current()
    if not sp.is_empty():
        var req := String(sp["Requirement1"])
        var have := game.board.count_of(req)
        var sa_v: Variant = ConfigDB.order_avatars.get("SpecialAvatars")
        var sa: Dictionary = sa_v if sa_v is Dictionary else {}
        var who := String(sa.get(str(sp["AvatarId"]), ""))
        var b := Button.new()
        b.text = "* %s *\n%s\nneeds 1x %s (have %d)\nfrom chain %s" % [
                Cast.display_name(who), String(sp["DescriptionKey"]), req, have,
                str(sp["GeneratorChain"])]
        b.disabled = have < 1
        b.pressed.connect(func() -> void:
            var res: Dictionary = game.deliver_special(Time.get_unix_time_from_system())
            if not res["ok"]:
                action_rejected.emit(String(res["reason"])))
        add_child(b)
```

In `curio-hall/scenes/main.gd`: `REJECT_MESSAGES` gains:

```gdscript
    "not_active": "No special request is waiting",
    "no_item": "The requested curio isn't on the board",
```

and the save-pending signal list gains `game.specials.special_changed`.

- [ ] **Step 4: Verify headless boot + full suite**

`./curio-hall/test.sh` — totals **188 tests / 188 passing**, no Parse Error/SCRIPT ERROR. Then background a headless boot ~8s and kill it; expect zero `SCRIPT ERROR` lines.

- [ ] **Step 5: Update the roadmap**

In `docs/curio-hall-roadmap.md`, mark Phase 4b2 ✅ in the doc's style (colon header, no em dashes in new text): six sequential special orders with seed-grant stand-in for the cache queue, order-bar special slot, level-gated customer avatars, save v7. Spec: `docs/superpowers/specs/2026-09-07-curio-hall-phase4b2-special-orders-design.md`. Plan: `docs/superpowers/plans/2026-09-07-curio-hall-phase4b2-special-orders.md`. Deferred: branch order + swallow mechanic (dormant data in this build; nothing produces chain 83 and no coop item exists — phase 5), Start/End timelines, celebration UI, non-cast avatar retheme names.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/view/order_bar.gd curio-hall/scenes/main.gd curio-hall/test/unit/test_smoke.gd docs/curio-hall-roadmap.md
git commit -m "feat: order bar special slot and customer avatars - phase 4b2 playable"
```
