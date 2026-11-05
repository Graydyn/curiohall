# Curio Hall — Phase 2 Design: Orders + Economy

**Date:** 2026-09-02
**Status:** Approved design, awaiting spec review
**Depends on:** Phase 1 (`docs/superpowers/plans/2026-09-02-curio-hall-phase1.md`, merged), `HANDOFF.md`, `docs/creative-direction.md`
**Roadmap:** `docs/curio-hall-roadmap.md`

## Goal

Turn phase 1's stubbed order loop into the real, config-faithful economy: a timed
order board with gem-skip, level-up reward chests that dispense collectible currency
tokens, and tap-to-collect crediting coins/gems/energy. From a fresh install a player
can play until a level-up drops a chest, tap the chest to dispense currency tokens,
merge and collect them for gems, and spend those gems to skip an order refresh or
unlock an inventory slot — all numbers from the config, all placeholder art,
surviving quit/resume.

## How it works

- **Random orders pay coins only:** the reward for delivery is the sum of each
  delivered item's `OrderItem.Price`. XP is inferred from `OrderItem.DiffScore` (the
  config has no explicit order-XP field; DiffScore scales with tier like an XP
  value, and phase 1 already uses it). No chests or gems on random orders.
- **Gems and energy enter through chests, not orders.** `LevelConfig.rewards` grants
  chest items (`main_e_chest_new_1`, `main_g_chest_new_1`, `main_t_chest_new_1`, ...).
- **Chests are board items that dispense their contents on tap** — generators with
  `Spread_CostEnergy: 0` and a finite budget (`Spread_ItemMaxNumber`), no recharge,
  sometimes a timed open (`Spread_OpenDuration` + `Spread_OpenSpeedUpCost` gem-skip).
  They dispense **currency-token items** from collectible chains: chain 24 → coins,
  25 → gems, 26 → energy.
- **Currency tokens are mergeable collectibles.** Each carries
  `CollectRewards: ["gold-2"]` / `["gem-3"]` / `["energy-6"]` (the config calls coins
  "gold"). They also have `MergedType`, so two small tokens merge into a bigger one
  worth more. **Tapping a token collects it**: its `CollectRewards` credit the wallet
  and the item is removed.
- **Chest vs generator predicate** (verified across all 157 `Spread_Weight` items):
  a **chest** has `Spread_CostEnergy == 0 AND Spread_ItemRecoveryDuration == 0`
  (finite, free, no recharge); a **generator** recharges (`Spread_ItemRecoveryDuration
  > 0`). All 27 chest-named items satisfy the chest predicate; none recharge.

## Scope

**In:** timed order refresh + gem-skip for all 8 order types; the `Rewards` grant
helper; collect-on-tap for `CollectRewards` items; `ChestState` + chest tap-to-dispense;
the level-up reward pipeline honoring `main_*_chest` grants; view/HUD wiring; save
extension; smoke test.

**Out (deferred to later phases — see roadmap):** Shop/IAP (gem packs, daily deals,
energy boosters), special/branch/fixed orders (event- and character-driven, carry their
own `Rewards`), the meta-layer (MainTask campaign, AreaUnlock, Skin decoration,
characters/intimacy), and live-ops events. No new screens in this slice.

## 1. Currency & the reward grammar

New `sim/rewards.gd` (static helpers):

- `Rewards.parse(token: String) -> Dictionary` → `{kind, id, amount}`. Grammar:
  `"gold-N"` → coins, `"gem-N"` → gems, `"energy-N"` → energy, otherwise a bare item
  id + count (`"104-1"`, `"main_g_chest_new_1-1"`) → `{kind: "item", id, amount}`.
  Reuses the `rsplit("-", true, 1)` convention already in `Weighted.parse`.
- `Rewards.grant(token: String, game, now: float) -> void` routes one token:
  `gold` → `game.wallet.add_coins`, `gem` → `add_gems`, `energy` →
  `add_energy(n, now)`, `item` → spawn `amount` copies near board center, falling back
  to `game.player.store(id)` when the board is full.

This is the single sink for every reward source: `CollectRewards`, `LevelConfig.rewards`,
and (later) order/event rewards. It replaces phase 1's ad-hoc reward handling in
`PlayerState.add_xp` and `Game.deliver_order`.

## 2. Sim changes

### 2a. ChestState (`sim/chest_state.gd`, new RefCounted)

