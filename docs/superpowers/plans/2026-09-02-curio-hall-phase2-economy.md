# Curio Hall Phase 2 (Orders + Economy) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn phase 1's stubbed order loop into the config-faithful economy: a timed order board with gem-skip, level-up reward chests that dispense collectible currency tokens, and tap-to-collect crediting coins/gems/energy.

**Architecture:** Add a `Rewards` grammar helper (single sink for every reward), a `ChestState` sim class (finite free dispensers, parallel to `GeneratorState`), collect-on-tap routing in `Game.tap`, a reward pipeline that runs `LevelConfig` rewards through `Rewards.grant`, and an `OrderBook` reworked to per-slot timed refresh with gem-skip. View is additive: order timers, chest/token rendering, collect feedback. Sim stays pure `RefCounted`; time and RNG stay injected.

**Tech Stack:** Godot 4.x (GDScript), GUT, JSON config already copied into `curio-hall/config/`.

**Spec:** `docs/superpowers/specs/2026-09-02-curio-hall-phase2-economy-design.md`

## Global Constraints

- Godot 4.x, GDScript only. Project at `curio-hall/`. Tests: `./curio-hall/test.sh` (must stay green and warning-free; commit after each green cycle).
- Item ids are Strings. Tier = last 2 chars: `int(code.substr(code.length() - 2))`. No config file is edited (they are verbatim copies); the currency chains (24/25/26), chests (`main_*_chest*`), and all 8 order types already exist in the copied `ItemModelConfig.json` / `OrderRandomConfig.json`.
- Time enters the sim only as injected `now: float`; randomness only via the injected `Game.rng` (or an RNG argument). Never call `Time.*` in `sim/`.
- Reward grammar (from `CollectRewards` / `LevelConfig.rewards`): `"gold-N"` = coins, `"gem-N"` = gems, `"energy-N"` = energy, anything else = item id + count. "gold" means coins.
- Chest predicate: `Spread_Weight` present AND `Spread_CostEnergy == 0` AND `Spread_ItemRecoveryDuration == 0`. Generators are the rest (they recharge).
- Order model (documented reading — `OrderRandomConfig` has no per-type selection weight): eligible order types = those with `RefreshTime >= 60` and `UnlockLevel <= player_level` (this is types 1,2,3,4,9,12 as they unlock; excludes the degenerate 1-second types 15/16). Pick uniformly among eligible. Per-type `Filters` cap item tiers by position.
- `order_skip_gems` default 30 (new tuning constant).

## File Structure

```
curio-hall/
  sim/rewards.gd            # Task 1 (new)  reward-token parse + grant
  sim/game.gd               # Tasks 1,2,3,4 (modify) tap routing + reward pipeline
  sim/chest_state.gd        # Task 3 (new)  finite free dispenser
  sim/config_db.gd          # Task 3 (modify) is_chest()
  sim/item_instance.gd      # Task 3 (modify) attach chest vs generator
  sim/merge_board.gd        # Task 3 (modify) serialize chest state
  sim/player_state.gd       # Task 4 (modify) add_xp returns gained levels
  sim/order_book.gd         # Task 5 (rewrite) timed refresh + gem-skip
  config/curio_hall_tuning.json  # Task 5 (modify) order_skip_gems
  view/item_view.gd         # Task 6 (modify) token + chest placeholders
  view/board_view.gd        # Task 6 (modify) tap -> game.tap; collect feedback
  view/order_bar.gd         # Task 6 (modify) timers + skip button
  scenes/main.gd            # Task 6 (modify) collect/level toast wiring
  test/unit/test_*.gd       # per task
```

---

### Task 1: Rewards grammar helper

**Files:**
- Create: `curio-hall/sim/rewards.gd`
- Test: `curio-hall/test/unit/test_rewards.gd`

**Interfaces:**
- Consumes: `Weighted.parse` convention (`rsplit("-", true, 1)`), `Game` (its `wallet`, `board`, `player`).
- Produces: `Rewards.parse(token: String) -> Dictionary` → `{"kind": String, "id": String, "amount": int}` where kind ∈ `"coins"|"gems"|"energy"|"item"`. `Rewards.grant(token: String, game, now: float) -> void`. `Rewards.grant_all(tokens: Array, game, now: float) -> void`.

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_rewards.gd`:

```gdscript
extends GutTest

func test_parse_currency_kinds() -> void:
    assert_eq(Rewards.parse("gold-2"), {"kind": "coins", "id": "gold", "amount": 2})
    assert_eq(Rewards.parse("gem-15"), {"kind": "gems", "id": "gem", "amount": 15})
    assert_eq(Rewards.parse("energy-100"), {"kind": "energy", "id": "energy", "amount": 100})

func test_parse_item_token() -> void:
    var p := Rewards.parse("main_g_chest_new_1-1")
    assert_eq(p["kind"], "item")
    assert_eq(p["id"], "main_g_chest_new_1")
    assert_eq(p["amount"], 1)

func test_grant_currency_credits_wallet() -> void:
    var g := Game.fresh(1000.0, 42)
    var coins0 := g.wallet.coins
    Rewards.grant("gold-5", g, 1000.0)
    Rewards.grant("gem-3", g, 1000.0)
    Rewards.grant("energy-10", g, 1000.0)  # wallet starts full (100), so capped
    assert_eq(g.wallet.coins, coins0 + 5)
    assert_eq(g.wallet.gems, 3)
    assert_eq(g.wallet.energy(1000.0), 100)

func test_grant_item_spawns_or_stores() -> void:
    var g := Game.fresh(1000.0, 42)
    # Fresh board is full; free one cell so a spawn lands.
    g.board.remove(Vector2i(1, 3))
    g.board.set_state(Vector2i(1, 3), MergeBoard.CellState.OPEN)
    Rewards.grant("205-1", g, 1000.0)
    assert_gt(g.board.count_of("205"), 0)

