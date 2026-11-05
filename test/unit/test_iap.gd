extends GutTest

func test_packs_reflect_config() -> void:
    var iap := Iap.new()
    var ps := iap.packs()
    assert_eq(ps.size(), 6)
    assert_eq(ps[0]["goods"], ["gem-100"])
    assert_true(ps[0]["purchase_id"] != "")

func test_purchase_pack_stub_grants_gems() -> void:
    var g := Game.fresh(1000.0, 42)
    var gems0 := g.wallet.gems
    var res := g.iap.purchase_pack("getgem_1", g, 1000.0)   # goods gem-100
    assert_true(res["ok"])
    assert_eq(g.wallet.gems, gems0 + 100)

func test_purchase_pack_unknown_id() -> void:
    var g := Game.fresh(1000.0, 42)
    assert_eq(g.iap.purchase_pack("nope", g, 1000.0).get("reason", ""), "unknown")

func test_bundle_locked_below_level_3() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 1
    g.iap.note_seen(1000.0)
    assert_eq(g.iap.bundle_state(g, 1000.0)["reason"], "locked")
    assert_eq(g.iap.purchase_bundle(g, 1000.0)["reason"], "locked")

func test_bundle_purchase_then_one_time() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 3
    g.iap.note_seen(1000.0)
    for p in [Vector2i(1, 3), Vector2i(1, 4), Vector2i(2, 3)]:
        g.board.remove(p); g.board.set_state(p, MergeBoard.CellState.OPEN)
    var gems0 := g.wallet.gems
    var res := g.iap.purchase_bundle(g, 1000.0)   # goods gem-510, energy-200, 3601-2
    assert_true(res["ok"])
    assert_eq(g.wallet.gems, gems0 + 510)
    assert_eq(g.iap.purchase_bundle(g, 1000.0)["reason"], "already_bought")

func test_bundle_expires_after_duration() -> void:
    var g := Game.fresh(1000.0, 42)
    g.player.level = 3
    g.iap.note_seen(1000.0)
    var dur := int(ConfigDB.bundles[0]["lastDuration"])
    assert_eq(g.iap.bundle_state(g, 1000.0 + dur + 1.0)["reason"], "expired")
    assert_eq(g.iap.purchase_bundle(g, 1000.0 + dur + 1.0)["reason"], "expired")

func test_round_trip() -> void:
    var iap := Iap.new()
    iap.bundle_bought = true
    iap.bundle_first_seen = 1234.0
    var i2 := Iap.from_dict(iap.to_dict())
    assert_true(i2.bundle_bought)
    assert_eq(i2.bundle_first_seen, 1234.0)
