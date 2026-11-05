# Curio Hall Phase 4b: Character Intimacy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The 11 society members get their config-driven intimacy tracks: gifts earned from orders and a daily gift shop, given on a Society screen for level rewards and story unlocks, with save v6.

**Architecture:** One new time-driven `Intimacy` RefCounted sim class (gift satchel, per-character tracks, daily shop) beside the existing pure-logic sim; order delivery feeds gifts; a `SocietyPanel` CanvasLayer modal (ShopPanel pattern) presents roster/detail/shop; a shared `Cast` name map is extracted from MapPanel.

**Tech Stack:** Godot 4.7.1 / GDScript, GUT headless tests

**Spec:** `docs/superpowers/specs/2026-09-04-curio-hall-phase4b-intimacy-design.md`

## Global Constraints

- Warnings are errors: never `var x := <Dictionary/Array lookup>`; annotate types explicitly; no bare integer division. GDScript's `or` is boolean-only — for nullable config fields use `var v: Variant = row.get("K")` then `var arr: Array = v if v is Array else []`.
- Run tests with `./curio-hall/test.sh` from repo root. Single file: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/<file> -gexit)`. After creating any NEW `class_name` script run `(cd curio-hall && godot --headless --import)` once.
- The starting board is FULL. Grants that spawn items fall back to `player.store` — fine in tests.
- All reward grants route through `Rewards.grant`/`grant_all`; spends are check-then-mutate with no partial state on failure.
- The gift shop's daily restock is time-driven: `Game.tick_gifts(now)` is the tick, hosted by `main.gd`'s existing 1-second timer (Task 3 wires it — the plan's one tick host).
- `SAVE_VERSION` becomes 6; version/shape mismatch backs up to `save.corrupt.json` and resets (no migration).
- New files use 4-space indentation; edits match each file's existing style (`config_db.gd` uses TABS).
- Exact config values used in tests: gift rows — flower `{Intimacy 8, Coin 40, CoinIncreasementNum 4, CoinIncreasementCost 20, Gem 10}`, chocolate `{10, 50, 4, 25, 12}`, book `{10, 50, 4, 25, 12}`, watch `{12, 60, 4, 30, 15}`. Shop slots — 1 free ×1 (all types), 2 gold ×6 (all types), 3-6 gem ×3 each (flower/chocolate/book/watch respectively). Coin→gift brackets — 1-25→2..3, 26-45→3..4, 46-75→4..5, 76+ (no MaxCoin)→5..6. Cornelia: preferred chocolate, L1 cost 36 rewards `["energy-30"]`, L2 cost 60 rewards 3 story tokens. Barnaby: preferred flower, L1 cost 48 rewards `["2403-1"]`. Aldous unlocks: `["day_12", "intimacy_Barnaby_3"]`. Ambrose is `Released: 0`.

---

### Task 1: ConfigDB loads the intimacy tables

**Files:**
- Create: `curio-hall/config/CharacterIntimacyListConfig.json`, `CharacterIntimacyLevelConfig.json`, `CharacterIntimacyGiftConfig.json`, `CharacterIntimacyShopConfig.json`, `CharacterIntimacyCoinToGiftConfig.json`, `CharacterIntimacyDialogConfig.json`
- Modify: `curio-hall/sim/config_db.gd` (TABS)
- Test: `curio-hall/test/unit/test_config_db.gd` (append)

**Interfaces:**
- Produces: `ConfigDB.intimacy_list: Array` (11 rows), `ConfigDB.intimacy_levels: Dictionary` (character name → level rows sorted by `Level`), `ConfigDB.intimacy_gifts: Dictionary` (gift type → row), `ConfigDB.intimacy_shop: Array` (6 slot rows), `ConfigDB.coin_to_gift: Array` (4 bracket rows), `ConfigDB.intimacy_dialogs: Array` (110 rows). `validate()` warns (never errors) on unknown gift types in `PreferredGifts` or shop `Gifts`.

- [ ] **Step 1: Copy the config files**

```bash

```

- [ ] **Step 2: Write the failing test**

Append to `curio-hall/test/unit/test_config_db.gd` (match its indentation — tabs):

```gdscript
func test_intimacy_tables_loaded() -> void:
	assert_eq(ConfigDB.intimacy_list.size(), 11)
	assert_eq((ConfigDB.intimacy_levels["Cornelia"] as Array).size(), 30)
	assert_eq(int(ConfigDB.intimacy_levels["Cornelia"][0]["Intimacy"]), 36)   # sorted by Level
	assert_eq(int(ConfigDB.intimacy_gifts["flower"]["Coin"]), 40)
	assert_eq(ConfigDB.intimacy_shop.size(), 6)
	assert_eq(ConfigDB.coin_to_gift.size(), 4)
	assert_eq(ConfigDB.intimacy_dialogs.size(), 110)

func test_intimacy_levels_absent_for_unreleased() -> void:
	# Ambrose has no level rows in config; only the 10 released characters do.
	assert_false(ConfigDB.intimacy_levels.has("Ambrose"))
```

- [ ] **Step 3: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_config_db.gd -gexit)`
Expected: FAIL — `intimacy_list` nonexistent.

- [ ] **Step 4: Implement**

In `curio-hall/sim/config_db.gd` (TABS), add vars after `var paperbox_rewards ...`:

```gdscript
var intimacy_list: Array = []          # 11 character rows
var intimacy_levels: Dictionary = {}   # character name -> level rows sorted by Level
var intimacy_gifts: Dictionary = {}    # gift type -> row
var intimacy_shop: Array = []          # 6 shop slot rows
var coin_to_gift: Array = []           # order-coin -> gift-count brackets
var intimacy_dialogs: Array = []
```

At the top of `load_all`, extend the reload-clear block with:

```gdscript
	intimacy_levels.clear()
	intimacy_gifts.clear()
```

In `load_all`, after the `paperbox_rewards` line:

