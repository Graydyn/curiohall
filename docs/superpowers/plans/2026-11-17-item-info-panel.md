# Item Info Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A **?** button opens an info panel for the selected board item (family, tier, generator, effect) with a Sell button for plain items.

**Architecture:** Pure item facts (name, tier, sources, price, description lines) live in a static `ItemInfo` class in `sim/`, fed by a new `ConfigDB.item_images` map. `Game.sell` does the selling. A thin `InfoPanel` CanvasLayer (modelled on `StoragePanel`) renders it; `InventoryPanel` hosts the **?** button.

**Tech Stack:** Godot 4.7 / GDScript, GUT tests (`./test.sh`).

**Spec:** `docs/superpowers/specs/2026-11-17-item-info-panel-design.md`

## Global Constraints
- Sell price in coins = `2^(tier-1)`, for every family; drop odds and generator energy cost ignored.
- Not sellable: consumables (`CollectRewards`), generators (`Spread_Weight`, not chest), chests (`ConfigDB.is_chest`).
- Copy: title `"<Family> - Tier <n>"`; source `"Made by: <Gen>"` or `"Found in chests"`; consumable `"Tap twice to collect: <rewards>"`; chest `"Tap twice to open"`; sell button `"Sell (<n> coins)"`.
- GDScript files use 4-space indentation (except `config_db.gd`/`rewards.gd`, which use tabs: match the file).

## Review Focus
- Item with no `ItemViewConfig` image → family name falls back to the item id, no crash.
- Family dropped by many tiers of one generator chain (`801` from Fishing `705`–`711`) → listed once; several chains → sorted, comma-joined.
- Selected item removed or merged away while the panel is open / button pressed → Sell is a no-op, no crash.
- Selling clears the board selection (the ? button must disable again).
- `exp-N` reward tokens render as "N XP", unknown item tokens as "<family> x<n>".

---

### Task 1: ItemInfo facts

**Files:**
- Modify: `sim/config_db.gd` (add `var item_images: Dictionary = {}`; fill in `load_all` from `ItemViewConfig.json`: `Type` -> `Image[0]`, skip rows without `Image`)
- Create: `sim/item_info.gd`
- Test: `test/unit/test_item_info.gd`

**Interfaces:**
- Produces (all `static` on `class_name ItemInfo`):
  - `family_name(type: String) -> String` — `item_images[type]` with trailing digits stripped and CamelCase split by spaces (`"RawFish01"` -> `"Raw Fish"`); no image → `type`.
  - `tier(type: String) -> int` — 1 + number of `MergedType` steps from the chain root to `type` (build a reverse `MergedType` map once, cache in a static var).
  - `sources(type: String) -> Array[String]` — sorted, deduped family names of items that have `Spread_Weight`, are not `ConfigDB.is_chest`, and whose weight list drops any member of `type`'s chain.
  - `is_sellable(type: String) -> bool`
  - `sell_price(type: String) -> int` — `2^(tier-1)` if sellable else 0.
  - `reward_text(tokens: Array) -> String` — `"gold-2"`→`"2 coins"`, `gem-1`→`"1 gem"`/`"3 gems"`, `energy-N`→`"N energy"`, `exp-N`→`"N XP"`, items → `"<family> x<n>"`; joined with `", "`.
  - `lines(type: String) -> Array[String]` — info lines below the title: source line (generators: `"Produces: <families>"` and `"Costs <n> energy per tap"` instead); consumables add the collect line; chests the open line.

- [ ] **Step 1: Write failing tests** in `test/unit/test_item_info.gd`:
  - `family_name("205") == "Flour"`, `family_name("801") == "Raw Fish"`, `family_name("no_such") == "no_such"`
  - `tier("201") == 1`, `tier("205") == 5`, `tier("104") == 4`
  - `sources("205") == ["Grocery Bag"]`; `sources("801") == ["Fishing"]` (deduped across `705`–`711`), `sources("901") == ["Fishing"]` (`805` is chest-like: no recharge); `sources("2401") == []`
  - `sell_price("205") == 16`, `sell_price("201") == 1`, `sell_price("2501") == 0` (consumable), `sell_price("104") == 0` (generator), `sell_price("main_g_chest_new_1") == 0` (chest), `sell_price("103") == 4` (pre-generator chain item is plain)
  - `reward_text(["gold-2"]) == "2 coins"`, `reward_text(["gem-1"]) == "1 gem"`, `reward_text(["exp-5"]) == "5 XP"`
  - `lines("2401")` contains `"Found in chests"` and `"Tap twice to collect: 2 coins"`; `lines("205")` contains `"Made by: Grocery Bag"`; `lines("104")` contains `"Costs 1 energy per tap"`; `lines("main_g_chest_new_1")` contains `"Tap twice to open"`
