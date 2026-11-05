class_name Hud
extends VBoxContainer

var game: Game
var _energy := Label.new()
var _coins := Label.new()
var _level := Label.new()

func setup(g: Game) -> void:
    game = g
    for l in [_energy, _coins, _level]:
        add_child(l)
    game.wallet.changed.connect(refresh)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(refresh)
    add_child(t)
    refresh()

func refresh() -> void:
    var now := Time.get_unix_time_from_system()
    var e := game.wallet.energy(now)
    var suffix := "" if e >= int(ConfigDB.tuning["energy_max"]) else " (+1 in %ds)" % int(game.wallet.seconds_to_next_energy(now))
    _energy.text = "Energy: %d%s" % [e, suffix]
    _coins.text = "Coins: %d   Gems: %d" % [game.wallet.coins, game.wallet.gems]
    _level.text = "Level %d   XP %d" % [game.player.level, game.player.xp]