func test_grant_item_falls_back_to_inventory_when_full() -> void:
    var g := Game.fresh(1000.0, 42)  # board full, no free cell
    var inv0 := g.player.inventory.size()
    Rewards.grant("205-1", g, 1000.0)
    assert_eq(g.player.inventory.size(), inv0 + 1)
    assert_eq(g.player.inventory[-1], "205")

func test_unknown_kind_is_skipped_not_crashed() -> void:
    var g := Game.fresh(1000.0, 42)
    Rewards.grant("mystery-9", g, 1000.0)  # "mystery" is not a currency, treated as item id; not in ConfigDB -> skipped
    pass_test("no crash")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL (`Rewards` not declared).

- [ ] **Step 3: Implement**

`curio-hall/sim/rewards.gd`:

```gdscript
class_name Rewards
## Single grammar + sink for every reward token in the game.
## "gold-N" = coins, "gem-N" = gems, "energy-N" = energy, else item id + count.

const _CURRENCY := {"gold": "coins", "gem": "gems", "energy": "energy"}

static func parse(token: String) -> Dictionary:
    var parts: PackedStringArray = String(token).rsplit("-", true, 1)
    var id: String = parts[0]
    var amount: int = int(parts[1]) if parts.size() > 1 else 1
    var kind: String = _CURRENCY.get(id, "item")
    return {"kind": kind, "id": id, "amount": amount}

static func grant(token: String, game, now: float) -> void:
    var r := parse(token)
    match r["kind"]:
        "coins":
            game.wallet.add_coins(int(r["amount"]))
        "gems":
            game.wallet.add_gems(int(r["amount"]))
        "energy":
            game.wallet.add_energy(int(r["amount"]), now)
        "item":
            var id: String = r["id"]
            if not ConfigDB.items.has(id):
                push_warning("Rewards.grant: unknown item token '%s' skipped" % token)
                return
            for i in range(int(r["amount"])):
                if game.board.spawn(id, Vector2i(3, 4)) == Vector2i(-1, -1):
                    game.player.store(id)

static func grant_all(tokens: Array, game, now: float) -> void:
    for t in tokens:
        grant(String(t), game, now)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS (all prior suites still green).

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/rewards.gd curio-hall/test/unit/test_rewards.gd
git commit -m "feat: reward-token grammar and grant sink (coins/gems/energy/item)"
```

---

### Task 2: Collect-on-tap (Game.tap routing)

**Files:**
- Modify: `curio-hall/sim/game.gd`
- Test: `curio-hall/test/unit/test_collect.gd`

**Interfaces:**
- Consumes: `Rewards.grant_all`, `ConfigDB.items`, existing `Game.tap_generator`.
- Produces: `Game.tap(pos: Vector2i, now: float) -> Dictionary` returning `{"ok": bool, "kind": String, "reason": String}` where kind ∈ `"generator"|"collect"|"none"` (chest added in Task 3). On a collectible (an OPEN item whose config row has `CollectRewards`): grant its tokens, remove it, return `{ok:true, kind:"collect", reason:""}`. On a generator: delegate to `tap_generator` and return its result with `kind:"generator"`. Otherwise `{ok:false, kind:"none", reason:"not_tappable"}` (or `"not_open"` if the cell is not OPEN, `"empty"` if no item).

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_collect.gd`:

```gdscript
extends GutTest

func _open_cell(g: Game, pos: Vector2i, type: String) -> void:
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(type, 1000.0))

func test_tap_collects_currency_token() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "2501")  # CollectRewards ["gem-1"]
    var gems0 := g.wallet.gems
    var res := g.tap(Vector2i(1, 3), 1000.0)
    assert_true(res["ok"])
    assert_eq(res["kind"], "collect")
    assert_eq(g.wallet.gems, gems0 + 1)
    assert_null(g.board.item_at(Vector2i(1, 3)))

func test_tap_collects_coin_and_energy_tokens() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "2401")  # ["gold-2"]
    var coins0 := g.wallet.coins
    assert_true(g.tap(Vector2i(1, 3), 1000.0)["ok"])
    assert_eq(g.wallet.coins, coins0 + 2)

func test_tap_generator_still_routes() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "104")     # generator
    _open_cell(g, Vector2i(1, 4), "201")     # a free-ish neighbor target
    g.board.remove(Vector2i(1, 4))
    g.board.set_state(Vector2i(1, 4), MergeBoard.CellState.OPEN)
    var res := g.tap(Vector2i(1, 3), 1000.0)
    assert_eq(res["kind"], "generator")
    assert_true(res["ok"])

func test_tap_plain_item_not_tappable() -> void:
    var g := Game.fresh(1000.0, 42)
    _open_cell(g, Vector2i(1, 3), "205")  # no CollectRewards, no Spread_Weight
    var res := g.tap(Vector2i(1, 3), 1000.0)
    assert_false(res["ok"])
    assert_eq(res["kind"], "none")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL (`Game.tap` not defined).

- [ ] **Step 3: Implement**

Add to `curio-hall/sim/game.gd`:

```gdscript
func tap(pos: Vector2i, now: float) -> Dictionary:
    var item := board.item_at(pos)
    if item == null:
        return {"ok": false, "kind": "none", "reason": "empty"}
    if board.state_at(pos) != MergeBoard.CellState.OPEN:
        return {"ok": false, "kind": "none", "reason": "not_open"}
    var row: Dictionary = ConfigDB.items.get(item.type, {})
    if row.has("CollectRewards"):
        Rewards.grant_all(row["CollectRewards"], self, now)
        board.remove(pos)
        return {"ok": true, "kind": "collect", "reason": ""}
    if item.gen != null:
        var res := tap_generator(pos, now)
        res["kind"] = "generator"
        return res
    return {"ok": false, "kind": "none", "reason": "not_tappable"}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/game.gd curio-hall/test/unit/test_collect.gd
git commit -m "feat: Game.tap routes collectible tokens, generators (chests next)"
```

