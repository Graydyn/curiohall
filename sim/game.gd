class_name Game
extends RefCounted

signal spawned(pos: Vector2i, type: String)

const SAVE_VERSION := 12

var board: MergeBoard
var wallet: EnergyWallet
var player: PlayerState
var orders: OrderBook
var shop: ItemShop
var deals: DailyDeals
var membership: Membership
var campaign: Campaign
var intimacy: Intimacy
var specials: SpecialOrders
var events: Events
var boost: Boost
var hall: HallState
var story: Story
var rng := RandomNumberGenerator.new()
var tz_offset_seconds: int = 0   # not saved; scenes/main.gd sets it at startup

static func fresh(now: float, seed_value: int = 0) -> Game:
    var g := Game.new()
    g.board = MergeBoard.new()
    BoardLayout.apply(g.board, ConfigDB.board_layout)
    g.wallet = EnergyWallet.fresh(now)
    g.player = PlayerState.new()
    if seed_value != 0:
        g.rng.seed = seed_value
    else:
        g.rng.randomize()
    g.orders = OrderBook.new()
    g.orders.fill(g.player.level, g.rng, now)
    g.shop = ItemShop.new()
    g.shop.fill(g.rng, now)
    g.deals = DailyDeals.new()
    g.membership = Membership.new()
    g.campaign = Campaign.new()
    g.intimacy = Intimacy.new()
    g.specials = SpecialOrders.new()
    g.events = Events.new()
    g.boost = Boost.new()
    g.hall = HallState.new()
    g.story = Story.new()
    g.story.enqueue(["area_opened:1"])
    return g

func merge(a: Vector2i, b: Vector2i, now: float) -> String:
    var err := board.merge(a, b)
    for pos in board.take_unboxed():
        var token := ConfigDB.paperbox_reward(pos)
        if token != "":
            Rewards.grant(token, self, now)
    return err

## Sell the item at `pos` for its coin price (see ItemInfo.sell_price).
func sell(pos: Vector2i) -> Dictionary:
    var res := board.sell(pos)
    if res["ok"]:
        wallet.add_coins(int(res["coins"]))
    return res

func tap(pos: Vector2i, now: float) -> Dictionary:
    var item := board.item_at(pos)
    if item == null:
        return {"ok": false, "kind": "none", "reason": "empty"}
    if board.state_at(pos) != MergeBoard.CellState.OPEN:
        return {"ok": false, "kind": "none", "reason": "not_open"}
    var row: Dictionary = ConfigDB.items.get(item.type, {})
    if row.has("CollectRewards"):
        Rewards.grant_all(row["CollectRewards"], self, now)
        board.remove(pos)
        return {"ok": true, "kind": "collect", "reason": ""}
    if item.chest != null:
        if item.chest.is_spent():
            board.remove(pos)
            return {"ok": false, "kind": "chest", "reason": "spent"}
        if not item.chest.can_open(now):
            return {"ok": false, "kind": "chest", "reason": "chest_wait"}
        var target := board.find_free_cell(pos)
        if target == Vector2i(-1, -1):
            return {"ok": false, "kind": "chest", "reason": "board_full"}
        var drop := item.chest.open(now, rng)
        board.place(target, ItemInstance.make(drop, now))
        spawned.emit(target, drop)
        if item.chest.is_spent():
            board.remove(pos)
        return {"ok": true, "kind": "chest", "reason": "", "spawned": [{"pos": target, "type": drop}]}
    if item.gen != null:
        var res := tap_generator(pos, now)
        res["kind"] = "generator"
        return res
    return {"ok": false, "kind": "none", "reason": "not_tappable"}

