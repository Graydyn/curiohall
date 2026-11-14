#!/usr/bin/env python3
"""Tile the PNGs in a directory (recursively) into one labelled contact sheet.

usage: contact_sheet.py <dir> --out sheet.png [--cols 6] [--cell 256]
"""
import argparse
import os
import sys

from PIL import Image, ImageDraw


def find_pngs(root):
    found = []
    for d, _, files in os.walk(root):
        found += [os.path.join(d, f) for f in files if f.lower().endswith(".png")]
    return sorted(found)


def make_sheet(paths, root, cols=6, cell=256):
    label_h = 28
    rows = max(1, -(-len(paths) // cols))
    sheet = Image.new("RGB", (cols * cell, rows * (cell + label_h)), (40, 40, 48))
    draw = ImageDraw.Draw(sheet)
    for i, p in enumerate(paths):
        x, y = (i % cols) * cell, (i // cols) * (cell + label_h)
        with Image.open(p) as im:
            im = im.convert("RGBA")
            im.thumbnail((cell - 8, cell - 8))
            tile = Image.new("RGBA", (cell, cell), (70, 70, 80, 255))
            tile.alpha_composite(im, ((cell - im.width) // 2, (cell - im.height) // 2))
            sheet.paste(tile.convert("RGB"), (x, y))
        name = os.path.relpath(p, root)
        draw.text((x + 4, y + cell + 2), name[-(cell // 6):], fill=(235, 230, 215))
        draw.text((x + 4, y + cell + 14), "%dx%d" % Image.open(p).size, fill=(160, 160, 170))
    return sheet


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dir")
    ap.add_argument("--out", required=True)
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--cell", type=int, default=256)
    a = ap.parse_args(argv)
    paths = find_pngs(a.dir)
    if not paths:
        print("no PNGs under %s" % a.dir, file=sys.stderr)
        return 1
    make_sheet(paths, a.dir, a.cols, a.cell).save(a.out)
    print("%d images -> %s" % (len(paths), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
