class_name Membership
extends RefCounted
## The one real-money product: a 30-day membership pass, bought by hand (DEV
## stub, no billing), never auto-renewing. Google Play Pass grants the same
## membership (DEV toggle stands in for detection). Members get a daily gem
## allowance (paid by tick) and a once-a-day energy refill they claim.
## Days are local-day indices supplied by the caller (Game.local_day).

signal membership_changed

const DAY := 86400.0

var member_until: float = 0.0     # unix seconds; 0 = never a member
var last_perk_day: int = -1       # local day the gem allowance was last paid
var last_refill_day: int = -1     # local day the refill was last claimed
var last_reminder_day: int = -1   # local day a lapse reminder was last shown
var play_pass: bool = false

func is_member(now: float) -> bool:
    return play_pass or now < member_until

func days_left(now: float) -> int:
    return maxi(0, ceili((member_until - now) / DAY))

func buy_pass(now: float) -> Dictionary:
    if play_pass:
        return {"ok": false, "reason": "play_pass"}
    var until := maxf(now, member_until) + float(ConfigDB.tuning["membership_pass_days"]) * DAY
    if until > now + float(ConfigDB.tuning["membership_max_days_ahead"]) * DAY:
        return {"ok": false, "reason": "stack_limit"}
    member_until = until
    membership_changed.emit()
    return {"ok": true, "reason": ""}

func set_play_pass(on: bool) -> void:
    play_pass = on
    membership_changed.emit()

func tick(game, now: float, day: int) -> void:
    if not is_member(now) or day <= last_perk_day:
        return
    Rewards.grant_all(ConfigDB.tuning["membership_daily_rewards"], game, now)
    last_perk_day = day
    membership_changed.emit()

func refill_available(now: float, day: int) -> bool:
    return is_member(now) and day > last_refill_day

func claim_refill(game, now: float, day: int) -> Dictionary:
    if not is_member(now):
        return {"ok": false, "reason": "not_member"}
    if day <= last_refill_day:
        return {"ok": false, "reason": "already_claimed"}
    Rewards.grant_all(ConfigDB.tuning["membership_refill_rewards"], game, now)
    last_refill_day = day
    membership_changed.emit()
    return {"ok": true, "reason": ""}

## Returns a reminder key at most once per local day; never for Play Pass.
func take_reminder(now: float, day: int) -> String:
    if play_pass or day <= last_reminder_day:
        return ""
    var left := member_until - now
    var key := ""
    if left > 0.0 and left < DAY:
        key = "last_day"
    elif left >= DAY and days_left(now) <= int(ConfigDB.tuning["membership_reminder_days"]):
        key = "ending_soon"
    if key != "":
        last_reminder_day = day
        membership_changed.emit()
    return key

func to_dict() -> Dictionary:
    return {"member_until": member_until, "last_perk_day": last_perk_day,
            "last_refill_day": last_refill_day, "last_reminder_day": last_reminder_day,
            "play_pass": play_pass}

static func from_dict(d: Dictionary) -> Membership:
    var m := Membership.new()
    m.member_until = float(d.get("member_until", 0.0))
    m.last_perk_day = int(d.get("last_perk_day", -1))
    m.last_refill_day = int(d.get("last_refill_day", -1))
    m.last_reminder_day = int(d.get("last_reminder_day", -1))
    m.play_pass = bool(d.get("play_pass", false))
    return m
