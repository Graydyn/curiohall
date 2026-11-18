# Membership — design

**Date:** 2026-11-17
**Status:** Draft, awaiting approval
**Replaces:** the real-money half of Phase 3 (`sim/iap.gd` gem packs + starter bundle)

## Intent

Most merge games earn money through escalating, pay-per-pack pressure. Curio Hall
shouldn't. Real money buys exactly one thing: a **30-day membership pass**, giving a
predictable, capped amount of comfort and a clear edge in events. The same membership
comes free with **Google Play Pass**. Nothing else is for sale for real money.

## Goals

- One real-money product: a 30-day pass, bought by hand each time. It **never renews
  automatically**.
- Members get, every local day: a **gem allowance** (paid automatically) and an
  **energy refill they claim when they choose** (+100, can go over the cap).
- Members get an **event edge**: their main-game orders drop a tier-2 event feed item
  instead of tier-1, so they reach exactly one prize tier higher for the same play. Events
  are tuned so a steady free player reaches the **second-to-last** prize tier and a steady
  member reaches the **last**.
- Event prizes **get better at each tier**. The final prize is the largest single one,
  but **at most 25% of the event's total prize value**, so a free player who falls
  short still collects most of the value.
- Play Pass and the bought pass feed the same `member_until` date, so the rest of the
  game never knows which source applied.

## Non-goals

- Real Google Play Billing / Play Pass detection. Payment stays a **DEV stub**, as it
  is today. Real billing is deferred until there's a shipped app (see roadmap Phase 3).
  How Google tells a game that a player has Play Pass still needs checking against
  Google's partner docs before billing work starts. That doesn't affect this design.
- iOS / App Store.
- A free-vs-member event budget model (energy per order etc.). Deferred; tune by play later.
- Rebalancing gem sinks (order skip 30, shop skip 30, deals 10–25). They stay as they are.

## Anti-goals (a failure even if it works)

