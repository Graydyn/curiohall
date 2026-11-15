#!/usr/bin/env python3
"""Checks the Hall story scenes. Usage: check_story.py [--through DAY] (default: all days, plus panels)."""
import json
import os
import sys
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import story_days  # noqa: E402

UNLOCK = {"cornelia": 1, "barnaby": 1, "aldous": 12, "sam": 20, "mark": 30, "anjali": 40,
          "hugo": 60, "prudence": 80, "zephyrine": 90, "rosalind": 100}
ARRIVALS = {12: "aldous", 20: "sam", 30: "mark", 40: "anjali", 60: "hugo", 80: "prudence",
            90: "zephyrine", 100: "rosalind"}
MILESTONES = ["20_11", "37_10", "43_11", "47_11", "52_11"]
EXTRA_BEAT_ELEMENTS = {"02_001"}  # welcome beat, not a day beat
MIN_LINES, MAX_LINES = 3, 8
MAX_OPENER_REPEAT = 6  # same first three words opening more than this many beats


def check(through=None):
    fin, els, _mt = story_days.day_finals()
    last_day = max(fin)
    full = through is None
    through = through or last_day
    scenes = story_days.load("curio_hall_story.json")
    problems = []
    ids = Counter(s["id"] for s in scenes)
    problems += ["duplicate scene id %s" % i for i, n in ids.items() if n > 1]
    by_id = {s["id"]: s for s in scenes}
    el_by_id = {e["id"]: e for e in els}

    final_to_day = {v: d for d, v in fin.items()}
    for d in range(1, through + 1):
        e = el_by_id[fin[d]]
        b = by_id.get(e["beat"]) if e["beat"] else None
        if b is None or b["kind"] != "beat":
            problems.append("day %d: final element %s has no beat" % (d, fin[d]))
            continue
        if b["trigger"] != "element:" + fin[d]:
            problems.append("day %d: beat %s trigger %s != element:%s" % (d, b["id"], b["trigger"], fin[d]))
        n = len(b["lines"])
        if not MIN_LINES <= n <= MAX_LINES:
            problems.append("day %d: beat %s has %d lines" % (d, b["id"], n))
        for ln in b["lines"]:
            who = ln["speaker"]
            if who == "ambrose":
                problems.append("day %d: Ambrose speaks" % d)
            elif UNLOCK[who] > d:
                problems.append("day %d: %s speaks before unlock day %d" % (d, who, UNLOCK[who]))
    for e in els:
        if e["beat"] and e["id"] not in final_to_day and e["id"] not in EXTRA_BEAT_ELEMENTS:
            problems.append("element %s has a beat but is not a day's final element" % e["id"])
        if e["beat"] and e["id"] in final_to_day and final_to_day[e["id"]] > through:
            problems.append("element %s has a beat beyond --through" % e["id"])
    beats = [s for s in scenes if s["kind"] == "beat"]
    for s in beats:
        for ln in s["lines"]:
            if ln["speaker"] == "ambrose":
                problems.append("%s: Ambrose speaks" % s["id"])
    lines = Counter(ln["text"] for s in beats for ln in s["lines"])
    problems += ["repeated line: %r" % t for t, n in lines.items() if n > 1]
    openers = Counter(" ".join(ln["text"].split()[:3]).lower() for s in beats for ln in s["lines"][:1])
    problems += ["opener %r used %d times" % (o, n) for o, n in openers.items() if n > MAX_OPENER_REPEAT]

    if full:
        panels = [s for s in scenes if s["kind"] == "panel"]
        for s in panels:
            if not s.get("panels") or not all(p.get("caption", "").strip() for p in s["panels"]):
                problems.append("panel %s: empty or missing captions" % s["id"])
            elif not 1 <= len(s["panels"]) <= 3:
                problems.append("panel %s: %d captions" % (s["id"], len(s["panels"])))
        trig = Counter(s["trigger"] for s in panels)
        for a in range(1, 48):
            if trig["area_opened:%d" % a] != 1:
                problems.append("area_opened:%d panels: %d" % (a, trig["area_opened:%d" % a]))
        for d in ARRIVALS:
            if trig["day:%d" % d] != 1:
                problems.append("day:%d arrival panels: %d" % (d, trig["day:%d" % d]))
        for k in MILESTONES:
            if trig["task:" + k] != 1:
                problems.append("task:%s panels: %d" % (k, trig["task:" + k]))
        caps = Counter(p["caption"] for s in panels for p in s["panels"])
        problems += ["repeated caption: %r" % c[:40] for c, n in caps.items() if n > 1]
    return problems, len(beats), sum(1 for s in scenes if s["kind"] == "panel")


def main():
    through = None
    if "--through" in sys.argv:
        through = int(sys.argv[sys.argv.index("--through") + 1])
    problems, nb, npn = check(through)
    for p in problems:
        print("PROBLEM:", p)
    print("%d beats, %d panels, %d problems" % (nb, npn, len(problems)))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
