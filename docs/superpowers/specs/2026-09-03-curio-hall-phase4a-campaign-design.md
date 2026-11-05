# Curio Hall — Phase 4a Design: MainTask campaign + map

**Date:** 2026-09-03
**Status:** Approved design (task-currency correction applied post-approval, see below), awaiting implementation
**Depends on:** Phases 1-3 (merged), `HANDOFF.md`, `docs/creative-direction.md`
**Roadmap:** `docs/curio-hall-roadmap.md` (phase 4 splits into 4a/4b/4c; this is 4a)

## Goal

Turn the merge loop into a game with a destination: the coins earned from orders now pay
for the restoration tasks of the `MainTask` campaign (4,107 tasks across 282 story days
spanning the 47 Hall wings), presented on a pannable 2D floor-plan map of Curio Hall.
From a fresh install a player can earn coins from orders, open the map, see the Front
Gates' tasks as pins, pay coins to complete them (collecting their XP/item rewards),
watch the day advance and wings restore, and have all of it survive quit/resume. Every
number comes from the config.

**Phase 4 decomposition:** 4a (this spec) = MainTask campaign, AreaUnlock, map screen.
4b = characters/intimacy, special/branch/avatar orders, story recap. 4c = `Skin`
decoration. Each gets its own spec-plan cycle.

**Task-currency correction (post-approval):** the design as first approved introduced a
new "task points" currency fed by `OrderRandomConfig.Point`. Deeper config analysis
overturned that: `Point` exists on only ONE order type (Type 1, value 5) across every
config variant — far too scarce to fund day 1's 185-cost task list — `new_task_tip` = "New tasks are available now! **Earn coins to
complete them!**" `Point` belongs to event/battle-pass systems (phase 5). MainTask
`cost` is paid in **coins**, so no new currency, no `PlayerState` change, and no HUD
change; spends go through the existing atomic `EnergyWallet.spend_coins`.

## How it works (verified from config)

- **`MainTaskConfig`** (4,107 rows): each task has `day` (1..282, a story chapter — NOT
  a real-time day), `id` (unique within its day; 7-18 tasks per day), `area` (1..47;
  every day maps to exactly one area, and area is monotonic over days), `cost` (int,
  paid in coins — see the correction above), `rewards` (mostly `exp-15`, sometimes item
  tokens like `2701-1`), `detail_icon` (an original character name), `name` (loc key).
  Only 93 rows carry `edit_pos` (positions lived in scene prefabs), so map pin positions
  must be our own. The `_fire` variant config is an alternate campaign and is ignored.
- **`AreaUnlockConfig`** (1 row): `{id: 3, level: 5, condition: "TaskCompleted-1_9"}` —
  extra gates on entering an area, on top of the implicit day-order progression.
  **Erratum:** task keys are `day_id` (confirmed via `StoryRecapConfig`, whose 309 keys
  all resolve), but task `1_9` does not exist (day 1 has ids 1-7). Enforcing it literally
  would deadlock the campaign at day 8, so a condition referencing an unknown task is
  treated as satisfied (warned at config load); the level gate still applies.
- **`StoryRecapConfig`**, `CharacterIntimacy*`, `OrderSpecial/Branch/Avatar` — phase 4b.
  `SkinConfig` — phase 4c. `OrderRandomConfig.Point` — an event/pass currency, phase 5.

## Scope

**In:** the `Campaign` sim (current day, coin-paid task completion, day advancement,
area gating), `exp` added to the `Rewards` grammar, ConfigDB loading of
`MainTaskConfig` + `AreaUnlockConfig`, the floor-plan `MapPanel` overlay with a
hand-authored 47-wing layout and per-task pins, original→Curio Hall character-name
mapping for task icons, and save v4.

**Out (deferred):** everything 4b/4c (characters, story, skins), the `_fire` alternate
campaign, the `Point` event currency (phase 5), task text (names stay placeholder until
the text-rewrite track), real art, any gem-skip or timer on tasks (the campaign has none
in config).

## 1. Sim: `Rewards` grammar + `Campaign`

### `Rewards` grammar: `exp`
- `"exp-N"` routes to `game.player.add_xp(N)` and grants any level-up rewards through
  a new public `Game.grant_xp(n, now)` (wrapping the existing `_grant_level_rewards`
  path; `deliver_order` refactors onto it). All other tokens unchanged.

