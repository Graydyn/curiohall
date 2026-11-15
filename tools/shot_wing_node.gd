extends Control
## Helper for tools/shot_wing.gd: builds a WingView (or the exterior map) from
## the command line args:
##   <area> <out.png> [done]
##   exterior <out.png> [states] [zoom] [center_area]
## states like "1r,2r,3b,4b" (r restored, a active, b/l locked) override the
## campaign's wing states for the shot.

var out_path := "user://wing.png"

func _ready() -> void:
    var args := OS.get_cmdline_user_args()
    out_path = String(args[1]) if args.size() > 1 else out_path
    size = Vector2(720, 1280)
    theme = CurioTheme.build()
    var g := Game.fresh(0.0)
    if args.size() > 0 and args[0] == "exterior":
        var m := ExteriorMap.new()
        add_child(m)
        m.size = size
        m.setup(g)
        if args.size() > 2 and args[2] != "":
            var codes := {"r": Campaign.AreaState.RESTORED, "a": Campaign.AreaState.ACTIVE,
                    "b": Campaign.AreaState.LOCKED, "l": Campaign.AreaState.LOCKED}
            for t in String(args[2]).split(","):
                m.state_override[int(t.substr(0, t.length() - 1))] = codes[t.right(1)]
            m.refresh()
        if args.size() > 3:
            m.zoom = float(args[3])
        m.center_on(int(args[4]) if args.size() > 4 else 1)
        return
    var area := int(args[0]) if args.size() > 0 else 1
    if args.size() > 2 and args[2] == "done":
        for row in HallElements.in_area(area):
            for key in row["tasks"]:
                g.campaign.done[String(key)] = true
            g.hall.looks[String(row["id"])] = 0
    var w := WingView.new()
    add_child(w)
    w.size = size
    w.setup(g, area, "")
