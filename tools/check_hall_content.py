#!/usr/bin/env python3
"""Check Hall element content: no placeholders, distinct names, varied looks, isolated subjects."""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

MAX_LOOK_NAME_USES = 3
SUFFIX = ", keep the same object, framing, viewpoint and lighting"
MIN_SUBJECT_WORDS = 14
MIN_AREA_SUBJECT_MEAN = 17.0
MIN_LOOK_BODY_WORDS = 10  # edit text before the shared suffix
MAX_METAL_LOOK_SHARE = 0.15
METAL_WORD = re.compile(r"gild|gold|silver", re.I)  # of looks 1-2 outside area 2
METAL = re.compile(r"\b(gild\w*|gold\w*|gilt|silver\w*|bronze\w*)\b", re.I)
# A scene word means the subject describes a place or backdrop instead of one object.
SCENE = re.compile(
    r"\b(corner of|in a corner|in the corner|surrounded|surrounding|background|beyond|behind|scene|street|landscape|"
    r"mural|skylight|ceiling|horizon|village|valley|forest|shore|in front of|courtyard|"
    r"(by|at|beside|through|near|under) (a|the) (window|door|fire|hearth|wall|stair|staircase)|"
    # placement phrases: the object must stand alone, not in a setting
    r"at the (foot|bottom|top|end|edge|base) of|in the corner|beside (a|an|the)|next to|against (a|the) \w+|"
    r"on (a|the) (floor|wall|ground|ceiling)|set (in|into) (a|the) \w+( \w+)? (floor|wall)|set into the|"
    r"under (a|an|the) (arch|roof|canopy|tree|sky|dome)|leaning (on|against)|"
    r"(hung|hanging) (on|from) (a|the) (wall|ceiling|rafter|beam)|"
    r"(in|on|at) (a|the) (garden|courtyard|terrace|lawn|landing)|(in|inside) (a|the) (room|hall|cave)|"
    # floor, ground, grass
    r"(on|onto|in|into|across|over|along) (a|an|the) ([\w'-]+ ){0,2}(floor|ground|grass|lawn|paving)|"
    # table, desk, shelf and similar surfaces
    r"(on|onto|upon) (a|an|the) ([\w'-]+ ){0,2}(table|desk|shelf|bench|counter|ledge|windowsill)|"
    # corner, alcove, niche, arch
    r"(in|into|within) (a|an|the) ([\w'-]+ ){0,2}(corner|alcove|nook|niche|recess|arch|archway|doorway)|"
    r"(wall|room|shadowy|quiet) corner|"
    # water and edges
    r"(by|near|beside|at|along) (a|the) ([\w'-]+ ){0,2}(water|pool|pond|bank|shore|water's edge|pool's edge)|"
    r"water's edge|pool's edge|"
    # stairs and architecture
    r"(up|down|on|at|along|above|below|beneath) (a|an|the) ([\w'-]+ ){0,2}(stair|stairs|staircase|stairwell|landing|rooftops)|"
    # companion objects placed next to the subject
    r"beside it|beside them|next to it|alongside|nearby)\b", re.I)
SCENE_ALLOWED = {}  # element id -> reason, for deliberate exceptions
PEOPLE = re.compile(r"\b(person|persons|people|man|men|woman|women|child|children|boy|girl|human|humans|lady|ladies|gentleman|gentlemen|crowd)\b", re.I)


def body(instruction):
    return instruction[:-len(SUFFIX)] if instruction.endswith(SUFFIX) else instruction


def is_metal_look(look):
    """True when the look is mainly a gold/silver/bronze-style metal swap."""
    head = " ".join(body(look["instruction"]).split()[:6])
    return bool(METAL.search(look["name"]) or METAL.search(head))