---

### Task 3: ChestState + chest tap-to-dispense

**Files:**
- Create: `curio-hall/sim/chest_state.gd`
- Modify: `curio-hall/sim/config_db.gd` (add `is_chest`), `curio-hall/sim/item_instance.gd` (attach chest vs generator), `curio-hall/sim/merge_board.gd` (serialize chest), `curio-hall/sim/game.gd` (`tap` chest branch, spent-chest removal, save_version 2)
- Test: `curio-hall/test/unit/test_chest.gd`

**Interfaces:**
- Consumes: `ConfigDB.items`, `Weighted`, `EnergyWallet.spend_gems`.
- Produces:
  - `ConfigDB.is_chest(type: String) -> bool`.
  - `ChestState` (RefCounted): `static func for_type(type: String, now: float) -> ChestState` (null if not a chest); `remaining() -> int`; `is_spent() -> bool`; `can_open(now: float) -> bool`; `open(now: float, rng: RandomNumberGenerator) -> String` (dispensed item id, or "" if not openable); `seconds_to_open(now: float) -> float`; `skip_open(wallet: EnergyWallet, now: float) -> bool`; `to_dict()/from_dict`.
  - `ItemInstance` gains `var chest: ChestState = null`; `make` attaches a `ChestState` when `ConfigDB.is_chest(type)`, else a `GeneratorState` when the row has `Spread_Weight`.
  - `Game.tap` gains a chest branch returning `kind:"chest"`; a chest that becomes spent is removed from the board.
  - `Game.SAVE_VERSION` becomes `2`; `MergeBoard` cells serialize `chest`.

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_chest.gd`:

```gdscript
extends GutTest

func _place_chest(g: Game, pos: Vector2i, type: String, now: float) -> void:
    g.board.remove(pos)
    g.board.set_state(pos, MergeBoard.CellState.OPEN)
    g.board.place(pos, ItemInstance.make(type, now))

func test_is_chest_predicate() -> void:
    assert_true(ConfigDB.is_chest("main_g_chest_new_1"))  # cost 0, no recovery
    assert_false(ConfigDB.is_chest("104"))                # generator: recharges
    assert_false(ConfigDB.is_chest("205"))                # plain item

func test_item_instance_attaches_chest_not_generator() -> void:
    var it := ItemInstance.make("main_g_chest_new_1", 1000.0)
    assert_not_null(it.chest)
    assert_null(it.gen)
    var gen := ItemInstance.make("104", 1000.0)
    assert_not_null(gen.gen)
    assert_null(gen.chest)

func test_chest_dispenses_up_to_budget_then_spent() -> void:
    # main_g_chest_new_1: Spread_ItemMaxNumber 5, weight ["2401-2","2402-3"], no open duration
    var cs := ChestState.for_type("main_g_chest_new_1", 1000.0)
    var rng := RandomNumberGenerator.new(); rng.seed = 1
    assert_eq(cs.remaining(), 5)
    var dispensed: Array[String] = []
    for i in range(5):
        assert_true(cs.can_open(1000.0))
        dispensed.append(cs.open(1000.0, rng))
    assert_eq(cs.remaining(), 0)
    assert_true(cs.is_spent())
    assert_false(cs.can_open(1000.0))
    assert_eq(cs.open(1000.0, rng), "")
    for d in dispensed:
        assert_true(d == "2401" or d == "2402")

func test_timed_chest_gates_and_skips() -> void:
    # main_t_chest_new_1: Spread_OpenDuration 120, SpeedUpCost 2
    var cs := ChestState.for_type("main_t_chest_new_1", 1000.0)
    var rng := RandomNumberGenerator.new(); rng.seed = 1
    assert_false(cs.can_open(1000.0))                 # must wait 120s
    assert_almost_eq(cs.seconds_to_open(1000.0), 120.0, 0.01)
    assert_true(cs.can_open(1000.0 + 120.0))
    var w := EnergyWallet.fresh(1000.0); w.add_gems(10)
    assert_true(cs.skip_open(w, 1000.0))              # pay 2 gems to skip
    assert_eq(w.gems, 8)
    assert_true(cs.can_open(1000.0))

