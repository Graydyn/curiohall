#!/usr/bin/env python3
"""Strip the pale backdrop shadow a chroma key leaves under a painted sprite.

usage: clean_sprite.py PNG... [--dry-run] [--crop]

--crop also trims the image to its opaque bounds (UI frames are nine-sliced,
so their art must reach the texture edges).

A sampled chroma key removes the flat backdrop but keeps the soft grey cast
shadow the generator paints on it, which reads as a pale blob on the wing
floor. This flood-fills from the transparent area into connected pixels that
are pale and nearly grey (the backdrop family), making them transparent, and
softens the new edge. The subject itself (saturated or dark) is untouched.
"""
import argparse
import colorsys
from collections import deque

from PIL import Image, ImageChops, ImageFilter

PALE = 0.55      # min lightness (0..1) for backdrop-family pixels
GREY = 0.16      # max HLS saturation


def is_backdrop(px):
    r, g, b, a = px
    if a == 0:
        return True
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    return l >= PALE and s <= GREY


def clean(im):
    """Returns (cleaned RGBA image, number of pixels cleared)."""
    im = im.convert("RGBA")
    w, h = im.size
    px = im.load()
    seen = bytearray(w * h)
    q = deque((x, y) for y in range(h) for x in range(w) if px[x, y][3] == 0)
    for x, y in q:
        seen[y * w + x] = 1
    cleared = []
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and not seen[ny * w + nx]:
                seen[ny * w + nx] = 1
                if is_backdrop(px[nx, ny]):
                    cleared.append((nx, ny))
                    q.append((nx, ny))
    alpha = im.getchannel("A")
    a = alpha.load()
    for x, y in cleared:
        a[x, y] = 0
    if cleared:
        # Feather the new cut: min with a slight blur only lowers edge pixels.
        alpha = ImageChops.darker(alpha, alpha.filter(ImageFilter.GaussianBlur(0.7)))
        im.putalpha(alpha)
    return im, len(cleared)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("png", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--crop", action="store_true", help="trim to the opaque bounds")
    a = ap.parse_args(argv)
    for p in a.png:
        im, n = clean(Image.open(p))
        box = im.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox() if a.crop else None
        if box and box != (0, 0) + im.size:
            im = im.crop(box)
            n += 1
        print("%s: cleared %d px%s" % (p, n, " cropped to %s" % (box,) if box else ""))
        if not a.dry_run and n:
            im.save(p)


if __name__ == "__main__":
    main()
