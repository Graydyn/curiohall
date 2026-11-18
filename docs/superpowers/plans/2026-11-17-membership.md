# Membership Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the pay-per-pack IAP with a single 30-day membership pass (gem allowance, claimable daily energy refill, tier-2 event feed for members) and give the expedition a per-tier prize ladder.

**Architecture:** A new pure-sim `Membership` (`sim/membership.gd`) owns pass dates and daily-perk bookkeeping; `Game` wraps it with a local-day clock and replaces `Iap`. `Events` reads membership to pick the feed item and pays a config-driven prize per tier. The view swaps the shop's "Get Gems" section for a Membership section and adds a HUD refill button.

**Tech Stack:** Godot 4 / GDScript, GUT unit tests (`./test.sh`).

**Spec:** `docs/superpowers/specs/2026-11-17-membership-design.md`

## Global Constraints

- Payment stays a DEV stub. Every buy/toggle control is labeled `(DEV)`. No real billing code.
- No real-money gems, packs, bundles, discounts, or countdown-pressure copy anywhere.
- Sim classes are `RefCounted`, take `now` injected, grant only through `Rewards`.
- All numbers come from `config/curio_hall_tuning.json`. New keys, exact values:
  `membership_pass_days: 30`, `membership_max_days_ahead: 60`, `membership_reminder_days: 3`,
  `membership_daily_rewards: ["gem-20"]`, `membership_refill_rewards: ["energy-100"]`,
  `membership_price_label: "$4.99 / 30 days"`, `event_member_feed_item: "pb_dogpark_tar_2"`,
  `event_tier_rewards` (Task 3), `reward_value_weights` (Task 3). Remove `event_end_rewards`.
- `SAVE_VERSION` becomes 11. Old saves reset (existing behaviour). No migration.
- Reminder copy: "Your membership ends in N days" / "Your membership ends today". Nothing else.
- Run the full suite with `./test.sh`. A single file:
  `godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/<file>.gd -gexit`.

## Review Focus

1. **Members skip the tier-2 prize.** Members' feed starts at tier 2, so their first merge makes tier 3. Every unpaid tier ≤ the new tier must be paid, not just the new one. → Task 3 test `test_member_first_merge_pays_skipped_tiers`.
2. **Buying a pass after a lapse** must start from `now`, not from the old `member_until` (otherwise they pay for days already gone). → Task 1 `test_buy_after_lapse_starts_from_now`.
3. **Crossing midnight with the game open** must pay the gem allowance and make a new refill available without a relaunch. → Task 2 `test_tick_across_midnight_pays_again`.
4. **Time zone:** the day boundary is local midnight, not UTC. → Task 2 `test_local_day_uses_offset`.
5. **Prize double-pay across save/load or a second top merge.** → Task 3 `test_prizes_survive_round_trip_without_repaying`.

---

### Task 1: `Membership` sim class

**Files:**
- Create: `sim/membership.gd`
- Modify: `config/curio_hall_tuning.json` (add the six `membership_*` keys from Global Constraints)
- Test: `test/unit/test_membership.gd`

**Interfaces:**
- Produces (`class_name Membership extends RefCounted`):
  - vars `member_until: float = 0.0`, `last_perk_day: int = -1`, `last_refill_day: int = -1`, `last_reminder_day: int = -1`, `play_pass: bool = false`
  - `signal membership_changed`
  - `is_member(now: float) -> bool`
  - `days_left(now: float) -> int`: `ceil((member_until - now) / 86400)`, min 0. Returns 0 when only Play Pass applies.
  - `buy_pass(now: float) -> Dictionary` (`{ok, reason}`; reasons `"play_pass"`, `"stack_limit"`)
  - `set_play_pass(on: bool) -> void`
  - `tick(game, now: float, day: int) -> void` (pays the gem allowance)
  - `refill_available(now: float, day: int) -> bool`
  - `claim_refill(game, now: float, day: int) -> Dictionary` (reasons `"not_member"`, `"already_claimed"`)
  - `take_reminder(now: float, day: int) -> String`: returns `"ending_soon"` / `"last_day"` / `""`. Returns non-empty at most once per `day` (records `last_reminder_day`). Always `""` while `play_pass`.
  - `to_dict() -> Dictionary`, `static from_dict(d: Dictionary) -> Membership`
  - Every state change emits `membership_changed`.