```gdscript
	intimacy_list = _read(dir + "CharacterIntimacyListConfig.json")
	for row in _read(dir + "CharacterIntimacyLevelConfig.json"):
		if row == null:
			continue
		var who := String(row["Character"])
		if not intimacy_levels.has(who):
			intimacy_levels[who] = []
		intimacy_levels[who].append(row)
	for who in intimacy_levels:
		(intimacy_levels[who] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["Level"]) < int(b["Level"]))
	for row in _read(dir + "CharacterIntimacyGiftConfig.json"):
		if row != null:
			intimacy_gifts[String(row["Type"])] = row
	intimacy_shop = _read(dir + "CharacterIntimacyShopConfig.json")
	coin_to_gift = _read(dir + "CharacterIntimacyCoinToGiftConfig.json")
	intimacy_dialogs = _read(dir + "CharacterIntimacyDialogConfig.json")
```

In `validate()`, before `return errors`:

```gdscript
	for row in intimacy_list:
		var prefs_v: Variant = row.get("PreferredGifts")
		var prefs: Array = prefs_v if prefs_v is Array else []
		for g in prefs:
			if not intimacy_gifts.has(String(g)):
				push_warning("CharacterIntimacyListConfig %s: unknown gift type %s" % [row.get("Name"), g])
	for row in intimacy_shop:
		for g in row.get("Gifts", []):
			if not intimacy_gifts.has(String(g)):
				push_warning("CharacterIntimacyShopConfig slot %s: unknown gift type %s" % [row.get("Slot"), g])
```

- [ ] **Step 5: Run test to verify it passes**

Run the single file, then `./curio-hall/test.sh`. Expected: PASS, full suite green.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/config/CharacterIntimacy*.json curio-hall/sim/config_db.gd curio-hall/test/unit/test_config_db.gd
git commit -m "feat: load character intimacy config tables"
```

---

### Task 2: `Intimacy` sim core — satchel, order gifts, give_gift, unlock web

**Files:**
- Create: `curio-hall/sim/intimacy.gd`
- Modify: `curio-hall/sim/game.gd`
- Modify: `curio-hall/config/curio_hall_tuning.json`
- Test: `curio-hall/test/unit/test_intimacy.gd` (create)

**Interfaces:**
- Consumes: ConfigDB tables (Task 1), `Rewards.grant/parse`, `Campaign.day`, `Game.deliver_order`, `ConfigDB.tuning`.
- Produces: `Intimacy` (RefCounted): `const GIFT_TYPES := ["flower", "chocolate", "book", "watch"]`; `satchel: Dictionary`, `tracks: Dictionary` (name → `{"level": int, "points": int}`), `story_unlocks: Array`; signals `satchel_changed`, `intimacy_changed(name, level, points)`; `grant_order_gifts(coins: int, rng) -> Dictionary`; `give_gift(name: String, type: String, game, now: float) -> {ok, reason}` (reasons `locked | maxed | no_gift | bad_type`); `level_of(name) -> int`; `is_unlocked(name, campaign) -> bool`; `unlock_hint(name) -> Array`; `to_dict()/from_dict()`. `Game` gains `intimacy: Intimacy` (in `fresh`), `give_gift(name, type, now)` wrapper, and `deliver_order` grants order gifts. Tuning gains `intimacy_preferred_multiplier: 2` (shop constants arrive in Task 3; this task adds only the multiplier).

- [ ] **Step 1: Add the tuning constant**

In `curio-hall/config/curio_hall_tuning.json` add `"intimacy_preferred_multiplier": 2` (keep valid JSON, one line style as the file uses).

- [ ] **Step 2: Write the failing test**

Create `curio-hall/test/unit/test_intimacy.gd`:

```gdscript
extends GutTest
## Config facts used here: Cornelia prefers chocolate (Intimacy 10 -> 20 doubled),
## Cornelia L1 costs 36 and rewards energy-30, L2 costs 60 and rewards 3 story
## tokens. Barnaby prefers flower (8 -> 16), L1 costs 48, rewards item 2403.
## Aldous unlocks at day_12 + intimacy_Barnaby_3. Ambrose is unreleased.

const NOW := 1000.0

func _rng() -> RandomNumberGenerator:
    var rng := RandomNumberGenerator.new()
    rng.seed = 7
    return rng

func test_fresh_satchel_empty_and_tracks_at_zero() -> void:
    var g := Game.fresh(NOW, 42)
    for t in Intimacy.GIFT_TYPES:
        assert_eq(int(g.intimacy.satchel[t]), 0)
    assert_eq(g.intimacy.level_of("Cornelia"), 0)

func test_order_gifts_follow_coin_brackets() -> void:
    var im := Intimacy.new()
    var granted: Dictionary = im.grant_order_gifts(30, _rng())   # 26-45 -> 3..4 gifts
    var total := 0
    for t in granted:
        assert_has(Intimacy.GIFT_TYPES, String(t))
        total += int(granted[t])
    assert_between(total, 3, 4)
    var big: Dictionary = im.grant_order_gifts(200, _rng())      # 76+ -> 5..6
    var big_total := 0
    for t in big:
        big_total += int(big[t])
    assert_between(big_total, 5, 6)
    assert_eq(im.grant_order_gifts(0, _rng()).size(), 0)         # below every bracket

func test_deliver_order_grants_gifts() -> void:
    var g := Game.fresh(NOW, 42)
    g.player.level = 5
    g.orders.orders = [{"items": {"203": 1}, "coins": 30, "xp": 4,
            "created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
    g.board.remove(Vector2i(3, 4))
    g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
    g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
    assert_true(g.deliver_order(0, NOW)["ok"])
    var total := 0
    for t in Intimacy.GIFT_TYPES:
        total += int(g.intimacy.satchel[t])
    assert_between(total, 3, 4)

func test_give_gift_spends_and_adds_points_with_preferred_double() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["chocolate"] = 2   # Cornelia's preferred type, 10 x2 = 20 each
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(int(g.intimacy.satchel["chocolate"]), 1)
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 20)
    assert_eq(g.intimacy.level_of("Cornelia"), 0)   # 20 < 36
    var energy_before := g.wallet.energy(NOW)
    assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])   # 40 >= 36 -> level 1
    assert_eq(g.intimacy.level_of("Cornelia"), 1)
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 4)
    assert_eq(g.wallet.energy(NOW), energy_before + 30)          # L1 reward energy-30

