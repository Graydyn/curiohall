class_name HallElements
extends RefCounted
## Stateless view of Hall elements: each element's stage is derived from the
## campaign's completed tasks ("day_id" keys); nothing is stored here.

enum Stage { OUTLINE, IN_PROGRESS, DONE }

static func _tasks(id: String) -> Array:
    var row: Dictionary = ConfigDB.hall_elements.get(id, {})
    return row.get("tasks", [])

static func progress(id: String, c: Campaign) -> Vector2i:
    var tasks := _tasks(id)
    var done := 0
    for key in tasks:
        if c.done.has(String(key)):
            done += 1
    return Vector2i(done, tasks.size())

static func stage(id: String, c: Campaign) -> Stage:
    var p := progress(id, c)
    if p.x == 0:
        return Stage.OUTLINE
    if p.x >= p.y:
        return Stage.DONE
    return Stage.IN_PROGRESS

static func next_task(id: String, c: Campaign) -> String:
    for key in _tasks(id):
        if not c.done.has(String(key)):
            return String(key)
    return ""

static func is_workable(id: String, c: Campaign) -> bool:
    var key := next_task(id, c)
    if key == "":
        return false
    for row in c.tasks_today():
        if Campaign.task_key(int(row["day"]), int(row["id"])) == key:
            return true
    return false

static func of_task(key: String) -> String:
    return String(ConfigDB.element_by_task.get(key, ""))

static func in_area(area: int) -> Array:
    return ConfigDB.area_elements.get(area, [])
