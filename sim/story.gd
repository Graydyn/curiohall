class_name Story
extends RefCounted
## Queue of story scenes unlocked by campaign triggers, plus the set already seen.

signal scene_queued(id: String)

var seen: Dictionary = {}   # scene id -> true
var queue: Array = []       # scene ids awaiting playback, in order

func enqueue(triggers: Array) -> void:
    for trigger in triggers:
        for id in ConfigDB.scenes_by_trigger.get(trigger, []):
            if seen.has(id) or queue.has(id):
                continue
            queue.append(id)
            scene_queued.emit(id)

func has_pending() -> bool:
    return not queue.is_empty()

func peek() -> Dictionary:
    if queue.is_empty():
        return {}
    return ConfigDB.story_scenes.get(queue[0], {})

func finish_current() -> void:
    if queue.is_empty():
        return
    seen[queue.pop_front()] = true

func replayable() -> Array:
    var out := []
    for id in ConfigDB.story_scenes:
        if seen.has(id):
            out.append(ConfigDB.story_scenes[id])
    return out

func to_dict() -> Dictionary:
    return {"seen": seen.keys(), "queue": queue.duplicate()}

static func from_dict(d: Dictionary) -> Story:
    var s := Story.new()
    for id in d.get("seen", []):
        s.seen[String(id)] = true
    for id in d.get("queue", []):
        s.queue.append(String(id))
    return s
