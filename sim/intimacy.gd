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
var stock: Dictionary = {}        # shop slot (int) -> remaining today
var coin_buys_today: int = 0      # shared escalation counter for the gold slot
var restock_at: float = 0.0
var gift_source: String = ""        # return-gift sender ; "" = none waiting
var gift_refreshed_at: float = 0.0  # when the last return gift was armed

func _init() -> void:
    for t in GIFT_TYPES:
        satchel[t] = 0
    restock()

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

func restock() -> void:
    for row in ConfigDB.intimacy_shop:
        stock[int(row["Slot"])] = int(row["Number"])
    coin_buys_today = 0

func tick(now: float, rng: RandomNumberGenerator) -> void:
    if restock_at <= 0.0:
        restock_at = now + float(ConfigDB.tuning["gift_shop_restock_seconds"])
    elif now >= restock_at:
        restock()
        restock_at = now + float(ConfigDB.tuning["gift_shop_restock_seconds"])
        satchel_changed.emit()
    maybe_refresh_return_gift(now, rng)

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

## Once per cooldown window a befriended character (weight = intimacy level)
## sends a return gift. An empty pool of friends does NOT consume the window.
func maybe_refresh_return_gift(now: float, rng: RandomNumberGenerator) -> bool:
    if gift_source != "":
        return false
    if now - gift_refreshed_at < float(ConfigDB.tuning["return_gift_cooldown_seconds"]):
        return false
    var weighted: Array = []
    for row in ConfigDB.intimacy_list:
        var lvl := level_of(String(row["Name"]))
        if lvl > 0:
            weighted.append("%s-%d" % [String(row["Name"]), lvl])
    if weighted.is_empty():
        return false
    gift_source = String(Weighted.roll(Weighted.parse(weighted), rng))
    gift_refreshed_at = now
    satchel_changed.emit()
    return true

## The gift contents are one weighted roll from the sender's CURRENT level
## row's Gifts pool ("item-count-weight" triplets; Weighted's rsplit-once
## leaves "item-count", which is already a valid reward token).
func claim_return_gift(game, now: float) -> Dictionary:
    if gift_source == "":
        return {"ok": false, "reason": "no_gift"}
    var rows: Array = ConfigDB.intimacy_levels.get(gift_source, [])
    var lvl := clampi(level_of(gift_source), 1, maxi(1, rows.size()))
    if rows.is_empty():
        gift_source = ""
        return {"ok": false, "reason": "no_gift"}
    var row: Dictionary = rows[lvl - 1]
    var pool_v: Variant = row.get("Gifts")
    var pool: Array = pool_v if pool_v is Array else []
    if pool.is_empty():
        gift_source = ""
        satchel_changed.emit()
        return {"ok": false, "reason": "no_gift"}
    var picked := String(Weighted.roll(Weighted.parse(pool), game.rng))
    Rewards.grant(picked, game, now)
    var sender := gift_source
    gift_source = ""
    satchel_changed.emit()
    return {"ok": true, "reason": "", "sender": sender, "reward": picked}

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
    var mult := float(ConfigDB.tuning["intimacy_preferred_multiplier"]) if prefs.has(type) else 1.0
    t["points"] = int(t["points"]) + ceili(float(gift_row["Intimacy"]) * mult)
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

## Only character story/background/portrait keys are memories; any other
## unknown token (e.g. booster ids) falls through to Rewards' warn-and-skip.
func _is_story_token(token: String) -> bool:
    return token.begins_with("character_")

func to_dict() -> Dictionary:
    return {"satchel": satchel.duplicate(), "tracks": tracks.duplicate(true),
            "story_unlocks": story_unlocks.duplicate(), "stock": stock.duplicate(),
            "coin_buys_today": coin_buys_today, "restock_at": restock_at,
            "gift_source": gift_source, "gift_refreshed_at": gift_refreshed_at}

static func from_dict(d: Dictionary) -> Intimacy:
    var im := Intimacy.new()
    for t in d.get("satchel", {}):
        im.satchel[String(t)] = int(d["satchel"][t])
    for who in d.get("tracks", {}):
        im.tracks[String(who)] = {"level": int(d["tracks"][who]["level"]),
                "points": int(d["tracks"][who]["points"])}
    for s in d.get("story_unlocks", []):
        im.story_unlocks.append(String(s))
    for k in d.get("stock", {}):
        im.stock[int(k)] = int(d["stock"][k])
    im.coin_buys_today = int(d.get("coin_buys_today", 0))
    im.restock_at = float(d.get("restock_at", 0.0))
    im.gift_source = String(d.get("gift_source", ""))
    im.gift_refreshed_at = float(d.get("gift_refreshed_at", 0.0))
    return im
