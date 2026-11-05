class_name ShopPanel
extends CanvasLayer
## Modal shop overlay: item shop, daily deals, dev-stub IAP. Placeholder styling.

signal action_rejected(reason: String)

var game: Game
var _root: PanelContainer
var _list: VBoxContainer

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

func _label(text: String) -> void:
    var l := Label.new()
    l.text = text
    _list.add_child(l)

func _buy_button(text: String, disabled: bool, cb: Callable) -> void:
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
            _buy_button("  Buy %s x%d — %d coins" % [slot["item"], int(slot["count"]), int(slot["price"])],
                game.wallet.coins < int(slot["price"]),
                func(): _do(game.buy_shop_slot(n, Time.get_unix_time_from_system())))
    # Daily deals
    _label("-- Daily Deals --")
    for deal in game.deals.deals():
        var id := int(deal["id"])
        var tag := "  (watch ad, dev free) " if deal["is_ad"] else "  "
        if int(deal["stock"]) <= 0:
            _label("%s%s: out of stock" % [tag, deal["item"]])
        else:
            _buy_button("%sBuy %s — %d gems (stock %d)" % [tag, deal["item"], int(deal["cost_gems"]), int(deal["stock"])],
                game.wallet.gems < int(deal["cost_gems"]),
                func(): _do(game.buy_daily_deal(id, Time.get_unix_time_from_system())))
    # IAP (dev stub)
    _label("-- Get Gems (DEV STUB) --")
    for pack in game.iap.packs():
        var pid := String(pack["purchase_id"])
        _buy_button("  [DEV] %s -> %s" % [pid, ", ".join(pack["goods"])],
            false, func(): _do(game.buy_iap_pack(pid, Time.get_unix_time_from_system())))
    var bs := game.iap.bundle_state(game, now)
    if String(bs["reason"]) != "locked":
        game.iap.note_seen(now)
        bs = game.iap.bundle_state(game, now)
    if bs["available"]:
        _buy_button("  [DEV] Starter Bundle -> %s" % ", ".join(bs["goods"]),
            false, func(): _do(game.buy_bundle(Time.get_unix_time_from_system())))
    else:
        _label("  Starter Bundle: %s" % bs["reason"])

func _do(res: Dictionary) -> void:
    if not res["ok"]:
        action_rejected.emit(String(res["reason"]))
    refresh()