func test_game_tap_opens_chest_and_removes_when_spent() -> void:
    var g := Game.fresh(1000.0, 42)
    _place_chest(g, Vector2i(1, 3), "main_g_chest_new_1", 1000.0)
    # free neighbors so dispensed tokens have somewhere to land
    for p in [Vector2i(1, 4), Vector2i(2, 3), Vector2i(0, 3), Vector2i(2, 4), Vector2i(0, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    for i in range(5):
        var res := g.tap(Vector2i(1, 3), 1000.0)
        assert_eq(res["kind"], "chest")
        assert_true(res["ok"])
    # 6th tap: chest is spent and already removed from the board
    assert_null(g.board.item_at(Vector2i(1, 3)))

func test_chest_survives_save() -> void:
    var g := Game.fresh(1000.0, 42)
    _place_chest(g, Vector2i(1, 3), "main_g_chest_new_1", 1000.0)
    for p in [Vector2i(1, 4), Vector2i(2, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    g.tap(Vector2i(1, 3), 1000.0)  # dispense one, budget now 4
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.board.item_at(Vector2i(1, 3)).chest.remaining(), 4)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement**

Add to `curio-hall/sim/config_db.gd`:

```gdscript
func is_chest(type: String) -> bool:
    var row: Dictionary = items.get(type, {})
    if not row.has("Spread_Weight"):
        return false
    return int(row.get("Spread_CostEnergy", 0)) == 0 \
        and int(row.get("Spread_ItemRecoveryDuration", 0)) == 0
```

`curio-hall/sim/chest_state.gd`:

```gdscript
class_name ChestState
extends RefCounted
## Finite, free dispenser. Unlike GeneratorState it never recharges.

var type: String
var _budget: int = 0
var _open_ts: float = 0.0   # last dispense (or creation); gates the timed open

static func for_type(item_type: String, now: float) -> ChestState:
    if not ConfigDB.is_chest(item_type):
        return null
    var cs := ChestState.new()
    cs.type = item_type
    cs._budget = int(ConfigDB.items[item_type].get("Spread_ItemMaxNumber", 0))
    cs._open_ts = now
    return cs

func _row() -> Dictionary:
    return ConfigDB.items[type]

func remaining() -> int:
    return _budget

func is_spent() -> bool:
    return _budget <= 0

func seconds_to_open(now: float) -> float:
    var dur := float(_row().get("Spread_OpenDuration", 0))
    return maxf(0.0, dur - (now - _open_ts))

func can_open(now: float) -> bool:
    return not is_spent() and seconds_to_open(now) <= 0.0

func open(now: float, rng: RandomNumberGenerator) -> String:
    if not can_open(now):
        return ""
    var drop := Weighted.roll(Weighted.parse(_row()["Spread_Weight"]), rng)
    _budget -= 1
    _open_ts = now
    return drop

func skip_open(wallet: EnergyWallet, now: float) -> bool:
    var cost := int(_row().get("Spread_OpenSpeedUpCost", 0))
    if is_spent() or not wallet.spend_gems(cost):
        return false
    _open_ts = now - float(_row().get("Spread_OpenDuration", 0))
    return true

func to_dict() -> Dictionary:
    return {"type": type, "budget": _budget, "open_ts": _open_ts}

static func from_dict(d: Dictionary) -> ChestState:
    var cs := ChestState.new()
    cs.type = String(d["type"])
    cs._budget = int(d["budget"])
    cs._open_ts = float(d["open_ts"])
    return cs
```

Modify `curio-hall/sim/item_instance.gd`:

```gdscript
class_name ItemInstance
extends RefCounted

var type: String
var gen: GeneratorState = null
var chest: ChestState = null

static func make(item_type: String, now: float = 0.0) -> ItemInstance:
    var it := ItemInstance.new()
    it.type = item_type
    it.chest = ChestState.for_type(item_type, now)
    if it.chest == null:
        it.gen = GeneratorState.for_type(item_type, now)
    return it
```

Modify `curio-hall/sim/merge_board.gd` `to_dict`/`from_dict` cell handling to also carry chest. In `to_dict`, where each cell dict is built, add `"chest": item.chest.to_dict() if item.chest != null else null`. In `from_dict`, after building `item`, add:

```gdscript
        if c.get("chest") != null:
            item.chest = ChestState.from_dict(c["chest"])
```

Add the chest branch to `curio-hall/sim/game.gd` `tap` (insert BEFORE the generator branch, AFTER the collectible branch):

```gdscript
    if item.chest != null:
        if item.chest.is_spent():
            board.remove(pos)
            return {"ok": false, "kind": "chest", "reason": "spent"}
        if not item.chest.can_open(now):
            return {"ok": false, "kind": "chest", "reason": "chest_wait"}
        var target := board.find_free_cell(pos)
        if target == Vector2i(-1, -1):
            return {"ok": false, "kind": "chest", "reason": "board_full"}
        var drop := item.chest.open(now, rng)
        board.place(target, ItemInstance.make(drop, now))
        spawned.emit(target, drop)
        if item.chest.is_spent():
            board.remove(pos)
        return {"ok": true, "kind": "chest", "reason": "", "spawned": [{"pos": target, "type": drop}]}
```

Bump `const SAVE_VERSION := 1` to `const SAVE_VERSION := 2` in `game.gd`.

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS. (The save test now round-trips chests; the SAVE_VERSION bump means SaveManager must accept v2 — see Task 5 for the migration note. For now, `Game.from_dict` reads whatever version SaveManager passed; update the corrupt-version gate in Task 5. If `test_save.gd`'s existing version assertions fail here because they hardcode 1, update those constants to `Game.SAVE_VERSION`.)

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim curio-hall/test/unit/test_chest.gd
git commit -m "feat: ChestState finite dispenser, is_chest, chest tap, save v2"
```

---

### Task 4: Level-up reward pipeline

**Files:**
- Modify: `curio-hall/sim/player_state.gd` (`add_xp` returns gained levels; stop granting), `curio-hall/sim/game.gd` (`deliver_order` and a new `_grant_level_rewards`), `curio-hall/test/unit/test_player_state.gd` (update to new `add_xp` contract)
- Test: `curio-hall/test/unit/test_level_rewards.gd`

**Interfaces:**
- Consumes: `Rewards.grant`, `ConfigDB.levels`.
- Produces: `PlayerState.add_xp(n: int) -> Array[int]` returns the level numbers gained (empty if none). Its `leveled_up` signal becomes `leveled_up(new_level: int)` (no reward payload). `Game._grant_level_rewards(gained: Array, now: float) -> void` runs each gained level's `LevelConfig.rewards` through `Rewards.grant`. `Game.deliver_order` uses this pipeline.

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_level_rewards.gd`:

```gdscript
extends GutTest

func test_add_xp_returns_gained_levels() -> void:
    var p := PlayerState.new()
    var c1 := int(ConfigDB.levels[0]["cost"])
    var gained := p.add_xp(c1)
    assert_eq(gained, [1])          # crossed level 1 -> now level 2
    assert_eq(p.level, 2)

func test_add_xp_multi_level() -> void:
    var p := PlayerState.new()
    var big := int(ConfigDB.levels[0]["cost"]) + int(ConfigDB.levels[1]["cost"])
    var gained := p.add_xp(big)
    assert_eq(gained, [1, 2])
    assert_eq(p.level, 3)

func test_level_reward_grants_chest_onto_board() -> void:
    var g := Game.fresh(1000.0, 42)
    # free some cells so granted items/chests can land
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    # level 1 rewards include a chest/item token per LevelConfig; drive a level-up
    g._grant_level_rewards(g.player.add_xp(int(ConfigDB.levels[0]["cost"])), 1000.0)
    # LevelConfig level-1 rewards contain item "104-1" (a generator) -> now on board
    assert_gt(g.board.count_of("104"), 0)

func test_deliver_order_uses_pipeline() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 5
    g.orders.orders[0] = {"items": {"203": 1}, "coins": 4, "xp": 4, "created_at": 0.0, "type": 1}
    g.board.spawn("203", Vector2i(3, 4))
    var coins0 := g.wallet.coins
    var res := g.deliver_order(0, 1000.0)
    assert_true(res["ok"])
    assert_eq(g.wallet.coins, coins0 + 4)
    assert_eq(g.player.xp, 4)
```

Note for the implementer: Task 5 rewrites `OrderBook`; this test constructs an order dict inline with a `"type"` key so it stays valid under Task 5's shape. If run before Task 5, the extra `"type"` key is harmless.

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement**

Rewrite `add_xp` in `curio-hall/sim/player_state.gd`:

```gdscript
signal leveled_up(new_level: int)

func add_xp(n: int) -> Array[int]:
    xp += n
    var gained: Array[int] = []
    while _cost_for(level) > 0 and xp >= _cost_for(level):
        xp -= _cost_for(level)
        gained.append(level)   # the level just completed
        level += 1
        leveled_up.emit(level)
    return gained
```

(Delete the old reward-parsing loop and the `item_rewards` signal argument.)

In `curio-hall/sim/game.gd`, add and rewire:

```gdscript
func _grant_level_rewards(gained: Array, now: float) -> void:
    for lvl in gained:
        var rewards: Array = ConfigDB.levels[int(lvl) - 1].get("rewards", [])
        Rewards.grant_all(rewards, self, now)

func deliver_order(i: int, now: float) -> Dictionary:
    var res := orders.deliver(i, board)
    if not res["ok"]:
        return res
    wallet.add_coins(int(res["coins"]))
    _grant_level_rewards(player.add_xp(int(res["xp"])), now)
    orders.fill(player.level, rng, now)
    return res
```

Update `curio-hall/test/unit/test_player_state.gd`: the existing `test_levels_up_per_level_config` asserts `add_xp` returned granted item ids (old contract). Change it to assert the new contract — that `add_xp(cost1)` returns `[1]` and `p.level == 2` — and drop the `assert_has(granted, "104")` line (item granting now lives in `Game._grant_level_rewards`, covered by `test_level_reward_grants_chest_onto_board`).

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/player_state.gd curio-hall/sim/game.gd curio-hall/test
git commit -m "feat: level-up reward pipeline routes rewards through Rewards.grant"
```

---

### Task 5: Order board timed refresh + gem-skip

**Files:**
- Rewrite: `curio-hall/sim/order_book.gd`
- Modify: `curio-hall/config/curio_hall_tuning.json` (add `order_skip_gems`), `curio-hall/sim/save_manager.gd` (accept save_version 2), `curio-hall/test/unit/test_order_book.gd` (update to new shape)
- Test: `curio-hall/test/unit/test_order_refresh.gd`

**Interfaces:**
- Consumes: `ConfigDB.order_random` (all 8 types), `ConfigDB.order_items`, `ConfigDB.tuning["order_skip_gems"]`, `EnergyWallet.spend_gems`, `Weighted`.
- Produces: `OrderBook` with `const SLOTS := 3`; `var orders: Array` (order dict or null, as before) and `var refresh_at: Array` (float per slot, 0 = fillable now). Order dicts gain `"type": int` and `"refresh_time": int`. Methods: `fill(player_level, rng, now)` (fills any slot with null order and `refresh_at <= now`); `deliver(i, board)` (sets `refresh_at[i] = now`... see note); `is_cooling(i, now) -> bool`; `time_to_refresh(i, now) -> float`; `skip_refresh(i, wallet, now) -> bool`; `to_dict/from_dict` including `refresh_at`. Because `deliver` has no `now`, delivery records the cooldown in `Game.deliver_order` via a new `start_cooldown(i, now)` — see implementation.

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_order_refresh.gd`:

```gdscript
extends GutTest

func _rng() -> RandomNumberGenerator:
    var r := RandomNumberGenerator.new(); r.seed = 7; return r

func test_delivered_slot_enters_cooldown_then_refreshes() -> void:
    var ob := OrderBook.new()
    ob.fill(5, _rng(), 1000.0)
    assert_not_null(ob.orders[0])
    var rt := int(ob.orders[0]["refresh_time"])
    assert_gt(rt, 0)
    var board := MergeBoard.new()
    for code in ob.orders[0]["items"]:
        for i in range(int(ob.orders[0]["items"][code])):
            board.place(Vector2i(i, 0), ItemInstance.make(code))
        # ensure enough copies
    # deliver slot 0
    ob.deliver(0, board)
    ob.start_cooldown(0, 1000.0)
    assert_true(ob.is_cooling(0, 1000.0))
    ob.fill(5, _rng(), 1000.0)                 # too soon: stays empty
    assert_null(ob.orders[0])
    ob.fill(5, _rng(), 1000.0 + rt)            # cooldown elapsed: refills
    assert_not_null(ob.orders[0])

func test_skip_refresh_spends_gems_and_refills() -> void:
    var ob := OrderBook.new()
    ob.refresh_at = [1000.0 + 9999.0, 0.0, 0.0]  # slot 0 cooling far out
    ob.orders = [null, null, null]
    var w := EnergyWallet.fresh(1000.0); w.add_gems(100)
    assert_true(ob.skip_refresh(0, w, 1000.0))
    assert_eq(w.gems, 100 - int(ConfigDB.tuning["order_skip_gems"]))
    ob.fill(5, _rng(), 1000.0)
    assert_not_null(ob.orders[0])

func test_eligible_types_respect_level_and_refresh_floor() -> void:
    var ob := OrderBook.new()
    var elig := ob._eligible_types(3)   # level 3: types 1,2 unlock (refresh>=60)
    var nums := elig.map(func(r): return int(r["Type"]))
    assert_true(nums.has(1) and nums.has(2))
    assert_false(nums.has(15))          # refresh 1 -> excluded
    assert_false(nums.has(4))           # unlock 5 -> not yet at level 3

func test_order_item_tiers_respect_filter_caps() -> void:
    var ob := OrderBook.new()
    ob.fill(3, _rng(), 1000.0)
    # Type-1/2 filters cap tiers; every requested item's tier must be <= 8 here
    for slot in ob.orders:
        if slot == null: continue
        for code in slot["items"]:
            assert_lte(int(String(code).substr(String(code).length() - 2)), 8)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement**

Rewrite `curio-hall/sim/order_book.gd`:

```gdscript
class_name OrderBook
extends RefCounted

const SLOTS := 3
const REFRESH_FLOOR := 60   # exclude degenerate 1-second order types

signal orders_changed

var orders: Array = [null, null, null]
var refresh_at: Array = [0.0, 0.0, 0.0]   # slot fillable when now >= refresh_at

func pool_row(code: String) -> Dictionary:
    for row in ConfigDB.order_items:
        if String(row["Code"]) == code:
            return row
    return {}

func _eligible_types(player_level: int) -> Array:
    var out: Array = []
    for row in ConfigDB.order_random:
        if int(row.get("RefreshTime", 0)) >= REFRESH_FLOOR \
                and player_level >= int(row.get("UnlockLevel", 1)):
            out.append(row)
    return out

func _filter_for(type_row: Dictionary, player_level: int) -> Dictionary:
    for f in type_row.get("Filters", []):
        var lo = f.get("PlayerMin")
        var hi = f.get("PlayerMax")
        if (lo == null or player_level >= int(lo)) and (hi == null or player_level <= int(hi)):
            return f
    return {}

func _tier(code: String) -> int:
    return int(code.substr(code.length() - 2))

func _pool_for_level(player_level: int) -> Array:
    var out: Array = []
    for row in ConfigDB.order_items:
        if row != null and int(row.get("UnlockLevel", 1)) <= player_level:
            out.append(row)
    return out

func _build_order(type_row: Dictionary, player_level: int, rng: RandomNumberGenerator, now: float) -> Dictionary:
    var flt := _filter_for(type_row, player_level)
    var caps := [int(flt.get("FirstMax", 99)), int(flt.get("SecondMax", 99)), int(flt.get("ThirdMax", 99))]
    var amounts: Dictionary = type_row["ItemAmounts"]
    var kind_weights := Weighted.parse([
        "1-%d" % int(amounts.get("OneItemWeight", 100)),
        "2-%d" % int(amounts.get("TwoItemsWeight", 0)),
        "3-%d" % int(amounts.get("ThreeItemsWeight", 0)),
    ])
    var pool := _pool_for_level(player_level)
    var kinds := int(Weighted.roll(kind_weights, rng))
    var items := {}
    for k in range(kinds):
        var cap: int = caps[k]
        var sub := pool.filter(func(r): return _tier(String(r["Code"])) <= cap and not items.has(String(r["Code"])))
        if sub.is_empty():
            break
        var wp := Weighted.parse(sub.map(func(r): return "%s-%d" % [r["Code"], int(r.get("Weight", 1))]))
        items[Weighted.roll(wp, rng)] = rng.randi_range(1, 2)
    var coins := 0
    var xp := 0
    for code in items:
        var row := pool_row(code)
        coins += int(row["Price"]) * int(items[code])
        xp += int(row.get("DiffScore", 1)) * int(items[code])
    return {"items": items, "coins": coins, "xp": xp, "created_at": now,
            "type": int(type_row["Type"]), "refresh_time": int(type_row["RefreshTime"])}

func fill(player_level: int, rng: RandomNumberGenerator, now: float) -> void:
    var elig := _eligible_types(player_level)
    if elig.is_empty():
        return
    for i in range(SLOTS):
        if orders[i] != null or now < float(refresh_at[i]):
            continue
        var type_row: Dictionary = elig[rng.randi_range(0, elig.size() - 1)]
        var order := _build_order(type_row, player_level, rng, now)
        if order["items"].is_empty():
            continue
        orders[i] = order
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
    return {"ok": true, "coins": int(o["coins"]), "xp": int(o["xp"]), "refresh_time": int(o["refresh_time"])}

func start_cooldown(i: int, now: float) -> void:
    # Called by Game.deliver_order with the refresh_time captured from deliver().
    pass  # refresh_at set in Game via set_cooldown below; see note

func set_cooldown(i: int, seconds: float, now: float) -> void:
    refresh_at[i] = now + seconds
    orders_changed.emit()

func is_cooling(i: int, now: float) -> bool:
    return orders[i] == null and now < float(refresh_at[i])

func time_to_refresh(i: int, now: float) -> float:
    return maxf(0.0, float(refresh_at[i]) - now)

func skip_refresh(i: int, wallet: EnergyWallet, now: float) -> bool:
    if not is_cooling(i, now):
        return false
    if not wallet.spend_gems(int(ConfigDB.tuning["order_skip_gems"])):
        return false
    refresh_at[i] = 0.0
    orders_changed.emit()
    return true

func to_dict() -> Dictionary:
    return {"orders": orders.duplicate(true), "refresh_at": refresh_at.duplicate()}

static func from_dict(d: Dictionary) -> OrderBook:
    var ob := OrderBook.new()
    ob.orders = (d["orders"] as Array).duplicate(true)
    ob.refresh_at = (d.get("refresh_at", [0.0, 0.0, 0.0]) as Array).duplicate()
    return ob
```

Note on `start_cooldown`: the test calls `ob.start_cooldown(0, now)` after `deliver`, but the refresh_time is only known from `deliver`'s return. Simplify: DELETE `start_cooldown`; have the test and `Game` call `set_cooldown(i, refresh_time, now)` using the `refresh_time` from `deliver`'s result. Update the test's `ob.start_cooldown(0, 1000.0)` line to:
`ob.set_cooldown(0, rt, 1000.0)`.

Wire `Game.deliver_order` (from Task 4) to start the cooldown:

```gdscript
func deliver_order(i: int, now: float) -> Dictionary:
    var res := orders.deliver(i, board)
    if not res["ok"]:
        return res
    orders.set_cooldown(i, float(res["refresh_time"]), now)
    wallet.add_coins(int(res["coins"]))
    _grant_level_rewards(player.add_xp(int(res["xp"])), now)
    orders.fill(player.level, rng, now)
    return res
```

Add to `curio-hall/config/curio_hall_tuning.json`: `"order_skip_gems": 30`.

Update `curio-hall/sim/save_manager.gd`: the structural/version gate must accept `Game.SAVE_VERSION` (now 2). If it hardcodes `1`, change the comparison to `Game.SAVE_VERSION`. A v1 save (missing chest/refresh fields) should still be treated per its existing corrupt/gate logic — since save_version 1 != 2 it will now be rejected-as-corrupt; that is acceptable (phase-1 saves reset on upgrade), but leave a `# v1 saves reset on upgrade to v2` comment. Confirm the corrupt-save and round-trip tests in `test_save.gd` reference `Game.SAVE_VERSION` rather than a literal `1`.

Update `curio-hall/test/unit/test_order_book.gd`: its existing tests build orders and call `fill`/`deliver`. They remain valid, but any assertion that an order dict has exactly the old key set should be relaxed to allow the new `"type"`/`"refresh_time"` keys, and any test relying on instant-refill-after-deliver must now either not deliver or account for `refresh_at`. Specifically, the phase-1 `test_deliver_removes_items_and_pays` still passes (deliver clears the slot; it doesn't assert immediate refill). Leave passing tests alone; only fix ones that break.

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS (all suites).

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/order_book.gd curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/config/curio_hall_tuning.json curio-hall/test
git commit -m "feat: timed order refresh with gem-skip, type/tier filters, save v2"
```

---

### Task 6: View wiring — order timers, chest/token rendering, collect feedback, smoke test

**Files:**
- Modify: `curio-hall/view/item_view.gd`, `curio-hall/view/board_view.gd`, `curio-hall/view/order_bar.gd`, `curio-hall/scenes/main.gd`
- Test: `curio-hall/test/unit/test_smoke.gd` (extend)

**Interfaces:**
- Consumes: `Game.tap`, `OrderBook.is_cooling/time_to_refresh/skip_refresh`, `ConfigDB.is_chest`, item `CollectRewards`.
- Produces: board taps route through `Game.tap` (covering collect/chest/generator); order bar shows countdowns + a skip button; `ItemView` renders currency tokens and chests distinctly; a collect/level toast reuses the phase-1 toast.

- [ ] **Step 1: Extend the smoke test (drives the full economy loop through the sim)**

Add to `curio-hall/test/unit/test_smoke.gd` a new test:

```gdscript
func test_economy_loop_chest_to_gems() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    var g := Game.fresh(1000.0, 42)
    # place a gem chest and free neighbors
    var cpos := Vector2i(1, 3)
    g.board.remove(cpos); g.board.set_state(cpos, MergeBoard.CellState.OPEN)
    g.board.place(cpos, ItemInstance.make("main_g_chest_new_1", 1000.0))
    for p in [Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4), Vector2i(0, 3), Vector2i(0, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    # tap chest -> dispenses a currency token; collect every dispensed token
    var gems0 := g.wallet.gems
    var coins0 := g.wallet.coins
    for i in range(5):
        var r := g.tap(cpos, 1000.0)
        if r["ok"] and r.get("spawned"):
            var tp: Vector2i = r["spawned"][0]["pos"]
            g.tap(tp, 1000.0)   # collect it
    assert_true(g.wallet.gems > gems0 or g.wallet.coins > coins0)  # main_g chest yields gems (chain 24=coins? verify)
```

Note: `main_g_chest_new_1` dispenses chain-24 tokens (`2401`/`2402`), whose `CollectRewards` are `gold-*` (coins). If "g" chest yields coins in the data, assert coins increased; if a gem chest is wanted, use the chest whose `Spread_Weight` points at chain-25 (`gem-*`) tokens. The implementer MUST check `config/ItemModelConfig.json` for which chest dispenses which chain and assert the currency that chest actually produces — do not assume from the letter in the name.

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL (until wiring compiles; the sim path may already pass — if so, still complete the view wiring below).

- [ ] **Step 3: Implement the view wiring**

In `curio-hall/view/board_view.gd` `_end_drag`, replace the same-cell tap branch (currently calling `game.tap_generator`) so a same-cell drop routes through `game.tap`:

```gdscript
    if pos == from:
        var item := game.board.item_at(from)
        if item != null and game.board.state_at(from) == MergeBoard.CellState.OPEN \
                and (item.gen != null or item.chest != null or ConfigDB.items.get(item.type, {}).has("CollectRewards")):
            var res := game.tap(from, now)
            if not res["ok"] and res["reason"] != "" and res["reason"] != "not_tappable":
                action_rejected.emit(res["reason"])
            selected = Vector2i(-1, -1)
        elif item != null and game.board.state_at(from) == MergeBoard.CellState.OPEN:
            selected = from
        _snap_back(from)
        return
```

In `curio-hall/view/item_view.gd`, extend `_draw` (OPEN branch) so currency tokens and chests read distinctly through the single `apply()` seam. After computing `chain`/`tier`, before the normal fill:

```gdscript
    var row: Dictionary = ConfigDB.items.get(_type, {})
    if row.has("CollectRewards"):
        var kind := Rewards.parse(String(row["CollectRewards"][0]))["kind"]
        var tint := {"coins": Color(0.95, 0.8, 0.2), "gems": Color(0.4, 0.8, 1.0), "energy": Color(0.5, 1.0, 0.4)}.get(kind, Color.WHITE)
        draw_rect(rect, tint, true)
        draw_string(ThemeDB.fallback_font, Vector2(-SIZE/2 + 4, 8), "collect", HORIZONTAL_ALIGNMENT_CENTER, SIZE - 8, 16, Color.BLACK)
        return
    if ConfigDB.is_chest(_type):
        draw_rect(rect, Color(0.55, 0.4, 0.15), true)
        draw_rect(rect, Color(0.85, 0.65, 0.2), false, 4.0)
        draw_string(ThemeDB.fallback_font, Vector2(-SIZE/2 + 4, 6), "CHEST", HORIZONTAL_ALIGNMENT_CENTER, SIZE - 8, 18, Color.WHITE)
        return
```

In `curio-hall/view/order_bar.gd` `refresh`, replace the empty-slot rendering so a cooling slot shows a countdown + skip button:

```gdscript
        if o == null:
            if game.orders.is_cooling(i, Time.get_unix_time_from_system()):
                var secs := int(game.orders.time_to_refresh(i, Time.get_unix_time_from_system()))
                btn.text = "New order in %ds\nSkip (%d gems)" % [secs, int(ConfigDB.tuning["order_skip_gems"])]
                var idx := i
                btn.pressed.connect(func(): game.orders.skip_refresh(idx, game.wallet, Time.get_unix_time_from_system()))
            else:
                btn.text = "-"
                btn.disabled = true
```

Give `OrderBar` a 1-second refresh timer in `setup` (mirroring `Hud`) so countdowns tick:

```gdscript
    var t := Timer.new(); t.wait_time = 1.0; t.autostart = true
    t.timeout.connect(refresh); add_child(t)
```

In `curio-hall/scenes/main.gd`, connect a brief on-collect confirmation by reusing the toast: after `board_view.setup`, connect the board's `spawned` or add a lightweight signal is unnecessary — instead show the existing reject toast for `chest_wait`/`spent`/`board_full` (already routed through `action_rejected`). No new screen.

- [ ] **Step 4: Run test to verify it passes; boot the game**

Run: `./curio-hall/test.sh` — Expected: PASS (all suites, warning-free).
Then boot windowed to confirm no script errors and that chests/tokens render and order timers tick:
`godot --path curio-hall` (or, headless-only environments: `godot --headless --path curio-hall --quit-after 120` and confirm the log is error-free). Manual playtest: level up to drop a chest, tap it, collect the tokens, watch gems/coins move, and see an order slot show a countdown after delivery.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/view curio-hall/scenes/main.gd curio-hall/test/unit/test_smoke.gd
git commit -m "feat: view wiring for chests, collectible tokens, order timers - phase 2 playable"
```

---

## Self-review notes (already applied)

- Spec coverage: §1 Rewards (T1); §2a ChestState (T3); §2b collect-on-tap (T2); §2c order rework (T5); §2d reward pipeline (T4); §3 view (T6); §4 persistence (chest serialize T3, order serialize + save v2 T5); §5 testing distributed; §6 milestones map to T1-T6.
- Deliberate readings recorded as Global Constraints: chest predicate; uniform order-type selection with a 60-second refresh floor (config has no per-type weights, and types 15/16 have a 1-second refresh); order XP from `DiffScore`; `order_skip_gems` default 30.
- Type consistency: `add_xp` returns `Array[int]` of gained levels (T4) and every caller (`Game.deliver_order`, `_grant_level_rewards`, updated `test_player_state`) uses that contract; `ItemInstance` carries both `gen` and `chest`, exactly one non-null; `Game.tap` returns `{ok, kind, reason, [spawned]}` used by T6's view. `OrderBook` order dicts carry `type`/`refresh_time`; `set_cooldown` (not `start_cooldown`) is the final API — the T5 note deletes the stub and updates the test line.
- Known follow-ups (not in this plan, tracked in the roadmap): multi-order-board / per-slot type assignment if the true mapping is later recovered; positional `FirstMin`/`SecondMin` minimum-tier enforcement (only Max caps are honored here).
```
