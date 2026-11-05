# Curio Hall — Phase 4b2 Design: Special orders + order avatars

**Date:** 2026-09-07
**Status:** Approved design, awaiting spec review
**Depends on:** Phases 1-4b (merged), `HANDOFF.md`, `docs/creative-direction.md`
**Roadmap:** `docs/curio-hall-roadmap.md`

## Goal

Campaign milestones now summon the society with personal requests: the six `OrderSpecial`
orders appear one at a time as story tasks complete, each fronted by a cast member,
asking for one deep item whose generator arrives with the request, and paying gems and
energy. Regular orders gain rotating customer portraits from `OrderAvatarConfig`. All of
it survives quit/resume; every number comes from the config.

## How the it works

- **`OrderSpecialConfig`** (6 rows, sequential by Id `GetSpecialOrderConfigWithOffset`): each has `Trigger` (`taskFinish-D_I`, a campaign
  task key), `Requirement1`, `Requirement2` (order 3 only), `Requirement3` (delivery consumes all present RequirementN fields), `GeneratorChain` (string or Array: `"15"`, `"19"`, `"sp3_1"`,
  `["sp4_1","sp4_2"]`, `["sp5_1"]`, `["sp6_1"]`), `Rewards` (gems + energy), `AvatarId`
  (101-106) with `AvatarImage`/`BigAvatarImage`, `DescriptionKey`, and Start/End
  timelines (map effects — deferred). `CreateSpecialOrder` pushes items to the
  player through the cache queue (`CacheItems Type2`) — we have no cache queue, so
  activation instead GRANTS the seed item of each `GeneratorChain` (see Design). All six
  requirements are producible in this build: chains 16/20 from existing generators
  (1504+/1903+), and every `sp*` chain has its own generator items in `ItemModelConfig`
  (e.g. `sp3_1_1` spreads `sp3_2_1`, which merges to `sp3_2_10`).
- **`OrderAvatarConfig`**: `NormalAvatars` (rotating customer names, some with
  `UnlockLevel`) for regular orders; `SpecialAvatars` keyed by `AvatarId` for special
  orders; other groups (BakeOut/Branch/Timed/PK/Chest/Contiorder) belong to
  unimplemented systems and are ignored.
- **`OrderBranchConfig` is DORMANT in this build** and deferred: its requirement `8313`
  belongs to chain 83 which nothing produces (no `82xx` coop item exists, no spread
  includes `8301`), and the swallow mechanic it needs (`ItemSwallow`,
  `Swallow_Weight/Number` fields) appears only in live-ops event configs (Dig, Break,
  Pureboard, Stickerboard). Both move to phase 5, where real swallow config exists.

## Scope

**In:** the `SpecialOrders` sim (sequential activation on campaign triggers, seed-item
grants, deliver + rewards), ConfigDB loading of `OrderSpecialConfig` +
`OrderAvatarConfig`, avatar assignment on regular orders, the order bar's special slot
and avatar labels, save v7.

**Out (deferred):** the branch order + swallow mechanic (phase 5),
`StartTimeline`/`EndTimeline` map effects, `FrameColor`/reward/complete imagery,
special-order celebration UI, rethemed names for non-cast customer avatars (text-rewrite
track), real art.

## 1. Sim: `SpecialOrders` (`sim/special_orders.gd`, RefCounted)

- State: `next_id: int = 1` (1..6; 7 = all done), `active: bool = false`.
- `current() -> Dictionary`: the active order's config row, `{}` when inactive.
- **`maybe_activate(campaign, game, now) -> bool`**: when `not active`, `next_id <= 6`,
  and the next row's `Trigger` suffix (`taskFinish-2_7` → `"2_7"`) is in
  `campaign.done`: set `active`, grant one seed item per `GeneratorChain` entry
  (normalize string-or-Array; numeric chain `"15"` → item `"1501"` = chain + `"01"`;
  `sp` chain `"sp3_1"` → item `"sp3_1_1"` = chain + `"_1"`), each via `Rewards.grant`
  (full board falls back to inventory), emit `special_changed`, return true.
 
  the direct grant is our stand-in until a cache queue exists.
- Call sites: `Game.complete_task` after a successful completion, `deliver_special`
  after advancing, and `Game.from_dict` is NOT hooked (activation state is saved;
  triggers re-check on the next task completion).