func test_non_preferred_gift_counts_single() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["book"] = 1        # book Intimacy 10, not Cornelia's preference
    assert_true(g.give_gift("Cornelia", "book", NOW)["ok"])
    assert_eq(int((g.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 10)

func test_level_two_records_story_unlocks() -> void:
    var g := Game.fresh(NOW, 42)
    g.intimacy.satchel["chocolate"] = 5   # 100 points: L1 (36) + L2 (60), 4 left
    for i in range(5):
        assert_true(g.give_gift("Cornelia", "chocolate", NOW)["ok"])
    assert_eq(g.intimacy.level_of("Cornelia"), 2)
    assert_has(g.intimacy.story_unlocks, "character_story_cornelia_1")
    assert_has(g.intimacy.story_unlocks, "character_intimacy_background_cornelia")

func test_rejections() -> void:
    var g := Game.fresh(NOW, 42)
    assert_eq(g.give_gift("Cornelia", "chocolate", NOW)["reason"], "no_gift")
    g.intimacy.satchel["chocolate"] = 1
    assert_eq(g.give_gift("Aldous", "chocolate", NOW)["reason"], "locked")   # day 1 < 12
    assert_eq(g.give_gift("Ambrose", "chocolate", NOW)["reason"], "locked")     # unreleased
    assert_eq(g.give_gift("Cornelia", "pebbles", NOW)["reason"], "bad_type")
    assert_eq(int(g.intimacy.satchel["chocolate"]), 1)   # nothing consumed by rejections

func test_unlock_web_day_and_intimacy_gates() -> void:
    var g := Game.fresh(NOW, 42)
    assert_true(g.intimacy.is_unlocked("Cornelia", g.campaign))    # day_1
    assert_false(g.intimacy.is_unlocked("Aldous", g.campaign))
    g.campaign.day = 12
    assert_false(g.intimacy.is_unlocked("Aldous", g.campaign)) # still needs Barnaby 3
    (g.intimacy.track("Barnaby") as Dictionary)["level"] = 3
    assert_true(g.intimacy.is_unlocked("Aldous", g.campaign))
    assert_false(g.intimacy.is_unlocked("Ambrose", g.campaign))   # never
    assert_eq(g.intimacy.unlock_hint("Aldous"), ["day_12", "intimacy_Barnaby_3"])

func test_maxed_track_rejects() -> void:
    var g := Game.fresh(NOW, 42)
    (g.intimacy.track("Cornelia") as Dictionary)["level"] = 30
    g.intimacy.satchel["chocolate"] = 1
    assert_eq(g.give_gift("Cornelia", "chocolate", NOW)["reason"], "maxed")

func test_roundtrip() -> void:
    var im := Intimacy.new()
    im.satchel["flower"] = 3
    (im.track("Barnaby") as Dictionary)["level"] = 2
    (im.track("Barnaby") as Dictionary)["points"] = 15
    im.story_unlocks.append("character_story_barnaby_1")
    var im2 := Intimacy.from_dict(im.to_dict())
    assert_eq(int(im2.satchel["flower"]), 3)
    assert_eq(im2.level_of("Barnaby"), 2)
    assert_has(im2.story_unlocks, "character_story_barnaby_1")
```

- [ ] **Step 3: Run test to verify it fails**

Run: `(cd curio-hall && godot --headless -s res://addons/gut/gut_cmdln.gd -gtest=res://test/unit/test_intimacy.gd -gexit)`
Expected: FAIL — `Intimacy` nonexistent.

- [ ] **Step 4: Implement `Intimacy` (core half)**

Create `curio-hall/sim/intimacy.gd` (4 spaces):

```gdscript
class_name Intimacy
extends RefCounted
## Gift satchel, per-character intimacy tracks, and (Task 3) the daily gift
## shop. Gifts arrive from order deliveries (CoinToGift brackets) and the
## shop; giving them levels tracks that grant rewards and story unlocks.

signal satchel_changed
signal intimacy_changed(name: String, level: int, points: int)

const GIFT_TYPES := ["flower", "chocolate", "book", "watch"]

var satchel: Dictionary = {}      # gift type -> count
var tracks: Dictionary = {}       # character name -> {"level": int, "points": int}
var story_unlocks: Array = []     # story tokens granted by level rewards

func _init() -> void:
    for t in GIFT_TYPES:
        satchel[t] = 0

func _row_for(name: String) -> Dictionary:
    for row in ConfigDB.intimacy_list:
        if String(row["Name"]) == name:
            return row
    return {}

func track(name: String) -> Dictionary:
    if not tracks.has(name):
        tracks[name] = {"level": 0, "points": 0}
    return tracks[name]

func level_of(name: String) -> int:
    return int(track(name)["level"])

func is_unlocked(name: String, campaign: Campaign) -> bool:
    var row := _row_for(name)
    if row.is_empty() or int(row.get("Released", 0)) != 1:
        return false
    var reqs_v: Variant = row.get("UnlockRequirements")
    var reqs: Array = reqs_v if reqs_v is Array else []
    for req in reqs:
        var parts: PackedStringArray = String(req).split("_")
        if parts[0] == "day" and campaign.day < int(parts[1]):
            return false
        if parts[0] == "intimacy" and level_of(String(parts[1])) < int(parts[2]):
            return false
    return true

func unlock_hint(name: String) -> Array:
    var reqs_v: Variant = _row_for(name).get("UnlockRequirements")
    return reqs_v if reqs_v is Array else []

func grant_order_gifts(coins: int, rng: RandomNumberGenerator) -> Dictionary:
    var granted := {}
    for row in ConfigDB.coin_to_gift:
        if coins < int(row.get("MinCoin", 0)):
            continue
        var hi_v: Variant = row.get("MaxCoin")
        if hi_v != null and coins > int(hi_v):
            continue
        var range_v: Array = row["NumberRange"]
        for i in range(rng.randi_range(int(range_v[0]), int(range_v[1]))):
            var t: String = GIFT_TYPES[rng.randi_range(0, GIFT_TYPES.size() - 1)]
            satchel[t] = int(satchel[t]) + 1
            granted[t] = int(granted.get(t, 0)) + 1
        break
    if not granted.is_empty():
        satchel_changed.emit()
    return granted

func give_gift(name: String, type: String, game, now: float) -> Dictionary:
    if not is_unlocked(name, game.campaign):
        return {"ok": false, "reason": "locked"}
    var gift_row: Dictionary = ConfigDB.intimacy_gifts.get(type, {})
    if gift_row.is_empty():
        return {"ok": false, "reason": "bad_type"}
    var rows: Array = ConfigDB.intimacy_levels.get(name, [])
    var t := track(name)
    if int(t["level"]) >= rows.size():
        return {"ok": false, "reason": "maxed"}
    if int(satchel.get(type, 0)) <= 0:
        return {"ok": false, "reason": "no_gift"}
    satchel[type] = int(satchel[type]) - 1
    var prefs_v: Variant = _row_for(name).get("PreferredGifts")
    var prefs: Array = prefs_v if prefs_v is Array else []
    var mult := int(ConfigDB.tuning["intimacy_preferred_multiplier"]) if prefs.has(type) else 1
    t["points"] = int(t["points"]) + int(gift_row["Intimacy"]) * mult
    while int(t["level"]) < rows.size():
        var next_row: Dictionary = rows[int(t["level"])]
        if int(t["points"]) < int(next_row["Intimacy"]):
            break
        t["points"] = int(t["points"]) - int(next_row["Intimacy"])
        t["level"] = int(t["level"]) + 1
        _grant_level_rewards(next_row, game, now)
    satchel_changed.emit()
    intimacy_changed.emit(name, int(t["level"]), int(t["points"]))
    return {"ok": true, "reason": ""}

## Reward tokens that resolve to no known item and no currency are story keys
## (character_story_*, backgrounds, cosmetics): recorded for the 4b3 reader
## instead of Rewards' warn-and-skip.
func _grant_level_rewards(row: Dictionary, game, now: float) -> void:
    var rewards_v: Variant = row.get("Rewards")
    var rewards: Array = rewards_v if rewards_v is Array else []
    for token in rewards:
        if _is_story_token(String(token)):
            if not story_unlocks.has(String(token)):
                story_unlocks.append(String(token))
        else:
            Rewards.grant(String(token), game, now)

func _is_story_token(token: String) -> bool:
    var r := Rewards.parse(token)
    return String(r["kind"]) == "item" and not ConfigDB.items.has(String(r["id"]))

func to_dict() -> Dictionary:
    return {"satchel": satchel.duplicate(), "tracks": tracks.duplicate(true),
            "story_unlocks": story_unlocks.duplicate()}

static func from_dict(d: Dictionary) -> Intimacy:
    var im := Intimacy.new()
    for t in d.get("satchel", {}):
        im.satchel[String(t)] = int(d["satchel"][t])
    for who in d.get("tracks", {}):
        im.tracks[String(who)] = {"level": int(d["tracks"][who]["level"]),
                "points": int(d["tracks"][who]["points"])}
    for s in d.get("story_unlocks", []):
        im.story_unlocks.append(String(s))
    return im
```

In `curio-hall/sim/game.gd`:
- add `var intimacy: Intimacy` after `var campaign: Campaign`;
- in `fresh`, after `g.campaign = Campaign.new()`: `g.intimacy = Intimacy.new()`;
- in `deliver_order`, after `grant_xp(int(res["xp"]), now)`:

```gdscript
    intimacy.grant_order_gifts(int(res["coins"]), rng)
```

- add after `complete_task`:

```gdscript
func give_gift(name: String, type: String, now: float) -> Dictionary:
    return intimacy.give_gift(name, type, self, now)
```

(Save wiring is Task 3; `Game.from_dict` does not touch intimacy yet — note `Game.from_dict` games have `intimacy == null` until Task 3, which is fine because save tests for it arrive there.)

- [ ] **Step 5: Run test to verify it passes**

`(cd curio-hall && godot --headless --import)` (new class_name), then the single file, then `./curio-hall/test.sh`.
Expected: PASS, full suite green.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/sim/intimacy.gd curio-hall/sim/game.gd curio-hall/config/curio_hall_tuning.json curio-hall/test/unit/test_intimacy.gd
git commit -m "feat: intimacy sim - gift satchel, order gift drops, give_gift levels"
```

---

### Task 3: Gift shop, daily tick, save v6

**Files:**
- Modify: `curio-hall/sim/intimacy.gd`
- Modify: `curio-hall/sim/game.gd`
- Modify: `curio-hall/sim/save_manager.gd`
- Modify: `curio-hall/config/curio_hall_tuning.json`
- Test: `curio-hall/test/unit/test_intimacy.gd` (append), `curio-hall/test/unit/test_save.gd` (append + version bump), `curio-hall/test/unit/test_shop_game.gd` (version literal)

**Interfaces:**
- Consumes: Task 2's `Intimacy`, `EnergyWallet.spend_coins/spend_gems`.
- Produces: `Intimacy.stock: Dictionary` (slot int → remaining), `coin_buys_today: int`, `restock_at: float`, `restock()`, `tick(now)`, `gift_coin_price(type) -> int`, `claim_free(rng) -> {ok, reason, type}`, `buy_with_coins(type, wallet) -> {ok, reason}`, `buy_with_gems(type, wallet) -> {ok, reason}` (reasons `bad_type | out_of_stock | not_enough_coins | not_enough_gems`); `Game.tick_gifts(now)`, `Game.claim_free_gift()`, `Game.buy_gift_coins(type)`, `Game.buy_gift_gems(type)`; `Game.SAVE_VERSION == 6` with `intimacy` in the save; tuning `gift_shop_restock_seconds: 86400`.

- [ ] **Step 1: Add the tuning constant**

Add `"gift_shop_restock_seconds": 86400` to `curio-hall/config/curio_hall_tuning.json`.

- [ ] **Step 2: Write the failing tests**

Append to `curio-hall/test/unit/test_intimacy.gd`:

```gdscript
func test_free_slot_claims_once_per_day() -> void:
    var im := Intimacy.new()
    var res: Dictionary = im.claim_free(_rng())
    assert_true(res["ok"])
    assert_has(Intimacy.GIFT_TYPES, String(res["type"]))
    assert_eq(im.claim_free(_rng())["reason"], "out_of_stock")

func test_coin_price_escalates_every_four_buys() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10000)
    assert_eq(im.gift_coin_price("flower"), 40)
    for i in range(4):
        assert_true(im.buy_with_coins("flower", w)["ok"])
    assert_eq(im.gift_coin_price("flower"), 60)   # 40 + 1*20 after 4 buys
    assert_eq(im.gift_coin_price("watch"), 90)    # 60 + 1*30, escalation is shared
    assert_true(im.buy_with_coins("watch", w)["ok"])
    assert_true(im.buy_with_coins("watch", w)["ok"])   # 6th buy empties the slot
    assert_eq(im.buy_with_coins("flower", w)["reason"], "out_of_stock")
    assert_eq(int(im.satchel["flower"]), 4)
    assert_eq(int(im.satchel["watch"]), 2)

func test_coin_buy_rejects_without_spend_when_poor() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10)
    assert_eq(im.buy_with_coins("flower", w)["reason"], "not_enough_coins")
    assert_eq(w.coins, 10)
    assert_eq(int(im.satchel["flower"]), 0)

func test_gem_slots_sell_their_type_and_cap_at_three() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_gems(1000)
    var gems_before := w.gems
    for i in range(3):
        assert_true(im.buy_with_gems("chocolate", w)["ok"])   # slot 4, 12 gems each
    assert_eq(w.gems, gems_before - 36)
    assert_eq(im.buy_with_gems("chocolate", w)["reason"], "out_of_stock")
    assert_true(im.buy_with_gems("flower", w)["ok"])          # slot 3 unaffected
    assert_eq(im.buy_with_gems("pebbles", w)["reason"], "bad_type")

func test_tick_restocks_daily_and_resets_escalation() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10000)
    im.claim_free(_rng())
    for i in range(4):
        im.buy_with_coins("flower", w)
    im.tick(1000.0)                       # arms restock_at
    im.tick(1000.0 + 86400.0)             # a day later: restock
    assert_true(im.claim_free(_rng())["ok"])
    assert_eq(im.gift_coin_price("flower"), 40)

