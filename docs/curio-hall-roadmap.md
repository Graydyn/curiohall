# Curio Hall — Development Roadmap

Phase tracking for the Curio Hall merge game,. Theme and naming: `docs/creative-direction.md`.

Status legend: ✅ complete · 🔨 in progress · ⏳ planned

---

## Phase 1 — Core merge board ✅

Playable config-driven merge game: `ItemModelConfig` recipes + generators, energy with
timed regen, weighted drops, lucky bonus drops, 5→32 inventory slots, a minimal order
loop, the 300-level XP curve, and save/load with offline accrual. Godot 4 / GDScript,
pure-sim core under a thin view layer, placeholder art.

- Spec: `docs/superpowers/specs/2026-09-02-curio-hall-phase1-design.md`
- Plan: `docs/superpowers/plans/2026-09-02-curio-hall-phase1.md`
- Post-merge additions: rejected-action toast, locked-tile (padlock) rendering,
  test-isolated save path + structural save validation, cold-cache warm-up in test.sh.

## Phase 2 — Orders + economy ✅

Timed order board (eligible order types by level, per-slot `RefreshTime` + gem-skip with
a runtime refill tick), the `CollectRewards` reward grammar (single `Rewards.grant` sink),
level-up reward **chests** (`ChestState` finite dispensers) that dispense collectible
**currency tokens** (chain 24 = coins, 25 = gems, 26 = energy), and tap-to-collect
crediting the wallet. Makes gems earnable and spendable end to end. Save v2.

- Spec: `docs/superpowers/specs/2026-09-02-curio-hall-phase2-economy-design.md`
- Plan: `docs/superpowers/plans/2026-09-02-curio-hall-phase2-economy.md`
- Deferred to later cleanup: order-type `DiffSum` bracket selection (`_filter_for` uses
  first player-level match); `ChestState.skip_open` already-openable guard and
  `_row()` config-churn hardening; `OrderBook.from_dict` `refresh_at` shape validation;
  shared `_tier` helper. None block the playable.

## Phase 3 — Shop / IAP ✅

Modal shop overlay with three surfaces: coin item-shop (6 weighted slots, timed refresh +
gem-skip), gem daily-deals (limited stock, 24h restock, ad-deals as dev free-claims), and
dev-stubbed real-money IAP (gem packs + a level-3 starter bundle with real gating but fake
payment). Runtime tick (`game.tick_shop`) so shop timers advance with the panel closed; save v3.
Real payment processing, rewarded-ad SDK, and event shop variants are deferred.

- Spec: `docs/superpowers/specs/2026-09-02-curio-hall-phase3-shop-design.md`
- Plan: `docs/superpowers/plans/2026-09-03-curio-hall-phase3-shop.md`
- Deferred to later cleanup: bundle 48h clock intent (now starts from unlock); `skip_shop_refresh`
  reason split (done); event shop variants (`ShopSlotConfig_shell`, `ShopDailyDealsConfig_random`,
  `ShopIAPConfigCN`); real payment + rewarded-ad SDKs (blocked on a shipping app).

## Phase 4a: Campaign and map ✅

The `MainTask` campaign (282 story days, 4,107 coin-paid tasks), `AreaUnlock` gating to
unlock Hall areas as the campaign advances, the `exp` reward token for level progression,
and a Hall floor-plan map with task pins marking campaign checkpoints. This forms the
narrative and spatial meta-layer that turns the merge loop into a game. Save v4.

- Spec: `docs/superpowers/specs/2026-09-03-curio-hall-phase4a-campaign-design.md`
- Plan: `docs/superpowers/plans/2026-09-03-curio-hall-phase4a-campaign.md`
- Notes: task costs are coins per the `new_task_tip` text (`OrderRandomConfig.Point`
  is an event currency, phase 5); `AreaUnlock`'s `TaskCompleted-1_9` references a nonexistent
  task and is treated as satisfied (level gate still applies); map pin positions are custom
  authored (only 93 config `edit_pos` rows exist); the `_fire` alternate campaign is ignored;
  task text awaits the text-rewrite track.

## Phase 4b: Characters and intimacy ✅

The intimacy system (gift economy from orders + daily shop, 30-level tracks with rewards and
story-unlock flags, unlock web, SocietyPanel, save v6, `tick_gifts` tick host). Adds depth to
the narrative progression with character-driven content variants.

- Spec: `docs/superpowers/specs/2026-09-04-curio-hall-phase4b-intimacy-design.md`
- Plan: `docs/superpowers/plans/2026-09-05-curio-hall-phase4b-intimacy.md`
- Deferred: return-gift pools (level rows' `Gifts` columns), Ambrose/Ambrose track (unreleased
  in config), dialog text (rewrite track).

