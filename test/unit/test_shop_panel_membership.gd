extends GutTest
## Shop "Membership" section and the HUD refill button.

func _panel() -> Array:
    var g := Game.fresh(Time.get_unix_time_from_system(), 42)
    var p := ShopPanel.new()
    add_child_autofree(p)
    p.setup(g)
    p.visible = true
    p.refresh()
    return [g, p]

func test_non_member_sees_buy_button() -> void:
    var p: ShopPanel = _panel()[1]
    assert_eq(p._membership_status.text, "Not a member")
    assert_true(p._buy_pass_btn.text.begins_with("Buy 30 days (DEV)"))

func test_buy_pass_button_makes_member() -> void:
    var s := _panel()
    var g: Game = s[0]
    var p: ShopPanel = s[1]
    p._buy_pass_btn.pressed.emit()
    assert_true(g.membership.is_member(Time.get_unix_time_from_system()))
    p.refresh()
    assert_true(p._membership_status.text.begins_with("Member: 30 days left"))
    assert_eq(p._buy_pass_btn.text, "Add 30 days (DEV)")

func test_play_pass_hides_buy_button() -> void:
    var s := _panel()
    var g: Game = s[0]
    var p: ShopPanel = s[1]
    g.set_play_pass(true, Time.get_unix_time_from_system())
    p.refresh()
    assert_eq(p._membership_status.text, "Included with Play Pass")
    assert_null(p._buy_pass_btn)

func test_hud_refill_button_visibility() -> void:
    var now := Time.get_unix_time_from_system()
    var g := Game.fresh(now, 42)
    var h := Hud.new()
    add_child_autofree(h)
    h.setup(g)
    assert_false(h._refill_btn.visible)
    g.buy_pass(now)
    h.refresh()
    assert_true(h._refill_btn.visible)
    var e := g.wallet.energy(now)
    h._refill_btn.pressed.emit()
    assert_eq(g.wallet.energy(Time.get_unix_time_from_system()), e + 100)
    assert_false(h._refill_btn.visible)

func test_stack_limit_shows_reason() -> void:
    var s := _panel()
    var g: Game = s[0]
    var p: ShopPanel = s[1]
    var now := Time.get_unix_time_from_system()
    g.buy_pass(now)
    g.buy_pass(now)
    p.refresh()
    assert_true(p._buy_pass_btn.disabled)
    assert_not_null(p._stack_reason)
    assert_eq(p._stack_reason.text, "  You can hold at most 60 days of membership")
