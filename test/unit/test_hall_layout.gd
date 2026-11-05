extends GutTest

func test_47_wings_all_areas_once() -> void:
    var wings := HallLayout.wings()
    assert_eq(wings.size(), 47)
    var seen := {}
    for w in wings:
        seen[int(w["area"])] = true
    for area in range(1, 48):
        assert_true(seen.has(area), "area %d missing" % area)

func test_no_overlaps_and_inside_canvas() -> void:
    var wings := HallLayout.wings()
    var canvas := Rect2(Vector2.ZERO, HallLayout.canvas_size())
    for i in range(wings.size()):
        var a: Rect2 = wings[i]["rect"]
        assert_true(canvas.encloses(a), "wing %d outside canvas" % i)
        for j in range(i + 1, wings.size()):
            var b: Rect2 = wings[j]["rect"]
            assert_false(a.intersects(b), "wings %d and %d overlap" % [i, j])

func test_names_match_creative_direction() -> void:
    var by_area := {}
    for w in HallLayout.wings():
        by_area[int(w["area"])] = String(w["name"])
    assert_eq(by_area[1], "The Front Gates")
    assert_eq(by_area[2], "The Grand Atrium")
    assert_eq(by_area[47], "The Attic of Marvels")