func test_shop_state_roundtrip() -> void:
    var im := Intimacy.new()
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10000)
    im.claim_free(_rng())
    for i in range(4):
        im.buy_with_coins("flower", w)
    im.tick(1000.0)
    var im2 := Intimacy.from_dict(im.to_dict())
    assert_eq(im2.claim_free(_rng())["reason"], "out_of_stock")
    assert_eq(im2.gift_coin_price("flower"), 60)
    assert_eq(im2.restock_at, im.restock_at)
```

Append to `curio-hall/test/unit/test_save.gd` (tabs) and update its two version assertions (`5` → `6`, rename `test_v5_roundtrip_campaign` → `test_v6_roundtrip_campaign`, `test_save_version_is_5_and_campaign_key_present` → `..._is_6_...`); also update `test_shop_game.gd`'s `assert_eq(g2.to_dict()["save_version"], 5)` to `6`. New save test:

```gdscript
func test_v6_roundtrip_intimacy() -> void:
	var g := Game.fresh(1000.0, 42)
	g.intimacy.satchel["watch"] = 2
	g.give_gift("Cornelia", "watch", 1000.0)
	var g2 := Game.from_dict(g.to_dict())
	assert_eq(int(g2.intimacy.satchel["watch"]), 1)
	assert_eq(int((g2.intimacy.tracks["Cornelia"] as Dictionary)["points"]), 12)
	assert_true(g2.to_dict().has("intimacy"))
