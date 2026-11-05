# Curio Hall — Phase 4b3 Design: Story recap + return gifts

**Date:** 2026-09-07
**Status:** Approved design, awaiting spec review
**Depends on:** Phases 1-4b2 (merged), `HANDOFF.md`, `docs/creative-direction.md`
**Roadmap:** `docs/curio-hall-roadmap.md`

## Goal

The society gives back and the story becomes readable: once a day a befriended member
sends a return gift whose contents scale with their intimacy level, the five Chronicle
volumes unlock as campaign milestones complete and page through the Hall's story, and
each member's detail view lists the memories their friendship has unlocked. The
preferred-gift bonus is corrected to the   numbers. Save v8; every number from
the config

## How it works (verified from config)

- **Return gifts** (`CharacterIntimacyModel` protos 40-42, 47): refreshed at most once
  per day (`Sec2Day` gate on a stored timestamp), re-checked when a main order
  finishes. The sender is one character picked by weighted roll where the weight is
  their intimacy level (characters at level 0 contribute nothing). The gift contents
  are ONE weighted roll from the sender's CURRENT level row's `Gifts` pool in
  `CharacterIntimacyLevelConfig` — tokens are `item-count-weight` triplets (e.g.
  `1302-1-10` = item `1302`, count 1, weight 10) — granted through the reward pipeline.
  Claiming clears the source; the next arrives after the next daily refresh. Text:
  `character_intimacy_return_gift_hint` ("Someone sent you a free gift!"), per-character
  `*_intimacy_return_gift_desc`, and `return_gift`/`return_gift_finish` dialog pools.
- **Preferred-gift bonus** (proto 68): `math.ceil(Intimacy × 1.2)` when the gift type is
  in the character's `PreferredGifts`. Our phase-4b tuning default of ×2 was invented
  before this was decoded and is corrected here.
- **Story recap** (`StoryRecapConfig`, 309 rows): five Books, each keyed to exactly one
  campaign task (`20_11`, `37_10`, `43_11`, `47_11`, `52_11`); a book's rows are Page
  sequences of `title`/`subtitle`/`text`/`img` entries whose `Content` is a loc key
  (imgs are art asset names). A book is readable once its task is in the campaign's
  completed set.
- **Character stories**: the `character_story_*`/background tokens already recorded in
  `Intimacy.story_unlocks` are the per-character memory list (the  
  Story/Memory windows); their prose lives in the localization file (text-rewrite
  track renders titles only for now).

## Scope

**In:** the return-gift mechanic in `Intimacy` (daily weighted sender, level-pool roll,
claim), the ×1.2-ceil preferred-bonus correction, `StoryRecapConfig` in ConfigDB, the
`ChroniclePanel` reader opened from the MapPanel header, the memories list and
return-gift claim row in `SocietyPanel`, story-token filtering at record time, save v8.

**Out (deferred):** real recap art/text (loc keys and `[illustration]` placeholders),
return-gift presentation as an openable board item ,
per-character return-gift dialog lines beyond the placeholder key, Ambrose/Ambrose.

## 1. Sim: return gifts in `Intimacy` (`sim/intimacy.gd`)