### `Campaign` (`sim/campaign.gd`, RefCounted — mirrors OrderBook/ItemShop patterns)
- State: `day: int` (starts 1), `done: Dictionary` (task key `"<day>_<id>"` → true).
- Reads `ConfigDB.main_tasks` and `ConfigDB.area_unlocks`.
- Queries: `tasks_today() -> Array` (current day's rows), `current_area() -> int`,
  `area_state(area, player) -> int` (LOCKED / ACTIVE / RESTORED — derivable by
  comparison because area is monotonic over days), `is_area_unlocked(area, player)
  -> bool`, `wing_progress(area) -> Vector2i` (done/total across that area's tasks),
  `is_task_done(day, id) -> bool`, `is_complete() -> bool` (past day 282).
- `complete_task(id, game, now) -> {ok, reason}`; reasons:
  `"not_today"` (not a current-day task) · `"already_done"` · `"area_locked"` ·
  `"not_enough_coins"` (reuses the existing toast message). On success: spend `cost`
  coins via `EnergyWallet.spend_coins` (atomic check-then-spend), mark done, grant
  `rewards` via `Rewards.grant_all`, and when every task of the day is done advance
  `day` (which may enter a new area).
- Area gating: an area is reachable only in day order (implicit); an `AreaUnlockConfig`
  row for that area additionally requires `level` and its `TaskCompleted-D_I` condition
  (unknown condition tasks treated as satisfied per the erratum). If the next day's area
  is gated and locked, the day still advances but its tasks reject with `"area_locked"`
  until the gate passes (the check runs at complete time, so level-ups re-check
  naturally).
- Signals: `task_completed(day, id)`, `day_advanced(new_day)`, `area_restored(area)`.
- `to_dict/from_dict` (day + done keys). **No timers — first time-free system; no tick
  host needed, and the plan states this explicitly.**

## 2. ConfigDB

- `main_tasks`: `MainTaskConfig.json` parsed once into `{day -> Array[rows]}`, plus a
  flat `main_task_by_key` (`"day_id"` → row) and `area_tasks` (`area` → rows, for
  `wing_progress`); whole-number floats normalized to ints as usual.
- `area_unlocks`: `AreaUnlockConfig.json` as `{area_id -> row}`.
- `validate()` warns (not errors) on an AreaUnlock condition referencing a missing task.

## 3. View: the Hall map

- **`HallLayout`** (`view/hall_layout.gd`): a hand-authored const table, one entry per
  area 1..47 — display name (from `docs/creative-direction.md`) and a `Rect2` region on
  a large scrollable canvas, arranged as the restoration journey (public rooms →
  collections → workshops/gardens → secrets). Pure data, no logic.
- **`MapPanel`** (`view/map_panel.gd`, full-screen overlay like `ShopPanel`, hidden by
  default) opened by a new **Map button**, closed with an X:
  - A `ScrollContainer` canvas drawing each wing as a placeholder panel (ColorRect +
    Label): tinted by `area_state` — dim/locked, teal/active (with `wing_progress`
    "3/7"), warm-brass/restored.
  - The current day's tasks render as **pins** inside their wing's rect, placed
    deterministically (ordered grid within the rect — stable, no RNG). Done tasks show
    checked; pins show their coin cost.
  - Tapping a pin opens a **task card**: wing name, the character's Curio Hall name via
    a const original→new-cast map (cornelia→Cornelia Wren, barnaby→Barnaby Pluck, … per
    creative-direction), cost vs. current coins, and a Complete button.
  - On open, the panel scrolls to the active wing. Listens to `task_completed` /
    `day_advanced` / `wallet.changed` and re-renders; failures route to the existing
    main-scene toast (`REJECT_MESSAGES` gains `not_today`, `already_done`,
    `area_locked`; `not_enough_coins` already exists). No countdown timers on this
    panel (nothing to self-free).
- **HUD**: unchanged — coins are already displayed.

## 4. Persistence

- **Save v4**: `SAVE_VERSION` → 4; adds the `campaign` block. Per convention a
  version/shape mismatch backs up to `save.corrupt.json` and resets — old saves reset
  on upgrade.

## 5. Error handling & testing

- `complete_task` is atomic check-then-spend via `EnergyWallet.spend_coins`: every
  rejection returns a reason with no state change; unknown reward tokens degrade via
  `Rewards`' warning-and-skip; a full board falls back to inventory via the existing
  `Rewards` item path.
- **Testing** (GUT, sim-layer TDD; remember the full starting board — free cells before
  any board-place assertions):
  - `Rewards`: `exp-N` adds XP and triggers level rewards.
  - `Campaign`: `complete_task` happy path (coins down, rewards granted, done marked);
    all four rejection reasons; day advances only when all tasks done; entering a new
    area emits `area_restored` for the finished one; the area-3 gate (level 5; the
    unknown `1_9` condition treated as satisfied) rejects then passes;
    `wing_progress`/`area_state` correctness; campaign end (`is_complete`) past day 282.
  - ConfigDB: task counts/indexing, area-unlock row, the erratum warning.
  - `HallLayout`: 47 wings, every area exactly once, no overlapping rects, all inside
    the canvas.
  - Save v4 round-trip (day, done set); fresh-install defaults.
  - Smoke test: deliver an order → coins appear → complete a day-1 task → XP granted,
    day-1 progress advances; quit/resume preserves it.
- Headless boot + full suite via `./curio-hall/test.sh` (run `godot --headless
  --import` after adding the new `class_name` scripts).

## 6. Milestones

1. `Rewards` `exp` token + `Game.grant_xp`.
2. `ConfigDB.main_tasks` / `area_unlocks` loading.
3. `Campaign` sim (complete/advance/gate) + save v4.
4. `HallLayout` + `MapPanel` overlay + Map button + smoke test.

**Definition of done:** the Goal paragraph, verified by playing a fresh install through
day 1 on the map, every number traceable to the config.
