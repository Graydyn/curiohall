extends GutTest

func test_starts_full_and_spends() -> void:
    var w := EnergyWallet.fresh(1000.0)
    assert_eq(w.energy(1000.0), 100)
    assert_true(w.spend_energy(30, 1000.0))
    assert_eq(w.energy(1000.0), 70)
    assert_false(w.spend_energy(999, 1000.0))

func test_regenerates_one_per_120s_capped() -> void:
    var w := EnergyWallet.fresh(1000.0)
    w.spend_energy(10, 1000.0)
    assert_eq(w.energy(1000.0 + 119.0), 90)
    assert_eq(w.energy(1000.0 + 120.0), 91)
    assert_eq(w.energy(1000.0 + 120.0 * 5), 95)
    assert_eq(w.energy(1000.0 + 120.0 * 100000), 100)

func test_coins_gems_atomic() -> void:
    var w := EnergyWallet.fresh(0.0)
    w.add_coins(10)
    assert_false(w.spend_coins(11))
    assert_eq(w.coins, 10)
    assert_true(w.spend_coins(10))
    assert_eq(w.coins, 0)

func test_round_trip() -> void:
    var w := EnergyWallet.fresh(1000.0)
    w.spend_energy(7, 1000.0)
    w.add_coins(5)
    var w2 := EnergyWallet.from_dict(w.to_dict())
    assert_eq(w2.energy(1000.0), 93)
    assert_eq(w2.coins, 5)

func test_add_energy_overfills_past_max() -> void:
    var w := EnergyWallet.fresh(1000.0)
    assert_eq(w.energy(1000.0), 100)  # starts at max
    w.add_energy(30, 1000.0)          # grant energy-30 reward
    assert_eq(w.energy(1000.0), 130)  # overfilled past cap

func test_overfill_survives_spend_and_time() -> void:
    var w := EnergyWallet.fresh(1000.0)
    w.add_energy(30, 1000.0)
    assert_eq(w.energy(1000.0), 130)
    w.spend_energy(1, 1000.0)
    assert_eq(w.energy(1000.0), 129)  # overfill preserved after spend
    assert_eq(w.energy(1000.0 + 120.0), 129)  # no regen while above cap

func test_below_cap_regen_still_accrues() -> void:
    var w := EnergyWallet.fresh(1000.0)
    w.add_energy(30, 1000.0)          # overfill to 130
    assert_eq(w.energy(1000.0), 130)
    w.spend_energy(35, 1000.0)        # spend back to 95, below cap
    assert_eq(w.energy(1000.0), 95)
    assert_eq(w.energy(1000.0 + 120.0), 96)  # regen resumes when below cap

func test_overfill_no_retroactive_regen_after_idle_spend() -> void:
    var t0 := 1000.0
    var w := EnergyWallet.fresh(t0)
    w.add_energy(30, t0)              # overfill to 130 at t0
    assert_eq(w.energy(t0), 130)
    # Idle 2 hours, then spend below cap
    w.spend_energy(35, t0 + 7200.0)   # spend 35 -> base 95, at t0+7200
    assert_eq(w.energy(t0 + 7200.0), 95)  # no retroactive regen from idle time
    assert_eq(w.energy(t0 + 7200.0 + 120.0), 96)  # regen resumes normally from post-spend