- Any real-money gem pack, bundle, starter offer, limited-time deal, or discount bait.
- Countdown pressure or urgency messaging around the pass.
- Letting a player stack a large block of time in one go ("buy a year in a moment
  of weakness").
- A final event prize that dwarfs the rest, which would make missing it feel like
  losing the event.
- Old pay-per-pack code left in place behind a config switch.

## Approaches considered

1. **New `Membership` sim piece + perks set in config (chosen).** A clean new class,
   with perks as reward tokens in the tuning file and the old IAP removed. The most
   up-front work, but no leftover paid-offer code, and the adjustable values live in
   config with tests watching them.
2. **Add the pass into `Iap`.** A smaller change, but it keeps the pay-per-pack code one
   config edit away from coming back. Rejected because it undercuts the intent.
3. **A general entitlements system.** Built for future products the user has said they
   don't want. Rejected as over-built: one `member_until` date already covers both sources.

## Design

### 1. Sim: `Membership` (`sim/membership.gd`, new; replaces `sim/iap.gd`)

`RefCounted`, pure logic, with `now` injected like every other sim piece.

State (saved):
- `member_until: float`: unix seconds; `0.0` = never a member.
- `last_perk_day: int`: local day index the gem allowance was last paid for; `-1` = never.
- `last_refill_day: int`: local day index the energy refill was last claimed; `-1` = never.
- `play_pass: bool`: DEV toggle standing in for Play Pass detection. While true,
  `is_member` is true whatever `member_until` says.

API:
- `is_member(now) -> bool`: `play_pass or now < member_until`.
- `days_left(now) -> int`: whole days remaining (ceil), 0 if not a member. Play Pass
  reports no days count (the view shows "via Play Pass").
- `buy_pass(now) -> {ok, reason}`: **DEV stub**, with no payment. Rejected with reason
  `"play_pass"` while `play_pass` is true (it's already included, and Play Pass
  requires no purchases). Otherwise `member_until = max(now, member_until) + pass_days`.
  Rejected with reason `"stack_limit"` if the result would be more than
  `membership_max_days_ahead` days past `now`.
- `tick(game, now, day: int)`: if `is_member(now)` and `day > last_perk_day`, grant
  `membership_daily_rewards` (the gem allowance) through `Rewards.grant_all` and set
  `last_perk_day = day`. Missed days are **not** paid back. Only the current day pays.
  Non-members do not advance `last_perk_day`, so someone who joins mid-day is paid that day.
- `refill_available(now, day) -> bool`: `is_member(now) and day > last_refill_day`.
- `claim_refill(game, now, day) -> {ok, reason}`: the member's **once-a-day energy
  refill, claimed when they choose**. Grants `membership_refill_rewards` (default
  `["energy-100"]`) through `Rewards.grant_all`. That's a plain add, so it **can go over
  the cap**. Then sets `last_refill_day = day`. Reasons: `"not_member"`,
  `"already_claimed"`. An unclaimed refill is lost at the end of the day (no banking).
- `reminder(now) -> String`: `""`, `"ending_soon"` (≤ `membership_reminder_days`
  left), or `"last_day"` (< 1 day left). Never shown for Play Pass.
- `to_dict / from_dict`.
- `signal membership_changed`.

**Local day.** The sim stays clock-agnostic: `day` is passed in. `Game.local_day(now)`
computes `floor((now + tz_offset_seconds) / 86400)`, where `tz_offset_seconds` comes
from `Time.get_time_zone_from_system()` at the call site in `scenes/main.gd`. Tests pass
`day` directly.

### 2. Why the refill is claimed, not automatic

An automatic "top up to full" at the start of each day almost never did anything.
Energy regenerates from empty to the 100 cap in about 3h20m, so a member opening the game
in the morning is usually already full. A claimed +100 that can go over the cap always
helps, and the member chooses when. *(Changed after the builder check; user agreed.)*
The refill is now a **comfort perk**. The event edge comes from §7, not from energy.

### 3. Tuning (`config/curio_hall_tuning.json`)

New keys:
- `membership_pass_days`: 30
- `membership_max_days_ahead`: 60
- `membership_reminder_days`: 3
- `membership_daily_rewards`: `["gem-20"]`. **20 gems/day is the builder's starting
  value** (≈ 600/month, about two gem-skips every three days). The user can adjust it.
- `membership_refill_rewards`: `["energy-100"]`.
- `event_member_feed_item`: `"pb_dogpark_tar_2"` (see §7).
- `membership_price_label`: display string for the DEV button, e.g. `"$4.99 / 30 days"`.
  The price is not decided; this is a placeholder.

### 4. Removing the pay-per-pack IAP

- Delete `sim/iap.gd`, `test/unit/test_iap.gd`, `ConfigDB.iap_packs`/`bundles` and the
  loading of `ShopIAPConfig.json` / `BundleConfig.json`. Delete those two config files
  and `ShopIAPConfigCN.json`.
- Remove `Game.buy_iap_pack`, `Game.buy_bundle`, `Game.iap`, and the `"iap"` save key.
  Add `Game.membership`, `Game.buy_pass(now)`, `Game.tick_membership(now, day)`.
- Update the tests that touch IAP (`test_shop_game`, `test_smoke`, `test_shop_config`).
  `test_smoke`'s `buy_iap_pack` gem grant becomes a direct gem grant or `buy_pass` + tick.

### 5. Ad-gated daily deal

Play Pass forbids ads for subscribers. Today the ad deal (id 2, `ad: 1`, 10 gems) has
no ad step in the sim. `DailyDeals.buy` charges gems for everyone, and "(watch ad, dev
free)" is only a label in `view/shop_panel.gd`. So **the sim does not change**. Members
see the deal without the ad label. When a real ad SDK arrives, the ad step must be
skipped for members (note for that future work). *(Builder-check call.)*

### 6. Event prize ladder (expedition)

- Replace the single `event_end_rewards` with **per-tier prizes**:
  `event_tier_rewards`, a tuning list indexed by feed-chain tier (12 tiers for
  `pb_dogpark_tar_*`), each an array of reward tokens (empty array = no prize at that tier).
  A tier's prize is granted once, when `best_tier` first reaches it, in
  `Events.record_merge`. Save the highest tier already paid (`paid_tier`) so prizes can't
  be paid twice across save/load.
- **Prize value** for comparing tiers: a pure helper `Rewards.value(token)` using
  tuning weights `reward_value_weights` (e.g. gem = 1, energy = 0.3, gold = 0.05, exp = 0,
  item = a flat per-item weight). The weights are the builder's call, documented in the tuning file.
- **Test-enforced rules** (`test_event_prizes.gd`):
  1. Tier prize values never decrease from one prized tier to the next.
  2. The final tier's value is the largest single one.
  3. The final tier's value ≤ 25% of the sum over all tiers.
- The builder authors the starting `event_tier_rewards` to satisfy these rules. Final
  values are for the user to adjust.

### 7. The member event edge: richer order drops

Each delivered main order drops one tier-1 feed item (`event_feed_item`) onto the
expedition's supply row (`Events.on_order_delivered`). **For members, it drops a tier-2
feed item (`event_member_feed_item`) instead.** `on_order_delivered` reads
`game.membership.is_member(now)` to choose.

