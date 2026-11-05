class_name OrderBar
extends HBoxContainer

signal action_rejected(reason: String)

var game: Game

func setup(g: Game) -> void:
    game = g
    game.orders.orders_changed.connect(refresh)
    game.specials.special_changed.connect(refresh)
    game.board.item_placed.connect(func(_p, _t): refresh())
    game.board.item_removed.connect(func(_p): refresh())
    refresh()
    var t := Timer.new(); t.wait_time = 1.0; t.autostart = true
    t.timeout.connect(refresh); add_child(t)

func refresh() -> void:
    for c in get_children():
        if c is Timer:
            continue
        c.queue_free()
    for i in range(OrderBook.SLOTS):
        var o: Variant = game.orders.orders[i]
        var btn := Button.new()
        if o == null:
            if game.orders.is_cooling(i, Time.get_unix_time_from_system()):
                var secs := int(game.orders.time_to_refresh(i, Time.get_unix_time_from_system()))
                btn.text = "New order in %ds\nSkip (%d gems)" % [secs, int(ConfigDB.tuning["order_skip_gems"])]
                var idx := i
                btn.pressed.connect(func():
                    var res: Dictionary = game.skip_order_refresh(idx, Time.get_unix_time_from_system())
                    if not res["ok"]:
                        action_rejected.emit(String(res["reason"])))
            else:
                btn.text = "-"
                btn.disabled = true
        else:
            var parts: Array[String] = []
            for code in o["items"]:
                parts.append("%s x%d (have %d)" % [code, o["items"][code], game.board.count_of(code)])
            var avatar_line := ""
            var avatar_v: Variant = o.get("avatar")
            if avatar_v != null and String(avatar_v) != "":
                avatar_line = Cast.display_name(String(avatar_v)) + "\n"
            btn.text = "%s%s\n%d coins" % [avatar_line, ", ".join(parts), o["coins"]]
            btn.disabled = not game.orders.can_deliver(i, game.board)
            btn.pressed.connect(func(): game.deliver_order(i, Time.get_unix_time_from_system()))
        add_child(btn)
    var sp: Dictionary = game.specials.current()
    if not sp.is_empty():
        var reqs: Array = SpecialOrders.requirements(sp)
        var sa_v: Variant = ConfigDB.order_avatars.get("SpecialAvatars")
        var sa: Dictionary = sa_v if sa_v is Dictionary else {}
        var who := String(sa.get(str(sp["AvatarId"]), ""))
        var needs_lines: Array[String] = []
        var all_present := true
        for req in reqs:
            var have := game.board.count_of(String(req))
            needs_lines.append("needs 1x %s (have %d)" % [String(req), have])
            if have < 1:
                all_present = false
        var b := Button.new()
        b.text = "* %s *\n%s\n%s\nfrom chain %s" % [
                Cast.display_name(who), String(sp["DescriptionKey"]),
                "\n".join(needs_lines), str(sp["GeneratorChain"])]
        b.disabled = not all_present
        b.pressed.connect(func() -> void:
            var res: Dictionary = game.deliver_special(Time.get_unix_time_from_system())
            if not res["ok"]:
                action_rejected.emit(String(res["reason"])))
        add_child(b)
