class_name Boost
extends RefCounted
## Patron's Gala (the   GeneratorBoost): a multi-day main-board buff
## window. Finishing main orders climbs a task ladder; each rung activates a
## buff, cumulatively. Ladder state resets at every UTC midnight inside the
## window (the   RefreshTime/RoundNum). Expiry advances on
## Game.tick_boost (main.gd's 1s timer hosts the tick).

signal boost_changed

enum State { IDLE, ACTIVE }

var state: int = State.IDLE
var ends_at: float = 0.0
var next_boost_at: float = 0.0    # 0.0 = start as soon as the gate passes
var rollover_at: float = 0.0
var round_num: int = 1
var progress: int = 0             # main orders delivered this round
var buff_level: int = 0           # rungs unlocked this round
var window_left: int = 0          # extraProduce quota: taps left in window
var extras_left: int = 0          # extraProduce quota: extras left in window
var extra_cached: bool = false    # one-slot cache for a blocked extra spawn
var extra_lucky_cached: String = ""  # blocked twin lucky item type, "" = none

func is_active() -> bool:
    return state == State.ACTIVE

static func _next_midnight(now: float) -> float:
    return floor(now / 86400.0 + 1.0) * 86400.0   # next UTC midnight

func tick(now: float, player: PlayerState) -> void:
    if state == State.IDLE:
        if now >= next_boost_at and player.level >= int(ConfigDB.tuning["boost_unlock_level"]):
            start_boost(now)
    elif now >= ends_at:
        end_boost(now)
    elif now >= rollover_at:
        _daily_reset()
        round_num += 1
        rollover_at = _next_midnight(now)
        boost_changed.emit()

func start_boost(now: float) -> bool:
    if state == State.ACTIVE:
        return false
    state = State.ACTIVE
    ends_at = now + float(ConfigDB.tuning["boost_duration_seconds"])
    rollover_at = _next_midnight(now)
    round_num = 1
    _daily_reset()
    boost_changed.emit()
    return true

func end_boost(now: float) -> void:
    if state != State.ACTIVE:
        return
    state = State.IDLE
    _daily_reset()
    next_boost_at = now + float(ConfigDB.tuning["boost_gap_seconds"])
    boost_changed.emit()

func _daily_reset() -> void:
    progress = 0
    buff_level = 0
    window_left = 0
    extras_left = 0
    extra_cached = false
    extra_lucky_cached = ""

## Ladder: each delivered main order is one point; rung N unlocks at the
## cumulative count boost_tasks[N-1]. All rungs <= buff_level are active.
func on_order_delivered(_now: float) -> void:
    if state != State.ACTIVE:
        return
    progress += 1
    var tasks: Array = ConfigDB.tuning["boost_tasks"]
    while buff_level < tasks.size() and progress >= int(tasks[buff_level]):
        buff_level += 1
    boost_changed.emit()

func is_buff_active(kind: String) -> bool:
    if state != State.ACTIVE:
        return false
    var buffs: Array = ConfigDB.tuning["boost_buffs"]
    for i in range(mini(buff_level, buffs.size())):
        if String(buffs[i]) == kind:
            return true
    return false

func is_boosted(type: String) -> bool:
    return ConfigDB.is_boost_type(type)

## extraProduce quota: exactly M extras per window of N taps, uniformly
## placed (fire chance extras_left/window_left, the   Left/Total
## spread-count scheme). Call once per boosted tap.
func take_extra(rng: RandomNumberGenerator) -> bool:
    if window_left <= 0:
        var quota: Array = ConfigDB.tuning["boost_extra_produce"]
        extras_left = int(quota[0])
        window_left = int(quota[1])
    var fire := rng.randi_range(1, window_left) <= extras_left
    window_left -= 1
    if fire:
        extras_left -= 1
    return fire

## Cache-first delivery: a cached extra goes out before a fresh fire; a
## same-tap fire then occupies the freed slot. At most one extra per tap.
func claim_extra(rng: RandomNumberGenerator) -> bool:
    var fired := take_extra(rng)
    if extra_cached:
        if not fired:
            extra_cached = false   # fired keeps the slot occupied
        return true
    return fired

func report_extra_blocked() -> void:
    if extra_cached:
        push_warning("Boost: extra produce lost, cache full")
    else:
        extra_cached = true

func cache_extra_lucky(type: String) -> void:
    if extra_lucky_cached != "":
        push_warning("Boost: twin lucky lost, cache full")
        return
    extra_lucky_cached = type

func take_cached_lucky() -> String:
    var t := extra_lucky_cached
    extra_lucky_cached = ""
    return t

## Query-seam config overrides: ConfigDB is never mutated. Only Spread_Weight
## differs in the override rows (charge caps/durations are identical to base,
## so GeneratorState keeps reading ConfigDB.items directly).
func effective_row(type: String) -> Dictionary:
    if is_buff_active("moreLuckyProduce") and is_boosted(type):
        var row := ConfigDB.boost_item_row("MoreLuckyProduce", type)
        if not row.is_empty():
            return row
    return ConfigDB.items.get(type, {})

func effective_lucky() -> Array:
    if is_buff_active("moreLuckyProduce"):
        return ConfigDB.boost_lucky_table("MoreLuckyProduce")
    if is_buff_active("extraLuckyProduce"):
        return ConfigDB.boost_lucky_table("ExtraLuckyProduce")
    return ConfigDB.lucky

func to_dict() -> Dictionary:
    return {"state": state, "ends_at": ends_at, "next_boost_at": next_boost_at,
            "rollover_at": rollover_at, "round_num": round_num,
            "progress": progress, "buff_level": buff_level,
            "window_left": window_left, "extras_left": extras_left,
            "extra_cached": extra_cached,
            "extra_lucky_cached": extra_lucky_cached}

static func from_dict(d: Dictionary) -> Boost:
    var b := Boost.new()
    b.state = int(d.get("state", State.IDLE))
    b.ends_at = float(d.get("ends_at", 0.0))
    b.next_boost_at = float(d.get("next_boost_at", 0.0))
    b.rollover_at = float(d.get("rollover_at", 0.0))
    b.round_num = int(d.get("round_num", 1))
    b.progress = int(d.get("progress", 0))
    b.buff_level = int(d.get("buff_level", 0))
    b.window_left = int(d.get("window_left", 0))
    b.extras_left = int(d.get("extras_left", 0))
    b.extra_cached = bool(d.get("extra_cached", false))
    b.extra_lucky_cached = String(d.get("extra_lucky_cached", ""))
    return b
