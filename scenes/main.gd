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
    game.orders.fill(game.player.level, game.rng, now)
    home.setup(game)
    for sig in [game.board.item_placed, game.board.item_removed, game.wallet.changed, game.shop.shop_changed, game.deals.deals_changed, game.campaign.task_completed, game.intimacy.satchel_changed, game.intimacy.intimacy_changed, game.specials.special_changed, game.events.event_changed, game.boost.boost_changed, game.hall.element_finished, game.hall.look_changed, game.story.scene_queued]:
        sig.connect(func(..._args): _save_pending = true)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_flush_save)
    add_child(t)

func _flush_save() -> void:
    game.tick_shop(Time.get_unix_time_from_system())
    game.tick_orders(Time.get_unix_time_from_system())
    game.tick_gifts(Time.get_unix_time_from_system())
    game.tick_events(Time.get_unix_time_from_system())
    game.tick_boost(Time.get_unix_time_from_system())
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
