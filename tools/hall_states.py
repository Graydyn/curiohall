#!/usr/bin/env python3
"""Wing states for the "Hall as one building" exterior.

The master painting (_raw/hall/master.png) is the RESTORED look of everything.
Locked looks are Sectilia edits of crops ("tiles") of the master, pasted back
under masks limited to each wing's rect:

  base.png               = the all-locked composite (drawn by the game)
  wing_NN_restored.png   = master pixels of the wing's rect, alpha = its mask
                           (drawn over the base when the wing is reached)

So a reached wing shows exactly master pixels and a locked one exactly its
locked edit, and neighbours never bleed into each other (masks fade to 0
inside the rect edge).

usage:
  hall_states.py crop NAME x,y,w,h            crop a tile of the master (<=1024)
  hall_states.py manifest NAME... --kind boarded|empty [--style-key K...]
  hall_states.py check NAME EDIT.png          drift check of an edit (JSON, exit 1 = drift)
  hall_states.py build [--only AREA...]       compose base.png and wing textures
  hall_states.py rects                        overlap/size report of config rects
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageStat

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

MAX_SIDE = 1024
HDIR = C.BASE + "/_raw/hall"
MASTER = HDIR + "/master.png"
TILES = HDIR + "/tiles"
INSTR = {
    "boarded": (
        "board up this part of the building: nail weathered wooden planks across every window "
        "and door, dark unlit glass, grey dust sheets hanging inside, no lamps lit; keep the "
        "building's shape, roofs, walls, colours, the sky, the grounds, the composition and the "
        "framing exactly identical, make only these changes"),
    "empty": (
        "remove the building in the middle of the picture completely and leave its plot as "
        "empty mown lawn with the same grass as around it; keep everything else, the paths, "
        "trees, hedges, the composition and the framing exactly identical"),
    # Second-pass instructions for sections the general board-up left
    # nearly unchanged (roofs, towers, the dome have few windows).
    "roof": (
        "this roof is neglected: many slates missing showing bare dark battens, a torn grey "
        "tarpaulin weighed down with planks over part of it, the dormer windows dark with broken "
        "glass and boarded with planks; keep the building's shape, the walls, the sky, the "
        "grounds, the composition and the framing exactly identical, make only these changes"),
    "towers": (
        "the two towers are shut up: planks nailed over every tower window and door, the "
        "observatory dome on the right tower closed and wrapped in a torn grey tarpaulin tied "
        "with rope, the pointed spire on the left tower missing slates with bare dark battens; "
        "keep the buildings' shapes, the sky, the trees, the composition and the framing exactly "
        "identical, make only these changes"),
    "dome": (
        "the big dome is neglected: its copper streaked and stained dark, a torn grey tarpaulin "
        "draped over part of it, its small windows boarded with planks and the lantern on top "
        "dark; keep the building's shape, the sky, the composition and the framing exactly "
        "identical, make only these changes"),
    "wing": (
        "this long wing is shut up and neglected: many roof slates missing showing bare dark "
        "battens, a torn grey tarpaulin over part of the roof, dark dormers, every courtyard "
        "window boarded with planks and grey dust sheets; keep the building's shape, the sky, "
        "the trees, the composition and the framing exactly identical, make only these changes"),
    # The first "empty" wording made several plots into new formal hedge
    # gardens seen top-down (re-framed), or removed only part of a structure.
    "empty2": (
        "erase the structure in the middle completely, together with its base, platform, paving "
        "and the flowers around it, so only plain grass remains where it stood: the same sunlit "
        "grass with the same soft light rays as the lawn around it; do not add hedges, paths, "
        "flower beds or anything else; keep everything else exactly identical and the framing "
        "unchanged"),
    # Separate structures came out of the background agent as clean-edged
    # stickers with no shadow; this settles them into the lawn first.
    "settle": (
        "blend the building in the middle into the surrounding lawn so the whole picture is one "
        "coherent painting: matching soft evening light and colour, a soft contact shadow where "
        "it meets the grass, its base settled naturally into the lawn; make only subtle changes, "
        "do not move, redraw or re-frame anything, keep its shape, position and size identical"),
}
# Change mask: diffs smaller than this (after a blur) are the edit's general
# repaint (grass smoothing, slight tone shift), not the state change.
CHANGE_THRESH = 28
SECTION_FEATHER = 14      # px ramp inside each rect edge
# Drift check limits (calibrated on the Task 9 pilot, see test_art_tools).
# Good edits scored corr 0.80-0.96, border 3-11, |tone| <= 7; the re-framed
# (isometric) Atrium scored corr 0.60-0.64, border 43-49.
MAX_SHIFT_STEPS = 1       # shift search steps (1/160 of the long side)
MIN_EDGE_CORR = 0.75
MAX_BORDER_DIFF = 25.0    # mean abs grey diff in the outer band (0-255)
MAX_TONE = 30.0           # global grey offset; more swallows the whole mask


def _p(rel):
    return os.path.join(C.ROOT, rel)


def tile_png(name):
    return "%s/%s.png" % (TILES, name)


def tile_meta(name):
    return "%s/%s.json" % (TILES, name)


def tile_edit(name):
    return "%s/%s_edit.png" % (TILES, name)


def tile_settle(name):
    return "%s/%s_settle.png" % (TILES, name)


# ---------------------------------------------------------------- geometry

def fit_size(w, h, max_side=MAX_SIDE):
    k = min(1.0, max_side / float(max(w, h)))
    return max(1, round(w * k)), max(1, round(h * k))


def rects_overlap(a, b):
    return not (a[0] + a[2] <= b[0] or b[0] + b[2] <= a[0] or
                a[1] + a[3] <= b[1] or b[1] + b[3] <= a[1])


def contains(outer, inner):
    return (outer[0] <= inner[0] and outer[1] <= inner[1] and
            inner[0] + inner[2] <= outer[0] + outer[2] and
            inner[1] + inner[3] <= outer[1] + outer[3])


# ExteriorMap's default zoom, and the smallest comfortable tap on screen.
DEFAULT_ZOOM = 0.7
MIN_TAP_PX = 120
MIN_SIDE = int(-(-MIN_TAP_PX // DEFAULT_ZOOM))   # 172 canvas px


def rect_problems(rows, min_side=MIN_SIDE):
    """Overlaps and too-small rects (min_side in canvas px)."""
    out = []
    for i, a in enumerate(rows):
        r = a["exterior_rect"]
        if min(r[2], r[3]) < min_side:
            out.append("area %d rect %s smaller than %d" % (a["area"], r, min_side))
        for b in rows[i + 1:]:
            if rects_overlap(r, b["exterior_rect"]):
                out.append("areas %d and %d overlap" % (a["area"], b["area"]))
    return out


def section_fade(size, feather=SECTION_FEATHER):
    """L mask of `size`: 255 inside, ramping to 0 at the edges."""
    w, h = size
    m = Image.new("L", size, 0)
    f = max(1, min(feather, w // 4, h // 4))
    ImageDraw.Draw(m).rectangle((f, f, w - 1 - f, h - 1 - f), fill=255)
    return m.filter(ImageFilter.GaussianBlur(f / 2.0))


def change_mask(a, b, thresh=CHANGE_THRESH, grow=5, blur=4):
    """Where b differs from a in a way that matters (the state change),
    as a soft L mask. Fine repaint noise is blurred out before thresholding."""
    d = ImageChops.difference(a.convert("RGB"), b.convert("RGB")).convert("L")
    d = d.filter(ImageFilter.GaussianBlur(2))
    m = d.point(lambda v: 255 if v >= thresh else 0)
    m = m.filter(ImageFilter.MaxFilter(grow | 1)).filter(ImageFilter.MinFilter(3))
    m = m.filter(ImageFilter.MaxFilter(grow | 1))
    return m.filter(ImageFilter.GaussianBlur(blur))


# ---------------------------------------------------------------- drift check

def _grey(im, side):
    g = im.convert("L")
    k = side / float(max(g.size))
    return g.resize((max(1, round(g.width * k)), max(1, round(g.height * k))), Image.BILINEAR)


def best_shift(a, b, radius):
    """Integer (dx, dy, diff) minimising the mean abs diff of b shifted
    against a, over the overlap."""
    best = (0, 0, 1e9)
    w, h = a.size
    for dy in range(-radius, radius + 1):
        for dx in range(-radius, radius + 1):
            ax0, ay0 = max(0, dx), max(0, dy)
            bx0, by0 = max(0, -dx), max(0, -dy)
            cw, ch = w - abs(dx), h - abs(dy)
            ca = a.crop((ax0, ay0, ax0 + cw, ay0 + ch))
            cb = b.crop((bx0, by0, bx0 + cw, by0 + ch))
            v = ImageStat.Stat(ImageChops.difference(ca, cb)).mean[0]
            if v < best[2] - 1e-6:
                best = (dx, dy, v)
    return best


def correlation(a, b):
    """Pearson correlation of two same-size L images."""
    xa, xb = list(a.tobytes()), list(b.tobytes())
    n = float(len(xa))
    ma, mb = sum(xa) / n, sum(xb) / n
    sab = sum((p - ma) * (q - mb) for p, q in zip(xa, xb))
    saa = sum((p - ma) ** 2 for p in xa)
    sbb = sum((q - mb) ** 2 for q in xb)
    if saa < 1e-6 or sbb < 1e-6:
        return 0.0
    return sab / (saa * sbb) ** 0.5


def edges(g):
    return g.filter(ImageFilter.GaussianBlur(1)).filter(ImageFilter.FIND_EDGES) \
            .filter(ImageFilter.GaussianBlur(1.5))


def drift(src, edit, band=0.12):
    """Compare an edit with its source crop. Returns a dict with the framing
    shift (px at source size, found on edge maps so a global darkening does
    not fool it), the edge-structure correlation, the mean grey diff of the
    outer band after removing the global tone offset, the tone offset itself,
    and ok=True/False."""
    edit = edit.convert("RGB")
    if edit.size != src.size:
        edit = edit.resize(src.size, Image.LANCZOS)
    ea, eb = edges(_grey(src, 160)), edges(_grey(edit, 160))
    k = src.width / float(ea.width)
    dx, dy, _ = best_shift(ea, eb, 8)
    corr = correlation(edges(_grey(src, 320)), edges(_grey(edit, 320)))
    g1, g2 = _grey(src, 320), _grey(edit, 320)
    tone = ImageStat.Stat(g2).mean[0] - ImageStat.Stat(g1).mean[0]
    off = int(round(-tone))
    g2n = g2.point(lambda v: max(0, min(255, v + off)))
    w, h = g1.size
    bw = max(2, int(min(w, h) * band))
    outer = Image.new("L", (w, h), 255)
    ImageDraw.Draw(outer).rectangle((bw, bw, w - 1 - bw, h - 1 - bw), fill=0)
    diff = ImageStat.Stat(ImageChops.difference(g1, g2n), outer).mean[0]
    shift = max(abs(dx), abs(dy)) * k
    res = {"shift_px": round(shift, 1), "dx": round(dx * k, 1), "dy": round(dy * k, 1),
           "edge_corr": round(corr, 3), "border_diff": round(diff, 1), "tone": round(tone, 1)}
    res["ok"] = (max(abs(dx), abs(dy)) <= MAX_SHIFT_STEPS and corr >= MIN_EDGE_CORR and
                 diff <= MAX_BORDER_DIFF and abs(tone) <= MAX_TONE)
    return res


# ---------------------------------------------------------------- composing

def load_tiles():
    out = {}
    d = _p(TILES)
    if not os.path.isdir(d):
        return out
    for f in sorted(os.listdir(d)):
        if f.endswith(".json"):
            meta = json.load(open(os.path.join(d, f)))
            if os.path.exists(_p(tile_edit(meta["name"]))):
                out[meta["name"]] = meta
    return out


def tile_for(rect, tiles, area=None):
    """The tile that contains rect with the most room around it. A tile with
    an "areas" list serves only those wings, and wins over general tiles."""
    if area is not None:
        own = {n: t for n, t in tiles.items() if area in t.get("areas", [])}
        if own:
            tiles = own
    best, room = None, -1
    for name, t in tiles.items():
        tr = t["rect"]
        if "areas" in t and area not in t["areas"]:
            continue
        if not contains(tr, rect):
            continue
        r = min(rect[0] - tr[0], rect[1] - tr[1], tr[0] + tr[2] - rect[0] - rect[2],
                tr[1] + tr[3] - rect[1] - rect[3])
        if r > room:
            best, room = name, r
    return best


def edit_in_canvas(meta):
    """The tile's edit, resized back to the tile rect in canvas px."""
    im = Image.open(_p(tile_edit(meta["name"]))).convert("RGBA")
    im = im.crop(im.getbbox() or (0, 0) + im.size).convert("RGB")
    return im.resize((meta["rect"][2], meta["rect"][3]), Image.LANCZOS)


