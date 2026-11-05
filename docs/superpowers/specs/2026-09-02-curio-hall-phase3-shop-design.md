# Curio Hall — Phase 3 Design: Shop / IAP

**Date:** 2026-09-02
**Status:** Approved design, awaiting spec review
**Depends on:** Phase 1 & 2 (merged), `HANDOFF.md`, `docs/creative-direction.md`
**Roadmap:** `docs/curio-hall-roadmap.md`

## Goal

Give the earned currencies real spend sinks: a coin item-shop, gem daily-deals, and
(dev-stubbed) real-money IAP, all on one modal shop overlay. From a fresh install a
player can open the shop, spend coins on item-shop slots (which go sold-out and refresh
on a gem-skippable timer), spend gems on limited-stock daily deals, and use clearly
labeled dev-stub IAP to grant gems, with everything surviving quit/resume and every
number from the config.

## How it works (verified from config)

- **Item shop** — `ShopSlotConfig` (19 rows) gives each of 6 slots per-chain weights
  (`Slot1Weight`..`Slot6Weight` keyed by `ChainId`). `ItemPropertyConfig` gives each
  buyable item its `Slot` list, `ShopWeight`, `Price` (coins), `ShopCount` (quantity per
  buy), and `CustomChain`. Roll per slot: pick a chain by that slot's weights, then an
  item within by `ShopWeight`; a slot's shop-chain is `CustomChain` when non-"0", else
  the item id's natural chain (2-digit-suffix prefix). Cheap commons sit in slots 1-3,
  rarer/pricier items in slot 6. Spend = `Price` coins; grant = `ShopCount` of the item.
- **Daily deals** — `ShopDailyDealsConfig` (3 rows): `itemCode`, `leftCount` (stock),
  `costType: "gem"`, `costCount` (gem price; one is 0 = free), optional `ad: 1`
  (ad-gated). All three item codes (`3101`, `2901`, `ShopNewChest_1`) resolve to real
  board items (chests/spread items).
- **IAP gem packs** — `ShopIAPConfig` (6 rows): `goods: ["gem-N"]` (100 / 265 / 580 /
  1260 / 3350 / 7450), `purchaseId`, `icon`. Real-money purchases.
- **Bundle** — `BundleConfig` (1 row): starter bundle `goods: ["gem-510","energy-200",
  "3601-2"]`, `condition: "Level-3"`, `buyCount: 1`, `lastDuration: 172800` (48h),
  `purchaseId`. Real-money, condition-gated, time-limited, one-time.
- **No refresh mechanic is in the config** for the item shop (as with phase-2 orders);
  it is added as tuning here.

## Scope

**In:** the coin item-shop (6 slots, weighted roll, buy-with-coins, timed refresh +
gem-skip), gem daily-deals (stock, 24h restock, ad-deals as dev free-claims), dev-stub
IAP (gem packs + starter bundle with real gating but fake payment), the modal shop
overlay + Shop button, a runtime tick so shop/deal timers advance without the panel
open, and save v3.

**Out (deferred — see roadmap):** real payment processing (App Store / Play Billing —
the whole reason IAP is stubbed), real rewarded-ad SDK integration, and event/rotating
shop variants (`ShopSlotConfig_shell`, `ShopDailyDealsConfig_random`, `ShopIAPConfigCN`).
`EnergyBoostItemConfig` ships empty (`return {}`) and is not consumed. No real art.

## 1. Sim: purchase surfaces

New `RefCounted` classes, pure logic, injected `now`/`rng`, all grants through the
existing `Rewards.grant` sink, all spends through the atomic `EnergyWallet`.

### `ItemShop` (`sim/item_shop.gd`)
- 6 slots; `roll_slot(n, rng)` picks a chain by `ShopSlotConfig` slot weights then an item
  by `ItemPropertyConfig` `ShopWeight` (chain grouped by `CustomChain`-or-natural-chain).
  Each slot holds `{item, price, count, sold_out}`.
- `fill(rng, now)` fills empty/never-filled slots; `buy(n, wallet, game, now) ->
  {ok, reason}`: checks affordability (`Price` coins) and not sold-out, spends coins,
  grants `ShopCount` via `Rewards`, marks the slot sold-out. Reasons:
  `"sold_out" | "not_enough_coins"`.
- Timed refresh: on refresh all slots re-roll. `refresh_at`, `time_to_refresh(now)`,
  `is_refreshing(now)`, `skip_refresh(wallet, now)` spends `tuning.shop_skip_gems`.
  Refresh cadence `tuning.shop_refresh_seconds`. `to_dict/from_dict`.
- `signal shop_changed`.

### `DailyDeals` (`sim/daily_deals.gd`)
- The 3 `ShopDailyDeals` rows as deals `{id, item, cost_gems, stock, is_ad}`. Note the
  `costCount` and `ad` flags are independent: deal 1 costs 25 gems, deal 2 costs 10 gems
  AND is ad-gated (`ad:1`), deal 3 is free (`costCount:0`, no ad).
- `buy(id, wallet, game, now) -> {ok, reason}`: spend `cost_gems` gems (a 0-cost deal
  spends nothing); if the deal `is_ad`, gate it behind a dev free "watch ad" claim
  (labeled in the view, no real ad SDK) that still charges its `cost_gems`; grant
  `itemCode`, decrement stock. Reasons: `"out_of_stock" | "not_enough_gems"`.
