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
    if game.intimacy.gift_source != "":
        _label("%s sent you a gift!" % Cast.display_name(game.intimacy.gift_source))
        _button("Claim gift", false, _claim_return_gift)
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
    _label("--- MEMORIES ---")
    var orig := name.to_lower()
    var mems: Array = []
    for s in game.intimacy.story_unlocks:
        if String(s).begins_with("character_story_" + orig) \
                or String(s).begins_with("character_intimacy_background_" + orig) \
                or String(s).begins_with("character_moment_" + orig) \
                or String(s).begins_with("character_" + orig):
            if not mems.has(String(s)):
                mems.append(String(s))
    if mems.is_empty():
        _label("No memories yet")
    for m in mems:
        _label(String(m))
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

func _claim_return_gift() -> void:
    var res: Dictionary = game.claim_return_gift(Time.get_unix_time_from_system())
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()

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
