class_name ChroniclePanel
extends CanvasLayer
## The five Chronicle volumes: campaign-milestone story recaps rendered from
## StoryRecapConfig loc keys. Placeholder text until the rewrite track.

var game: Game
var _root: PanelContainer
var _list: VBoxContainer
var _book := -1   # -1 = the volume list
var _page := 1

func setup(g: Game) -> void:
    game = g
    layer = 11
    visible = false
    _root = PanelContainer.new()
    _root.anchor_right = 1.0
    _root.anchor_bottom = 1.0
    add_child(_root)
    var scroll := ScrollContainer.new()
    _root.add_child(scroll)
    _list = VBoxContainer.new()
    _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list)

func open() -> void:
    visible = true
    _book = -1
    refresh()

func close() -> void:
    visible = false

func _label(text: String) -> void:
    var l := Label.new()
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.text = text
    _list.add_child(l)

func _button(text: String, disabled: bool, cb: Callable) -> void:
    var b := Button.new()
    b.text = text
    b.disabled = disabled
    b.pressed.connect(cb)
    _list.add_child(b)

func refresh() -> void:
    if not visible:
        return
    for c in _list.get_children():
        c.queue_free()
    if _book < 0:
        _draw_books()
    else:
        _draw_pages()

func _draw_books() -> void:
    _label("THE CURIO HALL CHRONICLE")
    _button("X Close", false, close)
    var books: Array = ConfigDB.story_recap.keys()
    books.sort()
    for b in books:
        var entry: Dictionary = ConfigDB.story_recap[b]
        if game.campaign.done.has(String(entry["task"])):
            _button("Volume %d" % int(b), false, _open_book.bind(int(b)))
        else:
            _label("Volume %d   (sealed until the restoration reaches further)" % int(b))

func _open_book(b: int) -> void:
    _book = b
    _page = 1
    refresh()

func _back_to_books() -> void:
    _book = -1
    refresh()

func _pages() -> Array:
    var entry: Dictionary = ConfigDB.story_recap.get(_book, {})
    var rows_v: Variant = entry.get("rows")
    var rows: Array = rows_v if rows_v is Array else []
    var out: Array = []
    for row in rows:
        var p := int(row["Page"])
        while out.size() < p:
            out.append([])
        (out[p - 1] as Array).append(row)
    return out

func _prev_page() -> void:
    _page -= 1
    refresh()

func _next_page() -> void:
    _page += 1
    refresh()

func _draw_pages() -> void:
    var pages := _pages()
    _button("< Volumes", false, _back_to_books)
    _label("Volume %d   page %d / %d" % [_book, _page, pages.size()])
    if _page >= 1 and _page <= pages.size():
        for row in pages[_page - 1]:
            match String(row["Type"]):
                "title":
                    _label("== %s ==" % String(row["Content"]))
                "subtitle":
                    _label("-- %s --" % String(row["Content"]))
                "img":
                    _label("[illustration: %s]" % String(row["Content"]))
                _:
                    _label(String(row["Content"]))
    _button("< Back", _page <= 1, _prev_page)
    _button("Next >", _page >= pages.size(), _next_page)
