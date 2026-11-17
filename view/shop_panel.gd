class_name ShopPanel
extends CanvasLayer
## Modal shop overlay: item shop, daily deals, membership (DEV-stub pass). Placeholder styling.

signal action_rejected(reason: String)

var game: Game
var _root: PanelContainer
var _list: VBoxContainer
var _membership_status: Label
var _buy_pass_btn: Button   # null when no buy button is shown (Play Pass)

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
    game.shop.shop_changed.connect(refresh)
    game.deals.deals_changed.connect(refresh)
    game.wallet.changed.connect(refresh)
    game.membership.membership_changed.connect(refresh)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(refresh)
    add_child(t)   # NOTE: child of the CanvasLayer, not of _list; refresh only rebuilds _list

func open() -> void:
    visible = true
    refresh()

func close() -> void:
    visible = false

func _label(text: String) -> Label:
    var l := Label.new()
    l.text = text
    _list.add_child(l)
    return l

func _buy_button(text: String, disabled: bool, cb: Callable) -> Button:
    var b := Button.new()
    b.text = text
    b.disabled = disabled
    b.pressed.connect(cb)
    _list.add_child(b)
    return b

func refresh() -> void:
    if not visible:
        return
    for c in _list.get_children():
        c.queue_free()
    var now := Time.get_unix_time_from_system()
    _label("SHOP   Coins: %d   Gems: %d" % [game.wallet.coins, game.wallet.gems])
    var close_b := Button.new()
    close_b.text = "X Close"
    close_b.pressed.connect(close)
    _list.add_child(close_b)
    # Item shop
    _label("-- Item Shop --")
    if game.shop.is_refreshing(now):
        _buy_button("Refresh in %ds — Skip (%d gems)" % [int(game.shop.time_to_refresh(now)), int(ConfigDB.tuning["shop_skip_gems"])],
            false, func(): _do(game.skip_shop_refresh(now)))
    for i in range(ItemShop.SLOTS):
        var slot: Variant = game.shop.slots[i]
        if slot == null:
            continue
        var n := i + 1
        if slot["sold_out"]:
            _label("  Slot %d: SOLD OUT" % n)
        else:
            var item := String(slot["item"])
            _buy_button("  Buy %s %d — %d coins (%d left)" % [ItemInfo.family_name(item), ItemInfo.tier(item),
                    int(slot["price"]), int(slot["left"])],
                game.wallet.coins < int(slot["price"]),
                func(): _do(game.buy_shop_slot(n, Time.get_unix_time_from_system())))
    # Daily deals
    _label("-- Daily Deals --")
    for deal in game.deals.deals():
        var id := int(deal["id"])
        var tag := "  (watch ad, dev free) " if deal["is_ad"] and not game.membership.is_member(now) else "  "
        if int(deal["stock"]) <= 0:
            _label("%s%s: out of stock" % [tag, deal["item"]])
        else:
            _buy_button("%sBuy %s — %d gems (stock %d)" % [tag, deal["item"], int(deal["cost_gems"]), int(deal["stock"])],
                game.wallet.gems < int(deal["cost_gems"]),
                func(): _do(game.buy_daily_deal(id, Time.get_unix_time_from_system())))
    _membership_section(now)

func _membership_section(now: float) -> void:
    var m := game.membership
    var t := ConfigDB.tuning
    _label("-- Membership --")
    if m.play_pass:
        _membership_status = _label("Included with Play Pass")
    elif m.is_member(now):
        _membership_status = _label("Member: %d days left" % m.days_left(now))
    else:
        _membership_status = _label("Not a member")
    var gems := 0
    for tok in t["membership_daily_rewards"]:
        var r := Rewards.parse(String(tok))
        if r["kind"] == "gems":
            gems += int(r["amount"])
    for perk in ["A free energy refill each day", "%d gems each day" % gems, "Double progress in events"]:
        _label("  • " + perk)
    _buy_pass_btn = null
    if not m.play_pass:
        if m.is_member(now):
            var max_until := now + float(t["membership_max_days_ahead"]) * Membership.DAY
            var would := m.member_until + float(t["membership_pass_days"]) * Membership.DAY
            _buy_pass_btn = _buy_button("Add 30 days (DEV)", would > max_until,
                func(): _do(game.buy_pass(Time.get_unix_time_from_system())))
        else:
            _buy_pass_btn = _buy_button("Buy 30 days (DEV) — %s" % String(t["membership_price_label"]), false,
                func(): _do(game.buy_pass(Time.get_unix_time_from_system())))
    _buy_button("Claim today's energy refill", not game.refill_available(now),
        func(): _do(game.claim_refill(Time.get_unix_time_from_system())))
    _buy_button("Play Pass (DEV): %s" % ("ON" if m.play_pass else "OFF"), false,
        func(): game.set_play_pass(not game.membership.play_pass))

func _do(res: Dictionary) -> void:
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()