```

- [ ] **Step 3: Run tests to verify they fail**

Run test_intimacy.gd and test_save.gd. Expected: FAIL — `claim_free` etc. nonexistent; version still 5.

- [ ] **Step 4: Implement**

In `curio-hall/sim/intimacy.gd`, add state vars after `story_unlocks`:

```gdscript
var stock: Dictionary = {}        # shop slot (int) -> remaining today
var coin_buys_today: int = 0      # shared escalation counter for the gold slot
var restock_at: float = 0.0
```

extend `_init` with `restock()`, and add the shop block after `unlock_hint`:

```gdscript
func restock() -> void:
    for row in ConfigDB.intimacy_shop:
        stock[int(row["Slot"])] = int(row["Number"])
    coin_buys_today = 0

func tick(now: float) -> void:
    if restock_at <= 0.0:
        restock_at = now + float(ConfigDB.tuning["gift_shop_restock_seconds"])
    elif now >= restock_at:
        restock()
        restock_at = now + float(ConfigDB.tuning["gift_shop_restock_seconds"])
        satchel_changed.emit()

func gift_coin_price(type: String) -> int:
    var row: Dictionary = ConfigDB.intimacy_gifts.get(type, {})
    if row.is_empty():
        return -1
    var step := int(coin_buys_today / maxf(1.0, float(row["CoinIncreasementNum"])))
    return int(row["Coin"]) + step * int(row["CoinIncreasementCost"])

