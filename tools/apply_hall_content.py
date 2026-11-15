#!/usr/bin/env python3
"""Merge the authored Hall content in tools/hall_content/areaNN.txt into the configs.

Each areaNN.txt holds an optional `@subrooms A; B; C` line, then one line per
element in id order:

    name | subject | look 0 name | look 1 name | look 1 change | look 2 name | look 2 change

Look instructions are edit prompts; the shared suffix below is appended here.
Only name, subject and looks (and wing subroom names) are written; every other
field keeps its value and the files keep their formatting.
Usage: apply_hall_content.py [area ...]   (default: every area file present)
"""
import glob
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CFG = os.path.join(ROOT, "config")
DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hall_content")
SUFFIX = ", keep the same object, framing, viewpoint and lighting"


def dump(path, obj):
    with open(path, "w") as f:
        f.write(json.dumps(obj, indent=1) + "\n")


def main():
    wanted = {int(a) for a in sys.argv[1:]}
    with open(os.path.join(CFG, "curio_hall_elements.json")) as f:
        elements = json.load(f)
    with open(os.path.join(CFG, "curio_hall_wings.json")) as f:
        wings = json.load(f)
    by_area = {}
    for el in elements:
        by_area.setdefault(el["area"], []).append(el)
    wing_by_area = {w["area"]: w for w in wings}
    parts_by_area = {}
    for path in sorted(glob.glob(os.path.join(DATA, "area*.txt"))):
        # areaNN.txt, or areaNNa.txt / areaNNb.txt ... for long wings (read in order)
        parts_by_area.setdefault(int(os.path.basename(path)[4:6]), []).append(path)
    for area, paths in sorted(parts_by_area.items()):
        if wanted and area not in wanted:
            continue
        rows = []
        for path in paths:
            read_part(path, area, wing_by_area, rows)
        els = by_area[area]
        assert len(rows) == len(els), "area %d: %d rows for %d elements" % (area, len(rows), len(els))
        for el, p in zip(els, rows):
            el["name"] = p[0]
            el["subject"] = p[1]
            el["looks"] = [
                {"name": p[2], "instruction": None},
                {"name": p[3], "instruction": p[4] + SUFFIX},
                {"name": p[5], "instruction": p[6] + SUFFIX},
            ]
    dump(os.path.join(CFG, "curio_hall_elements.json"), elements)
    dump(os.path.join(CFG, "curio_hall_wings.json"), wings)


def read_part(path, area, wing_by_area, rows):
    with open(path) as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("@subrooms"):
                names = [n.strip() for n in line[len("@subrooms"):].split(";")]
                subs = wing_by_area[area]["subrooms"]
                assert len(names) == len(subs), "area %d subroom count" % area
                for sub, n in zip(subs, names):
                    sub["name"] = n
                continue
            parts = [p.strip() for p in line.split("|")]
            assert len(parts) == 7, "area %d bad line: %s" % (area, line[:60])
            rows.append(parts)


if __name__ == "__main__":
    main()