def tone_match(src, edit):
    """Shift each channel of `edit` so that, away from what the edit changed
    on purpose, it has the same mean as `src` (edits brighten or darken the
    whole crop a little, which would show as a patch at the mask edge)."""
    keep = change_mask(src, edit).point(lambda v: 0 if v > 8 else 255)
    if ImageStat.Stat(keep).mean[0] < 8:
        return edit
    ms, me = ImageStat.Stat(src, keep).mean, ImageStat.Stat(edit, keep).mean
    bands = [b.point(lambda v, o=round(ms[i] - me[i]): max(0, min(255, v + o)))
             for i, b in enumerate(edit.split())]
    return Image.merge("RGB", bands)


def footprint(src, edit, grow=25, thresh=60, close=25):
    """Where a structure was removed: strong differences only (the general
    lawn repaint is softer), specks opened away, holes closed, grown for the
    contact shadow and softened."""
    d = ImageChops.difference(src, edit).convert("L").filter(ImageFilter.GaussianBlur(2))
    m = d.point(lambda v: 255 if v >= thresh else 0)
    m = m.filter(ImageFilter.MinFilter(7)).filter(ImageFilter.MaxFilter(7))
    m = m.filter(ImageFilter.MaxFilter(close | 1)).filter(ImageFilter.MinFilter(close | 1))
    m = m.filter(ImageFilter.MaxFilter(grow | 1))
    return m.filter(ImageFilter.GaussianBlur(grow / 2.0))


