# Curio Hall Phase 3 (Shop / IAP) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give earned currencies real spend sinks: a coin item-shop, gem daily-deals, and dev-stubbed real-money IAP, on a modal shop overlay, with timed refresh and save persistence.

**Architecture:** Three focused `RefCounted` sim classes (`ItemShop`, `DailyDeals`, `Iap`) mirroring phase 2's `OrderBook`, all grants routed through the existing `Rewards.grant` sink and all spends through the atomic `EnergyWallet`. `Game` owns them, exposes buy/tick methods, and serializes them at save v3. A `ShopPanel` CanvasLayer overlay renders the three surfaces. IAP is a labeled dev stub (no real payment).

**Tech Stack:** Godot 4.x (GDScript), GUT, JSON config copied into `curio-hall/config/`.

**Spec:** `docs/superpowers/specs/2026-09-02-curio-hall-phase3-shop-design.md`

## Global Constraints

- Godot 4.x, GDScript only. Project at `curio-hall/`. Tests: `./curio-hall/test.sh` (must stay green and warning-free; commit after each green cycle). This project treats GDScript warnings as errors — annotate types explicitly; never `var x :=` inferred from a Dictionary/Array lookup.
- Item ids are Strings. Config files are verbatim copies, never edited.
- Reward grammar (existing `Rewards.grant`/`grant_all`): `"gold-N"`=coins, `"gem-N"`=gems, `"energy-N"`=energy, else item id + count. Every grant goes through `Rewards`; every spend through `EnergyWallet.spend_coins`/`spend_gems` (atomic check-then-deduct).
- Time enters the sim only as injected `now: float`; randomness only via an injected `RandomNumberGenerator`. Never call `Time.*` in `sim/`.
- Shop-chain of an `ItemProperty` item = its `CustomChain` when that field is present and non-empty (e.g. `"0"`), else the item id's natural chain (`id.substr(0, id.length() - 2)`).
- New tuning constants: `shop_refresh_seconds` 3600, `shop_skip_gems` 30, `daily_deals_restock_seconds` 86400.
- IAP is a dev stub: `purchase_pack`/`purchase_bundle` grant `goods` directly; nothing touches real billing. Bundle honors `condition: "Level-3"`, `buyCount: 1`, `lastDuration: 172800` (48h).
- Save `SAVE_VERSION` becomes 3. A v2 save loads via SaveManager's existing structural+version gate (v2 != v3 → treated as corrupt, resets — acceptable, matching the phase-2 v1→v2 policy). New shop fields default when absent.
- Who ticks the sim: the main scene's existing 1-second `_flush_save` timer also calls `game.tick_shop(now)` (this is the third time-driven system after energy regen and orders). Do NOT reintroduce the phase-2 self-freeing-timer bug (a node's refresh loop must not `queue_free` its own timer).

## File Structure

```
curio-hall/
  config/ShopSlotConfig.json          # T1 (copied verbatim)
  config/ShopDailyDealsConfig.json     # T1
  config/ShopIAPConfig.json            # T1
  config/BundleConfig.json             # T1
  config/curio_hall_tuning.json        # T1 (add 3 constants)
  sim/config_db.gd                     # T1 (load 4 shop tables)
  sim/item_shop.gd                     # T2 (new)  6 coin slots + timed refresh
  sim/daily_deals.gd                   # T3 (new)  gem deals + 24h restock
  sim/iap.gd                           # T4 (new)  dev-stub packs + bundle
  sim/game.gd                          # T5 (modify) own + tick + buy + save v3
  sim/save_manager.gd                  # T5 (comment only; gate is dynamic)
  scenes/main.gd                       # T6 (modify) Shop button, tick_shop, toasts
  scenes/main.tscn                     # T6 (modify) ShopButton + ShopPanel nodes
  view/shop_panel.gd                   # T6 (new)  overlay with 3 sections
  test/unit/test_*.gd                  # per task
```

---

### Task 1: Shop config load + tuning constants

**Files:**
- Create: `curio-hall/config/ShopSlotConfig.json`, `curio-hall/config/ShopDailyDealsConfig.json`, `curio-hall/config/ShopIAPConfig.json`, `curio-hall/config/BundleConfig.json` 
- Modify: `curio-hall/config/curio_hall_tuning.json`, `curio-hall/sim/config_db.gd`
- Test: `curio-hall/test/unit/test_shop_config.gd`

**Interfaces:**
- Produces: `ConfigDB.shop_slots: Array` (ShopSlotConfig rows), `ConfigDB.daily_deals: Array` (ShopDailyDealsConfig rows), `ConfigDB.iap_packs: Array` (ShopIAPConfig rows), `ConfigDB.bundles: Array` (BundleConfig rows). `ConfigDB.tuning` gains `shop_refresh_seconds`, `shop_skip_gems`, `daily_deals_restock_seconds`. `ConfigDB.properties` (already present) is the ItemProperty lookup by id.

- [ ] **Step 1: Copy the four shop config files verbatim**

```bash



- [ ] **Step 2: Add the three tuning constants**

Edit `curio-hall/config/curio_hall_tuning.json` so it also contains (keep existing keys):

```json
{ "energy_max": 100, "energy_regen_seconds": 120, "starting_energy": 100, "starting_coins": 0, "starting_gems": 0, "order_skip_gems": 30, "shop_refresh_seconds": 3600, "shop_skip_gems": 30, "daily_deals_restock_seconds": 86400 }
```

(Preserve whatever keys already exist; only add the three shop ones. Do not remove `order_skip_gems`.)

- [ ] **Step 3: Write the failing test**

`curio-hall/test/unit/test_shop_config.gd`:

```gdscript
extends GutTest

func test_shop_tables_loaded() -> void:
    assert_gt(ConfigDB.shop_slots.size(), 0)
    assert_eq(ConfigDB.daily_deals.size(), 3)
    assert_eq(ConfigDB.iap_packs.size(), 6)
    assert_eq(ConfigDB.bundles.size(), 1)

