class_name Rewards
## Single grammar + sink for every reward token in the game.
## "gold-N" = coins, "gem-N" = gems, "energy-N" = energy, "exp-N" = player XP,
## else item id + count. Items go onto the player's reward stack rather than
## straight onto the board; Game.place_reward puts them down when tapped.

const _CURRENCY := {"gold": "coins", "gem": "gems", "energy": "energy", "exp": "xp"}

static func parse(token: String) -> Dictionary:
	var parts: PackedStringArray = String(token).rsplit("-", true, 1)
	var id: String = parts[0]
	var amount: int = int(parts[1]) if parts.size() > 1 else 1
	var kind: String = _CURRENCY.get(id, "item")
	return {"kind": kind, "id": id, "amount": amount}

static func grant(token: String, game, now: float) -> void:
	var r := parse(token)
	match r["kind"]:
		"coins":
			game.wallet.add_coins(int(r["amount"]))
		"gems":
			game.wallet.add_gems(int(r["amount"]))
		"energy":
			game.wallet.add_energy(int(r["amount"]), now)
		"xp":
			game.grant_xp(int(r["amount"]), now)
		"item":
			var id: String = r["id"]
			if not ConfigDB.items.has(id):
				push_warning("Rewards.grant: unknown item token '%s' skipped" % token)
				return
			for i in range(int(r["amount"])):
				game.player.push_reward(id)

## Comparable worth of a reward token, from tuning.reward_value_weights
## (keyed by parse()'s kind). Used to keep event prize ladders in shape.
static func value(token: String) -> float:
	var r := parse(token)
	var weights: Dictionary = ConfigDB.tuning["reward_value_weights"]
	return float(r["amount"]) * float(weights.get(r["kind"], 0.0))

static func grant_all(tokens: Array, game, now: float) -> void:
	for t in tokens:
		grant(String(t), game, now)
