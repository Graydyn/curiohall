class_name Rewards
## Single grammar + sink for every reward token in the game.
## "gold-N" = coins, "gem-N" = gems, "energy-N" = energy, "exp-N" = player XP,
## else item id + count.

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
				if game.board.spawn(id, Vector2i(3, 4)) == Vector2i(-1, -1):
					game.player.store(id)

static func grant_all(tokens: Array, game, now: float) -> void:
	for t in tokens:
		grant(String(t), game, now)
