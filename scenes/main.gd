extends Node

const REJECT_MESSAGES := {
    "not_open": "That item is still covered - merge next to it to free it",
    "mismatch": "Those items don't match",
    "chain_top": "That item is fully upgraded",
    "empty": "Nothing there to merge",
    "occupied": "That space is taken",
    "no_energy": "Out of energy",
    "no_charge": "Generator is recharging",
    "board_full": "The board is full",
    "chest_wait": "The chest isn't ready yet",
    "spent": "That chest is empty",
    "not_enough_gems": "Not enough gems",
    "not_refreshing": "Shop already refreshed",
    "not_enough_coins": "Not enough coins",
    "sold_out": "Sold out",
    "out_of_stock": "Out of stock",
    "locked": "Unlocks at level 3",
    "already_bought": "Already purchased",
    "expired": "Offer expired",
    "unknown": "Unavailable",
    "not_today": "That task isn't on today's docket",
    "already_done": "Already completed",
    "area_locked": "That wing is still locked",
    "no_gift": "None of that gift left - deliver more orders",
    "maxed": "Their friendship is already complete",
    "bad_type": "Unavailable",
    "not_active": "No special request is waiting",
    "no_item": "The requested curio isn't on the board",
    "no_event": "No expedition is underway",
    "event_already_active": "An expedition is already underway",
    "boost_already_active": "The gala is already under way.",
}

var game: Game
var _save_pending := false
var _toast: Label
var _toast_timer: Timer
var _event_panel_open := false
var _gala_panel_open := false
var gala_panel: GalaPanel
var gala_button: Button

@onready var board_view: BoardView = $BoardView
@onready var hud: Hud = $UI/Hud
@onready var order_bar: OrderBar = $UI/OrderBar
@onready var inventory: InventoryPanel = $UI/InventoryPanel
@onready var shop_panel: ShopPanel = $ShopPanel
@onready var shop_button: Button = $UI/ShopButton
@onready var map_panel: MapPanel = $MapPanel
@onready var map_button: Button = $UI/MapButton
@onready var society_panel: SocietyPanel = $SocietyPanel
@onready var society_button: Button = $UI/SocietyButton
@onready var chronicle_panel: ChroniclePanel = $ChroniclePanel
@onready var event_panel: EventPanel = $EventPanel
@onready var expedition_button: Button = $UI/ExpeditionButton

func _ready() -> void:
    var now := Time.get_unix_time_from_system()
    game = SaveManager.load_game()
    if game == null:
        game = Game.fresh(now)
    game.orders.fill(game.player.level, game.rng, now)
    board_view.setup(game)
    board_view.position = Vector2((720 - MergeBoard.WIDTH * BoardView.CELL) / 2.0, 260)
    hud.setup(game)
    order_bar.setup(game)
    inventory.setup(game, board_view)
    shop_panel.setup(game)
    shop_button.pressed.connect(shop_panel.open)
    shop_panel.action_rejected.connect(_show_toast)
    map_panel.setup(game)
    map_button.pressed.connect(map_panel.open)
    map_panel.action_rejected.connect(_show_toast)
    society_panel.setup(game)
    society_button.pressed.connect(society_panel.open)
    society_panel.action_rejected.connect(_show_toast)
    chronicle_panel.setup(game)
    map_panel.chronicle_requested.connect(chronicle_panel.open)
    event_panel.setup(game)
    expedition_button.pressed.connect(event_panel.open)
    event_panel.action_rejected.connect(_show_toast)
    event_panel.visibility_changed_to.connect(_on_event_panel_visibility_changed)
    game.events.event_changed.connect(_refresh_expedition_button)
    _refresh_expedition_button()
    gala_panel = GalaPanel.new()
    add_child(gala_panel)
    gala_panel.setup(game)
    gala_panel.action_rejected.connect(_show_toast)
    gala_panel.visibility_changed_to.connect(_on_gala_panel_visibility_changed)
    gala_button = Button.new()
    gala_button.text = "Gala"
    gala_button.position = expedition_button.position + Vector2(0.0, 44.0)
    gala_button.pressed.connect(gala_panel.open)
    $UI.add_child(gala_button)
    game.boost.boost_changed.connect(_refresh_gala_button)
    _refresh_gala_button()
    for sig in [game.board.item_placed, game.board.item_removed, game.wallet.changed, game.shop.shop_changed, game.deals.deals_changed, game.campaign.task_completed, game.intimacy.satchel_changed, game.intimacy.intimacy_changed, game.specials.special_changed, game.events.event_changed, game.boost.boost_changed]:
        sig.connect(func(..._args): _save_pending = true)
    var t := Timer.new()
    t.wait_time = 1.0
    t.autostart = true
    t.timeout.connect(_flush_save)
    add_child(t)
    _setup_toast()
    board_view.action_rejected.connect(_show_toast)
    order_bar.action_rejected.connect(_show_toast)

func _setup_toast() -> void:
    _toast = Label.new()
    _toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _toast.anchor_left = 0.0
    _toast.anchor_right = 1.0
    _toast.offset_top = 246.0
    _toast.offset_bottom = 246.0
    _toast.add_theme_font_size_override("font_size", 22)
    _toast.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
    _toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
    _toast.add_theme_constant_override("outline_size", 6)
    _toast.visible = false
    $UI.add_child(_toast)
    _toast_timer = Timer.new()
    _toast_timer.wait_time = 1.6
    _toast_timer.one_shot = true
    _toast_timer.timeout.connect(func(): _toast.visible = false)
    add_child(_toast_timer)

func _show_toast(reason: String) -> void:
    _toast.text = REJECT_MESSAGES.get(reason, reason)
    _toast.visible = true
    _toast_timer.start()

func _flush_save() -> void:
    game.tick_shop(Time.get_unix_time_from_system())
    game.tick_orders(Time.get_unix_time_from_system())
    game.tick_gifts(Time.get_unix_time_from_system())
    game.tick_events(Time.get_unix_time_from_system())
    game.tick_boost(Time.get_unix_time_from_system())
    if _save_pending:
        _save_pending = false
        SaveManager.save(game)

## Always reachable while the panel is closed: the DEV start control lives
## inside the panel, so hiding the button below level 12 would strand it.
func _refresh_expedition_button() -> void:
    expedition_button.visible = not _event_panel_open and not _gala_panel_open
    expedition_button.text = "Expedition!" if game.events.is_active() else "Expedition"

## Always reachable while closed: the DEV start control lives inside the
## panel (same rationale as the expedition button).
func _refresh_gala_button() -> void:
    gala_button.visible = not _gala_panel_open and not _event_panel_open
    gala_button.text = "Gala!" if game.boost.is_active() else "Gala"

func _on_event_panel_visibility_changed(open: bool) -> void:
    _event_panel_open = open
    board_view.input_enabled = not open
    hud.visible = not open
    order_bar.visible = not open
    inventory.visible = not open
    shop_button.visible = not open
    map_button.visible = not open
    society_button.visible = not open
    _refresh_expedition_button()
    _refresh_gala_button()

func _on_gala_panel_visibility_changed(open: bool) -> void:
    _gala_panel_open = open
    board_view.input_enabled = not open
    _refresh_gala_button()
    _refresh_expedition_button()

func _notification(what: int) -> void:
    if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
        SaveManager.save(game)