func test_shop_slot_shape() -> void:
    var row: Dictionary = ConfigDB.shop_slots[0]
    assert_true(row.has("ChainId"))
    assert_true(row.has("Slot1Weight"))

func test_iap_pack_shape() -> void:
    assert_eq(ConfigDB.iap_packs[0]["goods"], ["gem-100"])

func test_bundle_shape() -> void:
    var b: Dictionary = ConfigDB.bundles[0]
    assert_eq(b["condition"], "Level-3")
    assert_eq(int(b["buyCount"]), 1)
    assert_eq(int(b["lastDuration"]), 172800)

func test_tuning_constants() -> void:
    assert_eq(int(ConfigDB.tuning["shop_refresh_seconds"]), 3600)
    assert_eq(int(ConfigDB.tuning["shop_skip_gems"]), 30)
    assert_eq(int(ConfigDB.tuning["daily_deals_restock_seconds"]), 86400)

func test_item_property_lookup() -> void:
    assert_true(ConfigDB.properties.has("203"))
    assert_eq(int(ConfigDB.properties["203"]["Price"]), 1)
```

- [ ] **Step 4: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL (`ConfigDB.shop_slots` etc. missing).

- [ ] **Step 5: Add the ConfigDB members and loaders**

In `curio-hall/sim/config_db.gd`, add member vars near the other `var ... : Array` declarations:

```gdscript
var shop_slots: Array = []
var daily_deals: Array = []
var iap_packs: Array = []
var bundles: Array = []
```

In `load_all`, after the `tuning = _read(...)` line, add:

```gdscript
	shop_slots = _read(dir + "ShopSlotConfig.json")
	daily_deals = _read(dir + "ShopDailyDealsConfig.json")
	iap_packs = _read(dir + "ShopIAPConfig.json")
	bundles = _read(dir + "BundleConfig.json")
```

- [ ] **Step 6: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS (all prior suites still green).

- [ ] **Step 7: Commit**

```bash
git add curio-hall/config curio-hall/sim/config_db.gd curio-hall/test/unit/test_shop_config.gd
git commit -m "feat: load shop config tables and shop tuning constants"
```

---

### Task 2: ItemShop (coin slots + timed refresh + gem-skip)

**Files:**
- Create: `curio-hall/sim/item_shop.gd`
- Test: `curio-hall/test/unit/test_item_shop.gd`

**Interfaces:**
- Consumes: `ConfigDB.shop_slots`, `ConfigDB.properties`, `ConfigDB.tuning` (`shop_refresh_seconds`, `shop_skip_gems`), `Weighted`, `Rewards.grant`, `EnergyWallet` (`spend_coins`, `spend_gems`).
- Produces: `ItemShop` (RefCounted): `const SLOTS := 6`; `signal shop_changed`; `var slots: Array` (each `{item, price, count, sold_out}` or null) and `var refresh_at: float`. Methods: `roll_slot(n: int, rng) -> Dictionary`; `fill(rng, now) -> bool` (fills null/never-filled slots when `now >= refresh_at`, returns whether anything filled, emits only when it did); `buy(n: int, wallet: EnergyWallet, game, now: float) -> Dictionary` (`{ok, reason}`, reasons `"empty"|"sold_out"|"not_enough_coins"`); `is_refreshing(now) -> bool`; `time_to_refresh(now) -> float`; `set_refresh(now)`; `skip_refresh(wallet, now) -> bool`; `to_dict()/from_dict`.

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_item_shop.gd`:

```gdscript
extends GutTest

func _rng() -> RandomNumberGenerator:
    var r := RandomNumberGenerator.new(); r.seed = 11; return r

func test_roll_slot_yields_real_priced_item() -> void:
    var s := ItemShop.new()
    for n in range(1, ItemShop.SLOTS + 1):
        var slot := s.roll_slot(n, _rng())
        assert_true(ConfigDB.properties.has(slot["item"]))
        assert_true(int(n) in ConfigDB.properties[slot["item"]].get("Slot", []))
        assert_eq(int(slot["price"]), int(ConfigDB.properties[slot["item"]]["Price"]))
        assert_gt(int(slot["count"]), 0)
        assert_false(slot["sold_out"])

func test_fill_populates_all_slots_and_returns_true() -> void:
    var s := ItemShop.new()
    assert_true(s.fill(_rng(), 1000.0))
    for slot in s.slots:
        assert_not_null(slot)
    # already full and not yet refreshing -> no-op returns false
    assert_false(s.fill(_rng(), 1000.0))

func test_buy_spends_coins_grants_and_marks_sold_out() -> void:
    var g := Game.fresh(1000.0, 42)
    g.shop.fill(g.rng, 1000.0)
    # free a board cell so granted items can land
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    var n := 1
    var price := int(g.shop.slots[n - 1]["price"])
    g.wallet.add_coins(price + 100)
    var coins0 := g.wallet.coins
    var res := g.shop.buy(n, g.wallet, g, 1000.0)
    assert_true(res["ok"])
    assert_eq(g.wallet.coins, coins0 - price)
    assert_true(g.shop.slots[n - 1]["sold_out"])
    # buying a sold-out slot is rejected without spend
    assert_eq(g.shop.buy(n, g.wallet, g, 1000.0)["reason"], "sold_out")

func test_buy_insufficient_coins_rejected_without_spend() -> void:
    var g := Game.fresh(1000.0, 42)
    g.shop.fill(g.rng, 1000.0)
    g.wallet.spend_coins(g.wallet.coins)  # zero coins
    var res := g.shop.buy(1, g.wallet, g, 1000.0)
    assert_false(res["ok"])
    assert_eq(res["reason"], "not_enough_coins")
    assert_eq(g.wallet.coins, 0)

func test_timed_refresh_and_gem_skip() -> void:
    var s := ItemShop.new()
    s.fill(_rng(), 1000.0)
    s.set_refresh(1000.0)  # start a refresh cooldown
    assert_true(s.is_refreshing(1000.0))
    var secs := int(ConfigDB.tuning["shop_refresh_seconds"])
    assert_almost_eq(s.time_to_refresh(1000.0), float(secs), 1.0)
    var w := EnergyWallet.fresh(1000.0); w.add_gems(100)
    assert_true(s.skip_refresh(w, 1000.0))
    assert_eq(w.gems, 100 - int(ConfigDB.tuning["shop_skip_gems"]))
    assert_false(s.is_refreshing(1000.0))

func test_round_trip() -> void:
    var s := ItemShop.new()
    s.fill(_rng(), 1000.0)
    s.slots[0]["sold_out"] = true
    var s2 := ItemShop.from_dict(s.to_dict())
    assert_eq(s2.slots[0]["sold_out"], true)
    assert_eq(s2.slots.size(), ItemShop.SLOTS)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement**

`curio-hall/sim/item_shop.gd`:

```gdscript
class_name ItemShop
extends RefCounted
## The coin item-shop: 6 weighted slots, buy-with-coins, whole-shop timed refresh.

