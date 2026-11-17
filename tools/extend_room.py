#!/usr/bin/env python3
"""Extend a 720x1280 wing scene downward into one tall room (720xH).

usage: extend_room.py SRC OUT HEIGHT [--strip-top 760] [--fade 200]

The room's far wall stays at the top. Below the source, its own near-floor band
(rows strip_top..bottom: floor plus the side walls) is repeated down to HEIGHT,
every other copy mirrored left-right so repeats are less obvious, each one
feathered over the one above it with a linear vertical fade. The result reads as
one long hall seen from above, in exactly the room's own paint, palette and
light, with open floor running the full height.

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


def extend(im, height, strip_top=760, fade=200):
    im = im.convert("RGB")
    w, h0 = im.size
    if height <= h0:
        return im.crop((0, 0, w, height))
    if not 0 < fade < h0 - strip_top:
        raise ValueError("fade must be smaller than the strip")
    strip = im.crop((0, strip_top, w, h0))
    out = Image.new("RGB", (w, height))
    out.paste(im, (0, 0))
    mask = fade_mask(w, strip.height, fade)
    y, k = h0, 0
    while y < height:
        s = strip.transpose(Image.FLIP_LEFT_RIGHT) if k % 2 else strip
        top = y - fade
        out.paste(s, (0, top), mask)
        y = top + s.height
        k += 1
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("height", type=int)
    ap.add_argument("--strip-top", type=int, default=760)
    ap.add_argument("--fade", type=int, default=200)
    a = ap.parse_args(argv)
    extend(Image.open(a.src), a.height, a.strip_top, a.fade).save(a.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
