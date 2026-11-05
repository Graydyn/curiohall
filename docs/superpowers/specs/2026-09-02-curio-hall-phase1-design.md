# Curio Hall — Phase 1 Design: Core Merge Board

**Date:** 2026-09-02
**Status:** Approved design, awaiting spec review
**Depends on:** `HANDOFF.md` , `docs/creative-direction.md` (theme/name/style)

## Goal

A playable core merge game in Godot 4 with placeholder art. From a fresh install a player can: tap generators to
spawn items (spending energy), merge items up real chains, deliver randomly generated
orders for coins/XP, level up, run out of energy and watch it regenerate, store items
in inventory, and resume after quitting. 

## Decisions already made

| Decision | Choice |
|---|---|
| Engine / language | Godot 4, GDScript |
| Scope | Full phase-1 config (all 543 items, 40 chains), not a vertical slice |
| Art | Placeholders only (colored shapes + tier badges) behind a single view seam |
| Goal loop | Minimal order loop included (stripped OrderRandom/OrderItem) |
| Architecture | Approach A: pure simulation core + thin scene layer |
| Orientation | Portrait, 720×1280 base resolution |
| Board | 7 wide × 9 tall (from `BoardModelConfig`, which is also the starting layout) |

## Out of scope for phase 1

Story/tasks, map/decoration, characters, shop/IAP, live-ops events, sound, real art,
localization. These are phases 2–4 per `HANDOFF.md` §7.

## 1. Project layout & config pipeline

New Godot 4 project at `curio-hall/` in this repo

```
curio-hall/
  project.godot
  config/            # phase 1 design tables
  sim/               # pure logic, RefCounted classes, no Nodes
  scenes/            # Godot scenes: board view, HUD, order bar
  view/              # scripts for scenes, placeholder item rendering
  test/              # GUT unit tests for sim/
```

**Config tables copied into `config/` unmodified:** `ItemModelConfig`,
`ItemPropertyConfig`, `MergeItemScoreConfig`, `LuckyProduceConfig`,
`InventorySlotConfig`, `BoardModelConfig`, `SystemConfig`, `LevelConfig`,
`OrderRandomConfig`, `OrderItemConfig`, and the energy-related tables
(`EnergyBoostItemConfig`).

**`ConfigDB` (autoload):** parses all tables at startup into typed lookups (e.g.
`items_by_type[101]`). Validates on load: every `MergedType` resolves to an existing
item, every generator `Spread_Weight` target exists, `BoardModelConfig` cell ids
resolve. Validation failure is fatal at startup in dev builds with a message naming
the table and row.


## 2. Simulation core (`sim/`)

Plain `RefCounted` classes, no Nodes, no rendering. Time enters only as an injected
`now` timestamp (never read from the OS inside the sim), so tests can fast-forward
and offline recharge falls out naturally. All randomness goes through an injected,
seedable RNG.

- **`Board`** — the 7×9 grid. Cells hold an `ItemInstance` or null, plus cell state
  (open; covered `c#`; bubble-boxed `pb#` — per the `BoardModelConfig` encoding).
  API: `can_merge(a, b)`, `merge(a, b)`, `move(from, to)`, `sell(pos)`,
  `spawn(item_type, near)` with spiral-outward free-cell search.
- **`ItemInstance`** — `{type, created_at, generator state if generator}`. Behavior
  comes from `ConfigDB`; instances stay tiny.
- **`GeneratorState`** — per-generator charge/storage counters and recharge
  timestamps, driven by the `Spread_*` fields: energy cost per tap, weighted drop
  roll, live cap (`Spread_ItemMaxNumber`), stored-charge cap
  (`Spread_StorageMaxNumber`), recovery durations, gem skip cost.
- **`EnergyWallet`** — energy with timed regen, plus coins and gems. Single source of
  truth for spending; check-and-deduct is atomic.
   `SystemConfig` holds only 4 unrelated constants).
  Decision: use genre-standard defaults — cap 100, +1 energy per 2 minutes — defined
  in a new `config/curio_hall_tuning.json` so they are tunable without code changes.
- **`LuckyRoller`** — `LuckyProduceConfig`: on generator taps, rolls bonus drops by
  player-level bracket (`level_min`/`level_max`, `lucky_chance`, `lucky_items`,
  `super_items`).