def check(els):
    """Returns (problems, stats)."""
    problems = []
    seen = {}
    names = {}
    instrs = set()
    metal_looks = 0
    swap_elements = 0
    scene_subjects = 0
    thin_looks = 0
    thin_subjects = 0
    area_words = {}
    other_looks = 0
    for e in els:
        eid = e["id"]
        n = e["name"]
        if n.startswith("Exhibit ") or not n:
            problems.append("placeholder %s" % eid)
        if n.lower() in seen:
            problems.append("duplicate name %s %s %s" % (n, eid, seen[n.lower()]))
        seen[n.lower()] = eid
        lk = e["looks"]
        if lk[0]["instruction"] is not None or not lk[1]["instruction"] or not lk[2]["instruction"]:
            problems.append("bad instructions %s" % eid)
            continue
        if len({l["name"].lower() for l in lk}) != 3 or any(l["name"].startswith("Look ") for l in lk):
            problems.append("bad look names %s" % eid)
        if lk[1]["instruction"] == lk[2]["instruction"]:
            problems.append("same looks %s" % eid)
        for l in lk:
            names.setdefault(l["name"].lower(), []).append(eid)
            if l["instruction"]:
                instrs.add(l["instruction"])
        if e["area"] != 2 and PEOPLE.search(e["subject"]):
            problems.append("people word in subject %s %s" % (eid, e["name"]))
        if e["area"] == 2:
            continue
        words = len(e["subject"].split())
        area_words.setdefault(e["area"], []).append(words)
        if words < MIN_SUBJECT_WORDS:
            thin_subjects += 1
            problems.append("thin subject %s %s (%d words)" % (eid, e["name"], words))
        if SCENE.search(e["subject"]) and eid not in SCENE_ALLOWED:
            scene_subjects += 1
            problems.append("scene word in subject %s %s: %s" % (eid, e["name"], SCENE.search(e["subject"]).group(0)))
        flags = []
        for l in lk[1:]:
            other_looks += 1
            if len(body(l["instruction"]).split()) < MIN_LOOK_BODY_WORDS or l["instruction"].lower().startswith("make it "):
                thin_looks += 1
                problems.append("thin look %s %s | %s" % (eid, e["name"], l["name"]))
            flags.append(is_metal_look(l))
        if all(METAL_WORD.search(body(l["instruction"])) for l in lk[1:]):
            problems.append("both looks mention gold or silver %s %s" % (eid, e["name"]))
        metal_looks += sum(flags)
        if all(flags):
            swap_elements += 1
            problems.append("both looks are metal swaps %s %s" % (eid, e["name"]))
    by_instr = {}
    for e in els:
        for l in e["looks"][1:]:
            by_instr.setdefault(l["instruction"], []).append(e["id"])
    for text, ids in by_instr.items():
        if len(ids) > 1:
            problems.append("identical look instruction on %s" % ids)
    for n, ids in sorted(names.items()):
        if len(ids) > MAX_LOOK_NAME_USES:
            problems.append("look name used %d times: %s %s" % (len(ids), n, ids[:6]))
    share = metal_looks / max(1, other_looks)
    if share > MAX_METAL_LOOK_SHARE:
        problems.append("metal-swap looks %.1f%% exceed cap %.0f%%" % (share * 100, MAX_METAL_LOOK_SHARE * 100))
    for a, ws in sorted(area_words.items()):
        mean = sum(ws) / len(ws)
        if mean < MIN_AREA_SUBJECT_MEAN:
            problems.append("area %d mean subject length %.1f below %.0f" % (a, mean, MIN_AREA_SUBJECT_MEAN))
    stats = {
        "elements": len(els),
        "distinct_look_names": len(names),
        "distinct_instructions": len(instrs),
        "metal_looks": metal_looks,
        "metal_share": share,
        "both_metal_elements": swap_elements,
        "scene_subjects": scene_subjects,
        "thin_looks": thin_looks,
        "thin_subjects": thin_subjects,
        "area_subject_means": {a: sum(w) / len(w) for a, w in area_words.items()},
    }
    return problems, stats


def main():
    with open(os.path.join(ROOT, "config", "curio_hall_elements.json")) as f:
        els = json.load(f)
    problems, stats = check(els)
    for p in problems:
        print(p)
    means = stats.pop("area_subject_means")
    print(stats)
    print("lowest area subject means:", sorted(("%.1f" % m, a) for a, m in means.items())[:4])
    print("%d elements, %d problems" % (len(els), len(problems)))
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