func tap_generator(pos: Vector2i, now: float) -> Dictionary:
    var item := board.item_at(pos)
    if item == null or item.gen == null or board.state_at(pos) != MergeBoard.CellState.OPEN:
        return {"ok": false, "reason": "not_generator", "spawned": []}
    var row: Dictionary = boost.effective_row(item.type)
    var cost := int(row.get("Spread_CostEnergy", 0))
    if wallet.energy(now) < cost:
        return {"ok": false, "reason": "no_energy", "spawned": []}
    var nocd := boost.is_buff_active("nocd") and boost.is_boosted(item.type)
    if not nocd and item.gen.charges(now) <= 0 and item.gen.storage(now) <= 0:
        return {"ok": false, "reason": "no_charge", "spawned": []}
    var drop := Weighted.roll(Weighted.parse(row["Spread_Weight"]), rng)
    var target := board.find_free_cell(pos)
    if target == Vector2i(-1, -1):
        return {"ok": false, "reason": "board_full", "spawned": []}
    wallet.spend_energy(cost, now)
    if not nocd:
        item.gen.consume(now)
    board.place(target, ItemInstance.make(drop, now))
    spawned.emit(target, drop)
    var result := [{"pos": target, "type": drop}]
    # Patron's Gala: guaranteed double-spawn quota (free, cache-when-full).
    if boost.is_buff_active("extraProduce") and boost.is_boosted(item.type):
        if boost.claim_extra(rng):
            var extra_pos := board.find_free_cell(pos)
            if extra_pos == Vector2i(-1, -1):
                boost.report_extra_blocked()
            else:
                var extra_drop := Weighted.roll(Weighted.parse(row["Spread_Weight"]), rng)
                board.place(extra_pos, ItemInstance.make(extra_drop, now))
                spawned.emit(extra_pos, extra_drop)
                result.append({"pos": extra_pos, "type": extra_drop, "extra": true})
    var lucky_type: String = LuckyRoller.roll(item.type, player.level, rng, boost.effective_lucky())
    if lucky_type != "":
        var lucky_pos := board.find_free_cell(pos)
        if lucky_pos != Vector2i(-1, -1):
            board.place(lucky_pos, ItemInstance.make(lucky_type, now))
            spawned.emit(lucky_pos, lucky_type)
            result.append({"pos": lucky_pos, "type": lucky_type, "lucky": true})
        # Patron's Gala: twin lucky (a second copy, cache-when-full).
        if boost.is_buff_active("extraLuckyProduce") and boost.is_boosted(item.type):
            var twin_pos := board.find_free_cell(pos)
            if twin_pos == Vector2i(-1, -1):
                boost.cache_extra_lucky(lucky_type)
            else:
                board.place(twin_pos, ItemInstance.make(lucky_type, now))
                spawned.emit(twin_pos, lucky_type)
                result.append({"pos": twin_pos, "type": lucky_type, "lucky": true, "extra": true})
    elif boost.is_buff_active("extraLuckyProduce") and boost.is_boosted(item.type) \
            and boost.extra_lucky_cached != "":
        var cached_pos := board.find_free_cell(pos)
        if cached_pos != Vector2i(-1, -1):
            var cached_type := boost.take_cached_lucky()
            board.place(cached_pos, ItemInstance.make(cached_type, now))
            spawned.emit(cached_pos, cached_type)
            result.append({"pos": cached_pos, "type": cached_type, "lucky": true, "extra": true})
    return {"ok": true, "reason": "", "spawned": result}

func _grant_level_rewards(gained: Array, now: float) -> void:
    for lvl in gained:
        var rewards: Array = ConfigDB.levels[int(lvl) - 1].get("rewards", [])
        Rewards.grant_all(rewards, self, now)

func grant_xp(n: int, now: float) -> void:
    _grant_level_rewards(player.add_xp(n), now)

## Place the front item of the reward stack on the board, nearest the centre.
## Leaves the stack untouched if it is empty or the board has no free cell.
func place_reward() -> Dictionary:
    var t := player.peek_reward()
    if t == "":
        return {"ok": false, "reason": "no_reward"}
    var pos := board.spawn(t, Vector2i(3, 4))
    if pos == Vector2i(-1, -1):
        return {"ok": false, "reason": "board_full"}
    player.pop_reward()
    return {"ok": true, "reason": "", "pos": pos, "type": t}

