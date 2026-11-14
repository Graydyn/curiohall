class_name HallState
extends RefCounted
## Player choices for the Hall map: the chosen look per finished element and
## the queue of finished elements still awaiting their mandatory first pick.

signal element_finished(id: String)
signal look_changed(id: String, look: int)

var looks: Dictionary = {}        # element id -> look index
var pending_pick: Array = []      # element ids awaiting a first look pick

func finish(id: String) -> void:
    if not pending_pick.has(id):
        pending_pick.append(id)
    element_finished.emit(id)

func look_of(id: String) -> int:
    return int(looks.get(id, 0))

func set_look(id: String, look: int) -> void:
    looks[id] = look
    pending_pick.erase(id)
    look_changed.emit(id, look)

func pending_in_area(area: int) -> Array:
    var out := []
    for id in pending_pick:
        if int(ConfigDB.hall_elements.get(id, {}).get("area", -1)) == area:
            out.append(id)
    return out

func to_dict() -> Dictionary:
    return {"looks": looks.duplicate(), "pending": pending_pick.duplicate()}

static func from_dict(d: Dictionary) -> HallState:
    var h := HallState.new()
    for id in d.get("looks", {}):
        h.looks[String(id)] = int(d["looks"][id])
    for id in d.get("pending", []):
        h.pending_pick.append(String(id))
    return h
