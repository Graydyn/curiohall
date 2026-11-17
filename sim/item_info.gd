class_name ItemInfo
## Player-facing facts about an item type: family name, tier, where it comes
## from, what it does and what it sells for. Everything derives from config.

static var _trailing_digits := RegEx.create_from_string("_?\\d+$")

static func family_name(type: String) -> String:
    var art: String = ConfigDB.item_images.get(type, "")
    if art == "":
        return type
    art = _trailing_digits.sub(art, "")
    # Split CamelCase ("RawFish") and snake_case ("time_skip"), then title-case.
    var words := ""
    for i in art.length():
        var c := art[i]
        if c == "_":
            words += " "
            continue
        if i > 0 and c == c.to_upper() and c != c.to_lower() and art[i - 1] == art[i - 1].to_lower() and art[i - 1] != "_":
            words += " "
        words += c
    var out := []
    for w in words.split(" ", false):
        out.append(w[0].to_upper() + w.substr(1))
    return " ".join(out)

## The item a merge produced `type` from, or "" for a chain root.
static func _previous(type: String) -> String:
    for t in ConfigDB.items:
        if String(ConfigDB.items[t].get("MergedType", "")) == type:
            return t
    return ""

static func _root(type: String) -> String:
    var cur := type
    var prev := _previous(cur)
    while prev != "" and prev != type:
        cur = prev
        prev = _previous(cur)
    return cur

static func tier(type: String) -> int:
    var n := 1
    var cur := type
    var prev := _previous(cur)
    while prev != "" and prev != type:
        n += 1
        cur = prev
        prev = _previous(cur)
    return n

static func _chain(type: String) -> Array:
    var out := []
    var cur := _root(type)
    while cur != "" and not out.has(cur) and ConfigDB.items.has(cur):
        out.append(cur)
        cur = String(ConfigDB.items[cur].get("MergedType", ""))
    return out

static func is_consumable(type: String) -> bool:
    return ConfigDB.items.get(type, {}).has("CollectRewards")

static func is_generator(type: String) -> bool:
    return ConfigDB.items.get(type, {}).has("Spread_Weight") and not ConfigDB.is_chest(type)

static func is_sellable(type: String) -> bool:
    return ConfigDB.items.has(type) and not is_consumable(type) \
        and not ConfigDB.items[type].has("Spread_Weight")

static func sell_price(type: String) -> int:
    return 1 << (tier(type) - 1) if is_sellable(type) else 0

static func _drops(gen_type: String) -> Array:
    var out := []
    for token in ConfigDB.items[gen_type].get("Spread_Weight", []):
        out.append(String(token).rsplit("-", true, 1)[0])
    return out

## Family names of the generators that drop any member of `type`'s chain.
static func sources(type: String) -> Array:
    var chain := _chain(type)
    var out := []
    for t in ConfigDB.items:
        if not is_generator(t):
            continue
        for d in _drops(t):
            if chain.has(d):
                var name := family_name(t)
                if not out.has(name):
                    out.append(name)
                break
    out.sort()
    return out

static func reward_text(tokens: Array) -> String:
    var parts := []
    for token in tokens:
        var r := Rewards.parse(String(token))
        var n := int(r["amount"])
        match r["kind"]:
            "coins": parts.append("%d coin%s" % [n, "" if n == 1 else "s"])
            "gems": parts.append("%d gem%s" % [n, "" if n == 1 else "s"])
            "energy": parts.append("%d energy" % n)
            "xp": parts.append("%d XP" % n)
            _ when r["id"] == "skip": parts.append("time skip (%d)" % n)
            _ when r["id"] == "infinite": parts.append("unlimited energy (%d)" % n)
            _: parts.append("%s x%d" % [family_name(r["id"]), n])
    return ", ".join(parts)

## Info lines shown under the panel title.
static func lines(type: String) -> Array:
    var out := []
    var row: Dictionary = ConfigDB.items.get(type, {})
    if is_generator(type):
        var made := []
        for d in _drops(type):
            var name := family_name(d)
            if not made.has(name):
                made.append(name)
        out.append("Produces: " + ", ".join(made))
        out.append("Costs %d energy per tap" % int(row.get("Spread_CostEnergy", 0)))
    else:
        var src := sources(type)
        out.append("Made by: " + ", ".join(src) if not src.is_empty() else "Found in chests")
    if is_consumable(type):
        out.append("Tap twice to collect: " + reward_text(row["CollectRewards"]))
    elif ConfigDB.is_chest(type):
        out.append("Tap twice to open")
    return out
