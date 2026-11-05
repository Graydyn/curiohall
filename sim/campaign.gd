class_name Campaign
extends RefCounted
## MainTask restoration campaign. Story days (1..282) advance as their tasks
## complete; each day maps to exactly one of the 47 areas, monotonically.
## Task costs are paid in coins (see the spec's task-currency correction).
## Time-free by design: no timers, so no runtime tick host is needed.

signal task_completed(day: int, id: int)
signal day_advanced(new_day: int)
signal area_restored(area: int)

enum AreaState { LOCKED, ACTIVE, RESTORED }

var day: int = 1
var done: Dictionary = {}   # "day_id" -> true

static func task_key(d: int, id: int) -> String:
    return "%d_%d" % [d, id]

func tasks_today() -> Array:
    var rows: Array = ConfigDB.main_tasks.get(day, [])
    return rows

func is_complete() -> bool:
    return not ConfigDB.main_tasks.has(day)

func current_area() -> int:
    var rows := tasks_today()
    if rows.is_empty():
        return -1
    return int(rows[0]["area"])

func is_task_done(d: int, id: int) -> bool:
    return done.has(task_key(d, id))

func is_area_unlocked(area: int, player: PlayerState) -> bool:
    var row: Dictionary = ConfigDB.area_unlocks.get(area, {})
    if row.is_empty():
        return true
    if player.level < int(row.get("level", 1)):
        return false
    var cond := String(row.get("condition", ""))
    if cond.begins_with("TaskCompleted-"):
        var key := cond.trim_prefix("TaskCompleted-")
        # A condition naming a task that doesn't exist (the real config's 1_9)
        # is treated as satisfied; see the spec erratum.
        if ConfigDB.main_task_by_key.has(key):
            return done.has(key)
    return true

func area_state(area: int, player: PlayerState) -> AreaState:
    if is_complete():
        return AreaState.RESTORED
    var cur := current_area()
    if area < cur:
        return AreaState.RESTORED
    if area > cur:
        return AreaState.LOCKED
    return AreaState.ACTIVE if is_area_unlocked(area, player) else AreaState.LOCKED

func wing_progress(area: int) -> Vector2i:
    var finished := 0
    var rows: Array = ConfigDB.area_tasks.get(area, [])
    for row in rows:
        if done.has(task_key(int(row["day"]), int(row["id"]))):
            finished += 1
    return Vector2i(finished, rows.size())

func complete_task(id: int, game, now: float) -> Dictionary:
    var key := task_key(day, id)
    var row: Dictionary = ConfigDB.main_task_by_key.get(key, {})
    if row.is_empty():
        return {"ok": false, "reason": "not_today"}
    if done.has(key):
        return {"ok": false, "reason": "already_done"}
    if not is_area_unlocked(int(row["area"]), game.player):
        return {"ok": false, "reason": "area_locked"}
    if not game.wallet.spend_coins(int(row["cost"])):
        return {"ok": false, "reason": "not_enough_coins"}
    done[key] = true
    var rewards: Array = row.get("rewards", [])
    Rewards.grant_all(rewards, game, now)
    task_completed.emit(day, id)
    _advance_if_day_done()
    return {"ok": true, "reason": ""}

func _advance_if_day_done() -> void:
    for row in tasks_today():
        if not done.has(task_key(day, int(row["id"]))):
            return
    var finished_area := current_area()
    day += 1
    day_advanced.emit(day)
    if current_area() != finished_area:
        area_restored.emit(finished_area)

func to_dict() -> Dictionary:
    return {"day": day, "done": done.keys()}

static func from_dict(d: Dictionary) -> Campaign:
    var c := Campaign.new()
    c.day = int(d.get("day", 1))
    for k in d.get("done", []):
        c.done[String(k)] = true
    return c
