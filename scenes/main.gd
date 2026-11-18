extends Node

var game: Game
var _save_pending := false

@onready var home: HomeScreen = $Home

func _ready() -> void:
    get_tree().set_auto_accept_quit(false)
    get_tree().quit_on_go_back = false
    var now := Time.get_unix_time_from_system()
    game = SaveManager.load_game()
    if game == null:
        game = Game.fresh(now)
    game.tz_offset_seconds = int(Time.get_time_zone_from_system()["bias"]) * 60
    game.orders.fill(game.player.level, game.rng, now)
    home.setup(game)
    home.workroom.save_requested.connect(func(): _save_pending = true)
    for sig in [game.board.item_placed, game.board.item_removed, game.wallet.changed, game.shop.shop_changed, game.deals.deals_changed, game.campaign.task_completed, game.intimacy.satchel_changed, game.intimacy.intimacy_changed, game.specials.special_changed, game.events.event_changed, game.boost.boost_changed, game.player.rewards_changed, game.membership.membership_changed, game.hall.element_finished, game.hall.look_changed, game.story.scene_queued]:
        sig.connect(func(..._args): _save_pending = true)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_flush_save)
    add_child(t)

## Pays the daily gem allowance and shows a calm lapse reminder at most once
## per local day. Toasts reuse the reject-message channel for their copy.
func _tick_membership(now: float) -> void:
    game.tick_membership(now)
    var key := game.take_membership_reminder(now)
    if key == "ending_soon":
        var n := game.membership_end_days(now)
        home.show_toast_text("Your membership ends in %d day%s" % [n, "" if n == 1 else "s"])
    elif key != "":
        home.show_toast(key)

func _flush_save() -> void:
    game.tick_shop(Time.get_unix_time_from_system())
    game.tick_orders(Time.get_unix_time_from_system())
    game.tick_gifts(Time.get_unix_time_from_system())
    game.tick_events(Time.get_unix_time_from_system())
    game.tick_boost(Time.get_unix_time_from_system())
    _tick_membership(Time.get_unix_time_from_system())
    if _save_pending:
        _save_pending = false
        SaveManager.save(game)

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST:
        SaveManager.save(game)
        get_tree().quit()
    elif what == NOTIFICATION_APPLICATION_PAUSED:
        SaveManager.save(game)
    elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
        if not home.go_back():
            SaveManager.save(game)
            get_tree().quit()
