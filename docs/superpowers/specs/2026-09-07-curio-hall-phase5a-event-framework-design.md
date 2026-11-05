# Curio Hall — Phase 5a Design: Event framework + Pureboard expedition

**Date:** 2026-09-07
**Status:** Approved design, awaiting spec review
**Depends on:** Phases 1-4b3 (merged), `HANDOFF.md`, `docs/creative-direction.md`
**Roadmap:** `docs/curio-hall-roadmap.md` (phase 5 sequences one event archetype per
sub-phase; this is the framework plus the first archetype)

## Goal

The Society mounts its first expedition: a live-ops event framework (auto-rotating
schedule with dev controls, a second merge board, main-loop coupling, progress and
expiry) proven end to end on the Pureboard archetype. While an event runs, delivering
main-board orders feeds expedition items onto a sealed 13×7 event board; the player
merges them up the event chain, popping event paperboxes for their per-cell extras,
and climbs a milestone track to completion before the clock runs out. Survives
quit/resume mid-event; save v9. Numbers come from the `Pureboard*_dogpark`
config;

## How it works (verified from config)

- **Activity framework** (`ActivityManager`, `*ActivityDefinition`): one model per
  activity definition with `ActivityState` (Started/Ended), server-heartbeat
  scheduling, per-activity DB tables, a scene-HUD entry button, and
  ready/main/complete/end windows. We have no server: scheduling is ours (see Design).
- **Pureboard** (`PureBoardActivityModel` 4 config tables): the event board
  (`PureboardBoardModelConfig_dogpark`, 13 rows × 7 cols, every cell `pb#c#<event
  item>`) starts fully sealed. Finishing MAIN-board orders adds event items
  (`AddOrderFinishItem` / `GetGenerateItemByOrder` — bytecode logic; our stand-in
  below). Items merge up event chains (`PureboardItemModelConfig_dogpark`, 35 items,
  prefix `pb_dogpark_`); progress is the highest merge level reached
  (`CurrentMergeLevel`, `GetLevelRewards`, `GetNextRewardLevel`, a LevelProgress UI)
  with a complete window at the top. Unboxing pays the per-cell extra from
  `PureboardBoardPaperRewardConfig_dogpark` (a 13×7 grid, same mechanism as
  `MainPaperboxExtraRewardConfig`). `PureboardBoardScrollConfig_dogpark` is
  `{level: 12, scrollRows: 3}` — read as the player-level unlock gate and the visible
  scroll window (we render a full scroll view instead; recorded interpretation).
- The end/level rewards live in prefabs/bytecode, not config tables — 
  tuning placeholders (recorded deviation).

## Scope

**In:** the `Events` sim (auto-rotating lifecycle + dev start/end, expiry tick), the
event board (second `MergeBoard` from Pureboard config with shock/unbox/veil rules and
per-cell paper extras), order-delivery feeding, tier progress + completion, the
`BoardView` parameterization, the `EventPanel` with Expedition HUD button, save v9.

**Out (deferred):** event points + decoration shop (Pureboard carries no point
config; arrives with an archetype that does), MergeLineReward and the 3-row scrolling
window presentation, event-board orders, all other archetypes (GeneratorBoost,
Farmboard, Dig, ...), real event names/art (variant key as placeholder title), the
  ready/notice/unlock window chrome.

## 1. Sim: `Events` (`sim/events.gd`, RefCounted)

- Enum `State { IDLE, ACTIVE }` (an ended event returns to IDLE after cleanup — no
  claim phase in 5a since end rewards are granted at completion).
- State: `state`, `variant: String` (`"dogpark"`), `ends_at: float`,
  `next_event_at: float`, `board: MergeBoard` (null when IDLE), `best_tier: int`,
  `completed: bool`.
- **Scheduling**: `tick(now, player) -> void` (host: `main.gd`'s 1-second timer via a
  new `Game.tick_events(now)` — the sixth time-driven system, named here):
  - IDLE and `now >= next_event_at` and `player.level >=` the scroll config's
    `level` (12): `start_event(now)` — builds the board from
    `ConfigDB.event_board_layout(variant)` via `BoardLayout.apply`, sets
    `ends_at = now + tuning.event_duration_seconds` (**604800**, 7 days), emits
    `event_changed`.
  - ACTIVE and `now >= ends_at`: `end_event(now)` — discards the board (live-ops
    semantics), sets `next_event_at = now + tuning.event_gap_seconds` (**172800**,
    2 days), emits `event_changed`.
  - First-run: `next_event_at` 0.0 means "start as soon as the gate passes".
- **Dev controls**: `Game.dev_start_event(now)` / `Game.dev_end_event(now)` call the
  same start/end paths regardless of timers AND bypass the level gate (the gate lives
  only in the scheduler tick) — otherwise the dev button could not serve its stated
  purpose of skipping the level-12 grind during verification.
- **Feeding**: `on_order_delivered(game, now)` — when ACTIVE, spawn one
  `tuning.event_feed_item` (**"pb_dogpark_tar_1"**) onto the EVENT board's **supply
  row**: the board is built one row taller than the config layout, with the extra
  bottom row open and empty (our stand-in for the   cache queue — fed items
  land there, and the normal merge-onto-veiled rules bootstrap the sealed board, the
  same pattern as the main tutorial). If the supply row is full the item is lost with
  a `push_warning` (event items are throwaway). . Called from `Game.deliver_order`.
  Requires `MergeBoard` to support per-instance dimensions (width/height instance
  vars defaulting to the main-board constants, persisted in its dict).
