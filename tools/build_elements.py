#!/usr/bin/env python3
"""Group MainTaskConfig tasks into Hall elements and generate wing/element configs.

Re-running keeps every field already present in the existing JSON for matching
element ids / wing areas; only missing fields are filled with placeholders.
"""
import json
import math
import os
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
CFG = os.path.join(ROOT, "config")

WING_NAMES = {
    1: "The Front Gates", 2: "The Grand Atrium", 3: "The Cloakroom & Vestibule",
    4: "The Curator's Office", 5: "The Tea Room", 6: "The Hall of Feathers",
    7: "The Butterfly House", 8: "The Conservatory", 9: "The Fossil Gallery",
    10: "The Mineral Vault", 11: "The Shell & Coral Room", 12: "The Aquarium Grotto",
    13: "The Map Room", 14: "The Library of Expeditions", 15: "The Archives",
    16: "The Clockwork Workshop", 17: "The Hall of Instruments", 18: "The Astronomy Dome",
    19: "The Orrery Landing", 20: "The Gaslight Gallery", 21: "The Sculpture Court",
    22: "The Hall of Giants", 23: "The Insectarium", 24: "The Herbarium",
    25: "The Apothecary Annex", 26: "The Gemstone Salon", 27: "The Meteorite Chamber",
    28: "The Cabinet of Whispers", 29: "The Portrait Stair", 30: "The Founders' Gallery",
    31: "The Music Box Parlor", 32: "The Print & Poster Room", 33: "The Model Ship Hall",
    34: "The Balloon Loft", 35: "The Observatory Walk", 36: "The Moonlit Courtyard",
    37: "The Reflecting Pool", 38: "The Glasshouse Menagerie", 39: "The Night Garden",
    40: "The Deep Vaults", 41: "The Forgotten Wing", 42: "The Founder's Study",
    43: "The Hidden Passage", 44: "The Chart Room of Lost Lands", 45: "The Grand Ballroom",
    46: "The Clock Tower", 47: "The Attic of Marvels",
}
SEPARATE = {7, 8, 18, 34, 35, 36, 37, 38, 39, 46}
CANVAS_W, CANVAS_H = 2160, 3240
COLS = 4
SUBROOM_MAX = 40


def load(name):
    path = os.path.join(CFG, name)
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return json.load(f)


def groups(n):
    k = max(1, round(n / 3))
    while math.ceil(n / k) > 4:
        k += 1
    base, extra = divmod(n, k)
    return [base + 1 if i < extra else base for i in range(k)]


def placeholder_pos(i):
    return [90 + 180 * (i % 4), 320 + 260 * (i // 4)]


def subroom_height(count):
    rows = math.ceil(count / 4)
    return max(1280, 320 + rows * 260 + 200)


def main():
    tasks = [r for r in load("MainTaskConfig.json") if r]
    by_day = defaultdict(list)
    for r in tasks:
        by_day[r["day"]].append(r)

    old_elements = {e["id"]: e for e in load("curio_hall_elements.json")}
    old_wings = {w["area"]: w for w in load("curio_hall_wings.json")}

    per_area = defaultdict(list)  # area -> [task-key groups], in day order
    for day in sorted(by_day):
        rows = sorted(by_day[day], key=lambda r: r["id"])
        area = rows[0]["area"]
        i = 0
        for size in groups(len(rows)):
            per_area[area].append(["%d_%d" % (day, r["id"]) for r in rows[i:i + size]])
            i += size

    elements = []
    wings = []
    total_sub = 0
    cw, ch = CANVAS_W // COLS, CANVAS_H // 12
    for area in range(1, 48):
        here = per_area.get(area, [])
        chunks = [here[i:i + SUBROOM_MAX] for i in range(0, len(here), SUBROOM_MAX)] or [[]]
        subrooms = [{"name": "Room %d" % (s + 1), "size": [720, subroom_height(len(c))]}
                    for s, c in enumerate(chunks)]
        total_sub += len(chunks)
        idx = 0
        for s, chunk in enumerate(chunks):
            for j, keys in enumerate(chunk):
                idx += 1
                eid = "%02d_%03d" % (area, idx)
                row = {
                    "id": eid, "area": area, "subroom": s, "name": "Exhibit " + eid,
                    "tasks": keys, "pos": placeholder_pos(j), "subject": "",
                    "looks": [{"name": "Look 1", "instruction": None},
                              {"name": "Look 2", "instruction": ""},
                              {"name": "Look 3", "instruction": ""}],
                    "beat": None,
                }
                # Preserved rows keep their old tasks/subroom (no re-grouping).
                row.update(old_elements.get(eid, {}))
                elements.append(row)

        wing = {
            "area": area, "name": WING_NAMES[area],
            "structure": "separate" if area in SEPARATE else "interior",
            "exterior_rect": [((area - 1) % COLS) * cw, ((area - 1) // COLS) * ch, cw, ch],
            "subrooms": subrooms,
        }
        wing.update(old_wings.get(area, {}))
        wings.append(wing)

    for name, data in (("curio_hall_elements.json", elements), ("curio_hall_wings.json", wings)):
        with open(os.path.join(CFG, name), "w") as f:
            json.dump(data, f, indent=1)
            f.write("\n")
    story = os.path.join(CFG, "curio_hall_story.json")
    if not os.path.exists(story):
        with open(story, "w") as f:
            f.write("[]\n")
    print("elements=%d subrooms=%d" % (len(elements), total_sub))


if __name__ == "__main__":
    main()