func claim_free(rng: RandomNumberGenerator) -> Dictionary:
    if int(stock.get(1, 0)) <= 0:
        return {"ok": false, "reason": "out_of_stock"}
    return _dispense(1, GIFT_TYPES[rng.randi_range(0, GIFT_TYPES.size() - 1)])

func buy_with_coins(type: String, wallet: EnergyWallet) -> Dictionary:
    if not ConfigDB.intimacy_gifts.has(type):
        return {"ok": false, "reason": "bad_type"}
    if int(stock.get(2, 0)) <= 0:
        return {"ok": false, "reason": "out_of_stock"}
    if not wallet.spend_coins(gift_coin_price(type)):
        return {"ok": false, "reason": "not_enough_coins"}
    coin_buys_today += 1
    return _dispense(2, type)

func _gem_slot_for(type: String) -> int:
    for row in ConfigDB.intimacy_shop:
        if String(row["Type"]) == "gem" and (row["Gifts"] as Array).has(type):
            return int(row["Slot"])
    return -1

func buy_with_gems(type: String, wallet: EnergyWallet) -> Dictionary:
    var slot := _gem_slot_for(type)
    if slot < 0:
        return {"ok": false, "reason": "bad_type"}
    if int(stock.get(slot, 0)) <= 0:
        return {"ok": false, "reason": "out_of_stock"}
    if not wallet.spend_gems(int(ConfigDB.intimacy_gifts[type]["Gem"])):
        return {"ok": false, "reason": "not_enough_gems"}
    return _dispense(slot, type)

func _dispense(slot: int, type: String) -> Dictionary:
    stock[slot] = int(stock.get(slot, 0)) - 1
    satchel[type] = int(satchel.get(type, 0)) + 1
    satchel_changed.emit()
    return {"ok": true, "reason": "", "type": type}
```

extend serialization:

```gdscript
func to_dict() -> Dictionary:
    return {"satchel": satchel.duplicate(), "tracks": tracks.duplicate(true),
            "story_unlocks": story_unlocks.duplicate(), "stock": stock.duplicate(),
            "coin_buys_today": coin_buys_today, "restock_at": restock_at}
```

and in `from_dict`, before `return im`:

```gdscript
    for k in d.get("stock", {}):
        im.stock[int(k)] = int(d["stock"][k])
    im.coin_buys_today = int(d.get("coin_buys_today", 0))
    im.restock_at = float(d.get("restock_at", 0.0))
```

In `curio-hall/sim/game.gd`:
- `const SAVE_VERSION := 6`
- after `give_gift` add:

```gdscript
func tick_gifts(now: float) -> void:
    intimacy.tick(now)

func claim_free_gift() -> Dictionary:
    return intimacy.claim_free(rng)

func buy_gift_coins(type: String) -> Dictionary:
    return intimacy.buy_with_coins(type, wallet)

func buy_gift_gems(type: String) -> Dictionary:
    return intimacy.buy_with_gems(type, wallet)
```

- `to_dict()`: add `"intimacy": intimacy.to_dict(),` after `"campaign"`; `from_dict()`: `g.intimacy = Intimacy.from_dict(d["intimacy"])` after the campaign line.

In `curio-hall/sim/save_manager.gd`: required-keys list gains `"intimacy"`; update the version comment to "v5 saves reset on upgrade to v6".

- [ ] **Step 5: Run tests to verify they pass**

test_intimacy.gd, test_save.gd, then `./curio-hall/test.sh`. Expected: PASS, full suite green.

- [ ] **Step 6: Commit**

```bash
git add curio-hall/sim/intimacy.gd curio-hall/sim/game.gd curio-hall/sim/save_manager.gd curio-hall/config/curio_hall_tuning.json curio-hall/test/unit/test_intimacy.gd curio-hall/test/unit/test_save.gd curio-hall/test/unit/test_shop_game.gd
git commit -m "feat: gift shop with daily restock, tick_gifts, save v6"
```

---

### Task 4: `Cast` map, `SocietyPanel`, main wiring, smoke test

**Files:**
- Create: `curio-hall/view/cast.gd`, `curio-hall/view/society_panel.gd`
- Modify: `curio-hall/view/map_panel.gd` (consume Cast), `curio-hall/scenes/main.gd`, `curio-hall/scenes/main.tscn`
- Test: `curio-hall/test/unit/test_smoke.gd` (append)

**Interfaces:**
- Consumes: `Game.intimacy` + wrappers (Tasks 2-3), `Campaign.day`, `ConfigDB.intimacy_*`.
- Produces: `Cast.display_name(original: String) -> String` (shared original→Curio Hall cast map); `SocietyPanel` (CanvasLayer) with `setup(g: Game)`, `open()`, `close()`, `signal action_rejected(reason: String)`. Main scene gains a Society button, `tick_gifts` in the 1s flush, save-pending on intimacy signals, and `REJECT_MESSAGES` for `no_gift`, `maxed`, `bad_type`.

- [ ] **Step 1: Write the failing smoke test**

Append to `curio-hall/test/unit/test_smoke.gd` (tabs):

```gdscript
func test_intimacy_smoke_orders_to_friendship() -> void:
	var g := Game.fresh(1000.0, 42)
	g.player.level = 5
	g.orders.orders = [{"items": {"203": 1}, "coins": 80, "xp": 4,
			"created_at": 0.0, "type": 1, "refresh_time": 3600}, null, null]
	g.board.remove(Vector2i(3, 4))
	g.board.set_state(Vector2i(3, 4), MergeBoard.CellState.OPEN)
	g.board.place(Vector2i(3, 4), ItemInstance.make("203"))
	assert_true(g.deliver_order(0, 1000.0)["ok"])   # 76+ coins -> 5..6 gifts
	var total := 0
	for t in Intimacy.GIFT_TYPES:
		total += int(g.intimacy.satchel[t])
	assert_between(total, 5, 6)
	var given := 0
	for t in Intimacy.GIFT_TYPES:
		while int(g.intimacy.satchel[t]) > 0 and g.give_gift("Barnaby", t, 1000.0)["ok"]:
			given += 1
	assert_gt(given, 0)
	assert_gt(int((g.intimacy.tracks["Barnaby"] as Dictionary)["points"]) + g.intimacy.level_of("Barnaby") * 48, 0)
	var g2 := Game.from_dict(g.to_dict())
	assert_eq(int((g2.intimacy.tracks["Barnaby"] as Dictionary)["points"]),
			int((g.intimacy.tracks["Barnaby"] as Dictionary)["points"]))