const SLOTS := 6

signal shop_changed

var slots: Array = [null, null, null, null, null, null]
var refresh_at: float = 0.0   # shop re-rolls when now >= refresh_at (0 = fill now)

func _natural_chain(id: String) -> String:
    return id.substr(0, id.length() - 2)

func _shop_chain(row: Dictionary) -> String:
    var custom := String(row.get("CustomChain", ""))
    return custom if custom != "" else _natural_chain(String(row["Type"]))

func roll_slot(n: int, rng: RandomNumberGenerator) -> Dictionary:
    var by_chain := {}
    for r in ConfigDB.properties.values():
        if n in r.get("Slot", []):
            var ch := _shop_chain(r)
            if not by_chain.has(ch):
                by_chain[ch] = []
            by_chain[ch].append(r)
    var chain_weights: Array = []
    for slotrow in ConfigDB.shop_slots:
        var ch := String(slotrow["ChainId"])
        var w := int(slotrow.get("Slot%dWeight" % n, 0))
        if w > 0 and by_chain.has(ch):
            chain_weights.append("%s-%d" % [ch, w])
    var pool: Array
    if chain_weights.is_empty():
        # fallback: any candidate uniformly
        pool = []
        for arr in by_chain.values():
            pool.append_array(arr)
    else:
        var chosen := Weighted.roll(Weighted.parse(chain_weights), rng)
        pool = by_chain[chosen]
    var item_weights := Weighted.parse(pool.map(
        func(r: Dictionary) -> String: return "%s-%d" % [r["Type"], int(r.get("ShopWeight", 1))]))
    var item_id := Weighted.roll(item_weights, rng)
    var prop: Dictionary = ConfigDB.properties[item_id]
    return {"item": item_id, "price": int(prop["Price"]), "count": int(prop.get("ShopCount", 1)), "sold_out": false}

func fill(rng: RandomNumberGenerator, now: float) -> bool:
    if now < refresh_at:
        return false
    var did := false
    for i in range(SLOTS):
        if slots[i] == null:
            slots[i] = roll_slot(i + 1, rng)
            did = true
    if did:
        shop_changed.emit()
    return did

func buy(n: int, wallet: EnergyWallet, game, now: float) -> Dictionary:
    var slot: Variant = slots[n - 1]
    if slot == null:
        return {"ok": false, "reason": "empty"}
    if slot["sold_out"]:
        return {"ok": false, "reason": "sold_out"}
    if not wallet.spend_coins(int(slot["price"])):
        return {"ok": false, "reason": "not_enough_coins"}
    for i in range(int(slot["count"])):
        Rewards.grant(String(slot["item"]), game, now)
    slot["sold_out"] = true
    shop_changed.emit()
    return {"ok": true, "reason": ""}

func set_refresh(now: float) -> void:
    refresh_at = now + float(ConfigDB.tuning["shop_refresh_seconds"])

func is_refreshing(now: float) -> bool:
    return now < refresh_at

func time_to_refresh(now: float) -> float:
    return maxf(0.0, refresh_at - now)

func skip_refresh(wallet: EnergyWallet, now: float) -> bool:
    if not is_refreshing(now):
        return false
    if not wallet.spend_gems(int(ConfigDB.tuning["shop_skip_gems"])):
        return false
    refresh_at = 0.0
    for i in range(SLOTS):
        slots[i] = null
    shop_changed.emit()
    return true

func to_dict() -> Dictionary:
    return {"slots": slots.duplicate(true), "refresh_at": refresh_at}

static func from_dict(d: Dictionary) -> ItemShop:
    var s := ItemShop.new()
    s.slots = (d.get("slots", [null, null, null, null, null, null]) as Array).duplicate(true)
    s.refresh_at = float(d.get("refresh_at", 0.0))
    return s
```

Note on the refresh model: `fill` re-rolls only null slots; a whole-shop refresh happens by setting all slots null then filling. `set_refresh` starts the cooldown (Game calls it when all slots are sold out — see Task 5), `skip_refresh` nulls the slots immediately so the next `fill` re-rolls. When a `fill` runs after `refresh_at` elapses, it only fills nulls, so Game must null sold-out slots at refresh time (Task 5's `tick_shop` handles this: when `now >= refresh_at` and refresh_at != 0, null all slots then fill and reset refresh_at to 0).

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS. (The buy tests reference `Game.fresh(...).shop`; that field is added in Task 5. If Task 2 runs before Task 5, temporarily construct `ItemShop.new()` directly and pass a fresh `EnergyWallet`/a minimal object with `board`/`player` for the grant — but since the plan runs tasks in order and Task 5 adds `Game.shop`, prefer to keep the tests as written and confirm they pass after Task 5. If they fail here solely because `Game` has no `shop` field yet, split: run the non-Game tests now, and the two `Game.fresh(...).shop` buy tests will pass once Task 5 lands. Mark this explicitly in the report.)

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/item_shop.gd curio-hall/test/unit/test_item_shop.gd
git commit -m "feat: ItemShop coin slots with weighted roll and timed refresh"
```

