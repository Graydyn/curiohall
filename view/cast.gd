class_name Cast
## Original character names -> the Curio Hall cast (docs/creative-direction.md).
## Names outside the 11 cast slots fall back to a capitalized placeholder.

const NAMES := {
    "cornelia": "Cornelia Wren", "barnaby": "Barnaby Pluck",
    "aldous": "Prof. Aldous Finch", "sam": "Sam Vane",
    "mark": "Mark Bloom", "anjali": "Anjali Bose",
    "hugo": "Hugo Pemberton", "prudence": "Prudence Quill",
    "zephyrine": "Zephyrine \"Zeph\" Blackwood", "rosalind": "Rosalind Thorne",
    "ambrose": "Ambrose Hall",
}

static func display_name(original: String) -> String:
    var key := original.to_lower()
    return String(NAMES.get(key, original.capitalize()))

static func is_cast(original: String) -> bool:
    return NAMES.has(original.to_lower())

## Display name for whoever is asking: cast members by name, anyone else is
## an anonymous Society request.
static func asker_name(original: String) -> String:
    return display_name(original) if is_cast(original) else "Society request"
