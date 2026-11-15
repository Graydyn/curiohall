extends SceneTree
## Screenshot one wing view (needs a display, not --headless).
## usage: godot --path . -s res://tools/shot_wing.gd -- <area|exterior> <out.png> [done]
## "done" marks every element of the area finished with look 0, so the art
## shows instead of the outline stage.
##
## Game classes reference autoloads (ConfigDB), so they are only loaded once
## the tree is running, from tools/shot_wing_node.gd.

var _frames := 0
var _node: Node

func _process(_delta: float) -> bool:
    _frames += 1
    if _frames == 2:
        _node = load("res://tools/shot_wing_node.gd").new()
        root.add_child(_node)
    if _frames > 2:
        for c in root.get_children():
            if c != _node and c is CanvasItem:
                (c as CanvasItem).visible = false
    if _frames == 16:
        var out: String = _node.out_path
        root.get_viewport().get_texture().get_image().save_png(out)
        print("saved ", out)
        return true
    return false