def empty_layer(src, edit):
    """(footprint, tone-matched empty plot). The empty edit relights the
    whole lawn, so: a coarse footprint from strong diffs, match the lawn
    tone on a wide ring around it, then a finer footprint (pale walls on
    pale lawn) and a final match on a tight ring."""
    core = footprint(src, edit)
    e1 = ring_match(src, edit, core, 61)
    # Dark glass on dark lawn differs only a little: a low threshold, with a
    # wide closing so the whole structure comes out as one blob, but only
    # near the strong core (the edit also relights open lawn further away,
    # which would paste back as a lighter patch).
    near = core.point(lambda v: 255 if v > 8 else 0).filter(ImageFilter.MaxFilter(61))
    fp = ImageChops.multiply(footprint(src, e1, grow=31, thresh=22, close=45), near)
    fp = fp.filter(ImageFilter.GaussianBlur(6))
    return fp, ring_match(src, edit, fp)


def sky_mask(src, edit, k=18):
    """Where the edit painted sky (blue over red) over something that was not
    sky. Edits sometimes swap a lawn or a far wing for open sky; boarding up
    never should."""
    r1, _, b1 = src.split()
    r2, _, b2 = edit.split()
    was = ImageChops.subtract(b1, r1).point(lambda v: 255 if v >= k else 0)
    now = ImageChops.subtract(b2, r2).point(lambda v: 255 if v >= k else 0)
    return ImageChops.subtract(now, was).filter(ImageFilter.MaxFilter(5)) \
        .filter(ImageFilter.GaussianBlur(3))


