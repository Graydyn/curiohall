class_name Hud
extends HBoxContainer
## Horizontal top bar: energy, coins, gems, level.

var game: Game
var _energy := Label.new()
var _coins := Label.new()
var _gems := Label.new()
var _level := Label.new()

func setup(g: Game) -> void:
    game = g
    add_theme_constant_override("separation", 18)
    for l in [_energy, _coins, _gems, _level]:
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
    var suffix := "" if e >= int(ConfigDB.tuning["energy_max"]) else " (+1 %ds)" % int(game.wallet.seconds_to_next_energy(now))
    _energy.text = "Energy %d%s" % [e, suffix]
    _coins.text = "Coins %d" % game.wallet.coins
    _gems.text = "Gems %d" % game.wallet.gems
    _level.text = "Lv %d" % game.player.level
