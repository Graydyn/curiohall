class_name HallArt
extends RefCounted
## Cached lookup for painted Hall art. Every accessor returns null when the
## file is missing so callers fall back to in-palette placeholders.

static var base_dir := "res://assets/map/"
static var _cache: Dictionary = {}

static func clear_cache() -> void:
    _cache.clear()

static func _load(rel: String) -> Texture2D:
    var path := base_dir + rel
    if _cache.has(path):
        return _cache[path]
    var tex: Texture2D = null
    if ResourceLoader.exists(path):
        tex = load(path) as Texture2D
    _cache[path] = tex
    return tex

static func exterior_base() -> Texture2D:
    return _load("exterior/base.png")

static func wing_exterior(area: int, state: String) -> Texture2D:
    return _load("exterior/wing_%02d_%s.png" % [area, state])

static func wing_scene(area: int, subroom: int) -> Texture2D:
    return _load("wings/%02d/scene_%d.png" % [area, subroom])

static func element(id: String, look: int) -> Texture2D:
    var area := int(id.get_slice("_", 0))
    return _load("elements/%02d/%s_%d.png" % [area, id, look])

static func portrait(speaker: String, expr: String) -> Texture2D:
    return _load("portraits/%s_%s.png" % [speaker, expr])

static func panel(scene_id: String, index: int) -> Texture2D:
    return _load("panels/%s_%d.png" % [scene_id, index])

static func ui(art_name: String) -> Texture2D:
    return _load("ui/%s.png" % art_name)
