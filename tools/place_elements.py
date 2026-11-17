#!/usr/bin/env python3
"""Lay one wing's elements out on its room floor (pos + size in the elements config).

usage: place_elements.py AREA --floor X0,Y0,X1,Y1 [--write] [--preview out.png]
                         [--max-size 330] [--gap 16] [--wall Y] [--min-px 150]
                         [--hang ID,ID --hang-band Y0,Y1] [--subroom N]

Each element's visible box is measured from the union of its look sprites. All
elements share one scale factor (stars 1.4x), found by binary search so that
shelf-packed rows fill the floor without overlapping. The star (the element
carrying a `beat`, last of the wing) sits at the centre of the middle row.
`--wall` is the far-wall line: the back row's bases must sit on the floor below
it (its tops may rise above the floor rect, against the wall). When a short side
would drop below `--min-px`, the gap shrinks first. `--hang` items (chandeliers,
lamps on chains) form one row hanging from the top of `--hang-band`.
`--subroom N` places only that subroom's elements, on its own scene (wings with
several rooms); without it every element of the area is placed together.
`pos` is the bottom-centre of the sprite and `size` its square side, as in
view/element_sprite.gd. Only pos and size are written.
"""
import argparse
import json
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

CANVAS = 384.0
STAR_BOOST = 1.4


def visible_box(el):
    """(w, h) of the union of the looks' opaque boxes, in canvas units (384)."""
    w = h = 0
    for i in range(len(el["looks"])):
        p = os.path.join(C.ROOT, C.element_path(el["id"], i))
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA")
        box = im.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
        if box:
            sc = CANVAS / im.width
            w, h = max(w, (box[2] - box[0]) * sc), max(h, (box[3] - box[1]) * sc)
    return (w or 200.0), (h or 200.0)


def sprite_offset(el):
    """(dx, pad) of look 0 in canvas units: how far the opaque box's centre sits
    right of the canvas centre, and the empty band under it. pos is the canvas
    bottom-centre, so the visible object is shifted by these."""
    p = os.path.join(C.ROOT, C.element_path(el["id"], 0))
    if not os.path.exists(p):
        return 0.0, 0.0
    im = Image.open(p).convert("RGBA")
    box = im.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox()
    if not box:
        return 0.0, 0.0
    sc = CANVAS / im.width
    return ((box[0] + box[2]) / 2.0 - im.width / 2.0) * sc, (im.height - box[3]) * sc


def to_pos(placed, offsets):
    """Visible bottom-centre (cx, base) -> sprite pos (canvas bottom-centre)."""
    out = {}
    for i, (cx, by, size) in placed.items():
        dx, pad = offsets.get(i, (0.0, 0.0))
        out[i] = (round(cx - dx * size / CANVAS), round(by + pad * size / CANVAS), size)
    return out


