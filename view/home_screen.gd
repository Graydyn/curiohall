class_name HomeScreen
extends Control
## The Hall home screen: top bar, exterior (placeholder), bottom nav, event
## banners, and the overlays. Hosts the Workroom and wing views and owns
## back-navigation. Everything is built in code from setup().

signal screen_changed(name: String)

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
var hud: Hud
var workroom: Workroom
var shop_panel: ShopPanel
var society_panel: SocietyPanel
var chronicle_panel: ChroniclePanel
var event_panel: EventPanel
var gala_panel: GalaPanel
var exterior: ExteriorMap
var focus_element := ""
var wing_view: WingView
var wing_area := -1
var story_player: StoryPlayer

var _screen := "home"
var _event_panel_open := false
var _gala_panel_open := false
var _home_view: Control
var _back_button: Button
var _next_strip: Button
var _next_area := -1
var _next_element := ""
var _hall_dirty := false
var _expedition_banner: Button
var _gala_banner: Button
var _toast: Label
var _toast_timer: Timer

func setup(g: Game) -> void:
    game = g
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE   # passive container: drags must reach BoardView
    theme = CurioTheme.build()

    workroom = Workroom.new()
    workroom.name = "Workroom"
    add_child(workroom)
    workroom.setup(game, show_toast)
    workroom.back_requested.connect(go_back)

    _home_view = _passive_rect("HomeView")
    add_child(_home_view)
    exterior = ExteriorMap.new()
    exterior.name = "Exterior"
    _home_view.add_child(exterior)
    exterior.setup(game)
    exterior.wing_tapped.connect(func(a: int) -> void: open_wing(a))
    game.campaign.task_completed.connect(func(_d: int, _i: int) -> void: _hall_dirty = true)
    game.campaign.day_advanced.connect(func(_d: int) -> void: _hall_dirty = true)
    game.campaign.area_restored.connect(func(_a: int) -> void: _hall_dirty = true)
    _build_banners()
    _build_next_strip()
    _build_nav()

    wing_view = WingView.new()
    wing_view.name = "WingView"
    wing_view.visible = false
    add_child(wing_view)
    wing_view.toast.connect(show_toast)
    wing_view.picks_done.connect(refresh_next_task)
    wing_view.picks_done.connect(play_story)

    hud = Hud.new()
    hud.name = "Hud"
    _place(hud, 10.0, 12.0, 710.0, 50.0)
    add_child(hud)
    hud.setup(game)

    _back_button = Button.new()
    _back_button.name = "BackButton"
    _back_button.text = "Back"
    _place(_back_button, 10.0, 64.0, 130.0, 108.0)
    _back_button.pressed.connect(go_back)
    add_child(_back_button)

    _build_overlays()
    _setup_toast()
    story_player = StoryPlayer.new()
    story_player.name = "StoryPlayer"
    add_child(story_player)
    story_player.setup(game)
    story_player.scene_started.connect(_on_scene_started)
    story_player.finished.connect(_refresh_hall)
    chronicle_panel.scene_requested.connect(story_player.play)
    game.campaign.task_completed.connect(func(_d: int, _i: int) -> void: play_story.call_deferred())
    game.events.event_changed.connect(_refresh_banners)
    game.boost.boost_changed.connect(_refresh_banners)
    _show_screen("home", false)
    play_story.call_deferred()

func _passive_rect(n: String) -> Control:
    var c := Control.new()
    c.name = n
    c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    c.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return c

func _place(c: Control, l: float, t: float, r: float, b: float) -> void:
    c.offset_left = l
    c.offset_top = t
    c.offset_right = r
    c.offset_bottom = b

func _build_banners() -> void:
    ## Always reachable while closed: the DEV start control lives inside each
    ## panel, so hiding a banner without an active event would strand it.
    _expedition_banner = Button.new()
    _expedition_banner.name = "ExpeditionBanner"
    _place(_expedition_banner, 10.0, 64.0, 350.0, 108.0)
    _home_view.add_child(_expedition_banner)
    _gala_banner = Button.new()
    _gala_banner.name = "GalaBanner"
    _place(_gala_banner, 370.0, 64.0, 710.0, 108.0)
    _home_view.add_child(_gala_banner)

func _build_next_strip() -> void:
    _next_strip = Button.new()
    _next_strip.name = "NextTaskStrip"
    _place(_next_strip, 10.0, 1118.0, 710.0, 1180.0)
    _next_strip.pressed.connect(func() -> void:
        if _next_area > 0:
            open_wing(_next_area, _next_element))
    _home_view.add_child(_next_strip)
    refresh_next_task()


## Shows the first workable element of the active area, or hides the strip.
func refresh_next_task() -> void:
    var c := game.campaign
    _next_area = -1
    _next_element = ""
    if not c.is_complete():
        var area := c.current_area()
        for row in HallElements.in_area(area):
            var id := String(row["id"])
            if HallElements.is_workable(id, c):
                _next_area = area
                _next_element = id
                _next_strip.text = "Next: %s  %d●" % [String(row["name"]), _task_cost(HallElements.next_task(id, c))]
                break
    _next_strip.visible = _next_area > 0

func _task_cost(key: String) -> int:
    for row in game.campaign.tasks_today():
        if Campaign.task_key(int(row["day"]), int(row["id"])) == key:
            return int(row["cost"])
    return 0

func _refresh_hall() -> void:
    if _hall_dirty:
        _hall_dirty = false
        exterior.refresh()
    refresh_next_task()

