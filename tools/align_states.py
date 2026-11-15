#!/usr/bin/env python3
"""Line an edited state sprite up with its source sprite.

usage: align_states.py SOURCE.png STATE.png [STATE.png ...] [--dry-run]

Sectilia edits ("board up the windows") can come back re-framed: the subject
smaller or shifted on the canvas, so swapping restored/boarded in place makes
the building jump. This trims the state's subject to its opaque bounds, scales
it uniformly to fit the source subject's box (width-led), and places it
bottom-centred on the source subject's ground line, on a canvas the size of
the source. The state image is overwritten.
"""
import argparse

from PIL import Image

ALPHA_CUT = 16


def subject_box(im):
    return im.getchannel("A").point(lambda v: 255 if v > ALPHA_CUT else 0).getbbox()


def align(source, state):
    """Returns `state` re-placed on a canvas like `source` (both RGBA)."""
    source, state = source.convert("RGBA"), state.convert("RGBA")
    sb, tb = subject_box(source), subject_box(state)
    if not sb or not tb:
        return state
    subj = state.crop(tb)
    # Fit inside the source subject box, ground lines matched.
    k = min((sb[2] - sb[0]) / float(subj.width), (sb[3] - sb[1]) / float(subj.height))
    subj = subj.resize((max(1, round(subj.width * k)), max(1, round(subj.height * k))),
                       Image.LANCZOS)
    out = Image.new("RGBA", source.size, (0, 0, 0, 0))
    cx = (sb[0] + sb[2]) / 2.0
    out.alpha_composite(subj, (round(cx - subj.width / 2.0), max(0, sb[3] - subj.height)))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("source")
    ap.add_argument("states", nargs="+")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    src = Image.open(a.source)
    for p in a.states:
        before = subject_box(Image.open(p).convert("RGBA"))
        out = align(src, Image.open(p))
        print("%s: %s -> %s (source %s)" % (p, before, subject_box(out), subject_box(src.convert("RGBA"))))
        if not a.dry_run:
            out.save(p)


if __name__ == "__main__":
    main()