- 24h restock: `restock_at`; on elapse, stock resets to each row's `leftCount`.
- `to_dict/from_dict`; `signal deals_changed`.

### `Iap` (`sim/iap.gd`, mostly stateless)
- Catalog from `ShopIAPConfig` (6 packs) and `BundleConfig` (1 bundle).
- `packs() -> Array`, `bundle() -> Dictionary` (with availability).
- `purchase_pack(purchase_id, game, now) -> {ok}`: **dev stub** — grants `goods` via
  `Rewards`, no real payment. `purchase_bundle(game, now) -> {ok, reason}`: honors
  `condition` (`Level-3` gate → reason `"locked"`), `buyCount: 1` (one-time → reason
  `"already_bought"`), `lastDuration` expiry from first-seen (reason `"expired"`).
- Bundle purchase state (bought flag, first-seen timestamp) lives in save; pack
  purchases are stateless (repeatable dev grants).
- Every IAP action is tagged as a fake dev transaction; nothing touches real billing.

## 2. View: the shop overlay

- **`ShopPanel`** (`view/shop_panel.gd`, a `CanvasLayer`/`Control` overlay, hidden by
  default) opened by a new **Shop button** on the main scene, closed with an X, drawn
  over the board. Three placeholder-styled sections:
  - **Item Shop**: 6 slot buttons (item placeholder + coin price + sold-out state), a
    refresh countdown, and a gem-skip button.
  - **Daily Deals**: 3 deals (item + gem cost + remaining stock; ad-deals labeled
    "Watch ad (dev: free)").
  - **Get Gems**: 6 IAP packs + the starter bundle, each with a clear **"DEV"** tag and
    a stub-buy button; the bundle shows its lock/expiry/one-time state.
- Buy buttons disable when unaffordable/unavailable and route failures to the existing
  main-scene toast (new `REJECT_MESSAGES`: `not_enough_coins`, `sold_out`,
  `out_of_stock`, `locked`, `already_bought`, `expired`). Shop items render through the
  existing `ItemView`-style placeholder seam.
- The panel listens to `shop_changed`/`deals_changed`/`wallet.changed` and re-renders;
  a 1-second timer drives the refresh countdown, hosted so it survives its own rebuild
  (the exact self-freeing-timer bug phase 2 caught — do not reintroduce it).

## 3. Runtime ticks & persistence

- **Who ticks the sim** (carrying phase 2's lesson forward): the main scene's existing
  1-second timer calls `game.tick_shop(now)` so item-shop and daily-deal timers refill
  without opening the panel. This is the third time-driven system (energy regen, orders,
  now shop) — the plan will name the tick host explicitly.
- **Save v3**: `SAVE_VERSION` → 3. Serialize item-shop slots + `refresh_at`, daily-deal
  stock + `restock_at`, and bundle bought-flag + first-seen timestamp. All timers accrue
  offline (reconciled against `now` on load) like orders/energy. v2→v3 migration defaults
  the new fields (fresh shop, full stock, bundle unbought); a v2 save loads cleanly
  through SaveManager's existing structural+version gate.

## 4. Error handling & testing

- Purchases are atomic check-then-spend via `EnergyWallet` (`spend_coins`/`spend_gems`
  fail without mutating), so no currency is lost on a failed grant; every rejected buy
  returns a reason code surfaced via toast, never crashes. Unknown config goods degrade
  via `Rewards`' existing warning-and-skip.
- **Testing** (GUT, sim-layer TDD):
  - `ItemShop`: slot roll respects slot/chain weights and yields a real `ItemProperty`
    item with its `Price`/`ShopCount`; buy spends coins, grants goods, marks sold-out;
    timed refresh re-rolls; gem-skip spends and refreshes; deterministic under seeded RNG.
  - `DailyDeals`: gem buy decrements stock and grants; out-of-stock and insufficient-gems
    rejected without spend; ad-deal free-claim grants without gems; 24h restock resets.
  - `Iap`: pack stub grants pack goods; bundle honors Level-3 lock, one-time buyCount,
    and 48h expiry.
  - Save round-trip for all shop state incl. offline restock; v2→v3 migration loads.
  - Smoke test extending phase 2's: earn coins, buy an item-shop slot (goes sold-out),
    gem-skip a shop refresh, buy a daily deal (stock decrements), dev-stub an IAP pack
    (gems increase), quit/resume preserves it.

## 5. Milestones

1. `ItemShop` (slots, weighted roll, buy, timed refresh + gem-skip).
2. `DailyDeals` (stock, gem buy, ad free-claim, 24h restock).
3. `Iap` stub (packs + bundle gating/expiry/one-time).
4. Save v3 + `Game.tick_shop` runtime tick wiring.
5. `ShopPanel` overlay + Shop button + view wiring + smoke test.

**Definition of done:** the Goal paragraph, verified by playing a fresh install through
the shop loop, every number traceable to the config.

## New tuning constants (`config/curio_hall_tuning.json`)

- `shop_refresh_seconds`: item-shop free-refresh cadence. Default **3600** (1h).
- `shop_skip_gems`: gems to skip the item-shop refresh. Default **30**.
- `daily_deals_restock_seconds`: daily-deal restock cadence. Default **86400** (24h).

(Genre-standard placeholder values; the config carries no shop-refresh timing. Tunable
without code.)
