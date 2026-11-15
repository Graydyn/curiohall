#!/usr/bin/env python3
"""Detect hard-edged translucent layers in a rendered screenshot.

usage: check_bands.py PNG... [--min-frac 0.55] [--min-step 8]

A semi-transparent rectangle drawn over a painting shifts every pixel under
its edge by about the same amount, so along that row the luminance step is
the same sign and size across most of the width. Real painted edges (a pool
rim, a hedge line) vary from column to column. For each row y this compares
rows y-2 and y+2 after a horizontal box blur (which removes brush-stroke
texture but keeps a layer edge); a row is flagged when at least MIN_FRAC of
the columns sit within +-TOL of the median step and that median is at least
MIN_STEP. Tuned on the Task 9 screenshots: the WindowGlow box scored 0.60 at a
step of 12; the cleanest painted edges scored at most 0.49.
Exit 1 if any row is flagged.
"""
import argparse
import sys

from PIL import Image

TOL = 3


def luminance_rows(im, blur=6):
    """Rows of luminance, each box-blurred horizontally by +-blur px."""
    g = im.convert("L")
    w, h = g.size
    px = g.load()
    rows = []
    for y in range(h):
        cs = [0]
        for x in range(w):
            cs.append(cs[-1] + px[x, y])
        rows.append([(cs[min(w, x + blur + 1)] - cs[max(0, x - blur)])
                     / float(min(w, x + blur + 1) - max(0, x - blur)) for x in range(w)])
    return rows


def find_bands(im, min_frac=0.55, min_step=8, span=2, step_x=3):
    """Returns [(y, median_step, fraction)] for flagged rows."""
    rows = luminance_rows(im)
    h = len(rows)
    w = len(rows[0]) if h else 0
    out = []
    for y in range(span, h - span):
        a, b = rows[y - span], rows[y + span]
        d = sorted(b[x] - a[x] for x in range(0, w, step_x))
        med = d[len(d) // 2]
        if abs(med) < min_step:
            continue
        near = sum(1 for v in d if abs(v - med) <= TOL)
        frac = near / float(len(d))
        if frac >= min_frac:
            out.append((y, round(med, 1), round(frac, 2)))
    # Collapse runs of adjacent rows (one edge flags ~2*span rows).
    merged = []
    for b in out:
        if merged and b[0] - merged[-1][0] <= 2 * span:
            continue
        merged.append(b)
    return merged


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("png", nargs="+")
    ap.add_argument("--min-frac", type=float, default=0.55)
    ap.add_argument("--min-step", type=int, default=8)
    a = ap.parse_args(argv)
    bad = False
    for p in a.png:
        bands = find_bands(Image.open(p), a.min_frac, a.min_step)
        print("%s: %s" % (p, "OK" if not bands else "BANDS at y=%s" % bands))
        bad = bad or bool(bands)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
