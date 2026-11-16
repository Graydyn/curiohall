#!/usr/bin/env python3
"""Lay one wing's elements out on its room floor (pos + size in the elements config).

usage: place_elements.py AREA --floor X0,Y0,X1,Y1 [--write] [--preview out.png]
                         [--max-size 330] [--gap 16]

Each element's visible box is measured from the union of its look sprites. All
elements share one scale factor (stars 1.4x), found by binary search so that
shelf-packed rows fill the floor without overlapping. The star (the element
carrying a `beat`, last of the wing) sits at the centre of the middle row.
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


def pack(items, star, k, floor, gap):
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
        rows.insert(len(rows) // 2, star_row)
    return rows


def heights(rows, gap):
    return sum(max(t[3] for t in r) for r in rows) + gap * max(0, len(rows) - 1)


def layout(els, floor, max_size, gap):
    x0, y0, x1, y1 = floor
    fh = y1 - y0
    boxes = {e["id"]: visible_box(e) for e in els}
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
        rows = pack(items, st, s, floor, gap)
        if rows is not None and heights(rows, gap) <= fh:
            best, lo = rows, s
        else:
            hi = s
    return best


def assign(rows, floor, gap):
    x0, y0, x1, y1 = floor
    fh = y1 - y0
    used = sum(max(t[3] for t in r) for r in rows)
    extra = (fh - used) / max(1, len(rows) + 1)      # spread leftover floor
    y = y0 + extra
    out = {}
    for r in rows:
        rh = max(t[3] for t in r)
        base = y + rh
        tw = sum(t[2] for t in r)
        space = (x1 - x0 - tw) / (len(r) + 1)
        x = x0 + space
        for t in r:
            out[t[0]["id"]] = (round(x + t[2] / 2 + 0.0), round(base), round(t[1]))
            x += t[2] + space
        y = base + extra
    return out


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
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--preview")
    a = ap.parse_args(argv)
    floor = [float(v) for v in a.floor.split(",")]
    allel = C.elements()
    els = [e for e in allel if e["area"] == a.area]
    rows = layout(els, floor, a.max_size, a.gap)
    if rows is None:
        print("does not fit", file=sys.stderr)
        return 1
    placed = assign(rows, floor, a.gap)
    for e in els:
        print(e["id"], placed[e["id"]], "star" if e.get("beat") else "")
    if a.preview:
        preview(els, placed, os.path.join(C.ROOT, C.scene_path(a.area, 0)), a.preview)
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
