class_name LuckyRoller

static func roll(generator_type: String, player_level: int, rng: RandomNumberGenerator, table: Array = []) -> String:
    var rows: Array = table if not table.is_empty() else ConfigDB.lucky
    for row in rows:
        if row == null:
            continue
        if not (row["generator"] as Array).has(generator_type):
            continue
        if player_level < int(row["level_min"]) or player_level > int(row["level_max"]):
            continue
        var chance: Array = row["lucky_chance"]   # [denominator, numerator]
        if rng.randi_range(1, int(chance[0])) > int(chance[1]):
            return ""
        return Weighted.roll(Weighted.parse(row["lucky_items"]), rng)
    return ""
