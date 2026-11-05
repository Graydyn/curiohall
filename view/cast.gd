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
