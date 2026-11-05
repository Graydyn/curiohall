# Curio Hall Phase 5b: Patron's Gala (GeneratorBoost) — Design

Date: 2026-09-11
Status: approved design, pre-implementation

## Summary

Phase 5b adds the second live-ops archetype: **GeneratorBoost**, themed as the
**Patron's Gala**. Unlike the Pureboard expedition (a separate event board), this is a
**main-board buff event**: for a multi-day window, finishing main orders climbs a daily
task ladder that unlocks cumulative buffs on the 32 boosted generator types.

(`GeneratorBoostActivity.Model.GeneratorBoostActivityModel`, `Board.Model.Item.ItemSpread`)
on 2026-09-11; 

## Mechanics

- The activity is a **daily-resetting buff ladder**. A task list (each task: "finish N
  main orders"; special orders excluded) raises the **buff level** one rung per completed
  task. All buffs at rungs <= the current level are **active simultaneously**.
- State (progress, buff level, quota counters, caches) **resets at each daily rollover**
  (`RefreshTime` = next midnight; `RoundNum` increments per day).
- Buff type enum (string-valued): `nocd`, `smartProduce`, `extraProduce`,
  `moreLuckyProduce`, `extraLuckyProduce`.
- **extraProduce**: a quota system. Param `[M, N]` = M guaranteed free double-spawns per
  window of N generator taps, at RNG-chosen positions within the window
  (`ExtraProduceTotalSpreadCount` / `ExtraProduceLeftSpreadCount`). The extra item costs
  no energy, rolls from the same weight table, and needs a second free cell; if the board
  is full the extra is **cached** (one slot) and delivered on a later tap.
- **extraLuckyProduce**: when a lucky drop procs, a second lucky item also spawns
  (same one-slot cache-if-full behavior).
- **moreLuckyProduce**: config swap. `GeneratorBoostLuckyProduceConfig.MoreLuckyProduce`
  boosts lucky chance from base 1/60 to 1/25–1/30 with tweaked pools;
  `GeneratorBoostItemModelConfig.MoreLuckyProduce` tweaks `Spread_Weight` per generator.
  swaps in `...Config.ExtraLuckyProduce` tables when extraLuckyProduce
  is active; when both are active, MoreLuckyProduce's tables win (model proto 25 order).
- **nocd**: generator charge cooldowns are skipped while active.
- **smartProduce**: produces items targeted at current order needs; rides on
  infrastructure we don't have. **Deferred, out of scope for 5b.**
- Eligibility (`CanSupportGeneratorBoost`): main-board, energy-costing, non-disposable
  generators — exactly the 32 types listed in the GeneratorBoost config families
  (105–111, 405–411, 706–711, 805, 1207–1211, 1706–1711).
- UI: HUD entry button, a main window with the task ladder, a fly-buff celebration
  animation (we skip the animation).

## Decisions

- **Parallel track**: GeneratorBoost gets its own lifecycle, independent of and
  concurrent with the expedition track. No Events refactor; a general activity scheduler
  waits until a third archetype demands it (rule of three).
- **Faithful ladder, 4 buffs** in rung order: moreLuckyProduce, extraProduce,
  extraLuckyProduce, nocd. Cumulative. smartProduce deferred.
- **Multi-day window with daily reset**, 
- **Theme**: "Patron's Gala" — a gala night at the Hall; patrons fund the workshops, so
  the display cases overflow. Rung display names: Lucky Finds (moreLuckyProduce),
  Overflowing Cases (extraProduce), Twin Discoveries (extraLuckyProduce),
  Tireless Curators (nocd).
- **Query-seam config overrides**: ConfigDB is never mutated at runtime (the original
  hot-reloads configs; we don't). Effective rows/tables are resolved per lookup.

## Architecture

### New: `curio-hall/sim/boost.gd` (`class_name Boost extends RefCounted`)

Signal `boost_changed`. Pure logic; time enters only as injected `now: float`,
randomness only via injected RNG. Mirrors `Events` conventions.

- **Lifecycle**: `enum State { IDLE, ACTIVE }`. `tick(now, player)`: start when
  `now >= next_boost_at` and `player.level >= tuning boost_unlock_level`; end at
  `ends_at`. `start_boost(now)` / `end_boost(now)` are also the dev controls.
  On end, `next_boost_at = now + boost_gap_seconds`.
- **Daily rollover**: on start, `rollover_at` = next local midnight after `now`
  (computed from the injected `now` via `Time.get_datetime_dict_from_unix_time`-style
  arithmetic; no wall-clock reads inside the sim). When `tick` crosses `rollover_at`:
  reset `progress`, `buff_level`, quota counters, both caches; `round += 1`;
  `rollover_at += 86400`.
- **Task ladder**: tuning `boost_tasks` (cumulative delivered-order counts per rung) and
  `boost_buffs` (buff kind per rung), same length. `on_order_delivered(now)` increments
  `progress`; while `buff_level < rungs` and `progress >= boost_tasks[buff_level]`,
  `buff_level += 1` (loop handles multi-rung edge). `is_buff_active(kind) -> bool`:
  kind appears in `boost_buffs[0 .. buff_level-1]` and state is ACTIVE.
- **ExtraProduce quota**: tuning `boost_extra_produce = [M, N]`. Maintain
  `window_left` (taps remaining in window) and `extras_left` (extras remaining in
  window). `take_extra(rng) -> bool`, called once per successful boosted tap while the
  buff is active: when `window_left == 0`, re-arm (`window_left = N`,
  `extras_left = M`); fire with probability `extras_left / window_left` (guarantees
  exactly M per N, uniformly placed); decrement both on fire, else decrement
  `window_left`.
- **Caches**: `extra_cached: bool`, `extra_lucky_cached: bool` — one slot each, set when
  a fired extra can't be placed, consumed on a later tap. Precise per-tap rule for
  extras: every boosted tap calls `take_extra(rng)` (the quota window always advances);
  at most **one** extra item is placed per tap — a cached extra is delivered first, and
  a same-tap `take_extra` fire then occupies the freed cache slot; a fire with no board
  room and the slot already full is lost with a `push_warning` (mirrors the supply-row
  rule in Events).
- **Eligibility**: `is_boosted(type) -> bool` = type present in the loaded
  GeneratorBoost item-model override map.
- **Effective config**:
  - `effective_row(type) -> Dictionary`: if ACTIVE and moreLuckyProduce active and type
    boosted, the `GeneratorBoostItemModelConfig.MoreLuckyProduce` row; else the base
    `ConfigDB.items` row.
  - `effective_lucky() -> Array`: moreLuckyProduce active →
    `GeneratorBoostLuckyProduceConfig.MoreLuckyProduce`; else extraLuckyProduce active →
    `...ExtraLuckyProduce`; else base `ConfigDB.lucky`.
- **Persistence**: `to_dict` / `from_dict` covering state, `ends_at`, `next_boost_at`,
  `rollover_at`, `round`, `progress`, `buff_level`, quota counters, both caches.

### ConfigDB additions

- Load `GeneratorBoostItemModelConfig.json` (keep both `ExtraProduce` and
  `MoreLuckyProduce` lists; store as maps type -> row) and
  `GeneratorBoostLuckyProduceConfig.json` (both lists) at startup, verbatim from
  config
- Accessors: `boost_item_row(mode, type)`, `boost_lucky(mode)`, `boost_types()` (the 32
  boosted type ids).
- New tuning keys in `curio_hall_tuning.json`:
  `boost_duration_seconds` (259200 = 3 days), `boost_gap_seconds` (86400 = 1 day,
  deliberately different from the expedition cadence so overlap occurs naturally),
  `boost_unlock_level`,
  `boost_tasks` ([2, 3, 4, 5]), `boost_buffs`
  (["moreLuckyProduce", "extraProduce", "extraLuckyProduce", "nocd"]),
  `boost_extra_produce` ([1, 3]).

### Game integration (`curio-hall/sim/game.gd`)

- `var boost: Boost`, created in `Game.fresh`, saved/loaded like `events`.
- `tick_boost(now)` calls `boost.tick(now, player)`; **tick host** is `main.gd`'s
  existing 1s timer, alongside `tick_events` (named per the recurring plan defect).
- `deliver_order`: after the existing `events.on_order_delivered`, call
  `boost.on_order_delivered(now)` (special orders route through `deliver_special`, so
  they are naturally excluded, matching the original).
- `tap_generator` changes, in order:
  1. Read the generator row via `boost.effective_row(item.type)` (weights only; charge
     caps/durations keep using the live `GeneratorState` row source — see note below).
  2. **nocd**: if active and `boost.is_boosted(type)`, skip `item.gen.consume(now)`
     (still require the energy cost and the free cell).
  3. Normal spawn as today, rolling from the effective row's `Spread_Weight`.
  4. **extraProduce**: if active and boosted, call `boost.take_extra(rng)` and apply the
     one-extra-per-tap cache rule above; a delivered extra is one more roll from the same
     effective weight table at no extra energy/charge into a free cell.
  5. Lucky roll via `LuckyRoller.roll(type, level, rng, boost.effective_lucky())`.
  6. **extraLuckyProduce**: if the lucky roll procs and the buff is active and the type
     boosted, attempt a second independent lucky spawn (consume/set
     `extra_lucky_cached` by the same rule).
  - Extra spawns append to the result's `spawned` array with `"extra": true` /
    `"lucky": true` flags so the view can distinguish them later if wanted.
- `LuckyRoller.roll` gains a trailing `table: Array = []` parameter; empty means
  `ConfigDB.lucky` (existing callers unchanged).
- Event-board play is unaffected: boost hooks live only in `tap_generator`
  (main board) and `deliver_order`.

Note on GeneratorState: the MoreLuckyProduce override rows keep identical charge
caps/durations to base for all 32 types (verified for the families spot-checked), so
`GeneratorState` continues reading `ConfigDB.items` directly; only `Spread_Weight` is
read through the effective row. This keeps the override surface minimal.

### Save

`SAVE_VERSION` 9 → **10**; `"boost"` key added. Per convention, older saves back up to
`save.corrupt.json` and reset.

### View

- **HUD button** "Patron's Gala": visible only while the boost is ACTIVE (plus the dev
  affordance below), opens the gala panel. Placement must not overlap the Expedition
  button (both can be visible at once — the 5a "stranded behind it" fix is the
  cautionary tale).
- **`curio-hall/view/gala_panel.gd`** (CanvasLayer, modeled on `event_panel.gd`
  including its input-lifecycle handling): shows the four rungs with themed names and
  their unlock counts, current progress toward the next rung, active-buff states, time
  until daily reset, time until window end, and clearly-labeled DEV Start / DEV End
  buttons (the dev entry point for starting a boost while idle lives here, as the
  expedition's does in its panel).
- The 1s timer's tick drives countdown refresh; the countdown Timer is parented on the
  CanvasLayer, never inside a container that `refresh()` clears (the self-freeing-timer
  trap).
- No board-cell glow/badge in 5b; the panel is the boost's visibility. The  
  fly-buff animation is skipped.

## Testing

GUT sim tests (deterministic RNG, injected `now`):

- Lifecycle: gated start (level + `next_boost_at`), end at `ends_at`, gap re-arm,
  dev start/end, concurrency with an ACTIVE expedition.
- Daily rollover: progress/buff level/quota/caches reset, round increments,
  `rollover_at` advances exactly one day; no reset when the window ends first.
- Ladder: order deliveries advance progress; rungs unlock at tuning thresholds;
  buffs are cumulative; special-order delivery does not advance progress.
- Quota: over K windows of N taps, exactly K*M extras fire (RNG-seeded); cache set when
  the board is full and consumed on the next tap with room.
- nocd: charges do not deplete while active for boosted types; deplete normally for
  non-boosted generators and after the window ends.
- Effective config: fallback to base when IDLE or buff inactive; MoreLuckyProduce wins
  over ExtraLuckyProduce when both are active; non-boosted types always get base rows.
- Lucky: boosted table actually changes proc chance (statistical or direct-table
  assertion), `LuckyRoller` default-parameter path unchanged.
- Save: v10 round-trip of all boost fields; v9 save resets per convention.

View verification: headless boot plus the test suite; hands-on click check left to the
user (per project convention).

## Out of scope / deferred

- smartProduce buff (needs the smart-produce/order-targeting infrastructure).
- Board-cell boost glow/badge and the fly-buff celebration animation.
- Event points / decoration shop (already on the 5a deferred list).
- Any expedition-track changes.