def darker_mask(src, edit, dl=12, ds=30):
    """Where the edit is darker or greyer than the source: boarding up turns
    lit windows into planks, dark glass and dust sheets. Edits also repaint
    things they should not (a sky instead of a lawn, a bush removed), which
    come out lighter; this keeps those out."""
    l1, l2 = src.convert("L"), edit.convert("L")
    s1, s2 = src.convert("HSV").getchannel("S"), edit.convert("HSV").getchannel("S")
    a = ImageChops.subtract(l1, l2).point(lambda v: 255 if v >= dl else 0)
    b = ImageChops.subtract(s1, s2).point(lambda v: 255 if v >= ds else 0)
    m = ImageChops.lighter(a, b).filter(ImageFilter.GaussianBlur(2))
    return m.point(lambda v: 255 if v > 100 else 0).filter(ImageFilter.MaxFilter(5)) \
            .filter(ImageFilter.GaussianBlur(2))


def ring_match(src, edit, mask, width=41):
    """Offset edit's channels so they match src on a ring just outside mask."""
    hard = mask.point(lambda v: 255 if v > 8 else 0)
    ring = ImageChops.subtract(hard.filter(ImageFilter.MaxFilter(width)), hard)
    if ImageStat.Stat(ring).mean[0] < 1:
        return edit
    ms, me = ImageStat.Stat(src, ring).mean, ImageStat.Stat(edit, ring).mean
    return Image.merge("RGB", [b.point(lambda v, o=round(ms[i] - me[i]): max(0, min(255, v + o)))
                               for i, b in enumerate(edit.split())])


