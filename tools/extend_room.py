#!/usr/bin/env python3
"""Extend a 720x1280 wing scene downward into one tall room (720xH).

usage: extend_room.py SRC OUT HEIGHT [--strip-top 760] [--fade 200] [--vary]

The room's far wall stays at the top. Below the source, its own near-floor band
(rows strip_top..bottom: floor plus the side walls) is repeated down to HEIGHT,
every other copy mirrored left-right so repeats are less obvious, each one
feathered over the one above it with a linear vertical fade. The result reads as
one long hall seen from above, in exactly the room's own paint, palette and
light, with open floor running the full height.

`vary` (chunk 3) breaks up the period: each copy starts its band at a different
row below strip_top (VARY_OFFSETS) and only some copies are mirrored
(VARY_MIRROR), so neither the seams nor the floor pattern repeat at a fixed
interval and the copies do not zigzag left-right.

Sectilia `background` was tried first for a 720x2880 room: its agent stacked
separate floor sections with marble bands between them (not one room).
"""
import argparse

from PIL import Image


def fade_mask(width, height, fade):
    """L mask: 0 at the top row rising linearly to 255 at row `fade`, then 255."""
    m = Image.new("L", (width, height), 255)
    for r in range(min(fade, height)):
        m.paste(int(255 * r / fade), (0, r, width, r + 1))
    return m


# Band-start offsets (fractions of the strip) and mirror flags, cycled per copy.
VARY_OFFSETS = [0.0, 0.27, 0.12, 0.38, 0.19, 0.05, 0.32]
VARY_MIRROR = [False, False, True, False, False, True, False]


def bands(strip_h, vary):
    """Yield (offset into the strip, mirrored) for copy 0, 1, 2, ..."""
    k = 0
    while True:
        if vary:
            yield (int(strip_h * VARY_OFFSETS[k % len(VARY_OFFSETS)]),
                   VARY_MIRROR[k % len(VARY_MIRROR)])
        else:
            yield 0, k % 2 == 1
        k += 1


def extend(im, height, strip_top=760, fade=200, vary=False):
    im = im.convert("RGB")
    w, h0 = im.size
    if height <= h0:
        return im.crop((0, 0, w, height))
    if not 0 < fade < h0 - strip_top:
        raise ValueError("fade must be smaller than the strip")
    strip = im.crop((0, strip_top, w, h0))
    out = Image.new("RGB", (w, height))
    out.paste(im, (0, 0))
    y = h0
    for off, mirrored in bands(strip.height, vary):
        if y >= height:
            break
        s = strip.crop((0, off, w, strip.height))
        if mirrored:
            s = s.transpose(Image.FLIP_LEFT_RIGHT)
        f = min(fade, s.height // 2)
        top = y - f
        out.paste(s, (0, top), fade_mask(w, s.height, f))
        y = top + s.height
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("height", type=int)
    ap.add_argument("--strip-top", type=int, default=760)
    ap.add_argument("--fade", type=int, default=200)
    ap.add_argument("--vary", action="store_true", help="vary band starts, mirror less often")
    a = ap.parse_args(argv)
    extend(Image.open(a.src), a.height, a.strip_top, a.fade, a.vary).save(a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