- [ ] **Step 1: Write the failing tests** in `test/unit/test_membership.gd`. Use `const DAY := 86400.0`, `const NOW := 1000.0`, and `var g := Game.fresh(NOW, 42)` for the `game` argument (Task 1 doesn't need `Game.membership`):

```gdscript
func test_not_member_by_default() -> void:
    var m := Membership.new()
    assert_false(m.is_member(NOW))
    assert_eq(m.days_left(NOW), 0)

func test_buy_pass_gives_30_days() -> void:
    var m := Membership.new()
    assert_true(m.buy_pass(NOW)["ok"])
    assert_eq(m.member_until, NOW + 30 * DAY)
    assert_true(m.is_member(NOW + 30 * DAY - 1.0))
    assert_false(m.is_member(NOW + 30 * DAY))
    assert_eq(m.days_left(NOW), 30)

func test_buy_while_active_extends() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    assert_true(m.buy_pass(NOW + 10 * DAY)["ok"])
    assert_eq(m.member_until, NOW + 60 * DAY)

func test_stack_limit_60_days_ahead() -> void:
    var m := Membership.new()
    m.buy_pass(NOW); m.buy_pass(NOW)            # exactly 60 ahead: allowed
    assert_eq(m.buy_pass(NOW)["reason"], "stack_limit")
    assert_eq(m.member_until, NOW + 60 * DAY)   # unchanged on rejection

func test_buy_after_lapse_starts_from_now() -> void:
    var m := Membership.new()
    m.buy_pass(NOW)
    var later := NOW + 45 * DAY
    m.buy_pass(later)
    assert_eq(m.member_until, later + 30 * DAY)

func test_play_pass_is_member_and_blocks_buying() -> void:
    var m := Membership.new()
    m.set_play_pass(true)
    assert_true(m.is_member(NOW))
    assert_eq(m.buy_pass(NOW)["reason"], "play_pass")
    assert_eq(m.member_until, 0.0)

func test_tick_pays_gem_allowance_once_per_day() -> void:
    var m := Membership.new(); m.buy_pass(NOW)
    var gems := g.wallet.gems
    m.tick(g, NOW, 5); m.tick(g, NOW + 60.0, 5)
    assert_eq(g.wallet.gems, gems + 20)
    m.tick(g, NOW + DAY, 6)
    assert_eq(g.wallet.gems, gems + 40)

func test_tick_does_not_back_pay_missed_days() -> void:
    var m := Membership.new(); m.buy_pass(NOW)
    var gems := g.wallet.gems
    m.tick(g, NOW, 5); m.tick(g, NOW + 3 * DAY, 8)
    assert_eq(g.wallet.gems, gems + 40)

func test_non_member_tick_pays_nothing_and_join_mid_day_pays() -> void:
    var m := Membership.new()
    var gems := g.wallet.gems
    m.tick(g, NOW, 5)
    assert_eq(g.wallet.gems, gems)
    m.buy_pass(NOW + 60.0); m.tick(g, NOW + 60.0, 5)
    assert_eq(g.wallet.gems, gems + 20)

func test_refill_adds_100_over_cap_once_per_day() -> void:
    var m := Membership.new(); m.buy_pass(NOW)
    assert_eq(g.wallet.energy(NOW), 100)
    assert_true(m.refill_available(NOW, 5))
    assert_true(m.claim_refill(g, NOW, 5)["ok"])
    assert_eq(g.wallet.energy(NOW), 200)
    assert_eq(m.claim_refill(g, NOW, 5)["reason"], "already_claimed")
    assert_false(m.refill_available(NOW, 5))
    assert_true(m.refill_available(NOW + DAY, 6))

func test_refill_rejected_for_non_member() -> void:
    var m := Membership.new()
    assert_false(m.refill_available(NOW, 5))
    assert_eq(m.claim_refill(g, NOW, 5)["reason"], "not_member")

func test_reminder_once_per_day() -> void:
    var m := Membership.new(); m.buy_pass(NOW)
    assert_eq(m.take_reminder(NOW, 0), "")
    var t := NOW + 27 * DAY + 1.0                  # 3 days left (ceil)
    assert_eq(m.take_reminder(t, 27), "ending_soon")
    assert_eq(m.take_reminder(t, 27), "")
    var last := NOW + 30 * DAY - 3600.0            # < 1 day left
    assert_eq(m.take_reminder(last, 29), "last_day")

func test_no_reminder_on_play_pass() -> void:
    var m := Membership.new(); m.set_play_pass(true)
    assert_eq(m.take_reminder(NOW, 0), "")

func test_round_trip() -> void:
    var m := Membership.new()
    m.buy_pass(NOW); m.last_perk_day = 4; m.last_refill_day = 3; m.last_reminder_day = 2; m.play_pass = true
    var m2 := Membership.from_dict(m.to_dict())
    assert_eq(m2.member_until, m.member_until)
    assert_eq([m2.last_perk_day, m2.last_refill_day, m2.last_reminder_day], [4, 3, 2])
    assert_true(m2.play_pass)
```

- [ ] **Step 2: Run** the file. Expected: FAIL (`Membership` not found).
- [ ] **Step 3: Implement `sim/membership.gd`** and add the tuning keys. `buy_pass` computes `max(now, member_until) + pass_days*86400` and rejects if that is `> now + max_days_ahead*86400`. `tick` and `claim_refill` grant via `Rewards.grant_all(ConfigDB.tuning[...], game, now)`. `"ending_soon"` = `days_left(now) <= membership_reminder_days` and `member_until - now >= 86400`; `"last_day"` = `0 < member_until - now < 86400`.
- [ ] **Step 4: Run** the file. Expected: all pass.
- [ ] **Step 5: Commit** `feat: Membership sim (30-day pass, gem allowance, daily refill)`.

---

### Task 2: Wire membership into `Game`; remove the IAP; save v11

**Files:**
- Modify: `sim/game.gd`, `sim/save_manager.gd:22-27`, `sim/config_db.gd:19-20,108-109`
- Delete: `sim/iap.gd` (+ `.uid`), `test/unit/test_iap.gd` (+ `.uid`), `config/ShopIAPConfig.json`, `config/BundleConfig.json`, `config/ShopIAPConfigCN.json`
- Modify tests: `test/unit/test_shop_game.gd:22`, `test/unit/test_smoke.gd:133`, `test/unit/test_shop_config.gd` (drop `iap_packs`/`bundles` asserts and `test_iap_pack_shape`/`test_bundle_shape`)
- Test: `test/unit/test_membership_game.gd`

**Interfaces:**
- Consumes: Task 1's `Membership`.
- Produces on `Game`:
  - `var membership: Membership` (created in `fresh`, saved under key `"membership"`)
  - `var tz_offset_seconds: int = 0` (not saved; `scenes/main.gd` sets it at startup)
  - `local_day(now: float) -> int`: `floori((now + tz_offset_seconds) / 86400.0)`
  - `tick_membership(now: float) -> void` → `membership.tick(self, now, local_day(now))`
  - `buy_pass(now: float) -> Dictionary`, `claim_refill(now: float) -> Dictionary`, `refill_available(now: float) -> bool`, `take_membership_reminder(now: float) -> String`, `set_play_pass(on: bool) -> void`
  - Removed: `iap`, `buy_iap_pack`, `buy_bundle`. `ConfigDB.iap_packs` and `ConfigDB.bundles` are gone.
  - `SAVE_VERSION := 11`. The SaveManager key list replaces `"iap"` with `"membership"`.

(The spec writes `tick_membership(now, day)`. The plan computes the day inside `Game` so callers can't pass a mismatched one. Same behaviour.)

- [ ] **Step 1: Write failing tests** in `test/unit/test_membership_game.gd`:

```gdscript
func test_fresh_game_has_membership_not_member() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_not_null(g.membership)
    assert_false(g.membership.is_member(1000.0))

func test_local_day_uses_offset() -> void:
    var g := Game.fresh(1000.0, 42)
    var t := 86400.0 * 100 + 3600.0          # 01:00 UTC on day 100
    assert_eq(g.local_day(t), 100)
    g.tz_offset_seconds = -2 * 3600           # UTC-2: still 23:00 on day 99
    assert_eq(g.local_day(t), 99)

func test_tick_across_midnight_pays_again() -> void:
    var g := Game.fresh(1000.0, 42)
    var t := 86400.0 * 100 + 86000.0         # 400s before midnight
    g.buy_pass(t)
    var gems := g.wallet.gems
    g.tick_membership(t)
    g.tick_membership(t + 500.0)               # next local day
    assert_eq(g.wallet.gems, gems + 40)
    assert_true(g.refill_available(t + 500.0))

func test_claim_refill_via_game() -> void:
    var g := Game.fresh(1000.0, 42)
    g.buy_pass(1000.0)
    assert_true(g.claim_refill(1000.0)["ok"])
    assert_eq(g.claim_refill(1000.0)["reason"], "already_claimed")

func test_save_round_trip_keeps_membership() -> void:
    var g := Game.fresh(1000.0, 42)
    g.buy_pass(1000.0)
    g.claim_refill(1000.0)
    var g2 := Game.from_dict(g.to_dict())
    assert_eq(g2.membership.member_until, g.membership.member_until)
    assert_eq(g2.membership.last_refill_day, g.membership.last_refill_day)
    assert_eq(int(g.to_dict()["save_version"]), 11)
    assert_false(g.to_dict().has("iap"))
```

- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement** the `Game` API above. Delete the IAP files, ConfigDB fields and loads, and the `Game` IAP methods. Update the SaveManager key list and its comment ("v10 saves reset on upgrade to v11"). Fix the three existing tests: `test_shop_game` asserts `g.membership` not null; `test_smoke` replaces `g.buy_iap_pack("getgem_1", 1000.0)` with `g.wallet.add_gems(100)`.
- [ ] **Step 4: Run** `./test.sh`. Expected: all pass, and no remaining references (`grep -rn "iap\|Iap\|bundle" sim test view scenes` shows only unrelated hits). `view/shop_panel.gd` still references `game.iap` until Task 4, so do Task 4's shop-panel removal of the "Get Gems" block here as well, replacing it with a single `_label("-- Membership --")` placeholder so the project parses.
- [ ] **Step 5: Commit** `feat: membership on Game; remove gem packs and starter bundle; save v11`.

---

### Task 3: Expedition member feed + per-tier prize ladder

**Files:**
- Modify: `sim/events.gd` (`on_order_delivered`, `record_merge`, `start_event`, `to_dict/from_dict`), `sim/rewards.gd` (add `value`), `config/curio_hall_tuning.json`
- Modify test: `test/unit/test_events.gd` (`test_completion_grants_end_rewards_once` → final-tier prize amounts)
- Test: `test/unit/test_event_prizes.gd`

**Interfaces:**
- Consumes: `game.membership.is_member(now)` (Task 2).
- Produces:
  - `Events.paid_tier: int = 0` (saved; reset to 0 in `start_event`)
  - `Events.on_order_delivered(game, now)` drops `event_member_feed_item` for members, `event_feed_item` otherwise
  - `Events.record_merge(new_type, game, now)`: after updating `best_tier`, grants `event_tier_rewards[t-1]` for every tier `t` in `paid_tier+1 .. new tier`, then sets `paid_tier`. `completed` is still set when the chain top is reached (the event panel uses it). Remove the `event_end_rewards` grant and key.
  - `static Rewards.value(token: String) -> float`: `amount × reward_value_weights[kind]` (kinds `coins`, `gems`, `energy`, `xp`, `item`, using `parse()`'s kind names).

Tuning values (12 entries, index 0 = tier 1; values as computed by `Rewards.value`):

```json
"reward_value_weights": {"gems": 1.0, "energy": 0.3, "coins": 0.05, "xp": 0.0, "item": 5.0},
"event_tier_rewards": [[], ["energy-20"], ["gem-8"], ["energy-40"], ["gem-15"],
  ["gem-10", "energy-30"], ["gem-25"], ["gem-20", "energy-50"], ["gem-40"],
  ["gem-35", "energy-60"], ["gem-60"], ["gem-60", "energy-100"]]
```
(Values 0, 6, 8, 12, 15, 19, 25, 35, 40, 53, 60, 90; total 363; final 24.8%.)

- [ ] **Step 1: Write failing tests** in `test/unit/test_event_prizes.gd`:

```gdscript
func _tier_value(i: int) -> float:
    var v := 0.0
    for t in ConfigDB.tuning["event_tier_rewards"][i]:
        v += Rewards.value(String(t))
    return v

func test_ladder_has_one_entry_per_chain_tier() -> void:
    assert_eq((ConfigDB.tuning["event_tier_rewards"] as Array).size(), 12)

func test_prizes_never_decrease() -> void:
    var prev := 0.0
    for i in range(12):
        var v := _tier_value(i)
        if v > 0.0:
            assert_true(v >= prev, "tier %d" % (i + 1)); prev = v

func test_final_prize_is_largest_and_at_most_quarter() -> void:
    var total := 0.0; var biggest := 0.0
    for i in range(12):
        total += _tier_value(i); biggest = max(biggest, _tier_value(i))
    assert_eq(_tier_value(11), biggest)
    assert_true(_tier_value(11) <= 0.25 * total)

func test_member_order_drops_tier_2_feed() -> void   # deliver path: g.buy_pass(NOW); g.dev_start_event(NOW); g.events.on_order_delivered(g, NOW); supply row (y = board.height-1) holds "pb_dogpark_tar_2"
func test_free_order_drops_tier_1_feed() -> void     # same without buy_pass → "pb_dogpark_tar_1"
func test_merge_to_tier_2_pays_tier_2_prize() -> void  # two tar_1 on supply row, merge_event → energy +20, paid_tier == 2
func test_member_first_merge_pays_skipped_tiers() -> void  # two tar_2 merged → tar_3: energy +20 AND gems +8, paid_tier == 3
func test_prizes_survive_round_trip_without_repaying() -> void  # pay tier 2, Events.from_dict(to_dict()), merge two more tar_1 → tier 2 again: no extra energy
```

(The last five follow `test_events.gd`'s pattern: `b.spawn(type, Vector2i(x, 13))`, `g.merge_event(a, b, NOW)`. Spend energy to below cap before asserting energy grants, since grants can go over the cap but the reading is easier from below. **Watch out:** a supply-row merge also unboxes the cell above it, which can pay a paperbox token (`ConfigDB.event_paperbox_reward("dogpark", pos)`). Either pick merge positions whose shocked cells carry no token, or add those tokens to the expected totals.)

- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement** as in Interfaces. Update `test_completion_grants_end_rewards_once`: the final merge pays all unpaid tiers up to 12. With an empty `paid_tier` that's every gem prize = 273 gems. Assert gems `+273`, then no change on the second top merge.
- [ ] **Step 4: Run** `./test.sh`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: expedition prize ladder and tier-2 feed for members`.

---

### Task 4: View: Membership shop section, HUD refill, ticks, reminders

**Files:**
- Modify: `view/shop_panel.gd` (replace the placeholder from Task 2; ad label), `view/hud.gd`, `scenes/main.gd` (tz offset, tick, save signal, reminder toast, `REJECT_MESSAGES`), `docs/curio-hall-roadmap.md`
- Test: `test/unit/test_shop_panel_membership.gd`

**Interfaces:**
- Consumes: Task 2's `Game` membership API.
- Produces: `ShopPanel._membership_status: Label` and `ShopPanel._buy_pass_btn: Button` (for tests; rebuilt in `refresh()`); `Hud._refill_btn: Button`.

Copy (exact):
- Perks: `"A free energy refill each day"`, `"%d gems each day" % gems`, `"Double progress in events"`. `gems` comes from `membership_daily_rewards`.
- Status: non-member `"Not a member"`; member `"Member: %d days left"`; Play Pass `"Included with Play Pass"`.
- Buttons: `"Buy 30 days (DEV) — %s" % price_label` (non-member), `"Add 30 days (DEV)"` (member; disabled when adding would exceed the stack limit), no buy button on Play Pass; `"Claim today's energy refill"` (enabled when `refill_available`); `"Play Pass (DEV): ON"/"OFF"` toggle.
- HUD: `_refill_btn.text = "Refill +100"`, visible only while `game.refill_available(now)`.
- Ad deal tag shows only when `deal["is_ad"] and not game.membership.is_member(now)`.
- `REJECT_MESSAGES`: add `"stack_limit": "You can hold at most 60 days of membership"`, `"play_pass": "Included with Play Pass"`, `"not_member": "Members only"`, `"already_claimed": "Already claimed today"`, `"ending_soon": "Your membership ends in %d days"` (formatted with `days_left` by the caller), `"last_day": "Your membership ends today"`. Remove `locked`, `already_bought`, `expired` (`grep` first: remove only if unused).

- [ ] **Step 1: Write failing tests** in `test/unit/test_shop_panel_membership.gd` (pattern: `test_info_panel.gd`; set `p.visible = true` before `p.refresh()`):

```gdscript
func test_non_member_sees_buy_button() -> void      # _membership_status.text == "Not a member"; _buy_pass_btn.text begins_with "Buy 30 days (DEV)"
func test_buy_pass_button_makes_member() -> void    # _buy_pass_btn.pressed.emit() → g.membership.is_member(now); after refresh status begins_with "Member: 30 days left"
func test_play_pass_hides_buy_button() -> void      # g.set_play_pass(true); refresh → status "Included with Play Pass"; _buy_pass_btn == null or not visible
func test_hud_refill_button_visibility() -> void    # Hud non-member: hidden; after g.buy_pass: visible; pressed → energy +100 and hidden
```

- [ ] **Step 2: Run** the file. Expected: FAIL.
- [ ] **Step 3: Implement.** In `main.gd`'s `_ready`, set `game.tz_offset_seconds = int(Time.get_time_zone_from_system()["bias"]) * 60`. Add `game.membership.membership_changed` to the `_save_pending` signal list. In `_flush_save`, call `game.tick_membership(now)`, then show `game.take_membership_reminder(now)` through the toast when non-empty. `ShopPanel` connects `membership_changed` to `refresh`. Roadmap: add a "Membership ✅" entry under Phase 3 noting the gem packs and bundle are gone and billing is still stubbed.
- [ ] **Step 4: Run** `./test.sh`. Expected: all pass. Then launch the game (`godot --path .`, or the project's run skill), open the shop, buy a pass, claim the refill, and toggle Play Pass. Confirm the labels above and that the HUD button disappears after claiming.
- [ ] **Step 5: Commit** `feat: membership shop section, HUD refill, reminders`.
