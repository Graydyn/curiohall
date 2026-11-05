class_name ItemView
extends Node2D
## Placeholder rendering. When real art arrives, only apply() changes.

const SIZE := 88.0

var _type := ""
var _state := MergeBoard.CellState.OPEN
var _is_generator := false

func apply(item_type: String, cell_state: int) -> void:
    _type = item_type
    _state = cell_state
    _is_generator = ConfigDB.items.get(item_type, {}).has("Spread_Weight")
    queue_redraw()

static func chain_of(item_type: String) -> String:
    return item_type.substr(0, item_type.length() - 2)

static func tier_of(item_type: String) -> int:
    return int(item_type.substr(item_type.length() - 2))

func _draw() -> void:
    var rect := Rect2(-SIZE / 2, -SIZE / 2, SIZE, SIZE)
    if _state == MergeBoard.CellState.BOXED:
        _draw_locked(rect)
        return
    _draw_content(rect)
    if _state == MergeBoard.CellState.COVERED:
        _draw_veil(rect)

func _draw_content(rect: Rect2) -> void:
    var chain := chain_of(_type)
    var tier := tier_of(_type)
    var row: Dictionary = ConfigDB.items.get(_type, {})
    if row.has("CollectRewards"):
        var kind: String = Rewards.parse(String(row["CollectRewards"][0]))["kind"]
        var tint: Color = {"coins": Color(0.95, 0.8, 0.2), "gems": Color(0.4, 0.8, 1.0), "energy": Color(0.5, 1.0, 0.4)}.get(kind, Color.WHITE)
        draw_rect(rect, tint, true)
        draw_string(ThemeDB.fallback_font, Vector2(-SIZE/2 + 4, 8), "collect", HORIZONTAL_ALIGNMENT_CENTER, SIZE - 8, 16, Color.BLACK)
        return
    if ConfigDB.is_chest(_type):
        draw_rect(rect, Color(0.55, 0.4, 0.15), true)
        draw_rect(rect, Color(0.85, 0.65, 0.2), false, 4.0)
        draw_string(ThemeDB.fallback_font, Vector2(-SIZE/2 + 4, 6), "CHEST", HORIZONTAL_ALIGNMENT_CENTER, SIZE - 8, 18, Color.WHITE)
        return
    var hue := fmod(hash(chain) * 0.6180339887, 1.0)
    var col := Color.from_hsv(hue, 0.55, clampf(0.95 - tier * 0.04, 0.4, 0.95))
    draw_rect(rect, col, true)
    if _is_generator:
        draw_rect(rect, Color.GOLD, false, 4.0)
    var font := ThemeDB.fallback_font
    draw_string(font, Vector2(-SIZE / 2 + 6, -8), chain, HORIZONTAL_ALIGNMENT_CENTER, SIZE - 12, 18)
    draw_string(font, Vector2(-SIZE / 2 + 6, 22), "T%d" % tier, HORIZONTAL_ALIGNMENT_CENTER, SIZE - 12, 22, Color.WHITE)

## COVERED tiles show their item under a dim cobweb veil: visible (so the
## player can plan matching merges onto them) but clearly not free yet.
func _draw_veil(rect: Rect2) -> void:
    draw_rect(rect, Color(0.08, 0.08, 0.12, 0.55), true)
    var web := Color(0.85, 0.85, 0.9, 0.5)
    draw_line(rect.position, rect.end, web, 2.0)
    draw_line(Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y), web, 2.0)
    draw_arc(Vector2.ZERO, SIZE * 0.28, 0, TAU, 24, web, 2.0)

## BOXED tiles hide their contents entirely: a muted slab plus a padlock glyph
## reads as "not reachable yet"; a nearby merge pops the box open.
func _draw_locked(rect: Rect2) -> void:
    var fill := Color(0.24, 0.22, 0.20)
    draw_rect(rect, fill, true)
    draw_rect(rect, Color(0, 0, 0, 0.25), false, 2.0)
    var lock_col := Color(0.62, 0.60, 0.56)
    # Shackle: an upward half-ring above the body.
    draw_arc(Vector2(0, -6), 11.0, PI, TAU, 20, lock_col, 4.0)
    # Body: a rounded slab below the shackle.
    draw_rect(Rect2(-14, -6, 28, 22), lock_col, true)
