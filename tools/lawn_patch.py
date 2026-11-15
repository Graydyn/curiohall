#!/usr/bin/env python3
"""Paint lawn over areas of a painted backdrop by tiling a clean grass sample.

usage: lawn_patch.py BASE.png --sample X,Y,W,H --poly x1,y1,x2,y2,... [--poly ...]
                     [--feather 14] [--seed 1] [--out OUT.png]

Used for the Hall exterior: the generated grounds came with paved plaza
footprints where wing sprites sit, and the sprites' own lawn bases do not cover
them, so they read as pasted on. Each polygon is filled with the sample tiled
at jittered offsets, blended in through a feathered mask.
"""
import argparse
import random

from PIL import Image, ImageDraw, ImageFilter


def parse_ints(text):
    return [int(v) for v in text.split(",")]


def lawn_fill(size, sample, seed=1):
    """An RGB image of `size` covered by soft-edged stamps of `sample` (random
    positions, random mirror), so no tile seams or blocks show."""
    rnd = random.Random(seed)
    w, h = size
    sw, sh = sample.size
    soft = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(soft).ellipse((sw // 8, sh // 8, sw - sw // 8, sh - sh // 8), fill=255)
    soft = soft.filter(ImageFilter.GaussianBlur(min(sw, sh) // 6))
    flipped = sample.transpose(Image.FLIP_LEFT_RIGHT)
    out = sample.resize((w, h))   # a smeared base so gaps are grass-coloured
    out = out.filter(ImageFilter.GaussianBlur(20))
    n = int(4 * (w * h) / (sw * sh)) + 8
    for _ in range(n):
        x = rnd.randrange(-sw // 2, w)
        y = rnd.randrange(-sh // 2, h)
        out.paste(sample if rnd.random() < 0.5 else flipped, (x, y), soft)
    return out


def patch(base, sample_box, polys, feather=14, seed=1):
    base = base.convert("RGB")
    sample = base.crop((sample_box[0], sample_box[1],
                        sample_box[0] + sample_box[2], sample_box[1] + sample_box[3]))
    mask = Image.new("L", base.size, 0)
    d = ImageDraw.Draw(mask)
    for p in polys:
        d.polygon(list(zip(p[0::2], p[1::2])), fill=255)
    if feather:
        mask = mask.filter(ImageFilter.GaussianBlur(feather))
    box = mask.getbbox()
    if not box:
        return base
    fill = Image.new("RGB", base.size)
    fill.paste(lawn_fill((box[2] - box[0], box[3] - box[1]), sample, seed), box[:2])
    return Image.composite(fill, base, mask)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("base")
    ap.add_argument("--sample", required=True, type=parse_ints)
    ap.add_argument("--poly", action="append", required=True, type=parse_ints)
    ap.add_argument("--feather", type=int, default=14)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    out = patch(Image.open(a.base), a.sample, a.poly, a.feather, a.seed)
    out.save(a.out or a.base)
    print("patched %d polygon(s) -> %s" % (len(a.poly), a.out or a.base))


if __name__ == "__main__":
    main()