```

- [ ] **Step 2: Run it — expected to PASS already** (it exercises Tasks 2-3 and guards the wiring). If it fails, fix the earlier task first.

- [ ] **Step 3: Implement `Cast` and refactor `MapPanel`**

Create `curio-hall/view/cast.gd`:

```gdscript
class_name Cast
## Original character names -> the Curio Hall cast (docs/creative-direction.md).
## Names outside the 11 cast slots fall back to a capitalized placeholder.

const NAMES := {
    "cornelia": "Cornelia Wren", "barnaby": "Barnaby Pluck",
    "aldous": "Prof. Aldous Finch", "sam": "Jasper Vane",
    "mark": "Tobias Bloom", "anjali": "Anjali Bose",
    "hugo": "Hugo Pemberton", "prudence": "Prudence Quill",
    "zephyrine": "Zephyrine \"Zeph\" Blackwood", "rosalind": "Rosalind Thorne",
    "ambrose": "Ambrose Hall",
}

static func display_name(original: String) -> String:
    var key := original.to_lower()
    return String(NAMES.get(key, original.capitalize()))
```

In `curio-hall/view/map_panel.gd`: delete the `CHARACTER_NAMES` const and replace its one use (`String(CHARACTER_NAMES.get(icon, icon.capitalize()))`) with `Cast.display_name(icon)`.

- [ ] **Step 4: Implement `SocietyPanel`**

Create `curio-hall/view/society_panel.gd`:

```gdscript
class_name SocietyPanel
extends CanvasLayer
## The society roster: intimacy tracks, gift giving, and the daily gift shop.
## Placeholder styling; loc keys render as placeholder text.

signal action_rejected(reason: String)

const GIFT_LABELS := {
    "flower": "Botanicals", "chocolate": "Confections",
    "book": "Volumes", "watch": "Timepieces",
}

var game: Game
var _root: PanelContainer
var _list: VBoxContainer
var _selected := ""   # original character name, "" = roster view

func setup(g: Game) -> void:
    game = g
    layer = 10
    visible = false
    _root = PanelContainer.new()
    _root.anchor_right = 1.0
    _root.anchor_bottom = 1.0
    add_child(_root)
    var scroll := ScrollContainer.new()
    _root.add_child(scroll)
    _list = VBoxContainer.new()
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list)
    game.intimacy.satchel_changed.connect(refresh)
    game.intimacy.intimacy_changed.connect(func(_n: String, _l: int, _p: int) -> void: refresh())
    game.wallet.changed.connect(refresh)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(refresh)
    add_child(t)   # on the CanvasLayer, never inside _list (self-freeing-timer trap)

func open() -> void:
    visible = true
    _selected = ""
    refresh()

func close() -> void:
    visible = false

func _label(text: String) -> void:
    var l := Label.new()
    l.text = text
    _list.add_child(l)

func _button(text: String, disabled: bool, cb: Callable) -> void:
    var b := Button.new()
    b.text = text
    b.disabled = disabled
    b.pressed.connect(cb)
    _list.add_child(b)

func refresh() -> void:
    if not visible:
        return
    for c in _list.get_children():
        c.queue_free()
    if _selected == "":
        _draw_roster()
    else:
        _draw_detail()

func _draw_roster() -> void:
    _label("THE SOCIETY   Coins: %d   Gems: %d" % [game.wallet.coins, game.wallet.gems])
    _button("X Close", false, close)
    for row in ConfigDB.intimacy_list:
        var name := String(row["Name"])
        if int(row.get("Released", 0)) != 1:
            _label("???   (a vanished founder...)")
            continue
        if game.intimacy.is_unlocked(name, game.campaign):
            _button("%s   Lv %d" % [Cast.display_name(name), game.intimacy.level_of(name)],
                    false, _select.bind(name))
        else:
            _label("%s   locked: %s" % [Cast.display_name(name), _hint_text(name)])
    _draw_gift_shop()

func _hint_text(name: String) -> String:
    var parts: Array = []
    for req in game.intimacy.unlock_hint(name):
        var bits: PackedStringArray = String(req).split("_")
        if bits[0] == "day":
            parts.append("reach day %s" % bits[1])
        elif bits[0] == "intimacy":
            parts.append("befriend %s to Lv %s" % [Cast.display_name(String(bits[1])), bits[2]])
    return ", ".join(parts)

func _select(name: String) -> void:
    _selected = name
    refresh()

func _draw_detail() -> void:
    var name := _selected
    _button("< Back", false, func() -> void: _select(""))
    var t: Dictionary = game.intimacy.track(name)
    var rows: Array = ConfigDB.intimacy_levels.get(name, [])
    var lvl := int(t["level"])
    _label("%s   Lv %d" % [Cast.display_name(name), lvl])
    _label(_greeting(name))
    if lvl < rows.size():
        var next_row: Dictionary = rows[lvl]
        _label("Progress: %d / %d" % [int(t["points"]), int(next_row["Intimacy"])])
        _label("Next reward: %s" % ", ".join(next_row.get("Rewards", [])))
    else:
        _label("Friendship complete!")
    var prefs_v: Variant = _list_row(name).get("PreferredGifts")
    var prefs: Array = prefs_v if prefs_v is Array else []
    for type in Intimacy.GIFT_TYPES:
        var gift_row: Dictionary = ConfigDB.intimacy_gifts[type]
        var star := "  *preferred*" if prefs.has(type) else ""
        var have := int(game.intimacy.satchel[type])
        _button("Give %s (+%d)%s   have %d" % [GIFT_LABELS[type], int(gift_row["Intimacy"]), star, have],
                have <= 0, _give.bind(name, type))
    _draw_gift_shop()