def pack(items, star, k, floor, gap, star_at=0.5):
    """Return rows [[(el, size, vw, vh)]] with the star centred in the middle
    row, or None when something is wider than the floor."""
    x0, y0, x1, y1 = floor
    width = x1 - x0
    items = sorted(items, key=lambda t: -t[3])   # tall things first
    star_row = None
    if star is not None:
        sw = star[2]
        if sw > width:
            return None
        cap = (width - sw) / 2.0 - gap
        left, right = [], []
        lw = rw = 0.0
        for t in sorted(items, key=lambda t: t[3]):      # smallest first
            if lw + t[2] + gap <= cap and lw <= rw:
                left.append(t)
                lw += t[2] + gap
            elif rw + t[2] + gap <= cap:
                right.append(t)
                rw += t[2] + gap
        taken = {id(t) for t in left + right}
        items = [t for t in items if id(t) not in taken]
        star_row = left + [star] + right
    rows, cur, curw = [], [], 0.0
    for t in items:
        if t[2] > width:
            return None
        if cur and curw + gap + t[2] > width:
            rows.append(cur)
            cur, curw = [], 0.0
        curw += (gap if cur else 0) + t[2]
        cur.append(t)
    if cur:
        rows.append(cur)
    if star_row is not None:
        rows.insert(min(len(rows), int(len(rows) * star_at + 0.5)) if star_at != 0.5
                    else len(rows) // 2, star_row)
    return rows


def heights(rows, gap):
    return sum(max(t[3] for t in r) for r in rows) + gap * max(0, len(rows) - 1)


def layout(els, floor, max_size, gap, wall=None, boxes=None, star="auto", star_at=0.5):
    """Rows for the floor elements. `wall`: the far-wall line; the first (back)
    row's base must sit at or below it, so its sprites may rise above y0
    against the wall while standing on the floor."""
    x0, y0, x1, y1 = floor
    fh = y1 - y0
    boxes = boxes or {e["id"]: visible_box(e) for e in els}
    if star == "auto":
        star = [e for e in els if e.get("beat") and e is els[-1]]
        star = star[0] if star else None
    lo, hi = 40.0, float(max_size)
    best = None
    for _ in range(18):
        s = (lo + hi) / 2
        items, st = [], None
        for e in els:
            m = STAR_BOOST if e is star else 1.0
            size = min(s * m, max_size * 1.15 if e is star else max_size)
            vw, vh = boxes[e["id"]][0] * size / CANVAS, boxes[e["id"]][1] * size / CANVAS
            t = (e, size, vw, vh)
            if e is star:
                st = t
            else:
                items.append(t)
        rows = pack(items, st, s, floor, gap, star_at)
        if rows is not None and heights(rows, gap) + back_drop(rows, floor, wall) <= fh:
            best, lo = rows, s
        else:
            hi = s
    return best


def back_drop(rows, floor, wall):
    """How far the back row must sit below y0 + its height to stand below `wall`."""
    if wall is None or not rows:
        return 0.0
    return max(0.0, wall - (floor[1] + max(t[3] for t in rows[0])))


def assign(rows, floor, gap, wall=None, star=None):
    """{id: (visible centre x, base y, size)}. The star's row keeps the star at
    the floor's centre, with its neighbours spread evenly on each side."""
    x0, y0, x1, y1 = floor
    fh = y1 - y0
    drop = back_drop(rows, floor, wall)
    used = sum(max(t[3] for t in r) for r in rows) + drop
    extra = (fh - used) / max(1, len(rows) + 1)      # spread leftover floor
    y = y0 + drop + extra
    out = {}
    for r in rows:
        rh = max(t[3] for t in r)
        base = y + rh
        k = next((i for i, t in enumerate(r) if star is not None and t[0] is star), None)
        if k is None:
            spread_row(out, r, x0, x1, base)
        else:
            st = r[k]
            cx = (x0 + x1) / 2.0
            out[star["id"]] = (round(cx), round(base), round(st[1]))
            spread_row(out, r[:k], x0, cx - st[2] / 2, base)
            spread_row(out, r[k + 1:], cx + st[2] / 2, x1, base)
        y = base + extra
    return out


def spread_row(out, items, a, b, base):
    """Space items evenly between a and b (equal gaps, including both ends)."""
    if not items:
        return
    space = (b - a - sum(t[2] for t in items)) / (len(items) + 1)
    x = a + space
    for t in items:
        out[t[0]["id"]] = (round(x + t[2] / 2), round(base), round(t[1]))
        x += t[2] + space


def min_side(rows):
    """Shortest visible side (px) over every placed element."""
    return min(min(t[2], t[3]) for r in rows for t in r) if rows else 0


def place(els, floor, max_size, gap, wall=None, hang=(), hang_band=None, min_px=0, hang_x=None,
          star_at=0.5):
    """{id: (cx, base_y, size)} for one wing.

    Hanging ids are laid out in one row in hang_band (y0, y1) high in the room,
    each hanging from y0; the star is centred there if it hangs. Floor elements
    are shelf-packed; when their shortest visible side falls below min_px the
    gap is shrunk (gap, gap/2, 4, 0) before accepting the smaller size."""
    boxes = {e["id"]: visible_box(e) for e in els}
    last = els[-1] if els else None
    star = last if last is not None and last.get("beat") else None
    floor_els = [e for e in els if e["id"] not in hang]
    hung = [e for e in els if e["id"] in hang]
    fstar = star if star in floor_els else None
    best = None
    for g in sorted({gap, gap / 2.0, min(gap, 4.0), 0.0}, reverse=True):
        rows = layout(floor_els, floor, max_size, g, wall, boxes, fstar, star_at)
        if rows is None:
            continue
        if best is None or min_side(rows) > min_side(best[0]):
            best = (rows, g)
        if min_side(rows) >= min_px:
            best = (rows, g)
            break
    if best is None:
        return None
    rows, g = best
    out = assign(rows, floor, g, wall, fstar)
    if hung:
        hy0, hy1 = hang_band
        size = max(t[1] for r in rows for t in r if t[0] is not fstar)
        x0, x1 = hang_x or (floor[0], floor[2])
        others = [e for e in hung if e is not star]
        order = others[:len(others) // 2] + ([star] if star in hung else []) + others[len(others) // 2:]
        sizes = []
        for e in order:
            sz = size * (STAR_BOOST if e is star else 1.0)
            bw, bh = boxes[e["id"]]
            sz = min(sz, (hy1 - hy0) * CANVAS / bh, (x1 - x0) / len(order) * CANVAS / bw)
            sizes.append((e, sz, bw * sz / CANVAS, bh * sz / CANVAS))

        def spread(ts, a, b):
            space = (b - a - sum(t[2] for t in ts)) / (len(ts) + 1)
            x = a + space
            for e, sz, vw, vh in ts:
                out[e["id"]] = (round(x + vw / 2), round(hy0 + vh), round(sz))
                x += vw + space
        if star in hung:
            k = order.index(star)
            st = sizes[k]
            cx = (x0 + x1) / 2.0
            out[star["id"]] = (round(cx), round(hy0 + st[3]), round(st[1]))
            spread(sizes[:k], x0, cx - st[2] / 2)
            spread(sizes[k + 1:], cx + st[2] / 2, x1)
        else:
            spread(sizes, x0, x1)
    return to_pos(out, {e["id"]: sprite_offset(e) for e in els})


def wing_elements(allel, area, subroom=None):
    """The elements one placement run lays out: the area's, or one subroom's."""
    return [e for e in allel if e["area"] == area
            and (subroom is None or int(e.get("subroom", 0)) == subroom)]


def preview(els, placed, scene, path):
    room = Image.open(scene).convert("RGBA")
    order = sorted(els, key=lambda e: placed[e["id"]][1])
    for e in order:
        cx, by, size = placed[e["id"]]
        p = os.path.join(C.ROOT, C.element_path(e["id"], 0))
        if not os.path.exists(p):
            continue
        im = Image.open(p).convert("RGBA").resize((size, size), Image.LANCZOS)
        room.alpha_composite(im, (cx - size // 2, by - size))
    room.convert("RGB").save(path)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("area", type=int)
    ap.add_argument("--floor", required=True, help="x0,y0,x1,y1 of the open floor")
    ap.add_argument("--max-size", type=float, default=330)
    ap.add_argument("--gap", type=float, default=16)
    ap.add_argument("--wall", type=float, help="far-wall line: back-row bases sit below it")
    ap.add_argument("--hang", default="", help="comma-separated ids that hang high in the room")
    ap.add_argument("--hang-band", default="", help="y0,y1 of the band hanging items fill")
    ap.add_argument("--hang-x", default="", help="x0,x1 the hanging row spans (default: the floor's)")
    ap.add_argument("--star-at", type=float, default=0.5,
                    help="where the star's row goes, as a fraction of the rows (0 = back row; "
                         "small values keep it on a tall room's first screen)")
    ap.add_argument("--min-px", type=float, default=150,
                    help="shrink the gap before letting a short side drop below this")
    ap.add_argument("--subroom", type=int, help="place only this subroom's elements")
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--preview")
    a = ap.parse_args(argv)
    floor = [float(v) for v in a.floor.split(",")]
    allel = C.elements()
    els = wing_elements(allel, a.area, a.subroom)
    hang = {h.strip() for h in a.hang.split(",") if h.strip()}
    band = [float(v) for v in a.hang_band.split(",")] if a.hang_band else None
    if hang and not band:
        print("--hang needs --hang-band", file=sys.stderr)
        return 2
    placed = place(els, floor, a.max_size, a.gap, a.wall, hang, band, a.min_px,
                   [float(v) for v in a.hang_x.split(",")] if a.hang_x else None, a.star_at)
    if placed is None:
        print("does not fit", file=sys.stderr)
        return 1
    boxes = {e["id"]: visible_box(e) for e in els}
    small = 1e9
    for e in els:
        cx, by, size = placed[e["id"]]
        bw, bh = boxes[e["id"]]
        side = min(bw, bh) * size / CANVAS
        small = min(small, side)
        print(e["id"], placed[e["id"]], "short=%d" % side,
              "star" if e is els[-1] and e.get("beat") else "", "hang" if e["id"] in hang else "")
    print("smallest short side %d px" % small)
    if a.preview:
        preview(els, placed, os.path.join(C.ROOT, C.scene_path(a.area, a.subroom or 0)), a.preview)
    if a.write:
        by = {e["id"]: e for e in allel}
        for i, (cx, b, size) in placed.items():
            by[i]["pos"] = [cx, b]
            by[i]["size"] = size
        path = os.path.join(C.ROOT, "config", "curio_hall_elements.json")
        with open(path, "w", encoding="utf-8") as f:
            f.write(json.dumps(allel, indent=1) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