- [ ] **Step 2:** `./test.sh` → new tests fail (`ItemInfo` not found).
- [ ] **Step 3:** Implement `ConfigDB.item_images` and `sim/item_info.gd` per Interfaces.
- [ ] **Step 4:** `./test.sh` → all pass.
- [ ] **Step 5:** Commit `feat: ItemInfo item facts and sell price`.

### Task 2: Selling

**Files:**
- Modify: `sim/merge_board.gd:111-119` (`sell` uses `ItemInfo.sell_price`, reason `"unsellable"` when 0)
- Modify: `sim/game.gd` (add `sell`)
- Modify: `test/unit/test_merge_board.gd:48-54`
- Test: `test/unit/test_sell.gd`

**Interfaces:**
- Consumes: `ItemInfo.sell_price`
- Produces: `Game.sell(pos: Vector2i) -> Dictionary` — `{"ok", "coins", "reason"}` from `board.sell`; on ok, `wallet.add_coins(coins)`.

- [ ] **Step 1:** Update `test_sell_uses_selling_price_and_rejects_zero` → rename `test_sell_price_doubles_per_tier_and_rejects_specials`: `"103"` sells for 4; `"2501"` → not ok, reason `"unsellable"`. Add `test/unit/test_sell.gd`: on `Game.fresh(1000.0, 42)` with `"205"` placed on an opened cell, `g.sell(pos)` → ok, coins 16, wallet coins +16, cell empty; selling an empty cell → not ok, coins unchanged.
- [ ] **Step 2:** `./test.sh` → those fail.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `./test.sh` → all pass.
- [ ] **Step 5:** Commit `feat: sell items for 2^(tier-1) coins`.

### Task 3: ? button and info panel

**Files:**
- Modify: `view/board_view.gd` (add `signal selection_changed(pos: Vector2i)` emitted from `_select`; delete unused `sell_requested`)
- Create: `view/info_panel.gd`
- Modify: `view/inventory_panel.gd` (add `signal info_requested`; `"?"` button after "Store selected", disabled when `board_view.selected == (-1,-1)`, refreshed on `selection_changed`)
- Modify: `scenes/main.gd` (create/setup `InfoPanel` like `storage_panel` at ~line 113; connect `inventory.info_requested` → `info_panel.open(board_view.selected)`, `info_panel.action_rejected` → `_show_toast`, `info_panel.sold` → mark save pending and `board_view._select(Vector2i(-1, -1))` via a public `clear_selection()`)
- Test: `test/unit/test_info_panel.gd`, extend `test/unit/test_inventory_panel.gd`

**Interfaces:**
- Consumes: `ItemInfo.*`, `Game.sell`, `ItemView.art_for(type)`
- Produces:
  - `BoardView.clear_selection() -> void`
  - `class_name InfoPanel extends CanvasLayer`: `signal sold`, `signal action_rejected(reason: String)`, `setup(g: Game)`, `open(pos: Vector2i)`, `close()`, internals `_title: Label`, `_sell_btn: Button`. Layer 10, hidden by default. Shows art, title, `ItemInfo.lines`, Sell button (hidden when `sell_price == 0`), Close. Sell re-checks the item still at `pos` is the type it opened with; otherwise closes silently.

- [ ] **Step 1:** Tests:
  - `test_info_panel.gd`: open on a `"205"` cell → `_title.text == "Flour - Tier 5"`, `_sell_btn.visible`, `_sell_btn.text == "Sell (16 coins)"`; pressing sell → item gone, coins +16, `sold` emitted, panel hidden. Open on `"2501"` → `_sell_btn.visible == false`. Open, then `g.board.remove(pos)`, press sell → no crash, `sold` not emitted.
  - `test_inventory_panel.gd`: `_info_btn.disabled` with nothing selected; after `bv._select(pos)` it is enabled; after `bv.clear_selection()` disabled again.
- [ ] **Step 2:** `./test.sh` → fail.
- [ ] **Step 3:** Implement. Keep the inventory panel's height check (`test_panel_fits_below_board_on_screen`) passing — the ? button goes in the existing header row.
- [ ] **Step 4:** `./test.sh` → all pass. Then launch the game via the run skill, select an item, press ?, check the panel and Sell.
- [ ] **Step 5:** Commit `feat: item info panel with sell button`.
