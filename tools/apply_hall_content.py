#!/usr/bin/env python3
"""Merge the authored Hall content in tools/hall_content/areaNN.txt into the configs.

Each areaNN.txt holds an optional `@subrooms A; B; C` line, then one line per
element in id order:

    name | subject | look 0 name | look 1 name | look 1 change | look 2 name | look 2 change
    name | subject | look 0 name | noun | preset | preset      (compact; presets in PRESETS)

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
# Shared edit treatments for compact rows: key -> (look name, instruction with {n} for the noun).
PRESETS = {
    "gilded": ("Gilded", "make the {n} burnished gold with fine engraved flourishes and small ruby accents"),
    "silvered": ("Silvered", "make the {n} polished silver with delicate engraving and pale blue enamel accents"),
    "bronze": ("Bronze", "recast the {n} in dark patinated bronze with warm golden highlights on a black marble base"),
    "verdigris": ("Verdigris", "make the {n} green-patinated copper with weathered verdigris streaks and bright brass edges"),
    "crystal": ("Cut crystal", "make the {n} clear cut crystal that sparkles and throws tiny rainbows"),
    "frosted": ("Frosted glass", "make the {n} frosted white glass lit softly from within"),
    "amber": ("Amber glow", "make the {n} translucent honey-amber glass glowing warmly from inside"),
    "jade": ("Jade", "make the {n} carved green jade with silver fittings and a pale cream base"),
    "marble": ("Marble", "make the {n} cream marble veined in grey with fine gilt edging"),
    "onyx": ("Black onyx", "make the {n} polished black onyx with thin gold veins and brass feet"),
    "porcelain": ("Willow china", "make the {n} glazed white porcelain painted with blue willow and floral patterns"),
    "teal": ("Teal lacquer", "paint the {n} glossy deep teal lacquer with gilded trim and cream accents"),
    "burgundy": ("Burgundy lacquer", "paint the {n} glossy burgundy lacquer with brass trim and cream accents"),
    "midnight": ("Starry night", "make the {n} deep midnight blue scattered with tiny gilt stars and a crescent moon"),
    "rosewood": ("Rosewood", "make the {n} dark polished rosewood with inlaid brass stringing"),
    "ash": ("Pale ash", "make the {n} pale blond ash wood with neat brass fittings"),
    "ebony": ("Ebony and pearl", "make the {n} black ebony with gilded carving and mother-of-pearl inlay"),
    "enamel": ("Jewel enamel", "make the {n} glazed in jewel-coloured enamel in teal, burgundy and cream"),
    "copper": ("Hammered copper", "make the {n} hammered warm copper with visible rivets and a soft shine"),
    "pearl": ("Mother-of-pearl", "make the {n} lustrous mother-of-pearl with a pink and green rainbow sheen"),
    "ivory": ("Scrimshaw", "make the {n} cream bone engraved with fine dark scrollwork"),
    "velvet": ("Velvet", "make the {n} covered in plush burgundy velvet with gold tassels and braid"),
    "glow": ("Lamplit", "make the {n} glow from within with warm gaslight amber and soft rays"),
    "mosaic": ("Mosaic", "make the {n} covered in tiny glass mosaic tiles in teal, gold and cream"),
    "ruby": ("Ruby red", "make the {n} deep ruby red glass with gold bands"),
    "sapphire": ("Sapphire", "make the {n} deep sapphire blue glass with silver bands"),
    "emerald": ("Emerald", "make the {n} rich emerald green glass with brass bands"),
    "frost": ("Frosted", "make the {n} dusted with white frost and icicles with a pale blue glow"),
    "mossy": ("Overgrown", "make the {n} overgrown with green moss, tiny ferns and trailing ivy"),
    "tartan": ("Tartan", "make the {n} covered in teal and burgundy tartan wool with leather trim"),
    "brass": ("Polished brass", "make the {n} bright polished brass with rivets and a warm shine"),
    "iron": ("Wrought iron", "make the {n} black wrought iron with curling scrollwork and gold-tipped finials"),
    "wicker": ("Woven cane", "make the {n} woven from pale cane and wicker with cream cushions"),
    "stone": ("Carved stone", "make the {n} carved grey stone with soft moss in the cracks"),
    "paper": ("Paper craft", "make the {n} folded from cream paper and thin card with painted details"),
    "clockwork": ("Clockwork", "make the {n} a brass clockwork automaton with visible gears and a wind-up key"),
    "chintz": ("Chintz", "make the {n} covered in cream chintz with large pink cabbage roses"),
}
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
            if len(parts) == 6:
                # compact row: name | subject | look 0 name | noun | preset | preset
                n, a, b = parts[3], PRESETS[parts[4]], PRESETS[parts[5]]
                parts = [parts[0], parts[1], parts[2],
                         a[0], a[1].format(n=n), b[0], b[1].format(n=n)]
            assert len(parts) == 7, "area %d bad line: %s" % (area, line[:60])
            rows.append(parts)


if __name__ == "__main__":
    main()
