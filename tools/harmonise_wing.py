#!/usr/bin/env python3
"""Blend an exterior wing sprite into the base painting (masked inpainting
built from crop + Sectilia upload + edit).

usage:
  harmonise_wing.py crop AREA [--margin 0.18]
      Composite the wing's restored sprite onto exterior/base.png at its
      exterior_rect, crop the rect plus a margin of grounds, scale to at most
      1024 a side, and write _raw/harmonise/wing_NN_crop.png + .json (crop
      rect in base px, scale, and the sprite's alpha at crop scale).
  harmonise_wing.py manifest AREA... [--style-jobs-from KEY...]
      Print a Sectilia manifest: upload the crop, edit it with the style refs
      into a harmonised painting (keep), edit that into the boarded state.
  harmonise_wing.py paste AREA STATE SRC.png
      Build exterior/wing_NN_<state>.png: SRC resized to the crop rect, alpha
      = a feathered mask (the building fully opaque, fading to 0 at the crop
      edges) so it melts into the base. Prints the new exterior_rect.
  harmonise_wing.py rects AREA...
      Print {area: crop rect} for writing into config.
"""
import argparse
import json
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

MAX_SIDE = 1024
HDIR = C.BASE + "/_raw/harmonise"
INSTR_RESTORED = (
    "blend the building into the surrounding grounds so the whole picture is one coherent "
    "painting: matching soft evening light and colour, a soft contact shadow where it meets "
    "the ground, its base and garden edges settled naturally into the lawn; keep the building, "
    "its shape, position, size, composition and framing identical")
INSTR_BOARDED = (
    "board up the windows and doors with weathered planks and dust sheets, dark unlit windows; "
    "keep everything else identical, same framing")


def _p(rel):
    return os.path.join(C.ROOT, rel)


def wing_row(area):
    return next(w for w in C.wings() if w["area"] == area)


def meta_path(area):
    return "%s/wing_%02d_crop.json" % (HDIR, area)


def crop_path(area):
    return "%s/wing_%02d_crop.png" % (HDIR, area)


def placed_sprite(sprite, rect):
    """The sprite scaled keep-aspect and centred in rect (as ExteriorMap draws
    it). Returns (image, (x, y)) in base px."""
    x, y, w, h = rect
    k = min(w / float(sprite.width), h / float(sprite.height))
    im = sprite.resize((max(1, round(sprite.width * k)), max(1, round(sprite.height * k))),
                       Image.LANCZOS)
    return im, (round(x + (w - im.width) / 2.0), round(y + (h - im.height) / 2.0))


def crop_rect(rect, margin, canvas):
    x, y, w, h = rect
    mx, my = round(w * margin), round(h * margin)
    x0, y0 = max(0, x - mx), max(0, y - my)
    x1, y1 = min(canvas[0], x + w + mx), min(canvas[1], y + h + my)
    return [x0, y0, x1 - x0, y1 - y0]


def make_crop(base, sprite, rect, margin=0.18):
    """Returns (crop RGB at <= MAX_SIDE, sprite alpha at the same scale, meta)."""
    base = base.convert("RGBA")
    im, (sx, sy) = placed_sprite(sprite.convert("RGBA"), rect)
    comp = base.copy()
    comp.alpha_composite(im, (sx, sy))
    alpha = Image.new("L", base.size, 0)
    alpha.paste(im.getchannel("A"), (sx, sy))
    cr = crop_rect(rect, margin, base.size)
    box = (cr[0], cr[1], cr[0] + cr[2], cr[1] + cr[3])
    scale = min(1.0, MAX_SIDE / float(max(cr[2], cr[3])))
    size = (max(1, round(cr[2] * scale)), max(1, round(cr[3] * scale)))
    crop = comp.crop(box).convert("RGB").resize(size, Image.LANCZOS)
    a = alpha.crop(box).resize(size, Image.LANCZOS)
    return crop, a, {"area": None, "crop_rect": cr, "scale": scale, "size": list(size)}


def feather_mask(sprite_alpha, ground=0.16, edge=0.12):
    """Where the harmonised crop replaces the base painting.

    The edit relights the building and adds a contact shadow, but it also
    repaints the far surroundings (sky, fog, smooth lawn) differently from
    the base. So: the building itself, tightly (a 1-2 px grow), plus a soft
    ellipse of ground along its base for the contact shadow, and nothing
    else; always 0 at the crop border."""
    w, h = sprite_alpha.size
    side = min(w, h)
    solid = sprite_alpha.point(lambda v: 255 if v > 24 else 0)
    m = solid.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.5))
    m = ImageChops.lighter(m, sprite_alpha)
    box = solid.getbbox()
    if box:
        bw, bh = box[2] - box[0], box[3] - box[1]
        gh = max(4, int(bh * ground))
        g = Image.new("L", (w, h), 0)
        ImageDraw.Draw(g).ellipse((box[0] - bw * 0.06, box[3] - gh * 1.2,
                                   box[2] + bw * 0.06, box[3] + gh * 0.6), fill=255)
        g = g.filter(ImageFilter.GaussianBlur(max(2.0, gh * 0.45)))
        m = ImageChops.lighter(m, g)
    # Border fade: a box that is opaque inside and ramps to 0 at the edges.
    e = max(2, int(side * edge))
    fade = Image.new("L", (w, h), 0)
    ImageDraw.Draw(fade).rectangle((e, e, w - 1 - e, h - 1 - e), fill=255)
    fade = fade.filter(ImageFilter.GaussianBlur(e / 2.0))
    return ImageChops.multiply(m, fade)


