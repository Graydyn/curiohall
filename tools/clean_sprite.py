#!/usr/bin/env python3
"""Clean the debris a chroma key leaves around a painted sprite.

usage: clean_sprite.py PNG... [--dry-run] [--crop]

Three passes, in order:
1. Shadow strip. The key removes the flat backdrop but keeps the soft cast
   shadow and vignette the generator paints on it (pale, low-saturation,
   smooth). Flood from the transparent area into pale greyish pixels, and on
   through neighbours that differ only slightly (a smooth gradient), stopping
   at the subject's outline. Those pixels become transparent.
2. Specks. Pixels with alpha below SPECK_ALPHA become fully transparent.
3. Islands. Keep the largest connected opaque component and anything attached
   to it; drop detached components smaller than ISLAND_FRACTION of it (stray
   blobs and specks off to the side). Larger detached parts are kept.

--crop then trims to the opaque bounds (UI frames are nine-sliced, so their art
must reach the texture edges).
"""
import argparse
import colorsys
from collections import deque

from PIL import Image, ImageChops, ImageFilter

SEED_PALE = 0.50     # min lightness for a backdrop/shadow pixel touching the cut
SEED_GREY = 0.30     # max HLS saturation for it
FLOW_PALE = 0.38     # the smooth flood may go a little darker than the seed
FLOW_GREY = 0.30
FLOW_STEP = 14       # max per-channel step between neighbours in the flood
MAX_PALE = 0.84      # brighter than this is the subject's own white (porcelain,
                     # marble highlights), never a painted shadow
EDIT_WHITE = 0.93    # edits are made on a white backdrop: near-pure white in
                     # the ground band is leftover backdrop, not subject
GROUND = 0.55        # shadows only: the lower part of the subject's bounds
                     # (from this fraction of its height down)
SPECK_ALPHA = 24
ISLAND_FRACTION = 0.03
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def _hls(px):
    r, g, b = px[0] / 255.0, px[1] / 255.0, px[2] / 255.0
    return colorsys.rgb_to_hls(r, g, b)


def _near(a, b):
    return abs(a[0] - b[0]) <= FLOW_STEP and abs(a[1] - b[1]) <= FLOW_STEP \
        and abs(a[2] - b[2]) <= FLOW_STEP


def strip_shadow(im, ground_frac=None):
    """Pass 1. Returns number of pixels cleared (in place on an RGBA image).
    Only the lower part of the subject (GROUND) is touched: cast shadows lie on
    the floor, and pale parts higher up are the subject itself."""
    w, h = im.size
    px = im.load()
    box = im.getchannel("A").getbbox()
    if not box:
        return 0
    ground = box[1] + int((box[3] - box[1]) * (GROUND if ground_frac is None else ground_frac))
    seen = bytearray(w * h)
    q = deque()
    for y in range(h):
        for x in range(w):
            if px[x, y][3] == 0:
                seen[y * w + x] = 1
                q.append((x, y))
    cleared = 0
    while q:
        x, y = q.popleft()
        cur = px[x, y]
        for dx, dy in N4:
            nx, ny = x + dx, y + dy
            if not (0 <= nx < w and ground <= ny < h) or seen[ny * w + nx]:
                continue
            p = px[nx, ny]
            _, l, s = _hls(p)
            if l >= 0.97 or (l >= EDIT_WHITE and s <= SEED_GREY):
                ok = True   # HLS saturation is unstable near l=1, so test l alone
            elif cur[3] == 0:
                ok = SEED_PALE <= l <= MAX_PALE and s <= SEED_GREY
            else:
                ok = FLOW_PALE <= l <= MAX_PALE and s <= FLOW_GREY and _near(p, cur)
            if ok:
                seen[ny * w + nx] = 1
                q.append((nx, ny))
                cleared += 1
    if cleared:
        alpha = im.getchannel("A")
        a = alpha.load()
        for y in range(h):
            for x in range(w):
                if seen[y * w + x]:
                    a[x, y] = 0
        # Feather the new cut: min with a slight blur only lowers edge pixels.
        im.putalpha(ImageChops.darker(alpha, alpha.filter(ImageFilter.GaussianBlur(0.7))))
    return cleared


WHITE_POOL = 0.88    # enclosed white pools (backdrop trapped between legs)
WHITE_POOL_MIN = 200  # px; smaller white areas are highlights, kept


