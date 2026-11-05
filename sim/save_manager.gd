class_name SaveManager

static var path := "user://save.json"
static var corrupt_path := "user://save.corrupt.json"

static func save(game: Game) -> void:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        print("[save] failed to open ", path)
        return
    f.store_string(JSON.stringify(game.to_dict()))

static func load_game() -> Game:
    if not FileAccess.file_exists(path):
        return null
    var text := FileAccess.open(path, FileAccess.READ).get_as_text()
    var json := JSON.new()
    var err := json.parse(text)
    var data: Variant = json.data if err == OK else null
    var is_valid := data != null and typeof(data) == TYPE_DICTIONARY
    if is_valid:
        for key in ["board", "wallet", "player", "orders", "shop", "deals", "iap", "campaign", "intimacy", "specials", "events", "boost"]:
            if not data.has(key):
                is_valid = false
                break
        if is_valid and int(data.get("save_version", 0)) != Game.SAVE_VERSION:
            is_valid = false  # old saves reset on version upgrade (v9 saves reset on upgrade to v10)
    if not is_valid:
        DirAccess.copy_absolute(path, corrupt_path)
        print("[save] corrupt save backed up to " + corrupt_path)
        return null
    return Game.from_dict(data)