**Controller note (resolve the Game.shop dependency):** to keep every task's suite green, Task 2's buy tests need `Game.shop`. The cleanest ordering is to have Task 2 also add a minimal `var shop: ItemShop` to `Game` initialized in `fresh` (`g.shop = ItemShop.new()`), WITHOUT the tick/buy/save wiring (that stays Task 5). Add exactly these two lines to `sim/game.gd` in Task 2 so the field exists; Task 5 builds the rest on top. Include that one-line `game.gd` change in this task's commit.

---

### Task 3: DailyDeals (gem deals + 24h restock)

**Files:**
- Create: `curio-hall/sim/daily_deals.gd`
- Test: `curio-hall/test/unit/test_daily_deals.gd`

**Interfaces:**
- Consumes: `ConfigDB.daily_deals`, `ConfigDB.tuning` (`daily_deals_restock_seconds`), `Rewards.grant`, `EnergyWallet.spend_gems`.
- Produces: `DailyDeals` (RefCounted): `signal deals_changed`; `var stock: Dictionary` (deal id → remaining count) and `var restock_at: float`. Methods: `deals() -> Array` (each `{id, item, cost_gems, stock, is_ad}`); `buy(id: int, wallet, game, now) -> Dictionary` (`{ok, reason}`, reasons `"out_of_stock"|"not_enough_gems"`); `restock(now)` / auto-restock inside `tick(now)`; `to_dict()/from_dict`. Also `Game` gains `var deals: DailyDeals` (init in `fresh`, mirroring the Task-2 note).

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_daily_deals.gd`:

```gdscript
extends GutTest

func _free_cells(g: Game) -> void:
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)

func test_deals_reflect_config() -> void:
    var d := DailyDeals.new()
    var list := d.deals()
    assert_eq(list.size(), 3)
    # deal 1: 25 gems, deal 2: 10 gems + ad, deal 3: free
    var by_id := {}
    for dl in list: by_id[int(dl["id"])] = dl
    assert_eq(int(by_id[1]["cost_gems"]), 25)
    assert_eq(int(by_id[2]["cost_gems"]), 10)
    assert_true(by_id[2]["is_ad"])
    assert_eq(int(by_id[3]["cost_gems"]), 0)

func test_buy_spends_gems_grants_and_decrements_stock() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_gems(100)
    var gems0 := g.wallet.gems
    var res := g.deals.buy(1, g.wallet, g, 1000.0)   # 25 gems
    assert_true(res["ok"])
    assert_eq(g.wallet.gems, gems0 - 25)
    assert_eq(int(g.deals.stock[1]), 0)              # leftCount was 1
    assert_eq(g.deals.buy(1, g.wallet, g, 1000.0)["reason"], "out_of_stock")

func test_buy_free_deal_costs_nothing() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    var gems0 := g.wallet.gems
    assert_true(g.deals.buy(3, g.wallet, g, 1000.0)["ok"])  # free
    assert_eq(g.wallet.gems, gems0)

func test_buy_insufficient_gems_rejected_without_spend() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.spend_gems(g.wallet.gems)  # zero
    var res := g.deals.buy(1, g.wallet, g, 1000.0)
    assert_false(res["ok"])
    assert_eq(res["reason"], "not_enough_gems")

func test_restock_after_24h() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_gems(100)
    g.deals.buy(1, g.wallet, g, 1000.0)
    assert_eq(int(g.deals.stock[1]), 0)
    var secs := int(ConfigDB.tuning["daily_deals_restock_seconds"])
    g.deals.tick(1000.0 + secs + 1.0)
    assert_eq(int(g.deals.stock[1]), 1)

