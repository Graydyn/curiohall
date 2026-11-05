class_name Weighted

## Parses weighted-entry strings like "201-100" into {"id": String, "weight": int} dicts.
static func parse(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in entries:
		var parts: PackedStringArray = String(e).rsplit("-", true, 1)
		out.append({"id": parts[0], "weight": int(parts[1])})
	return out

## Rolls one weighted pick from parsed entries using the given RNG.
static func roll(parsed: Array, rng: RandomNumberGenerator) -> String:
	var total := 0
	for p in parsed:
		total += int(p["weight"])
	var pick := rng.randi_range(1, total)
	for p in parsed:
		pick -= int(p["weight"])
		if pick <= 0:
			return p["id"]
	return parsed[-1]["id"]