func _build_nav() -> void:
    var bar := HBoxContainer.new()
    bar.name = "NavBar"
    bar.add_theme_constant_override("separation", 10)
    _place(bar, 10.0, 1190.0, 710.0, 1264.0)
    _home_view.add_child(bar)
    for spec in [["NavWorkroom", "Workroom"], ["NavShop", "Shop"], ["NavSociety", "Society"], ["NavChronicle", "Chronicle"]]:
        var b := Button.new()
        b.name = spec[0]
        b.text = spec[1]
        b.theme_type_variation = "NavButton"
        b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        bar.add_child(b)

func _build_overlays() -> void:
    shop_panel = ShopPanel.new()
    shop_panel.name = "ShopPanel"
    add_child(shop_panel)
    shop_panel.setup(game)
    shop_panel.action_rejected.connect(show_toast)
    society_panel = SocietyPanel.new()
    society_panel.name = "SocietyPanel"
    add_child(society_panel)
    society_panel.setup(game)
    society_panel.action_rejected.connect(show_toast)
    chronicle_panel = ChroniclePanel.new()
    chronicle_panel.name = "ChroniclePanel"
    add_child(chronicle_panel)
    chronicle_panel.setup(game)
    event_panel = EventPanel.new()
    event_panel.name = "EventPanel"
    add_child(event_panel)
    event_panel.setup(game)
    event_panel.action_rejected.connect(show_toast)
    event_panel.visibility_changed_to.connect(_on_event_panel_visibility_changed)
    gala_panel = GalaPanel.new()
    gala_panel.name = "GalaPanel"
    add_child(gala_panel)
    gala_panel.setup(game)
    gala_panel.action_rejected.connect(show_toast)
    gala_panel.visibility_changed_to.connect(_on_gala_panel_visibility_changed)

    _nav("NavWorkroom").pressed.connect(open_workroom)
    _nav("NavShop").pressed.connect(shop_panel.open)
    _nav("NavSociety").pressed.connect(society_panel.open)
    _nav("NavChronicle").pressed.connect(chronicle_panel.open)
    _expedition_banner.pressed.connect(event_panel.open)
    _gala_banner.pressed.connect(gala_panel.open)

func _nav(n: String) -> Button:
    return _home_view.get_node("NavBar/" + n) as Button

func _setup_toast() -> void:
    _toast = Label.new()
    _toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
    add_child(_toast)
    _toast_timer = Timer.new()
    _toast_timer.wait_time = 1.6
    _toast_timer.one_shot = true
    _toast_timer.timeout.connect(func(): _toast.visible = false)
    add_child(_toast_timer)

func show_toast(reason: String) -> void:
    _toast.text = REJECT_MESSAGES.get(reason, reason)
    _toast.visible = true
    _toast_timer.start()

func current_screen() -> String:
    return _screen

func open_workroom() -> void:
    _show_screen("workroom")

func open_wing(area: int, focus: String = "") -> void:
    wing_area = area
    focus_element = focus
    _show_screen("wing")
    wing_view.setup(game, area, focus)

## Closes the topmost overlay, else returns toward home. False when already
## at home with nothing open (the caller may then let the app quit).
func go_back() -> bool:
    if story_player.is_playing():
        story_player.skip()
        return true
    for p in [gala_panel, event_panel, chronicle_panel, society_panel, shop_panel]:
        if p.visible:
            p.close()
            return true
    if _screen == "wing" and (wing_view.is_modal_locked() or wing_view.close_top()):
        return true
    if _screen != "home":
        _show_screen("home")
        return true
    return false

func _show_screen(screen: String, emit := true) -> void:
    _screen = screen
    _home_view.visible = screen == "home"
    workroom.visible = screen == "workroom"
    wing_view.visible = screen == "wing"
    _refresh_chrome()
    if emit:
        screen_changed.emit(screen)
    if screen == "home":
        if not _open_pending_pick_wing():
            play_story()

## A finished element's mandatory look pick is owed: open its wing so the
## picker shows right away (its wing may be behind the active one).
func _open_pending_pick_wing() -> bool:
    for id in game.hall.pending_pick:
        if ConfigDB.hall_elements.has(id):
            open_wing(int(ConfigDB.hall_elements[id]["area"]))
            return true
    return false

## Plays any queued story scenes unless any look pick is pending (resumes from
## WingView.picks_done after the pick is made).
func play_story() -> void:
    if story_player == null or story_player.is_playing():
        return
    if not game.hall.pending_pick.is_empty():
        return
    story_player.play_pending()

func _on_scene_started(scene: Dictionary) -> void:
    var trig := String(scene.get("trigger", ""))
    if _screen == "wing" and trig.begins_with("element:"):
        wing_view.focus(trig.get_slice(":", 1))

func _overlay_open() -> bool:
    return _event_panel_open or _gala_panel_open

func _refresh_chrome() -> void:
    var over := _overlay_open()
    workroom.board_view.input_enabled = _screen == "workroom" and not over
    hud.visible = not _event_panel_open
    _back_button.visible = _screen != "home" and not over
    _refresh_banners()
    if _screen == "home":
        _refresh_hall()

func _refresh_banners() -> void:
    var show_banners := _screen == "home" and not _overlay_open()
    _expedition_banner.visible = show_banners
    _expedition_banner.text = "Expedition!" if game.events.is_active() else "Expedition"
    _gala_banner.visible = show_banners
    _gala_banner.text = "Gala!" if game.boost.is_active() else "Gala"

func _on_event_panel_visibility_changed(open: bool) -> void:
    _event_panel_open = open
    _refresh_chrome()

func _on_gala_panel_visibility_changed(open: bool) -> void:
    _gala_panel_open = open
    _refresh_chrome()