func _list_row(name: String) -> Dictionary:
    for row in ConfigDB.intimacy_list:
        if String(row["Name"]) == name:
            return row
    return {}

## Pick a greeting: an hour-matching "hello" pool wins, else the idle pool.
## The loc key itself is the placeholder text until the rewrite track.
func _greeting(name: String) -> String:
    var hour := int(Time.get_datetime_dict_from_system()["hour"])
    var idle_pool: Array = []
    for row in ConfigDB.intimacy_dialogs:
        if String(row["Character"]) != name:
            continue
        var periods_v: Variant = row.get("Periods")
        if String(row["Type"]) == "hello" and periods_v is Array and (periods_v as Array).has(hour):
            var pool_h: Array = row["Pool"]
            return String(pool_h[randi_range(0, pool_h.size() - 1)])
        if String(row["Type"]) == "idle":
            idle_pool = row["Pool"]
    if idle_pool.is_empty():
        return "..."
    return String(idle_pool[randi_range(0, idle_pool.size() - 1)])

func _give(name: String, type: String) -> void:
    var res: Dictionary = game.give_gift(name, type, Time.get_unix_time_from_system())
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()

func _draw_gift_shop() -> void:
    _label("--- GIFT SHOP (restocks daily) ---")
    var free_stock := int(game.intimacy.stock.get(1, 0))
    _button("Free daily gift", free_stock <= 0, _claim_free)
    var gold_stock := int(game.intimacy.stock.get(2, 0))
    for type in Intimacy.GIFT_TYPES:
        _button("Buy %s - %d coins (stock %d)" % [GIFT_LABELS[type], game.intimacy.gift_coin_price(type), gold_stock],
                gold_stock <= 0, _buy_coins.bind(type))
    for type in Intimacy.GIFT_TYPES:
        var slot := 3 + Intimacy.GIFT_TYPES.find(type)
        var gem_stock := int(game.intimacy.stock.get(slot, 0))
        _button("Buy %s - %d gems (stock %d)" % [GIFT_LABELS[type], int(ConfigDB.intimacy_gifts[type]["Gem"]), gem_stock],
                gem_stock <= 0, _buy_gems.bind(type))

func _claim_free() -> void:
    var res: Dictionary = game.claim_free_gift()
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()

func _buy_coins(type: String) -> void:
    var res: Dictionary = game.buy_gift_coins(type)
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()

func _buy_gems(type: String) -> void:
    var res: Dictionary = game.buy_gift_gems(type)
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()
```

- [ ] **Step 5: Wire the main scene**

`curio-hall/scenes/main.tscn`: bump `load_steps` by 1 (8 → 9); add after the map_panel ext_resource:

```
[ext_resource type="Script" path="res://view/society_panel.gd" id="8"]
```

add after MapButton:

```
[node name="SocietyButton" type="Button" parent="UI"]
offset_left = 600.0
offset_top = 10.0
offset_right = 710.0
offset_bottom = 50.0
text = "Society"
```

add after MapPanel:

```
[node name="SocietyPanel" type="CanvasLayer" parent="."]
script = ExtResource("8")
```

`curio-hall/scenes/main.gd`:
- `REJECT_MESSAGES` gains:

```gdscript
    "no_gift": "None of that gift left - deliver more orders",
    "maxed": "Their friendship is already complete",
    "bad_type": "Unavailable",
```

- `@onready` after `map_button`:

```gdscript
@onready var society_panel: SocietyPanel = $SocietyPanel
@onready var society_button: Button = $UI/SocietyButton
```

- in `_ready`, after the map wiring:

```gdscript
    society_panel.setup(game)
    society_button.pressed.connect(society_panel.open)
    society_panel.action_rejected.connect(_show_toast)
```

- extend the save-pending signal list with `game.intimacy.satchel_changed, game.intimacy.intimacy_changed`;
- in `_flush_save`, after `game.tick_orders(...)`:

```gdscript
    game.tick_gifts(Time.get_unix_time_from_system())
```

- [ ] **Step 6: Verify headless boot + full suite**

`(cd curio-hall && godot --headless --import)` then `./curio-hall/test.sh` (expect all green), then boot ~8s headless and confirm zero `SCRIPT ERROR` lines (backgrounded run + kill; no `timeout` binary on this macOS).

- [ ] **Step 7: Commit**

```bash
git add curio-hall/view/cast.gd curio-hall/view/society_panel.gd curio-hall/view/map_panel.gd curio-hall/scenes/main.gd curio-hall/scenes/main.tscn curio-hall/test/unit/test_smoke.gd
git commit -m "feat: SocietyPanel roster, gift giving and gift shop - phase 4b playable"
```

---

### Task 5: Roadmap update

**Files:**
- Modify: `docs/curio-hall-roadmap.md`

- [ ] **Step 1: Update the roadmap**

Mark Phase 4b ✅ using the doc's existing style (colon headers for new sections, no em dashes in new text): the intimacy system (gift economy from orders + daily shop, 30-level tracks with rewards and story-unlock flags, unlock web, SocietyPanel, save v6, `tick_gifts` tick host). Spec: `docs/superpowers/specs/2026-09-04-curio-hall-phase4b-intimacy-design.md`. Plan: `docs/superpowers/plans/2026-09-05-curio-hall-phase4b-intimacy.md`. Deferred: return-gift pools (level rows' `Gifts` columns), Ambrose/Ambrose track (unreleased in config), dialog text (rewrite track). Add Phase 4b2 ⏳ (special/branch/avatar orders) and renumber the recap reader as 4b3 ⏳ alongside 4c.

- [ ] **Step 2: Commit**

```bash
git add docs/curio-hall-roadmap.md
git commit -m "docs: mark phase 4b complete, queue 4b2 orders and 4b3 recap"
```