- **`OrderBook`** — minimal orders: fills 2–3 slots using `OrderRandom` weights and
  the `OrderItem` pool filtered by player level; checks deliverability against board
  + inventory; pays coins/XP; refreshes per `RefreshTime`.
- **`PlayerState`** — level/XP against `LevelConfig`; inventory (5→32 slots per
  `InventorySlotConfig` with gem unlock costs); owns all of the above;
  `to_dict()`/`from_dict()` for saves.

**Event rule:** the sim emits Godot signals (`item_spawned`, `merged`,
`order_completed`, `energy_changed`, …). The view only listens; it never reaches
into sim internals.

**Invariants:** illegal merges/moves are rejected with a reason code, never crash.
Chain tops (empty `MergedType`) cannot merge. Sell-protection honors `ProtectLevel`.

## 3. View layer & interaction (`scenes/`, `view/`)

One main scene, portrait 720×1280:

- **`BoardView`** — draws the grid; occupied cells get an `ItemView`. Input: tap a
  generator to spawn; drag an item onto a matching item to merge; drop on an empty
  cell to move; tap bubble/covered cells to open. Drag feedback: lifted sprite,
  highlighted valid merge targets, snap-back on invalid drop.
- **`ItemView` (placeholders)** — rounded rect colored by chain id (40 distinct
  hues), shade darkening by tier, tier number badge, short label from item id.
  Generators get a distinct border and a charge pip. All rendering goes through one
  function, `ItemView.apply(item_type)` — the single seam where real art replaces
  placeholders later.
- **`HUD`** — energy bar with regen countdown, coin/gem counters, level/XP bar.
- **`OrderBar`** — 2–3 order slots: requested items with have/need counts; deliver
  button lights when fulfillable.
- **`InventoryPanel`** — slide-up item store (move items off-board), slot count and
  next-slot unlock cost.

Timers tick in `_process` for display only; the sim recomputes from timestamps
whenever touched, so display can never drift from truth.

## 4. Persistence & error handling

- **Saves:** `PlayerState.to_dict()` as JSON to `user://save.json` on every
  meaningful action (merge, delivery, purchase), debounced to ≤1 write/second, plus
  on app pause/quit.
- **Offline accrual:** on load, timestamps reconcile against current time; energy
  and generator charges accrue offline, capped at stored maxima.
- **Versioning:** `save_version` field from day one; mismatch runs a migration hook
  (trivial for now) rather than crashing.
- **Corrupt save:** back up to `save.corrupt.json`, start fresh, log it. Never
  silently overwrite.
- **Config errors:** fatal at startup in dev (see §1) — fail loudly at boot rather
  than merge into a missing item at runtime.

## 5. Testing

TDD with **GUT** over the sim layer:

- Merge rules walked against real config (101+101→102 … up to chain tops).
- Generator drop tables with seeded RNG (weight distribution sanity).
- Energy/recharge math across simulated time jumps, including the handoff's worked
  example: generator 104 spawns 201, 1 energy/tap, 80 live / 240 stored, 1 charge
  per 2 s.
- Order generation bounds: level filters, item counts, deliverability.
- Save round-trip: `to_dict` → `from_dict` equality, offline accrual capping.

View layer: manual playtesting plus smoke tests (main scene loads; a scripted
tap-drag-merge sequence works).

## 6. Milestones

Each is a working checkpoint:

1. **Config + sim skeleton** — ConfigDB loads/validates; Board move/merge/sell
   passing GUT tests against real config values.
2. **Generators + energy** — tap-to-spawn with weighted drops, charge/storage
   recharge, energy wallet with regen, lucky drops.
3. **Playable board** — BoardView + placeholders + HUD wired to sim; the
   `BoardModelConfig` starting layout renders with covered/bubble cells; playable
   with mouse/touch.
4. **Orders + progression** — OrderBar, OrderBook, coins/XP/levels, inventory panel
   with slot unlocks.
5. **Persistence** — save/load with offline accrual; quit and resume works.

**Definition of done:** the Goal paragraph at the top of this spec, verified by
playing a fresh install through one full loop