def wing_layers(master, rect, locked_tile_img, tile_rect, kind, fp_tile=None):
    """(mask L, locked RGB) of one wing's rect.
    kind 'boarded': the change mask inside the section fade.
    kind 'empty': the removed building's footprint inside the fade, with the
    empty lawn tone-matched to the lawn around it."""
    x, y, w, h = rect
    lx, ly = x - tile_rect[0], y - tile_rect[1]
    locked = locked_tile_img.crop((lx, ly, lx + w, ly + h))
    mine = master.crop((x, y, x + w, y + h)).convert("RGB")
    if kind == "empty":
        if fp_tile is not None:   # footprint worked out on the whole tile
            fp = fp_tile.crop((lx, ly, lx + w, ly + h))
        else:
            fp, locked = empty_layer(mine, locked)
        return ImageChops.multiply(fp, section_fade((w, h))), locked
    m = ImageChops.multiply(change_mask(mine, locked), darker_mask(mine, locked))
    m = ImageChops.subtract(m, sky_mask(mine, locked))
    m = ImageChops.multiply(m, section_fade((w, h)))
    return m, locked


def compose(master, wings, tiles, edits, footprints=None):
    """Returns (locked base RGB, {area: restored RGBA}, report).
    footprints: {tile name: L mask} for empty tiles prepared tile-wide."""
    footprints = footprints or {}
    base = master.convert("RGB").copy()
    restored, report = {}, {}
    for row in wings:
        area, rect = row["area"], row["exterior_rect"]
        x, y, w, h = rect
        name = tile_for(rect, tiles, area)
        if name is None:
            # No locked edit (the Front Gates are reached on day 1): master
            # pixels under a plain fade, identical to the base there.
            rgba = master.crop((x, y, x + w, y + h)).convert("RGBA")
            rgba.putalpha(section_fade((w, h)))
            restored[area] = rgba
            report[area] = "no tile (master)"
            continue
        kind = tiles[name].get("kind", "boarded")
        m, locked = wing_layers(master, rect, edits[name], tiles[name]["rect"], kind,
                                footprints.get(name))
        cov = ImageStat.Stat(m).mean[0] / 255.0
        base.paste(locked, (x, y), m)
        rgba = master.crop((x, y, x + w, y + h)).convert("RGBA")
        rgba.putalpha(m)
        restored[area] = rgba
        report[area] = {"tile": name, "coverage": round(cov, 3)}
    return base, restored, report


# ---------------------------------------------------------------- commands

def cmd_crop(a):
    master = Image.open(_p(MASTER)).convert("RGB")
    x, y, w, h = [int(v) for v in a.rect.split(",")]
    x0, y0 = max(0, x), max(0, y)
    x1, y1 = min(master.width, x + w), min(master.height, y + h)
    rect = [x0, y0, x1 - x0, y1 - y0]
    size = fit_size(rect[2], rect[3])
    os.makedirs(_p(TILES), exist_ok=True)
    master.crop((x0, y0, x1, y1)).resize(size, Image.LANCZOS).save(_p(tile_png(a.name)))
    meta = {"name": a.name, "rect": rect, "size": list(size), "kind": a.kind}
    if a.instr:
        meta["instr"] = a.instr
    if a.areas:
        meta["areas"] = [int(v) for v in a.areas.split(",")]
    json.dump(meta, open(_p(tile_meta(a.name)), "w"), indent=1)
    print("%s: %s -> %s" % (a.name, rect, list(size)))


def keep_spec(size):
    return {"canvas_size": list(size), "style": "painted", "background": {"type": "keep"},
            "anchor": "center", "alpha_threshold": 0, "palette": None, "margin": 0}