- **Merging on the event board** goes through a new `Game.merge_event(a, b, now)`
  mirroring `Game.merge`: same `MergeBoard.merge` rules (veiled targets legal, shocks
  unbox), but unbox extras come from
  `ConfigDB.event_paperbox_reward(variant, pos)` and progress updates:
  `best_tier = max(best_tier, tier_of(new_type))` (tier = trailing `_N` of the event
  item id). When `new_type` is the top of the tar chain (`MergedType` absent),
  `completed = true` and `Rewards.grant_all(tuning.event_end_rewards, game, now)`
  (default **["gem-30", "energy-100"]**, placeholder — recorded deviation), emit
  `event_changed`.
- `to_dict/from_dict`: full state including the board (via `MergeBoard.to_dict`,
  null-safe) and timers; offline expiry reconciles naturally on the first tick.

## 2. ConfigDB: event config bundles

- New loader: `_load_event_variant("Pureboard", "dogpark")` reads the four tables and
  stores `event_boards: Dictionary` (`variant -> layout Array`),
  `event_paper_rewards: Dictionary` (`variant -> grid`), `event_scroll: Dictionary`
  (`variant -> row`), and merges `PureboardItemModelConfig_dogpark` rows into
  `ConfigDB.items` (ids are `pb_dogpark_`-prefixed — collision-free; at load time a
  colliding event item id is skipped with a `push_error`, not merged over the
  existing entry, and `validate()` separately checks event layout cells and
  `MergedType` chains like the main board's).
- Helpers: `event_board_layout(variant) -> Array`,
  `event_paperbox_reward(variant, pos) -> String` (mirrors `paperbox_reward`),
  `event_unlock_level(variant) -> int` (scroll config `level`).

## 3. View

- **`BoardView` parameterization**: `setup(game)` becomes
  `setup(game, board: MergeBoard = null, merge_cb: Callable = Callable(), tap_cb:
  Callable = Callable())` with dimensions read from the board's own width/height
  (defaults preserve the main scene's existing call) — the main scene keeps the main
  board and `game.merge`/`game.tap`; the
  event panel passes the event board and `game.merge_event` (taps on the event board
  are no-ops in 5a: no event generators/chests exist in the dogpark config). All
  hardcoded `MergeBoard.WIDTH/HEIGHT` and `game.board` references inside BoardView
  route through the parameters. The main scene's behavior is unchanged (regression
  guard: the whole existing suite + boot).
- **`EventPanel`** (`view/event_panel.gd`, CanvasLayer modal): visible-while-active
  **Expedition button** on the HUD ("The Society Presents: dogpark" placeholder
  title); the panel hosts a scaled board holder (0.55) fitting the viewport for the
  event `BoardView`, a countdown
  ("ends in Xh Ym", 1s Timer parented on the CanvasLayer), the progress line
  ("Best find: tier N of M" + "Expedition complete!" once done), and the two
  clearly-labeled **DEV** buttons (Start event / End event). Failures route to the
  existing toast.
- `main.gd`: Expedition button visibility follows `event_changed`; save-pending on
  `event_changed`; `tick_events` joins the 1-second flush.

## 4. Persistence

**Save v8 → v9**: adds the `events` block. Reset on mismatch per convention.

## 5. Error handling & testing

- Start is level-gated and idempotent (starting while ACTIVE is a no-op); feeding and
  event merges reject cleanly when IDLE (`no_event` reason); the event board's grants
  route through `Rewards` into the main wallet/inventory.
- **Testing** (GUT, sim TDD; watch suite totals):
  - Lifecycle: no start below level 12; auto-start when gated+due; expiry discards
    the board and schedules the next; dev start/end paths; offline expiry on load
    (save mid-event, advance now past `ends_at`, first tick ends it).
  - Feeding: order delivery while ACTIVE spawns the feed item on the EVENT board
    (main board untouched); while IDLE grants nothing.
  - Event board rules: merge onto veiled event cells; shock unboxes and pays the
    per-cell grid extra to the main wallet; `merge_event` rejects when IDLE.
  - Progress: `best_tier` rises monotonically; completing the tar chain top sets
    `completed`, grants `event_end_rewards` once (idempotent).
  - Config: event items merged into `ConfigDB.items` without collisions; chain
    integrity validated; layout cells resolve.
  - BoardView refactor: existing suite + headless boot green (behavioral regression
    guard for the main board).
  - Save v9 roundtrip mid-event (board cells, timers, progress).
- Headless boot + full suite; `--import` after new class_name scripts.

## 6. Milestones

1. ConfigDB event bundle loading + validation (+ config copies).
2. `Events` sim: lifecycle, scheduling, dev controls, save v9.
3. Feeding + `merge_event` + progress/completion.
4. `BoardView` parameterization (regression-guarded), `EventPanel` + Expedition
   button + smoke test; roadmap update.

**Definition of done:** the Goal paragraph on a fresh install (with the dev Start
button to skip the level-12 grind during verification), every number traceable to the
config or a recorded tuning placeholder.

## New tuning constants (`config/curio_hall_tuning.json`)

- `event_duration_seconds`: **604800** (7 days — genre cadence; 
- `event_gap_seconds`: **172800** (2 days between events).
- `event_feed_item`: **"pb_dogpark_tar_1"** 
- `event_end_rewards`: **["gem-30", "energy-100"]** 