## Take the item in storage slot i out and place it on the board, nearest the
## centre. Leaves storage untouched if the board has no free cell.
func withdraw_stored(i: int) -> Dictionary:
    if i < 0 or i >= player.inventory.size():
        return {"ok": false, "reason": "empty"}
    var t: String = player.inventory[i]
    var pos := board.spawn(t, Vector2i(3, 4))
    if pos == Vector2i(-1, -1):
        return {"ok": false, "reason": "board_full"}
    player.withdraw(i)
    return {"ok": true, "reason": "", "pos": pos, "type": t}

func unlock_storage_slot() -> Dictionary:
    var cost := player.next_slot_cost()
    if cost < 0:
        return {"ok": false, "reason": "storage_maxed"}
    if not player.unlock_slot(wallet):
        return {"ok": false, "reason": "not_enough_gems"}
    return {"ok": true, "reason": ""}

func skip_order_refresh(i: int, now: float) -> Dictionary:
    if not orders.skip_refresh(i, wallet, now):
        return {"ok": false, "reason": "not_enough_gems"}
    orders.fill(player.level, rng, now)
    return {"ok": true, "reason": ""}

func tick_orders(now: float) -> void:
    orders.fill(player.level, rng, now)

func deliver_order(i: int, now: float) -> Dictionary:
    var res := orders.deliver(i, board)
    if not res["ok"]:
        return res
    orders.set_cooldown(i, float(res["refresh_time"]), now)
    wallet.add_coins(int(res["coins"]))
    grant_xp(int(res["xp"]), now)
    intimacy.grant_order_gifts(int(res["coins"]), rng)
    intimacy.maybe_refresh_return_gift(now, rng)
    events.on_order_delivered(self, now)
    boost.on_order_delivered(now)
    orders.fill(player.level, rng, now)
    return res

func tick_shop(now: float) -> void:
    if shop.refresh_at > 0.0 and now >= shop.refresh_at:
        for i in range(ItemShop.SLOTS):
            shop.slots[i] = null
        shop.refresh_at = 0.0
        shop.fill(rng, now)
    elif not shop.is_refreshing(now):
        var all_sold := true
        for slot in shop.slots:
            if slot == null or not slot["sold_out"]:
                all_sold = false
                break
        if all_sold:
            shop.set_refresh(now)
    deals.tick(now)

func buy_shop_slot(n: int, now: float) -> Dictionary:
    return shop.buy(n, wallet, self, now)

func skip_shop_refresh(now: float) -> Dictionary:
    if not shop.is_refreshing(now):
        return {"ok": false, "reason": "not_refreshing"}
    if shop.skip_refresh(wallet, now):
        shop.fill(rng, now)
        return {"ok": true, "reason": ""}
    return {"ok": false, "reason": "not_enough_gems"}

func buy_daily_deal(id: int, now: float) -> Dictionary:
    return deals.buy(id, wallet, self, now)

## Local calendar day index (midnight in the player's time zone).
func local_day(now: float) -> int:
    return floori((now + tz_offset_seconds) / 86400.0)

func tick_membership(now: float) -> void:
    membership.tick(self, now, local_day(now))

func buy_pass(now: float) -> Dictionary:
    return membership.buy_pass(now)

func refill_available(now: float) -> bool:
    return membership.refill_available(now, local_day(now))

func claim_refill(now: float) -> Dictionary:
    return membership.claim_refill(self, now, local_day(now))

## Calendar days from today to the local day the pass ends (0 = ends today).
func membership_end_days(now: float) -> int:
    return local_day(membership.member_until - 1.0) - local_day(now)

func take_membership_reminder(now: float) -> String:
    return membership.take_reminder(now, local_day(now), local_day(membership.member_until - 1.0))

func set_play_pass(on: bool, now: float) -> void:
    membership.set_play_pass(on, now)

func complete_task(id: int, now: float) -> Dictionary:
    var key := Campaign.task_key(campaign.day, id)
    var day_before := campaign.day
    var area_before := campaign.current_area()
    var res := campaign.complete_task(id, self, now)
    if res["ok"]:
        specials.maybe_activate(campaign, self, now)
        var triggers := ["task:" + key]
        var el := HallElements.of_task(key)
        if el != "" and HallElements.stage(el, campaign) == HallElements.Stage.DONE:
            hall.finish(el)
            res["element"] = el
            triggers.append("element:" + el)
        if campaign.day != day_before:
            triggers.append("day:%d" % campaign.day)
            var area_after := campaign.current_area()
            if area_after != area_before:
                triggers.append("area_opened:%d" % area_after)
        story.enqueue(triggers)
    return res