def build_manifest(names, style_keys=(), instr=None, settle=False):
    out = []
    for name in names:
        meta = json.load(open(_p(tile_meta(name))))
        sp = keep_spec(meta["size"])
        src = "hall_%s_src" % name
        out.append({"key": src, "out": "%s/%s_uploaded.png" % (TILES, name), "cmd": "upload",
                    "args": {"file": tile_png(name), "spec": sp}, "source_key": None})
        args = {"instruction": instr or INSTR[meta.get("instr", meta.get("kind", "boarded"))],
                "spec": sp}
        if style_keys:
            args["style_keys"] = list(style_keys)
        out.append({"key": "hall_%s_%s" % (name, meta.get("kind", "boarded")),
                    "out": tile_edit(name), "cmd": "edit", "args": args, "source_key": src})
        if settle and meta.get("kind") == "empty":
            out.append({"key": "hall_%s_settle" % name, "out": tile_settle(name), "cmd": "edit",
                        "args": {"instruction": INSTR["settle"], "spec": sp},
                        "source_key": src})
    return out


def cmd_manifest(a):
    json.dump(build_manifest(a.names, a.style_key, a.instruction, a.settle), sys.stdout, indent=1)
    sys.stdout.write("\n")


def settle_mask(src, empty):
    """Where a settled (relit, shadowed) structure replaces the master: the
    footprint of what the empty-plot edit removed, faded at the tile edge."""
    return ImageChops.multiply(empty_layer(src, empty)[0],
                               section_fade(src.size, max(8, min(src.size) // 10)))


def cmd_settle(a):
    master = Image.open(_p(MASTER)).convert("RGB")
    for name in a.names:
        meta = json.load(open(_p(tile_meta(name))))
        src = Image.open(_p(tile_png(name))).convert("RGB")
        fit = lambda f: Image.open(_p(f)).convert("RGB").resize(src.size, Image.LANCZOS)
        m = settle_mask(src, fit(tile_edit(name)))
        x, y, w, h = meta["rect"]
        # Pasted as is: the settled light and contact shadow are the point.
        # (Ring-matching the tone washed the buildings out; an edit that
        # relit the whole crop far darker is simply not settled.)
        settled = fit(tile_settle(name)).resize((w, h), Image.LANCZOS)
        master.paste(settled, (x, y), m.resize((w, h), Image.LANCZOS))
        m.save(_p("%s/%s_settle_mask.png" % (TILES, name)))
        print("settled", name, meta["rect"])
    master.save(_p(MASTER))


def used_box(meta, wings):
    """Bounding box (tile px) of the wing rects this tile serves."""
    tr = meta["rect"]
    k = meta["size"][0] / float(tr[2])
    boxes = [w["exterior_rect"] for w in wings if contains(tr, w["exterior_rect"]) and
             ("areas" not in meta or w["area"] in meta["areas"])]
    if not boxes:
        return None
    x0 = min(b[0] for b in boxes) - tr[0]
    y0 = min(b[1] for b in boxes) - tr[1]
    x1 = max(b[0] + b[2] for b in boxes) - tr[0]
    y1 = max(b[1] + b[3] for b in boxes) - tr[1]
    return tuple(round(v * k) for v in (x0, y0, x1, y1))


def correlation_masked(a, b, mask):
    """Pearson correlation of a and b over pixels where mask > 127."""
    pts = [(p, q) for p, q, m in zip(a.tobytes(), b.tobytes(), mask.tobytes()) if m > 127]
    if len(pts) < 50:
        return 0.0, 0
    n = float(len(pts))
    ma = sum(p for p, _ in pts) / n
    mb = sum(q for _, q in pts) / n
    sab = sum((p - ma) * (q - mb) for p, q in pts)
    saa = sum((p - ma) ** 2 for p, _ in pts)
    sbb = sum((q - mb) ** 2 for _, q in pts)
    if saa < 1e-6 or sbb < 1e-6:
        return 0.0, len(pts)
    return sab / (saa * sbb) ** 0.5, len(pts)


# Faithful state edits kept 0.98-0.99 of their untouched structure; the
# Task 9 re-framed Atrium edits kept 0.91-0.93 (over only 11-16% of the crop).
MIN_KEPT_CORR = 0.95      # structure of what the edit left alone
MIN_KEPT_FRAC = 0.10


def kept_structure(src, edit, kind):
    """Edge correlation over the pixels the state change did not touch, and
    their fraction. A faithful edit keeps walls/roofs/paths exactly where
    they were; a re-drawn scene keeps almost nothing."""
    side = 320
    if kind == "boarded":
        edit = tone_match(src, edit)
    g1, g2 = _grey(src, side), _grey(edit, side)
    small = lambda im: im.resize(g1.size, Image.BILINEAR)
    changed = footprint(src, edit) if kind == "empty" else change_mask(src, edit)
    keep = small(changed).point(lambda v: 255 if v < 16 else 0)
    corr, n = correlation_masked(edges(g1), edges(g2), keep)
    return round(corr, 3), round(n / float(g1.width * g1.height), 3)


def check_tile(meta, src, edit, wings):
    """Drift check of a state edit: no framing shift over the whole tile or
    the region actually used (the served wing rects), and the structure the
    edit was not asked to change still lines up (kept_corr). Border diff and
    tone are reported; they only matter outside the masks, which are thrown
    away."""
    kind = meta.get("kind", "boarded")
    edit = edit.convert("RGB").resize(src.size, Image.LANCZOS)
    whole = drift(src, edit)
    box = used_box(meta, wings) if kind == "boarded" else None
    used = drift(src.crop(box), edit.crop(box), band=0.06) if box else whole
    kc, kf = kept_structure(src.crop(box) if box else src, edit.crop(box) if box else edit, kind)
    step = src.width / 160.0 + 0.5
    ok = (whole["shift_px"] <= step and used["shift_px"] <= step and kc >= MIN_KEPT_CORR and
          kf >= MIN_KEPT_FRAC)
    return {"name": meta["name"], "ok": bool(ok), "kept_corr": kc, "kept_frac": kf,
            "whole": whole, "used": used}


def cmd_check(a):
    meta = json.load(open(_p(tile_meta(a.name))))
    res = check_tile(meta, Image.open(_p(tile_png(a.name))).convert("RGB"), Image.open(a.edit),
                     C.wings())
    print(json.dumps(res))
    sys.exit(0 if res["ok"] else 1)


def cmd_build(a):
    master = Image.open(_p(MASTER)).convert("RGB")
    tiles = load_tiles()
    edits, fps = {}, {}
    for n, t in tiles.items():
        x, y, w, h = t["rect"]
        e = edit_in_canvas(t)
        src = master.crop((x, y, x + w, y + h))
        if t.get("kind", "boarded") == "boarded":
            e = tone_match(src, e)
        else:
            # Tile-wide, so the tone-match ring lies outside the footprint
            # even where the footprint fills the wing's rect.
            fps[n], e = empty_layer(src, e)
        edits[n] = e
    base, restored, report = compose(master, C.wings(), tiles, edits, fps)
    ext = _p(C.BASE + "/exterior")
    base.save(os.path.join(ext, "base.png"))
    for area, im in restored.items():
        im.save(_p(C.exterior_path(area, "restored")))
    for area in sorted(report):
        print(area, report[area])


def cmd_rects(a):
    probs = rect_problems(C.wings())
    print("\n".join(probs) or "OK")
    sys.exit(1 if probs else 0)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crop")
    c.add_argument("name")
    c.add_argument("rect")
    c.add_argument("--kind", choices=["boarded", "empty"], default="boarded")
    c.add_argument("--instr", choices=sorted(INSTR))
    c.add_argument("--areas", help="comma list: the only wings this tile serves")
    m = sub.add_parser("manifest")
    m.add_argument("names", nargs="+")
    m.add_argument("--style-key", action="append", default=[])
    m.add_argument("--instruction")
    m.add_argument("--settle", action="store_true")
    st = sub.add_parser("settle")
    st.add_argument("names", nargs="+")
    k = sub.add_parser("check")
    k.add_argument("name")
    k.add_argument("edit")
    sub.add_parser("build")
    sub.add_parser("rects")
    a = ap.parse_args(argv)
    {"crop": cmd_crop, "manifest": cmd_manifest, "check": cmd_check, "build": cmd_build,
     "rects": cmd_rects, "settle": cmd_settle}[a.cmd](a)


if __name__ == "__main__":
    main()