def strip_white_pools(im):
    """Pass 1b. Large near-white low-saturation pools in the ground band that
    the flood cannot reach (enclosed by the subject) become transparent."""
    w, h = im.size
    px = im.load()
    box = im.getchannel("A").getbbox()
    if not box:
        return 0
    ground = box[1] + int((box[3] - box[1]) * GROUND)
    seen = bytearray(w * h)
    hit = []

    def white(p):
        _, l, s = _hls(p)
        return p[3] > 0 and (l >= 0.97 or (l >= WHITE_POOL and s <= SEED_GREY))

    for y in range(ground, h):
        for x in range(w):
            if seen[y * w + x] or not white(px[x, y]):
                continue
            comp = [(x, y)]
            seen[y * w + x] = 1
            i = 0
            while i < len(comp):
                cx, cy = comp[i]
                i += 1
                for dx, dy in N4:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and ground <= ny < h and not seen[ny * w + nx] \
                            and white(px[nx, ny]):
                        seen[ny * w + nx] = 1
                        comp.append((nx, ny))
            if len(comp) >= WHITE_POOL_MIN:
                hit.extend(comp)
    if hit:
        alpha = im.getchannel("A")
        a = alpha.load()
        for x, y in hit:
            a[x, y] = 0
        im.putalpha(ImageChops.darker(alpha, alpha.filter(ImageFilter.GaussianBlur(0.7))))
    return len(hit)


def drop_specks_and_islands(im):
    """Passes 2 and 3. Returns number of pixels cleared (in place)."""
    w, h = im.size
    alpha = im.getchannel("A")
    a = alpha.load()
    cleared = 0
    for y in range(h):
        for x in range(w):
            if 0 < a[x, y] < SPECK_ALPHA:
                a[x, y] = 0
                cleared += 1
    label = [0] * (w * h)
    sizes = [0]
    for y in range(h):
        for x in range(w):
            if a[x, y] == 0 or label[y * w + x]:
                continue
            n = len(sizes)
            label[y * w + x] = n
            q = deque([(x, y)])
            size = 0
            while q:
                cx, cy = q.popleft()
                size += 1
                for dx, dy in N8:
                    nx, ny = cx + dx, cy + dy
                    if 0 <= nx < w and 0 <= ny < h and a[nx, ny] and not label[ny * w + nx]:
                        label[ny * w + nx] = n
                        q.append((nx, ny))
            sizes.append(size)
    if len(sizes) > 2:
        biggest = max(sizes)
        drop = {i for i, s in enumerate(sizes) if i and s < biggest * ISLAND_FRACTION}
        if drop:
            for y in range(h):
                for x in range(w):
                    if label[y * w + x] in drop:
                        a[x, y] = 0
                        cleared += 1
    im.putalpha(alpha)
    return cleared


def clean(im, shadow=True, pools=False, ground=None):
    """Returns (cleaned RGBA image, number of pixels cleared)."""
    im = im.convert("RGBA")
    n = strip_shadow(im, ground) if shadow else 0
    if pools:
        n += strip_white_pools(im)
    n += drop_specks_and_islands(im)
    return im, n


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("png", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--crop", action="store_true", help="trim to the opaque bounds")
    ap.add_argument("--no-shadow", action="store_true",
                    help="skip the shadow strip (pale subjects: porcelain, stone, cane)")
    ap.add_argument("--ground", type=float, default=None,
                    help="fraction of the subject height where the shadow band starts "
                         "(default %.2f; higher = only the very bottom)" % GROUND)
    ap.add_argument("--white-pools", action="store_true",
                    help="also clear enclosed white backdrop pools (opt in: eats white marble)")
    a = ap.parse_args(argv)
    for p in a.png:
        im, n = clean(Image.open(p), shadow=not a.no_shadow, pools=a.white_pools,
                      ground=a.ground)
        box = im.getchannel("A").point(lambda v: 255 if v > 16 else 0).getbbox() if a.crop else None
        if box and box != (0, 0) + im.size:
            im = im.crop(box)
            n += 1
        print("%s: cleared %d px%s" % (p, n, " cropped to %s" % (box,) if box else ""))
        if not a.dry_run and n:
            im.save(p)


if __name__ == "__main__":
    main()