- **`deliver_special(board, game, now) -> {ok, reason}`**: reasons `not_active` |
  `no_item` (board lacks any RequirementN present). On success: verifies all RequirementN
  exist before removing any, then removes one of each, `Rewards.grant_all(row.Rewards)`,
  `active = false`, `next_id += 1`, `maybe_activate(...)` for the next one, emit
  `special_changed`.
- `is_all_done() -> bool` (`next_id > 6 and not active`).
- `to_dict/from_dict` (`next_id`, `active`). Time-free: no timers, no tick host.

## 2. ConfigDB

- `order_special: Array` — `OrderSpecialConfig.json` sorted by Id (copied verbatim).
- `order_avatars: Dictionary` — `OrderAvatarConfig.json` as-is (`NormalAvatars` Array,
  `SpecialAvatars` Dictionary keyed by stringified AvatarId, other groups present but
  unused).
- `validate()` warns when a special `Requirement1` or derived seed item id is missing
  from `ItemModelConfig` (never errors).

## 3. Avatars on regular orders

- `OrderBook._build_order` and `_build_fixed` add `"avatar": <name>`: rolled uniformly
  (injected RNG) from `NormalAvatars` rows whose `UnlockLevel` (default 1) ≤ player
  level; `_build_fixed` gains an `rng` parameter threaded from `fill` (and
  `player_level`, which `fill` already has). Orders saved before this change lack the
  key; the view falls back to no label (and save v7 resets old saves anyway).

## 4. View: order bar

- Each regular order card's text gains a first line: the avatar's display name via
  `Cast.display_name` (non-cast names like Lily/Gerald render capitalized until the
  text-rewrite track).
- A **special slot** appears at the right of the order bar while a special order is
  active: the cast name for `SpecialAvatars[AvatarId]`, the `DescriptionKey` as
  placeholder flavor, `needs 1x <Requirement1> (have N)` plus a
  `from chain <GeneratorChain>` hint, and a Deliver button (disabled at have-0).
  Failures route to the toast (`REJECT_MESSAGES` gains `not_active`, `no_item`).
- The bar listens to `special_changed` alongside `orders_changed`;
  `main.gd` adds `special_changed` to the save-pending signals.

## 5. Persistence

**Save v6 → v7**: adds the `specials` block; `SaveManager` requires the key; mismatch
backs up and resets per convention.

## 6. Error handling & testing

- Delivery is check-then-mutate; rejected delivery changes nothing.
- **Testing** (GUT, sim TDD; the board starts FULL — free cells before placing):
  - Activation: trigger satisfied → active + seed items granted (string chain `"15"` →
    `1501`; Array chain for id 4 grants both `sp4_1_1` and `sp4_2_1`); not before the
    trigger; special N+1 never activates while N is undelivered even with its trigger
    done; after delivering N, N+1 activates immediately when its trigger is already
    satisfied.
  - Delivery: checks all RequirementN exist, removes one of each, grants gems/energy
    (energy overfills per the 4b ruling), advances; `no_item`/`not_active` reject cleanly.
  - Full walk: scripted `campaign.done` marks + board plants walk specials 1→6 to
    `is_all_done()`.
  - Avatars: at level 1 only `UnlockLevel`≤1 names appear; deterministic under seeded
    RNG; fixed and random orders both carry `avatar`.
  - Save v7 roundtrip (`next_id`, `active`); version literals updated (v6 → v7 renames).
  - Smoke: complete campaign task 2_7's prerequisites via scripted done-marks, see the
    special activate, deliver it, rewards land; quit/resume preserves the sequence.
- Headless boot + full suite; `godot --headless --import` after new class_name scripts;
  **verify printed suite totals** (GUT swallows parse errors — the 4b lesson).

## 7. Milestones

1. ConfigDB: `order_special` + `order_avatars` (+ copies, validation warning).
2. `SpecialOrders` sim + `Game` wiring (`complete_task` hook, `deliver_special`,
   `specials` in fresh) + save v7.
3. Avatars on regular/fixed orders.
4. Order bar special slot + avatar labels + toasts + smoke test; roadmap update.

**Definition of done:** the Goal paragraph on a fresh install, every number traceable
to the config.
