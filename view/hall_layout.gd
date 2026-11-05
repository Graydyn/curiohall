class_name HallLayout
## Hand-authored floor plan of the 47 Hall wings (docs/creative-direction.md),
## laid out top-to-bottom in restoration order on one scrollable canvas.
## Pure data + geometry; no game state.

const CELL := Vector2(400.0, 230.0)
const GAP := 20.0
const COLS := 4

# One array per floor-plan row: [area, display name, column span].
const _ROWS: Array = [
    [[1, "The Front Gates", 4]],
    [[2, "The Grand Atrium", 2], [3, "The Cloakroom & Vestibule", 1], [4, "The Curator's Office", 1]],
    [[5, "The Tea Room", 1], [6, "The Hall of Feathers", 1], [7, "The Butterfly House", 1], [8, "The Conservatory", 1]],
    [[9, "The Fossil Gallery", 1], [10, "The Mineral Vault", 1], [11, "The Shell & Coral Room", 1], [12, "The Aquarium Grotto", 1]],
    [[13, "The Map Room", 1], [14, "The Library of Expeditions", 1], [15, "The Archives", 1], [16, "The Clockwork Workshop", 1]],
    [[17, "The Hall of Instruments", 1], [18, "The Astronomy Dome", 1], [19, "The Orrery Landing", 1], [20, "The Gaslight Gallery", 1]],
    [[21, "The Sculpture Court", 1], [22, "The Hall of Giants", 1], [23, "The Insectarium", 1], [24, "The Herbarium", 1]],
    [[25, "The Apothecary Annex", 1], [26, "The Gemstone Salon", 1], [27, "The Meteorite Chamber", 1], [28, "The Cabinet of Whispers", 1]],
    [[29, "The Portrait Stair", 1], [30, "The Founders' Gallery", 1], [31, "The Music Box Parlor", 1], [32, "The Print & Poster Room", 1]],
    [[33, "The Model Ship Hall", 1], [34, "The Balloon Loft", 1], [35, "The Observatory Walk", 1], [36, "The Moonlit Courtyard", 1]],
    [[37, "The Reflecting Pool", 1], [38, "The Glasshouse Menagerie", 1], [39, "The Night Garden", 1], [40, "The Deep Vaults", 1]],
    [[41, "The Forgotten Wing", 1], [42, "The Founder's Study", 1], [43, "The Hidden Passage", 1], [44, "The Chart Room of Lost Lands", 1]],
    [[45, "The Grand Ballroom", 2], [46, "The Clock Tower", 1], [47, "The Attic of Marvels", 1]],
]

static func wings() -> Array:
    var out: Array = []
    for r in range(_ROWS.size()):
        var x := GAP
        var row: Array = _ROWS[r]
        for entry in row:
            var e: Array = entry
            var span := int(e[2])
            var w := CELL.x * span + GAP * (span - 1)
            out.append({
                "area": int(e[0]),
                "name": String(e[1]),
                "rect": Rect2(x, GAP + r * (CELL.y + GAP), w, CELL.y),
            })
            x += w + GAP
    return out

static func canvas_size() -> Vector2:
    return Vector2(GAP + COLS * (CELL.x + GAP), GAP + _ROWS.size() * (CELL.y + GAP))