func test_round_trip() -> void:
    var d := DailyDeals.new()
    d.stock[1] = 0
    var d2 := DailyDeals.from_dict(d.to_dict())
    assert_eq(int(d2.stock[1]), 0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement**

`curio-hall/sim/daily_deals.gd`:

```gdscript
class_name DailyDeals
extends RefCounted
## Gem-priced daily deals with limited stock and a 24h restock.

signal deals_changed

var stock: Dictionary = {}      # deal id (int) -> remaining count
var restock_at: float = 0.0

func _init() -> void:
    _reset_stock()
    restock_at = 0.0

func _reset_stock() -> void:
    for row in ConfigDB.daily_deals:
        stock[int(row["id"])] = int(row.get("leftCount", 0))

func _row_for(id: int) -> Dictionary:
    for row in ConfigDB.daily_deals:
        if int(row["id"]) == id:
            return row
    return {}

func deals() -> Array:
    var out: Array = []
    for row in ConfigDB.daily_deals:
        var id := int(row["id"])
        out.append({
            "id": id,
            "item": String(row["itemCode"]),
            "cost_gems": int(row.get("costCount", 0)),
            "stock": int(stock.get(id, 0)),
            "is_ad": int(row.get("ad", 0)) == 1,
        })
    return out

func buy(id: int, wallet: EnergyWallet, game, now: float) -> Dictionary:
    var row := _row_for(id)
    if row.is_empty() or int(stock.get(id, 0)) <= 0:
        return {"ok": false, "reason": "out_of_stock"}
    var cost := int(row.get("costCount", 0))
    if not wallet.spend_gems(cost):
        return {"ok": false, "reason": "not_enough_gems"}
    Rewards.grant(String(row["itemCode"]), game, now)
    stock[id] = int(stock[id]) - 1
    deals_changed.emit()
    return {"ok": true, "reason": ""}

func tick(now: float) -> void:
    if restock_at == 0.0:
        restock_at = now + float(ConfigDB.tuning["daily_deals_restock_seconds"])
        return
    if now >= restock_at:
        _reset_stock()
        restock_at = now + float(ConfigDB.tuning["daily_deals_restock_seconds"])
        deals_changed.emit()

func to_dict() -> Dictionary:
    return {"stock": stock.duplicate(), "restock_at": restock_at}

static func from_dict(d: Dictionary) -> DailyDeals:
    var dd := DailyDeals.new()
    var raw: Dictionary = d.get("stock", {})
    dd.stock = {}
    for k in raw:
        dd.stock[int(k)] = int(raw[k])
    dd.restock_at = float(d.get("restock_at", 0.0))
    return dd
```

Add `var deals: DailyDeals` to `Game` and `g.deals = DailyDeals.new()` in `fresh` (mirroring Task 2's `shop` note); include that one-line `game.gd` change in this commit.

Note: `spend_gems(0)` on a free deal must return `true` (spending zero always succeeds — confirm `EnergyWallet.spend_gems` returns true for n=0; it does, since `gems < 0` is false). The ad flag is surfaced in `deals()` for the view to label; it does not change the gem cost in the sim (the view gates the "watch ad" affordance, dev-free, but the sim still charges `cost_gems`).

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/daily_deals.gd curio-hall/sim/game.gd curio-hall/test/unit/test_daily_deals.gd
git commit -m "feat: DailyDeals gem purchases with stock and 24h restock"
```

---

### Task 4: Iap (dev-stub packs + bundle)

**Files:**
- Create: `curio-hall/sim/iap.gd`
- Test: `curio-hall/test/unit/test_iap.gd`

**Interfaces:**
- Consumes: `ConfigDB.iap_packs`, `ConfigDB.bundles`, `Rewards.grant_all`, `PlayerState.level`.
- Produces: `Iap` (RefCounted): `var bundle_bought: bool` and `var bundle_first_seen: float` (save state). Methods: `packs() -> Array` (the 6 `ShopIAP` rows as `{purchase_id, goods, icon}`); `purchase_pack(purchase_id: String, game, now) -> Dictionary` (`{ok}`; dev stub grants `goods`, always ok for a known id, `{ok:false, reason:"unknown"}` otherwise); `bundle_state(game, now) -> Dictionary` (`{available: bool, reason: String, goods, purchase_id}` — reasons `"locked"|"already_bought"|"expired"|""`); `purchase_bundle(game, now) -> Dictionary` (`{ok, reason}`; honors Level-3 lock, one-time buyCount, 48h expiry from first-seen); `note_seen(now)` (records `bundle_first_seen` the first time the bundle is offered); `to_dict()/from_dict`.

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_iap.gd`:

```gdscript
extends GutTest

func test_packs_reflect_config() -> void:
    var iap := Iap.new()
    var ps := iap.packs()
    assert_eq(ps.size(), 6)
    assert_eq(ps[0]["goods"], ["gem-100"])
    assert_true(ps[0]["purchase_id"] != "")

func test_purchase_pack_stub_grants_gems() -> void:
    var g := Game.fresh(1000.0, 42)
    var gems0 := g.wallet.gems
    var res := g.iap.purchase_pack("getgem_1", g, 1000.0)   # goods gem-100
    assert_true(res["ok"])
    assert_eq(g.wallet.gems, gems0 + 100)

func test_purchase_pack_unknown_id() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_eq(g.iap.purchase_pack("nope", g, 1000.0).get("reason", ""), "unknown")

func test_bundle_locked_below_level_3() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 1
    g.iap.note_seen(1000.0)
    assert_eq(g.iap.bundle_state(g, 1000.0)["reason"], "locked")
    assert_eq(g.iap.purchase_bundle(g, 1000.0)["reason"], "locked")

func test_bundle_purchase_then_one_time() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 3
    g.iap.note_seen(1000.0)
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    var gems0 := g.wallet.gems
    var res := g.iap.purchase_bundle(g, 1000.0)   # goods gem-510, energy-200, 3601-2
    assert_true(res["ok"])
    assert_eq(g.wallet.gems, gems0 + 510)
    assert_eq(g.iap.purchase_bundle(g, 1000.0)["reason"], "already_bought")

func test_bundle_expires_after_duration() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 3
    g.iap.note_seen(1000.0)
    var dur := int(ConfigDB.bundles[0]["lastDuration"])
    assert_eq(g.iap.bundle_state(g, 1000.0 + dur + 1.0)["reason"], "expired")
    assert_eq(g.iap.purchase_bundle(g, 1000.0 + dur + 1.0)["reason"], "expired")

func test_round_trip() -> void:
    var iap := Iap.new()
    iap.bundle_bought = true
    iap.bundle_first_seen = 1234.0
    var i2 := Iap.from_dict(iap.to_dict())
    assert_true(i2.bundle_bought)
    assert_eq(i2.bundle_first_seen, 1234.0)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement**

`curio-hall/sim/iap.gd`:

```gdscript
class_name Iap
extends RefCounted
## Real-money IAP, DEV STUB ONLY. Purchases grant goods directly; no billing.

var bundle_bought: bool = false
var bundle_first_seen: float = -1.0   # -1 = not yet offered

func packs() -> Array:
    var out: Array = []
    for row in ConfigDB.iap_packs:
        out.append({
            "purchase_id": String(row["purchaseId"]),
            "goods": row["goods"],
            "icon": String(row.get("icon", "")),
        })
    return out

func purchase_pack(purchase_id: String, game, now: float) -> Dictionary:
    for row in ConfigDB.iap_packs:
        if String(row["purchaseId"]) == purchase_id:
            Rewards.grant_all(row["goods"], game, now)
            return {"ok": true, "reason": ""}
    return {"ok": false, "reason": "unknown"}

func _bundle_row() -> Dictionary:
    return ConfigDB.bundles[0] if ConfigDB.bundles.size() > 0 else {}

func _required_level() -> int:
    var cond := String(_bundle_row().get("condition", ""))
    if cond.begins_with("Level-"):
        return int(cond.substr(6))
    return 1

func note_seen(now: float) -> void:
    if bundle_first_seen < 0.0:
        bundle_first_seen = now

func bundle_state(game, now: float) -> Dictionary:
    var row := _bundle_row()
    var base := {"goods": row.get("goods", []), "purchase_id": String(row.get("purchaseId", ""))}
    if bundle_bought:
        base["available"] = false; base["reason"] = "already_bought"; return base
    if game.player.level < _required_level():
        base["available"] = false; base["reason"] = "locked"; return base
    if bundle_first_seen >= 0.0 and now >= bundle_first_seen + float(row.get("lastDuration", 0)):
        base["available"] = false; base["reason"] = "expired"; return base
    base["available"] = true; base["reason"] = ""; return base

func purchase_bundle(game, now: float) -> Dictionary:
    var st := bundle_state(game, now)
    if not st["available"]:
        return {"ok": false, "reason": st["reason"]}
    Rewards.grant_all(_bundle_row()["goods"], game, now)
    bundle_bought = true
    return {"ok": true, "reason": ""}

func to_dict() -> Dictionary:
    return {"bundle_bought": bundle_bought, "bundle_first_seen": bundle_first_seen}

static func from_dict(d: Dictionary) -> Iap:
    var iap := Iap.new()
    iap.bundle_bought = bool(d.get("bundle_bought", false))
    iap.bundle_first_seen = float(d.get("bundle_first_seen", -1.0))
    return iap
```

Add `var iap: Iap` to `Game` and `g.iap = Iap.new()` in `fresh` (mirroring the earlier note); include that one-line change in this commit.

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/iap.gd curio-hall/sim/game.gd curio-hall/test/unit/test_iap.gd
git commit -m "feat: Iap dev-stub gem packs and gated starter bundle"
```

---

### Task 5: Game wiring — tick_shop, buy methods, save v3

**Files:**
- Modify: `curio-hall/sim/game.gd`, `curio-hall/sim/save_manager.gd` (comment only), `curio-hall/test/unit/test_save.gd` (extend), `curio-hall/sim/item_shop.gd` (if a helper is needed for the refresh-null step)
- Test: `curio-hall/test/unit/test_shop_game.gd`

**Interfaces:**
- Consumes: `ItemShop`, `DailyDeals`, `Iap` (all with `to_dict/from_dict`), `EnergyWallet`.
- Produces on `Game`: fields `shop: ItemShop`, `deals: DailyDeals`, `iap: Iap` (created in `fresh`, from Tasks 2-4). New `const SAVE_VERSION := 3`. Methods: `tick_shop(now: float) -> void` (advances shop refresh: if `shop.is_refreshing(now)` has elapsed, null all shop slots + `shop.fill` + clear `refresh_at`; when all shop slots are sold out and not already refreshing, start the refresh cooldown; call `deals.tick(now)`); `buy_shop_slot(n, now) -> Dictionary`; `skip_shop_refresh(now) -> Dictionary` (`{ok, reason}` reason `"not_enough_gems"`); `buy_daily_deal(id, now) -> Dictionary`; `buy_iap_pack(purchase_id, now) -> Dictionary`; `buy_bundle(now) -> Dictionary`. `to_dict/from_dict` include `shop`, `deals`, `iap`.

- [ ] **Step 1: Write the failing test**

`curio-hall/test/unit/test_shop_game.gd`:

```gdscript
extends GutTest

func before_each() -> void:
    SaveManager.path = "user://test_save.json"
    SaveManager.corrupt_path = "user://test_save.corrupt.json"

func after_each() -> void:
    for p in [SaveManager.path, SaveManager.corrupt_path]:
        if FileAccess.file_exists(p):
            DirAccess.remove_absolute(p)
    SaveManager.path = "user://save.json"
    SaveManager.corrupt_path = "user://save.corrupt.json"

func _free_cells(g: Game) -> void:
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4), Vector2i(0, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)

func test_fresh_game_has_shop_surfaces() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_not_null(g.shop)
    assert_not_null(g.deals)
    assert_not_null(g.iap)
    # shop filled at fresh
    for slot in g.shop.slots:
        assert_not_null(slot)

func test_buy_shop_slot_via_game() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    var price := int(g.shop.slots[0]["price"])
    g.wallet.add_coins(price + 50)
    assert_true(g.buy_shop_slot(1, 1000.0)["ok"])
    assert_true(g.shop.slots[0]["sold_out"])

func test_tick_shop_starts_and_completes_refresh() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_coins(1000000)
    for n in range(1, ItemShop.SLOTS + 1):
        g.buy_shop_slot(n, 1000.0)   # sell out all slots
    g.tick_shop(1000.0)              # all sold out -> start refresh cooldown
    assert_true(g.shop.is_refreshing(1000.0))
    var secs := int(ConfigDB.tuning["shop_refresh_seconds"])
    g.tick_shop(1000.0 + secs + 1.0) # cooldown elapsed -> re-roll
    assert_false(g.shop.is_refreshing(1000.0 + secs + 1.0))
    for slot in g.shop.slots:
        assert_not_null(slot)
        assert_false(slot["sold_out"])

func test_skip_shop_refresh_insufficient_gems() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.add_coins(1000000)
    for n in range(1, ItemShop.SLOTS + 1):
        g.buy_shop_slot(n, 1000.0)
    g.tick_shop(1000.0)
    g.wallet.spend_gems(g.wallet.gems)
    assert_eq(g.skip_shop_refresh(1000.0)["reason"], "not_enough_gems")

func test_save_v3_round_trip_preserves_shop_state() -> void:
    var g := Game.fresh(1000.0, 42)
    _free_cells(g)
    g.wallet.add_coins(1000)
    g.buy_shop_slot(1, 1000.0)
    g.wallet.add_gems(100)
    g.buy_daily_deal(1, 1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.to_dict()["save_version"], 3)
    assert_true(g2.shop.slots[0]["sold_out"])
    assert_eq(int(g2.deals.stock[1]), 0)

func test_save_and_load_through_manager() -> void:
    var g := Game.fresh(1000.0, 42)
    g.wallet.add_gems(5)
    SaveManager.save(g)
    var g2 := SaveManager.load_game()
    assert_not_null(g2)
    assert_eq(g2.wallet.gems, 5)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./curio-hall/test.sh` — Expected: FAIL.

- [ ] **Step 3: Implement**

In `curio-hall/sim/game.gd`:

- Bump `const SAVE_VERSION := 2` to `const SAVE_VERSION := 3`.
- In `fresh`, after the orders setup, ensure the shop surfaces exist and the shop is filled:

```gdscript
    g.shop = ItemShop.new()
    g.shop.fill(g.rng, now)
    g.deals = DailyDeals.new()
    g.iap = Iap.new()
```

(If Tasks 2-4 already added `g.shop = ItemShop.new()` etc., replace those lines with this block so the shop is filled at fresh; keep exactly one initialization.)

- Add the methods:

```gdscript
func tick_shop(now: float) -> void:
    if shop.is_refreshing(now) and now >= shop.refresh_at:
        for i in range(ItemShop.SLOTS):
            shop.slots[i] = null
        shop.refresh_at = 0.0
        shop.fill(rng, now)
    elif not shop.is_refreshing(now):
        var all_sold := true
        for slot in shop.slots:
            if slot == null or not slot["sold_out"]:
                all_sold = false
                break
        if all_sold:
            shop.set_refresh(now)
    deals.tick(now)

func buy_shop_slot(n: int, now: float) -> Dictionary:
    return shop.buy(n, wallet, self, now)

func skip_shop_refresh(now: float) -> Dictionary:
    if shop.skip_refresh(wallet, now):
        shop.fill(rng, now)
        return {"ok": true, "reason": ""}
    return {"ok": false, "reason": "not_enough_gems"}

func buy_daily_deal(id: int, now: float) -> Dictionary:
    return deals.buy(id, wallet, self, now)

func buy_iap_pack(purchase_id: String, now: float) -> Dictionary:
    return iap.purchase_pack(purchase_id, self, now)

func buy_bundle(now: float) -> Dictionary:
    return iap.purchase_bundle(self, now)
```

- Extend `to_dict` to include the three surfaces:

```gdscript
        "shop": shop.to_dict(),
        "deals": deals.to_dict(),
        "iap": iap.to_dict(),
```

- Extend `from_dict`:

```gdscript
    g.shop = ItemShop.from_dict(d["shop"])
    g.deals = DailyDeals.from_dict(d["deals"])
    g.iap = Iap.from_dict(d["iap"])
```

In `curio-hall/sim/save_manager.gd`, update the version-reset comment to mention v2→v3 (the gate already compares `Game.SAVE_VERSION` dynamically — no logic change).

- [ ] **Step 4: Run test to verify it passes**

Run: `./curio-hall/test.sh` — Expected: PASS (all suites, including the Task-2/3/4 buy tests that use `Game.fresh(...).shop/.deals/.iap`). If `test_save.gd`'s existing round-trip test asserts `save_version == 2`, update that literal to `Game.SAVE_VERSION` (or 3).

- [ ] **Step 5: Commit**

```bash
git add curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/test
git commit -m "feat: Game shop wiring, tick_shop, buy methods, save v3"
```

---

### Task 6: ShopPanel overlay + Shop button + view wiring + smoke test

**Files:**
- Create: `curio-hall/view/shop_panel.gd`
- Modify: `curio-hall/scenes/main.gd`, `curio-hall/scenes/main.tscn`
- Test: `curio-hall/test/unit/test_smoke.gd` (extend)

**Interfaces:**
- Consumes: `Game` buy/tick methods, `ItemShop`/`DailyDeals`/`Iap` read APIs, `ConfigDB.tuning`.
- Produces: a `ShopPanel` overlay opened by a Shop button; board taps unaffected; the main 1s timer calls `game.tick_shop`; buy failures show toasts.

- [ ] **Step 1: Extend the smoke test (drives the shop loop through the sim)**

Add to `curio-hall/test/unit/test_smoke.gd`:

```gdscript
func test_shop_loop_buy_and_refresh() -> void:
    if FileAccess.file_exists(SaveManager.path):
        DirAccess.remove_absolute(SaveManager.path)
    var g := Game.fresh(1000.0, 42)
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3), Vector2i(2, 4), Vector2i(0, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    # buy an item-shop slot with coins
    var price := int(g.shop.slots[0]["price"])
    g.wallet.add_coins(price + 100)
    assert_true(g.buy_shop_slot(1, 1000.0)["ok"])
    assert_true(g.shop.slots[0]["sold_out"])
    # dev-stub an IAP pack -> gems, then buy a gem daily deal
    g.buy_iap_pack("getgem_1", 1000.0)   # +100 gems
    assert_true(g.buy_daily_deal(1, 1000.0)["ok"])   # 25 gems
    # save/load preserves it
    SaveManager.save(g)
    var g2 := SaveManager.load_game()
    assert_not_null(g2)
    assert_true(g2.shop.slots[0]["sold_out"])
```

- [ ] **Step 2: Run test to verify it fails (or passes on sim path)**

Run: `./curio-hall/test.sh` — Expected: the sim path may already pass after Task 5; still complete the view wiring below. If a `SaveManager.path` override is needed, mirror `before_each`/`after_each` from `test_shop_game.gd`.

- [ ] **Step 3: Implement the ShopPanel**

`curio-hall/view/shop_panel.gd`:

```gdscript
class_name ShopPanel
extends CanvasLayer
## Modal shop overlay: item shop, daily deals, dev-stub IAP. Placeholder styling.

signal action_rejected(reason: String)

var game: Game
var _root: PanelContainer
var _list: VBoxContainer

func setup(g: Game) -> void:
    game = g
    layer = 10
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
    game.shop.shop_changed.connect(refresh)
    game.deals.deals_changed.connect(refresh)
    game.wallet.changed.connect(refresh)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(refresh)
    add_child(t)   # NOTE: child of the CanvasLayer, not of _list; refresh only rebuilds _list

func open() -> void:
    visible = true
    refresh()

func close() -> void:
    visible = false

func _label(text: String) -> void:
    var l := Label.new()
    l.text = text
    _list.add_child(l)

func _buy_button(text: String, disabled: bool, cb: Callable) -> void:
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
    var now := Time.get_unix_time_from_system()
    _label("SHOP   Coins: %d   Gems: %d" % [game.wallet.coins, game.wallet.gems])
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.pressed.connect(close)
    _list.add_child(close_b)
    # Item shop
    _label("-- Item Shop --")
    if game.shop.is_refreshing(now):
        _buy_button("Refresh in %ds — Skip (%d gems)" % [int(game.shop.time_to_refresh(now)), int(ConfigDB.tuning["shop_skip_gems"])],
            false, func(): _do(game.skip_shop_refresh(now)))
    for i in range(ItemShop.SLOTS):
        var slot: Variant = game.shop.slots[i]
        if slot == null:
            continue
        var n := i + 1
        if slot["sold_out"]:
            _label("  Slot %d: SOLD OUT" % n)
        else:
            _buy_button("  Buy %s x%d — %d coins" % [slot["item"], int(slot["count"]), int(slot["price"])],
                game.wallet.coins < int(slot["price"]),
                func(): _do(game.buy_shop_slot(n, Time.get_unix_time_from_system())))
    # Daily deals
    _label("-- Daily Deals --")
    for deal in game.deals.deals():
        var id := int(deal["id"])
        var tag := "  (watch ad, dev free) " if deal["is_ad"] else "  "
        if int(deal["stock"]) <= 0:
            _label("%s%s: out of stock" % [tag, deal["item"]])
        else:
            _buy_button("%sBuy %s — %d gems (stock %d)" % [tag, deal["item"], int(deal["cost_gems"]), int(deal["stock"])],
                game.wallet.gems < int(deal["cost_gems"]),
                func(): _do(game.buy_daily_deal(id, Time.get_unix_time_from_system())))
    # IAP (dev stub)
    _label("-- Get Gems (DEV STUB) --")
    for pack in game.iap.packs():
        var pid := String(pack["purchase_id"])
        _buy_button("  [DEV] %s -> %s" % [pid, ", ".join(pack["goods"])],
            false, func(): _do(game.buy_iap_pack(pid, Time.get_unix_time_from_system())))
    game.iap.note_seen(now)
    var bs := game.iap.bundle_state(game, now)
    if bs["available"]:
        _buy_button("  [DEV] Starter Bundle -> %s" % ", ".join(bs["goods"]),
            false, func(): _do(game.buy_bundle(Time.get_unix_time_from_system())))
    else:
        _label("  Starter Bundle: %s" % bs["reason"])

func _do(res: Dictionary) -> void:
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()
```

- [ ] **Step 4: Wire the Shop button and tick into the main scene**

In `curio-hall/scenes/main.tscn`, add a `ShopButton` (a `Button` under the `UI` CanvasLayer, positioned near the HUD) and a `ShopPanel` node (type `CanvasLayer`, script `res://view/shop_panel.gd`). Add ExtResource for `res://view/shop_panel.gd`.

In `curio-hall/scenes/main.gd`:
- Add `@onready var shop_panel: ShopPanel = $ShopPanel` and `@onready var shop_button: Button = $UI/ShopButton`.
- In `_ready`, after the other `setup` calls: `shop_panel.setup(game)`, `shop_button.pressed.connect(shop_panel.open)`, `shop_panel.action_rejected.connect(_show_toast)`.
- In `_flush_save` (the existing 1s timer callback), add as its first line: `game.tick_shop(Time.get_unix_time_from_system())` (alongside the existing `game.tick_orders(...)`).
- Add to `REJECT_MESSAGES`: `"not_enough_coins": "Not enough coins", "sold_out": "Sold out", "out_of_stock": "Out of stock", "locked": "Unlocks at level 3", "already_bought": "Already purchased", "expired": "Offer expired", "unknown": "Unavailable", "empty": "Nothing here"`.

- [ ] **Step 5: Run tests + boot the game**

Run: `./curio-hall/test.sh` — Expected: all suites PASS, warning-free.
Then boot to confirm no script errors and the shop opens:
`godot --path curio-hall` (or headless: `godot --headless --path curio-hall --quit-after 180` and confirm error-free log). Manual playtest: earn coins, tap the Shop button, buy an item-shop slot (goes SOLD OUT), dev-stub a gem pack, buy a daily deal, close the shop.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/view/shop_panel.gd curio-hall/scenes/main.gd curio-hall/scenes/main.tscn curio-hall/test/unit/test_smoke.gd
git commit -m "feat: shop overlay with item shop, daily deals, dev-stub IAP - phase 3 playable"
```

---

## Self-review notes (already applied)

- Spec coverage: §1 ItemShop (T2), DailyDeals (T3), Iap (T4); §2 ShopPanel (T6); §3 tick_shop + save v3 (T5), config load (T1); §4 testing distributed, atomic spends via EnergyWallet throughout; §5 milestones map to T1-T6. Tuning constants (T1).
- Deliberate readings recorded as Global Constraints: shop-chain via CustomChain-or-natural-chain; three tuning defaults; v2 saves reset on upgrade to v3; the named 1s tick host; ad flag surfaced but sim still charges the deal's gem cost.
- Type consistency: `Game` gains `shop`/`deals`/`iap` incrementally (T2/T3/T4 each add their field + `fresh` init line; T5 consolidates to one `fresh` block that also fills the shop, and adds tick/buy/save). Buy methods everywhere return `{ok, reason}`. `ItemShop.SLOTS`=6, `refresh_at: float`; `DailyDeals.stock` keyed by int id; `Iap.bundle_bought`/`bundle_first_seen` are the only Iap save state. Every reject reason string used in a view toast is registered in `REJECT_MESSAGES` (T6).
- Known follow-ups (roadmap, not this plan): real payment/ad SDKs; event shop variants; `EnergyBoostItemConfig` (ships empty).
```
