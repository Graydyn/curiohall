# Curio Hall — Phase 4b Design: Character intimacy

**Date:** 2026-09-04
**Status:** Approved design, awaiting spec review
**Depends on:** Phases 1-4a (merged), `HANDOFF.md`, `docs/creative-direction.md`
**Roadmap:** `docs/curio-hall-roadmap.md` (phase 4b of the 4a/4b/4c split; special/branch/
avatar orders become 4b2 and the story-recap reader 4b3)

## Goal

Bring the society to life: the 11 members of `docs/creative-direction.md` get their
intimacy tracks. From a fresh install a player can earn gifts by delivering orders and
buying from the gift shop, open the Society screen, give gifts to unlocked members
(preferred gifts count double), watch intimacy levels grant rewards and story unlocks,
and meet later members through the campaign-day and befriend-X unlock web, all surviving
quit/resume. Every number comes from the config.

## How it works

- **`CharacterIntimacyListConfig`** (11 rows): per character `PreferredGifts` (one of
  flower/chocolate/book/watch) and `UnlockRequirements` — a list of `day_N` (campaign
  day) and `intimacy_<Char>_<Lvl>` (another character's intimacy level) conditions.
  Ambrose (slot 11, our Ambrose Hall) is `Released: 0` — never unlockable here.
  The unlock web routes through Barnaby (our Barnaby Pluck), matching creative direction.
- **`CharacterIntimacyLevelConfig`** (300 rows = 10 released characters × 30 levels):
  per level an `Intimacy` point cost, `RewardType` (1 = item/currency rewards, 2 = story
  and background unlocks, 3 = track finisher) and `Rewards` (reward-grammar tokens plus
  story keys like `character_story_cornelia_1`, `character_intimacy_background_cornelia`).
  Each row also carries `Gifts` — weighted return-gift pools (`item-count-weight`
  triplets) — **deferred** (the "she'll give something back" feature).
- **`CharacterIntimacyGiftConfig`** (4 rows): gift types with `Intimacy` value (8-12),
  `Coin` base price, `CoinIncreasementNum`/`CoinIncreasementCost` (price escalation),
  and `Gem` price.
- **`CharacterIntimacyShopConfig`** (6 slots): slot 1 `free`, `Number: 1`, all types;
  slot 2 `gold`, `Number: 6`, all types; slots 3-6 `gem`, `Number: 3` each, one gift
  type per slot (flower/chocolate/book/watch). `Number` is the per-day stock.
- **`CharacterIntimacyCoinToGiftConfig`** (4 brackets): maps an order's coin value to a
  gift count range (1-25 → 2-3, 26-45 → 3-4, 46-75 → 4-5, 76+ → 5-6). Combined with the
  text `character_intimacy_gift_obtain_hint` ("Complete orders to earn more gifts!"),
  this is the order-delivery gift drop.
- **`CharacterIntimacyDialogConfig`** (110 rows): per character `idle`/`hello` line
  pools with `Chance` and hour `Periods` — flavor for the character screen.
- Preferred-gift bonus: the config carries no multiplier; special reaction lines exist
  (`..._gift_special_1`, `..._gift_prefer_5`). The multiplier is ours as tuning.

## Scope

**In:** the `Intimacy` sim (gift satchel, order-delivery gift drops, gift shop with
daily stock/escalation, give-gift with preferred bonus, 30-level tracks with rewards and
story-unlock flags, the unlock web), ConfigDB loading of the six `CharacterIntimacy*`
tables, the `SocietyPanel` roster + detail screen with gift shop strip, a shared cast
name map, the `tick_gifts` runtime tick, and save v6.

**Out (deferred):** return-gift pools (level rows' `Gifts` columns), Ambrose/Ambrose's
track (unreleased in config), special/branch/avatar orders (4b2), the story-recap
reader (4b3 — this phase only RECORDS story unlocks), real dialog text (the text-rewrite
track; loc keys display as placeholders), real art.

## 1. Sim: `Intimacy` (`sim/intimacy.gd`, RefCounted)

- State: `satchel: Dictionary` (`"flower"|"chocolate"|"book"|"watch"` → count),
  `tracks: Dictionary` (character name → `{level: int, points: int}`, created lazily),
  `story_unlocks: Array[String]`, shop state (`stock: Dictionary` slot → remaining,
  `coin_buys_today: int` for escalation, `restock_at: float`).
- **Gift drops from orders**: `grant_order_gifts(coins: int, rng) -> Dictionary`
  (type → count granted): pick the `CoinToGiftConfig` bracket for `coins`, roll a count
  in `NumberRange`, each gift a uniform-random type. Called from `Game.deliver_order`
  after coin credit. Emits `satchel_changed`.
- **Gift shop**: `buy_free(now)`, `buy_with_coins(type, wallet, now)`,
  `buy_with_gems(wallet, now)` → `{ok, reason}` with reasons
  `out_of_stock | not_enough_coins | not_enough_gems | bad_type`. Coin price =
  `Coin + floor(coin_buys_today / CoinIncreasementNum) * CoinIncreasementCost` per the
  gift's row. Gem slot sells only its configured `Gifts` (flowers). Stock per slot =
  `Number`, restocking (and resetting `coin_buys_today`) every
  `tuning.gift_shop_restock_seconds` (default 86400) via `tick(now)`.
- **`give_gift(name, type, game, now) -> {ok, reason}`**; reasons
  `locked | no_gift | maxed`. Consumes one gift; points +=
  `GiftConfig.Intimacy × tuning.intimacy_preferred_multiplier` (default **2**) when
  `type` is in the character's `PreferredGifts`, else ×1. While points ≥ next level's
  `Intimacy` cost: subtract, level up, and grant that level's `Rewards` — reward-grammar
  tokens through `Rewards.grant_all`; tokens matching no known item and no currency
  (story keys) append to `story_unlocks` instead of warn-and-skip (matched by a
  `_is_story_token` check against `ConfigDB.items` before falling through).
  Emits `intimacy_changed(name, level, points)`.
- **`is_unlocked(name, campaign) -> bool`**: every requirement must hold — `day_N` ⇒
  `campaign.day >= N`; `intimacy_<Char>_<L>` ⇒ that character's level ≥ L. Unreleased
  characters are never unlocked. `unlock_hint(name)` returns the raw requirement list
  for the view.
- `to_dict/from_dict` (satchel, tracks, story_unlocks, shop state). **Tick host:**
  `Game.tick_gifts(now)` calls `intimacy.tick(now)`, wired into `main.gd`'s existing
  1-second timer next to `tick_orders`/`tick_shop` — the fourth time-driven system,
  named here explicitly.

## 2. ConfigDB

`intimacy_list: Array`, `intimacy_levels: Dictionary` (character → ordered level rows),
`intimacy_gifts: Dictionary` (type → row), `intimacy_shop: Array`,
`coin_to_gift: Array`, `intimacy_dialogs: Array`. `validate()` warns if a
`PreferredGifts` entry or shop `Gifts` entry names an unknown gift type.

## 3. View

- **`Cast`** (`view/cast.gd`): the original→Curio Hall name map (cornelia→Cornelia Wren …
  ambrose→Ambrose Hall), moved out of `MapPanel` (which now consumes it) so
  `SocietyPanel` shares it. Pure const data.
- **`SocietyPanel`** (`view/society_panel.gd`, CanvasLayer modal like ShopPanel/MapPanel,
  opened by a new **Society button**, closed with an X):
  - **Roster**: all 11 members as rows — unlocked: cast name + intimacy level; locked:
    dimmed with a readable unlock hint ("Reach day 20" / "Befriend Barnaby Pluck to
    level 10"); Ambrose Hall always a "???" silhouette row.
  - **Detail view** (tap a member): cast name + placeholder portrait initial, intimacy
    level with progress bar (points / next cost), a greeting line picked from the
    dialog config (`hello` rows matching the current hour by `Chance`, falling back to
    `idle`; the loc key rendered as placeholder text), next-level reward preview
    (reward tokens as text), and four **gift buttons** showing satchel counts, the
    intimacy each grants, and a ★ on the preferred type; disabled at count 0.
  - **Gift shop strip**: the free slot (claim button + stock), coin slot (current
    escalated price), gem slot; disabled when out of stock/unaffordable.
  - Listens to `satchel_changed` / `intimacy_changed` / `wallet.changed`; re-render
    rebuilds only inner containers. One 1-second Timer refreshes the restock countdown,
    parented on the CanvasLayer root — never inside the rebuilt list (the phase-2
    self-freeing-timer trap). The restock itself happens in the sim via `tick_gifts`.
  - New `REJECT_MESSAGES`: `no_gift`, `maxed`, `bad_type` (locked/out_of_stock/
    not_enough_* already exist).
- `main.tscn`: SocietyButton + SocietyPanel nodes; `main.gd` wiring + save-pending on
  `satchel_changed`/`intimacy_changed`.

## 4. Persistence

**Save v5 → v6**: adds the `intimacy` block; `SaveManager` requires the key; version
mismatch backs up and resets per convention.

## 5. Error handling & testing

- All spends check-then-mutate (wallet spends already atomic; gift consumption checks
  count first). Rejections return reasons, surfaced by the existing toast.
- **Testing** (GUT, sim-layer TDD; free board cells before any board-place assertions):
  - CoinToGift brackets: boundary coin values map to counts within range; gift types
    valid; deliver_order grants gifts (seeded RNG).
  - Shop: free claim once per day; coin price escalates per `CoinIncreasementNum`;
    gem slot sells flowers only and caps at stock; restock resets stock, buys, prices;
    rejections without state change.
  - give_gift: consumes, adds points, preferred ×2, multi-level-up loop, level rewards
    granted, story tokens recorded not warn-skipped, `locked`/`no_gift`/`maxed`.
  - Unlock web: day gate, cross-character intimacy gate, Ambrose never unlocks.
  - Save v6 roundtrip (satchel, tracks, story flags, shop state incl. offline restock);
    fresh defaults.
  - Smoke: deliver an order → gifts appear → give a preferred gift → points double,
    level 1 reached, reward granted; quit/resume preserves it.
- Headless boot + full suite via `./curio-hall/test.sh`; `godot --headless --import`
  after new class_name scripts.

## 6. Milestones

1. ConfigDB intimacy tables + config copies.
2. `Intimacy` sim: satchel, order gift drops, give_gift/levels/story flags, unlock web.
3. Gift shop (stock, escalation, restock) + `Game.tick_gifts` + save v6.
4. `Cast` + `SocietyPanel` + Society button + smoke test.

**Definition of done:** the Goal paragraph, verified on a fresh install, every number
traceable to the config.

## New tuning constants (`config/curio_hall_tuning.json`)

- `intimacy_preferred_multiplier`: **2** (config carries no value; reaction lines prove
  the mechanic exists).
- `gift_shop_restock_seconds`: **86400** (daily cadence implied by the shop's slot
  design; config carries no timer, same as the phase-3 shop).