- New state: `gift_source: String = ""` (sender's original name, `""` = none waiting),
  `gift_refreshed_at: float = 0.0` (last refresh check that armed or could have armed).
- **`maybe_refresh_return_gift(now, rng) -> bool`**: no-op when a gift is already
  waiting; otherwise when `now - gift_refreshed_at >= tuning.return_gift_cooldown_seconds`
  (default **86400**): build `{name: level}` over characters with level ≥ 1; if empty,
  return false (do NOT consume the window — retry until someone is befriended); else
  pick a sender by level-weighted roll (injected RNG), set `gift_source`,
  `gift_refreshed_at = now`, emit `satchel_changed`, return true. Called from
  `Intimacy.tick` (already on the 1s tick via `Game.tick_gifts` — needs `rng`, so
  `tick(now)` becomes `tick(now, rng)` and `Game.tick_gifts` passes `rng`) and from
  `Game.deliver_order` after a successful delivery (mirroring the  
  main-order-finished hook).
- **`claim_return_gift(game, now) -> {ok, reason, sender, reward}`**: reason `no_gift`
  when none waiting. On success: take the sender's CURRENT level row
  (`intimacy_levels[sender][level-1]`; a level-0 sender cannot occur by construction,
  and a maxed sender uses their last row), weighted-roll one `item-count-weight`
  triplet from its `Gifts` array, grant `item` × `count` via `Rewards.grant`
  (`"%s-%d" % [item, count]`), clear `gift_source`, emit `satchel_changed`.
- Serialization gains both fields (defaults `""`/`0.0`).

## 2. Preferred-bonus correction

- `config/curio_hall_tuning.json`: `intimacy_preferred_multiplier` **2 → 1.2**.
- `Intimacy.give_gift`: points gained become
  `ceili(float(gift_row["Intimacy"]) * mult)` where `mult` is the tuning value for
  preferred types and `1.0` otherwise (non-preferred stays exact). Existing 4b tests
  that assumed ×2 update to the ×1.2-ceil values (chocolate to Cornelia: 10 → **12**).

## 3. Recap: ConfigDB + `Chronicle` sim helper

- ConfigDB: `story_recap: Dictionary` — `StoryRecapConfig.json` grouped
  `{book:int -> {"task": String, "rows": Array}}` with rows in file order;
  `validate()` warns when a book's `Task` is missing from `main_task_by_key`.
- No new sim class: book unlock = `campaign.done.has(task)`; the view reads config
  directly (read-only content, matching the sim/view rule — no state to persist).

## 4. View

- **`ChroniclePanel`** (`view/chronicle_panel.gd`, CanvasLayer modal like the others),
  opened by a **Chronicle** button added to the MapPanel's header row (next to Close):
  - Book list: five volumes; unlocked ones show `recap_title_<book>_1`-style loc keys
    as placeholder titles; locked ones show "sealed until the restoration reaches
    further" (no task spoiler).
  - Reader: paging Back/Next through the book's Page groups; `title`/`subtitle`/`text`
    rows render their loc key as placeholder text, `img` rows render
    `[illustration: <asset name>]`.
- **`SocietyPanel`**:
  - A claim row above the roster when `gift_source != ""`:
    `"<Cast name> sent you a gift!"` + Claim button → `Game.claim_return_gift(now)`;
    result toast on failure, refresh on success.
  - Detail view gains a **Memories** section: this character's entries from
    `story_unlocks` (prefix-matched `character_story_<orig>` and
    `character_intimacy_background_<orig>`), listed as loc-key placeholders;
    "No memories yet" when empty.
- **Story-token filtering**: `_grant_level_rewards`' `_is_story_token` tightens to
  accept only tokens beginning `character_` (story/background/portrait keys); other
  unknown tokens (e.g. Mark L28's `time_skip_5-1-1`, `infi_ene_1-1` boosters) fall
  through to `Rewards.grant`'s existing warn-and-skip instead of polluting the
  memories list. Existing saves are reset by v8 anyway.

## 5. Persistence

**Save v7 → v8**: `intimacy` block gains `gift_source`/`gift_refreshed_at` (present in
`to_dict`, defaulted in `from_dict`); version literal tests renamed/updated. Reset on
mismatch per convention.

## 6. Error handling & testing

- Claim is check-then-mutate; a failed grant cannot lose the gift (grant is the last
  step before clearing, and `Rewards.grant` never throws — unknown items warn-skip).
- **Testing** (GUT, sim TDD; free board cells before place assertions; watch suite
  totals — GUT swallows parse errors):
  - Refresh: nothing arms with all characters at level 0 (and the window is not
    consumed); arms after cooldown with one leveled character; sender weighting
    deterministic under seeded RNG; no double-arm while one waits; order delivery
    triggers the check.
  - Claim: grants item×count parsed from a `Gifts` triplet; clears source; `no_gift`
    reject; maxed-level sender uses the last row.
  - Preferred bonus: chocolate to Cornelia yields ceil(10×1.2)=12 points; non-preferred
    book stays 10; 4b tests updated accordingly (Cornelia L1 now takes 3 chocolates:
    12+12+12=36).
  - Recap: `story_recap` grouping (5 books, page/type integrity); unlock gating flips
    with `campaign.done`; validation warning on a missing task key.
  - Story filter: booster tokens route to warn-skip, `character_*` tokens recorded.
  - Save v8 roundtrip (gift fields), version literals.
  - Smoke: level Barnaby to 1, tick past a day → gift armed from Barnaby; claim → item
    granted; quit/resume preserves the pending gift.
- Headless boot + full suite; `--import` after new class_name scripts.

## 7. Milestones

1. Preferred-bonus correction (tuning + give_gift + 4b test updates).
2. Return gifts in `Intimacy` (+ `tick(now, rng)` threading, deliver_order hook,
   save v8).
3. ConfigDB `story_recap` (+ copy, validation).
4. `ChroniclePanel` + MapPanel button; `SocietyPanel` claim row + Memories + story
   filter; smoke test; roadmap update.

**Definition of done:** the Goal paragraph on a fresh install, every number traceable
to the config

## New/changed tuning constants (`config/curio_hall_tuning.json`)

- `intimacy_preferred_multiplier`: **1.2** (was 2 — decoded from
  `CharacterIntimacyModel` proto 68's `math.ceil(x * 1.2)`).
- `return_gift_cooldown_seconds`: **86400** ( `Sec2Day`; a day).