Parallel to `GeneratorState`. `ConfigDB.is_chest(type) -> bool` implements the predicate
above and both sim and view use it. `ItemInstance.make` attaches a `ChestState` when
`is_chest(type)` (and a `GeneratorState` only when the type has `Spread_Weight` and is
NOT a chest — this refines phase 1's generator test).

- `ChestState.for_type(type, now)` → budget = `Spread_ItemMaxNumber`, `open_ts = now`.
- `remaining() -> int`, `is_spent() -> bool`.
- `can_open(now) -> bool`: budget remains AND the timed open has elapsed
  (`Spread_OpenDuration`, 0 = instant).
- `open(now) -> String`: rolls one item from `Spread_Weight` (seeded RNG via `Game`),
  decrements budget, restarts the open timer; returns "" if not openable.
- `seconds_to_open(now)`, `skip_open(wallet, now)` (spends `Spread_OpenSpeedUpCost`
  gems where present).
- `to_dict`/`from_dict` (budget + open_ts) for saves.

A spent chest (budget 0) is removed from the board by `Game` after the last dispense.

### 2b. Collect-on-tap

`Game.tap(pos, now)` becomes the single board-tap entry point, routing in order:
chest (`is_chest`) → dispense; generator → spawn (existing `tap_generator` logic);
collectible (`CollectRewards` present) → collect; else → no-op (selection stays a
view concern). Collect: run each `CollectRewards` token through `Rewards.grant`, then
remove the item. Returns a result dict `{ok, kind, reason, spawned/collected}` so the
view can show feedback and reason toasts (reusing phase 1's toast).

### 2c. Order board rework (`sim/order_book.gd`)

Each slot becomes `{order, refresh_at}` (null order + `refresh_at` timestamp = cooling
down; null both = never-filled). On delivery, the slot's order type's `RefreshTime`
sets `refresh_at = now + RefreshTime`. API:

- `fill(player_level, rng, now)`: fills any slot whose `refresh_at` has elapsed (or is
  unset) with a new order; order type chosen by weight across all 8 types eligible at
  the player's level; item tiers capped by the type's `Filters` for that level.
- `time_to_refresh(slot, now) -> float` and `is_cooling(slot, now) -> bool` for the UI.
- `skip_refresh(slot, wallet, now) -> bool`: spends
  `tuning.order_skip_gems` (new tuning constant; random orders have no per-order skip
  cost in config) and clears the cooldown so the next `fill` refills the slot.
- `deliver`/`can_deliver` unchanged except delivery now records `refresh_at`.

Rewards on delivery stay coins (`Price`) + XP (`DiffScore`) via `Rewards.grant` /
`player.add_xp`.

### 2d. Reward pipeline

`PlayerState.add_xp(n)` stops parsing rewards; it returns an `Array[int]` of the level
numbers gained by this call (empty if none; more than one if a large XP grant crosses
several levels). `Game` handles level-up: for each gained level `L`, run every token in
`LevelConfig.levels[L-1].rewards` through `Rewards.grant`. This is where `main_*_chest`
grants (skipped in phase 1) finally land on the board. `Game.deliver_order` and the
smoke path update to the new pipeline.

## 3. View & HUD

- **Order bar:** a cooling slot shows a countdown (`time_to_refresh`) plus a
  "skip (N gems)" button calling `skip_refresh`; the HUD's existing 1 s `_process`
  tick refreshes the display, sim stays source of truth.
- **`ItemView` (through the single `apply()` seam):** currency tokens (chains 24/25/26)
  get a coin/gem/energy tint and a "tap to collect" affordance; chests draw as a
  closed-box placeholder with a remaining-budget pip and, when timed, a countdown.
- **Collect feedback:** a brief floating "+N gems" label on collect; a spent chest
  husk fades and is removed. Coins/gems/energy HUD counters already exist and now move.
- No new screens.

## 4. Persistence & error handling

- Save extends to chest budgets/open timestamps and order `refresh_at` timestamps;
  both accrue offline exactly like generator/energy timers (reconciled against `now` on
  load). `save_version` bumps to 2 with a trivial migration (a v1 save has no chest/
  order-cooldown fields → treat as fresh cooldowns, no chests in flight).
- Illegal taps (spent chest, chest still on its open timer, empty collect) return reason
  codes surfaced through the existing toast; never crash.
- All reward tokens run through `Rewards.parse`; an unknown kind is logged via
  `push_warning` and skipped rather than crashing (defensive, mirrors phase 1's
  reward-skip for non-item level tokens).

## 5. Testing (GUT, sim-layer TDD)

- `Rewards.parse`/`grant`: each kind credits the right wallet field; `gold`→coins;
  item tokens spawn then fall back to inventory when the board is full; unknown kind
  skipped.
- `ChestState`: dispenses up to budget then `is_spent`; timed-open gating +
  `skip_open`; deterministic drops under seeded RNG; round-trip.
- Collect-on-tap: tapping a `CollectRewards` item credits the wallet and removes it; a
  merged higher token collects the higher value.
- `OrderBook` timed refresh: delivered slot enters cooldown, refreshes after
  `RefreshTime`, `skip_refresh` spends gems and refills; all-8-type selection respects
  level `Filters`.
- Save round-trip: chest budgets, order cooldown timestamps, offline refresh all
  survive; v1→v2 migration loads without crashing.
- Smoke test extending phase 1's: level-up grants a chest → tap dispenses a gem token →
  collect → gems increase → skip an order refresh with those gems.

## 6. Milestones

1. `Rewards` helper + collect-on-tap.
2. `ChestState` + chest tap-to-dispense + `is_chest` refinement of generator attach.
3. Level-up reward pipeline routes chests/items/currency through `grant()`.
4. Order board timed refresh + gem-skip.
5. View/HUD wiring + save v2 extension + smoke test.

**Definition of done:** the Goal paragraph, verified by playing a fresh install through
one full economy loop

## New tuning constants (`config/curio_hall_tuning.json`)

- `order_skip_gems`: gem cost to skip a random-order refresh. Default **30** (random
  orders carry no per-order skip cost in the config; this is a genre-standard placeholder
  value, tunable without code).