## Phase 4b2: Special orders ✅

Six sequential special orders (campaign-trigger-gated, seed-grant stand-in for the cache queue) with
their own generator chain and `Rewards`, an order-bar special slot, and fixed cast customer
avatars. Regular and fixed orders use level-gated avatars. Save v7.

- Spec: `docs/superpowers/specs/2026-09-07-curio-hall-phase4b2-special-orders-design.md`
- Plan: `docs/superpowers/plans/2026-09-07-curio-hall-phase4b2-special-orders.md`
- Deferred: branch order and swallow mechanic (dormant data in this build, nothing produces
  chain 83 and no coop item exists, phase 5), Start/End timelines, celebration UI, non-cast
  avatar retheme names.

## Phase 4b3: Story recap and return gifts ✅

Chronicle reader (five volumes gated by campaign milestones), daily return gifts
(level-weighted sender, level-pool contents, preferred bonus
corrected to 1.2x ceil, memories list, save v8.

- Spec: `docs/superpowers/specs/2026-09-07-curio-hall-phase4b3-recap-return-gifts-design.md`
- Plan: `docs/superpowers/plans/2026-09-07-curio-hall-phase4b3-recap-return-gifts.md`
- Deferred: return gifts as openable board items via a cache queue (direct grant stand-in),
  recap art/text (rewrite track).

## Phase 4c: Wings decoration ⏳

`Skin` decoration of the 47 Hall wings to add visual progression and personalization to the
player's growing collection.

## Phase 5a: Event framework and Pureboard expedition ✅

The event lifecycle framework and its first playable archetype: auto-rotating events with
clearly-labeled DEV start/end controls, per-instance board dimensions (an event board sized
independently of the main board), event config bundles, order
feeding onto the supply row as a cache-queue stand-in (delivering an order drops the event's
feed item there), tier progress tracked via a merge chain with a completion flag, and
placeholder end rewards. On the view side: `BoardView` parameterized to drive any board with
any merge/tap callbacks, and a new `EventPanel` (the Society's expedition screen) wired into
the main scene behind an Expedition HUD button. Save v9.

- Spec: `docs/superpowers/specs/2026-09-07-curio-hall-phase5a-event-framework-design.md`
- Plan: `docs/superpowers/plans/2026-09-07-curio-hall-phase5a-event-framework.md`
- Deferred: event points and the decoration shop, scrolling-window presentation for larger
  event boards, event-specific orders, the remaining board archetypes, real end rewards
  (once decoded from bytecode).

## Phase 5b: Patron's Gala (GeneratorBoost) ✅

The second live-ops archetype and the first main-board buff event, running as a
parallel track concurrent with the expedition. 
(GeneratorBoostActivityModel/ItemSpread): a daily-resetting task ladder — finishing
main orders unlocks cumulative buffs on the 32 boosted generator types
(moreLuckyProduce config swap, extraProduce guaranteed-double quota with
cache-when-full, extraLuckyProduce twin lucky, nocd free recharge). Query-seam
config overrides (ConfigDB never mutated), save v10, code-built Gala button + panel
with DEV controls.

- Spec: `docs/superpowers/specs/2026-09-11-curio-hall-phase5b-generator-boost-design.md`
- Plan: `docs/superpowers/plans/2026-09-11-curio-hall-phase5b-generator-boost.md`
- Deferred: smartProduce buff (needs order-targeting smart-produce infrastructure),
  board-cell boost glow and the fly-buff celebration animation, per-buff art.

## Phase 5 — Live-ops events ⏳

The rotating event calendar over the board archetypes: Multiboards,
Adventure (+wheel), Explore (path-unlock), Dig/Dig2, Freefall, and the themed
one-offs (Beat, Break, Stickerboard, Pureboard, Card, GeneratorBoost). Phase 5a lands the
framework and the Pureboard expedition; Phase 5b shipped GeneratorBoost (main-board buff
event, task-ladder ordered to unlock cumulative buffs); the remaining archetypes
(Dig/Break bringing swallow, Freefall, Multiboards, Explore) queue behind it,
each a reskinned variant driven by its own config family, sequenced as its own sub-project.

---

## Deferred nits (from phase-1 reviews, safe to batch later)

Level rewards lost on a full board should fall back to inventory (Phase 2's `Rewards.grant`
handles this); a visual highlight for the selected board tile; sim-file indentation
unification; a `godot --headless --import` CI warm-up step when CI is added.