func pick_look(id: String, look: int) -> Dictionary:
    if not ConfigDB.hall_elements.has(id):
        return {"ok": false, "reason": "unknown_element"}
    if HallElements.stage(id, campaign) != HallElements.Stage.DONE:
        return {"ok": false, "reason": "not_done"}
    var look_count: int = (ConfigDB.hall_elements[id]["looks"] as Array).size()
    if look < 0 or look >= look_count:
        return {"ok": false, "reason": "bad_look"}
    hall.set_look(id, look)
    return {"ok": true, "reason": ""}

func deliver_special(now: float) -> Dictionary:
    return specials.deliver(board, self, now)

func give_gift(name: String, type: String, now: float) -> Dictionary:
    return intimacy.give_gift(name, type, self, now)

func tick_gifts(now: float) -> void:
    intimacy.tick(now, rng)

func claim_free_gift() -> Dictionary:
    return intimacy.claim_free(rng)

func buy_gift_coins(type: String) -> Dictionary:
    return intimacy.buy_with_coins(type, wallet)

func buy_gift_gems(type: String) -> Dictionary:
    return intimacy.buy_with_gems(type, wallet)

func claim_return_gift(now: float) -> Dictionary:
    return intimacy.claim_return_gift(self, now)

func tick_events(now: float) -> void:
    events.tick(now, player)

func dev_start_event(now: float) -> bool:
    return events.start_event(now)

func dev_end_event(now: float) -> void:
    events.end_event(now)

func tick_boost(now: float) -> void:
    boost.tick(now, player)

func dev_start_boost(now: float) -> bool:
    return boost.start_boost(now)

func dev_end_boost(now: float) -> void:
    boost.end_boost(now)

func merge_event(a: Vector2i, b: Vector2i, now: float) -> String:
    if not events.is_active():
        return "no_event"
    var err := events.board.merge(a, b)
    if err != "":
        return err
    for pos in events.board.take_unboxed():
        var token := ConfigDB.event_paperbox_reward(events.variant, pos)
        if token != "":
            Rewards.grant(token, self, now)
    events.record_merge(events.board.item_at(b).type, self, now)
    return ""

func to_dict() -> Dictionary:
    return {
        "save_version": SAVE_VERSION,
        "board": board.to_dict(),
        "wallet": wallet.to_dict(),
        "player": player.to_dict(),
        "orders": orders.to_dict(),
        "shop": shop.to_dict(),
        "deals": deals.to_dict(),
        "membership": membership.to_dict(),
        "campaign": campaign.to_dict(),
        "intimacy": intimacy.to_dict(),
        "specials": specials.to_dict(),
        "events": events.to_dict(),
        "boost": boost.to_dict(),
        "hall": hall.to_dict(),
        "story": story.to_dict(),
    }

static func from_dict(d: Dictionary) -> Game:
    # Structural and version validation happens in SaveManager.load_game();
    # by the time a dict reaches here it is trusted to have the expected shape.
    var g := Game.new()
    g.board = MergeBoard.from_dict(d["board"])
    g.wallet = EnergyWallet.from_dict(d["wallet"])
    g.player = PlayerState.from_dict(d["player"])
    g.orders = OrderBook.from_dict(d["orders"])
    g.shop = ItemShop.from_dict(d["shop"])
    g.deals = DailyDeals.from_dict(d["deals"])
    g.membership = Membership.from_dict(d["membership"])
    g.campaign = Campaign.from_dict(d["campaign"])
    g.intimacy = Intimacy.from_dict(d["intimacy"])
    g.specials = SpecialOrders.from_dict(d["specials"])
    g.events = Events.from_dict(d["events"])
    g.boost = Boost.from_dict(d["boost"])
    g.hall = HallState.from_dict(d["hall"])
    g.story = Story.from_dict(d["story"])
    g.rng.randomize()
    return g
