class_name GalaPanel
extends CanvasLayer
## The Patron's Gala: task ladder, active buffs, countdowns, and
## clearly-labeled DEV lifecycle controls. Placeholder styling.
## No board here - the gala buffs the MAIN board.

signal action_rejected(reason: String)
signal visibility_changed_to(open: bool)

const RUNG_NAMES := {
    "moreLuckyProduce": "Lucky Finds",
    "extraProduce": "Overflowing Cases",
    "extraLuckyProduce": "Twin Discoveries",
    "nocd": "Tireless Curators",
}

var game: Game
var _body: Label

func setup(g: Game) -> void:
    game = g
    layer = 13            # above EventPanel's 12: both can be open in sequence
    visible = false
    var bg := ColorRect.new()
    bg.color = Color(0.10, 0.08, 0.05, 0.97)
    bg.anchor_right = 1.0
    bg.anchor_bottom = 1.0
    add_child(bg)
    var header := Label.new()
    header.text = "The Patron's Gala"
    header.position = Vector2(10, 8)
    header.add_theme_font_size_override("font_size", 24)
    add_child(header)
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.position = Vector2(600, 8)
    close_b.pressed.connect(close)
    add_child(close_b)
    var dev_start := Button.new()
    dev_start.text = "DEV: Start gala"
    dev_start.position = Vector2(10, 44)
    dev_start.pressed.connect(_dev_start)
    add_child(dev_start)
    var dev_end := Button.new()
    dev_end.text = "DEV: End gala"
    dev_end.position = Vector2(160, 44)
    dev_end.pressed.connect(_dev_end)
    add_child(dev_end)
    _body = Label.new()
    _body.position = Vector2(10, 90)
    _body.add_theme_font_size_override("font_size", 18)
    add_child(_body)
    game.boost.boost_changed.connect(_refresh)
    var t := Timer.new()   # parented on the CanvasLayer, never freed by refresh
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_refresh)
    add_child(t)

func open() -> void:
    visible = true
    _refresh()
    visibility_changed_to.emit(true)

func close() -> void:
    visible = false
    visibility_changed_to.emit(false)

func _dev_start() -> void:
    if not game.dev_start_boost(Time.get_unix_time_from_system()):
        action_rejected.emit("boost_already_active")
    _refresh()

func _dev_end() -> void:
    game.dev_end_boost(Time.get_unix_time_from_system())
    _refresh()

func _fmt(seconds: float) -> String:
    var s := maxi(0, int(seconds))
    return "%dh %02dm %02ds" % [s / 3600, (s % 3600) / 60, s % 60]

func _refresh() -> void:
    if not visible:
        return
    var b := game.boost
    if not b.is_active():
        _body.text = "The Hall is quiet. The next gala has not been announced."
        if b.next_boost_at > 0.0:
            var now := Time.get_unix_time_from_system()
            _body.text += "\nDoors open in " + _fmt(b.next_boost_at - now)
        return
    var now := Time.get_unix_time_from_system()
    var tasks: Array = ConfigDB.tuning["boost_tasks"]
    var buffs: Array = ConfigDB.tuning["boost_buffs"]
    var lines: Array[String] = []
    lines.append("Night %d of the gala.  Doors close in %s" % [b.round_num, _fmt(b.ends_at - now)])
    lines.append("Nightly reset (UTC midnight) in %s" % _fmt(b.rollover_at - now))
    lines.append("Orders fulfilled tonight: %d" % b.progress)
    lines.append("")
    for i in range(buffs.size()):
        var kind := String(buffs[i])
        var name: String = RUNG_NAMES.get(kind, kind)
        var need := int(tasks[i])
        if i < b.buff_level:
            lines.append("* %s - ACTIVE" % name)
        else:
            lines.append("  %s - unlocks at %d orders" % [name, need])
    _body.text = "\n".join(lines)