def paste(src, sprite_alpha, out_size=None):
    """RGBA wing sprite: src resized to the crop size, alpha = feather mask."""
    src = src.convert("RGB")
    size = sprite_alpha.size
    if src.size != size:
        # An edit may come back padded (keep fits without upscaling): trim
        # any transparent border first, then stretch to the crop size.
        rgba = src.convert("RGBA")
        src = rgba.crop(rgba.getbbox() or (0, 0) + src.size).convert("RGB").resize(size, Image.LANCZOS)
    out = src.convert("RGBA")
    out.putalpha(feather_mask(sprite_alpha))
    if out_size:
        out = out.resize(out_size, Image.LANCZOS)
    return out


def cmd_crop(a):
    base = Image.open(_p(C.BASE + "/exterior/base.png"))
    for area in a.areas:
        row = wing_row(area)
        # Keep the original sprite: after paste the exterior file is the
        # harmonised crop, so reruns must start from the saved original.
        orig = _p("%s/wing_%02d_sprite_restored.png" % (HDIR, area))
        os.makedirs(_p(HDIR), exist_ok=True)
        if not os.path.exists(orig):
            Image.open(_p(C.exterior_path(area, "restored"))).save(orig)
        sprite = Image.open(orig)
        crop, alpha, meta = make_crop(base, sprite, row["exterior_rect"], a.margin)
        meta["area"] = area
        meta["sprite_rect"] = row["exterior_rect"]
        os.makedirs(_p(HDIR), exist_ok=True)
        crop.save(_p(crop_path(area)))
        alpha.save(_p("%s/wing_%02d_alpha.png" % (HDIR, area)))
        json.dump(meta, open(_p(meta_path(area)), "w"), indent=1)
        print("wing %d: crop %s -> %s" % (area, meta["crop_rect"], meta["size"]))


def keep_spec(size):
    return {"canvas_size": list(size), "style": "painted", "background": {"type": "keep"},
            "anchor": "center", "alpha_threshold": 0, "palette": None, "margin": 0}


def build_manifest(areas, style_keys):
    out = []
    for area in areas:
        meta = json.load(open(_p(meta_path(area))))
        sp = keep_spec(meta["size"])
        src = "harm_%02d_src" % area
        res = "harm_%02d_restored" % area
        out.append({"key": src, "out": "%s/wing_%02d_uploaded.png" % (HDIR, area), "cmd": "upload",
                    "args": {"file": crop_path(area), "spec": sp}, "source_key": None})
        out.append({"key": res, "out": "%s/wing_%02d_restored.png" % (HDIR, area), "cmd": "edit",
                    "args": {"instruction": INSTR_RESTORED, "spec": sp,
                             "style_keys": list(style_keys)}, "source_key": src})
        if wing_row(area)["structure"] == "interior":
            out.append({"key": "harm_%02d_boarded" % area,
                        "out": "%s/wing_%02d_boarded.png" % (HDIR, area), "cmd": "edit",
                        "args": {"instruction": INSTR_BOARDED, "spec": sp}, "source_key": res})
    return out


def cmd_manifest(a):
    json.dump(build_manifest(a.areas, a.style_jobs_from), sys.stdout, indent=1)
    sys.stdout.write("\n")


def cmd_paste(a):
    meta = json.load(open(_p(meta_path(a.area))))
    alpha = Image.open(_p("%s/wing_%02d_alpha.png" % (HDIR, a.area))).convert("L")
    out = paste(Image.open(a.src), alpha)
    dst = _p(C.exterior_path(a.area, a.state))
    out.save(dst)
    print("wing %d %s -> %s rect %s" % (a.area, a.state, C.exterior_path(a.area, a.state),
                                       meta["crop_rect"]))


def cmd_rects(a):
    print(json.dumps({a_: json.load(open(_p(meta_path(a_))))["crop_rect"] for a_ in a.areas}))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    c = sub.add_parser("crop")
    c.add_argument("areas", type=int, nargs="+")
    c.add_argument("--margin", type=float, default=0.18)
    m = sub.add_parser("manifest")
    m.add_argument("areas", type=int, nargs="+")
    m.add_argument("--style-jobs-from", nargs="*", default=[])
    p = sub.add_parser("paste")
    p.add_argument("area", type=int)
    p.add_argument("state", choices=["restored", "boarded"])
    p.add_argument("src")
    r = sub.add_parser("rects")
    r.add_argument("areas", type=int, nargs="+")
    a = ap.parse_args(argv)
    {"crop": cmd_crop, "manifest": cmd_manifest, "paste": cmd_paste, "rects": cmd_rects}[a.cmd](a)


if __name__ == "__main__":
    main()