Why tier-2 rather than extra items or a chance of a bonus:
- Each prize tier needs **twice** the feed of the one before, so reaching one tier
  higher takes double the input. A tier-2 item is exactly two tier-1s, so a member who
  plays the same amount reaches **exactly one tier higher**. That's the free-falls-short,
  member-finishes split, and it holds across play styles. A smaller bonus gives a fraction
  of a tier and makes "just short" unreliable.
- It uses one supply-row slot, not two. Items are lost when the row is full (existing
  behaviour), and an extra-item version would make that happen more often.

The merge-tier prize ladder (§6) stays as it is (user: tier-based prizes are essential).

**General rule for future event types:** whatever drives an event's progress, a member's
contribution counts double.

**Tuning:** this ships with the doubling as the only check. A unit test asserts that
members get the tier-2 item and free players the tier-1 item. A full free-vs-member
budget model (energy per order, steady-play fraction) is **deferred**. The user will tune
by play later.

The **Gala** needs no member bonus: its daily tasks are small (2–5 orders), everyone
finishes them, and members get the comfort of the extra energy there.

### 8. View

- **Shop panel**: the "Get Gems (DEV STUB)" section becomes **"Membership"**:
  - Non-member: perks listed plainly ("A free energy refill each day", "N gems each
    day", "Double progress in events"), the price label, and a **"Buy 30 days (DEV)"**
    button.
  - Member: "Member: N days left" (or "via Play Pass"), the same perk list, and the buy
    button labelled "Add 30 days (DEV)", disabled with a reason at the stack limit.
  - A **"Claim today's energy refill"** button, enabled when `refill_available`. It also
    appears as a small HUD button next to the energy readout while a refill is
    available, since that's where a drained player looks.
  - Play Pass on: "Included with Play Pass", no buy button.
  - A **DEV "Play Pass" toggle**, clearly labeled.
- **Reminder**: a toast through the existing main-scene toast, at most once per local
  day, when `reminder()` is non-empty: "Your membership ends in N days" /
  "Your membership ends today". Calm wording, no discount, no countdown timer.
- **Rejection messages**: add `stack_limit`, `play_pass`, `not_member`,
  `already_claimed` to `REJECT_MESSAGES`; remove `locked`,
  `already_bought`, `expired` if nothing else uses them.

### 9. Ticks and persistence

- `scenes/main.gd`'s existing 1-second timer calls
  `game.tick_membership(now, game.local_day(now))` alongside the other ticks, so the gem
  allowance pays on the first tick of a new day without opening any panel, and on launch.
  `Game.claim_refill(now)` wraps `membership.claim_refill` with `local_day(now)`.
- **Save v11.** Replace the `"iap"` key with `"membership"` in `Game.to_dict/from_dict`
  and the `SaveManager` key list. Following existing practice, old-version saves reset on
  upgrade; no migration.

## Decisions log (user)

- Subscription-style membership instead of bundles; the same benefits via Play Pass.
- Event edge = extra access (option C), not a separate reward track or speed buff.
- Free players typically fall just short of finishing an event.
- Prizes get better at each tier; the final prize is the biggest single one but much
  smaller than all the others combined.
- Energy perk = daily refill, claimed by the member (+100, can go over the cap). Changed
  from an automatic top-up after the builder check showed the top-up rarely did anything.
- 30-day pass bought by hand, never auto-renewing.
- Build approach 1.
- Merge-tier prizes are essential and stay. The member event edge = member orders drop a
  tier-2 feed item (one tier higher for the same play). Tuning the exact split is deferred
  to playtesting.

## Calls made on the user's behalf (open to change)

- No real-money gems at all; packs, starter bundle, CN pack config deleted.
- Gem allowance paid daily (not a monthly lump), starting at 20/day.
- Unclaimed refills are lost at the end of the day (no banking).
- The Gala gets no member bonus; future event types count member contributions double.
- Play Pass players can't buy the pass (it's already included); buying extends from
  `max(now, member_until)`.
- Day boundary = player's local midnight.
- Buying while active extends; stack cap 60 days ahead.
- Reminders at 3 days and on the last day, counted in local calendar days ("ends today" only on the day it actually ends).
- Paid days pause while Play Pass applies and resume when it ends (final review).
- On lapse: earned gems are kept, perks stop, event tiers already reached are kept.
- Final prize ≤ 25% of total event prize value.
- The ad daily deal: no sim change; members just don't see the ad label.

## Left to the builder

- `reward_value_weights` starting values, with reasoning.
- Starting `event_tier_rewards` values within the test-enforced rules.
- Exact view layout and copy within the wording rules above.
