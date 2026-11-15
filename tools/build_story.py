#!/usr/bin/env python3
"""Builds config/curio_hall_story.json from tools/story_content/*.txt and sets element beat fields.

Beat blocks:   "== <day>" then lines "<speaker code> <expr code> <text>".
Panel blocks:  "=P <id> <trigger> [cast codes...]" then lines "> caption".
The three hand-written Task 9 scenes are kept as they are in the existing json.
"""
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import story_days  # noqa: E402

ROOT = story_days.ROOT
BASE_IDS = ["atrium_opened", "beat_umbrella_elephant", "beat_expedition_globe"]
SPEAKERS = {
    "c": "cornelia", "b": "barnaby", "a": "aldous", "s": "sam", "m": "mark",
    "j": "anjali", "h": "hugo", "p": "prudence", "z": "zephyrine", "r": "rosalind",
}
EXPRS = {"n": "neutral", "h": "happy", "s": "surprised", "w": "worried"}


def beat_id(day):
    return "beat_d%03d" % day


def parse(path):
    """Returns (beats {day: lines}, panels [dict])."""
    beats, panels = {}, []
    cur = None
    with open(path, encoding="utf-8") as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line.strip() or line.startswith("#"):
                continue
            if line.startswith("=P "):
                parts = line.split()
                cur = {"id": parts[1], "kind": "panel", "trigger": parts[2], "panels": []}
                if len(parts) > 3:
                    cur["cast"] = [SPEAKERS[c] for c in parts[3:]]
                panels.append(cur)
            elif line.startswith("== "):
                day = int(line[3:])
                if day in beats:
                    raise ValueError("%s:%d duplicate day %d" % (path, n, day))
                cur = beats[day] = []
            elif line.startswith("> "):
                cur["panels"].append({"caption": line[2:].strip()})
            else:
                sp, ex, text = line.split(" ", 2)
                cur.append({"speaker": SPEAKERS[sp], "expr": EXPRS[ex], "text": text.strip()})
    return beats, panels


def main():
    beats, panels = {}, []
    for path in sorted(glob.glob(os.path.join(ROOT, "tools", "story_content", "*.txt"))):
        b, p = parse(path)
        for d in b:
            if d in beats:
                raise ValueError("day %d in more than one file" % d)
        beats.update(b)
        panels.extend(p)
    fin, els, _mt = story_days.day_finals()
    story_path = os.path.join(ROOT, "config", "curio_hall_story.json")
    with open(story_path, encoding="utf-8") as f:
        existing = {s["id"]: s for s in json.load(f)}
    scenes = [existing[i] for i in BASE_IDS]
    existing_beat_el = {s["trigger"].split(":", 1)[1] for s in scenes if s["kind"] == "beat"}
    el_beat = {}
    for day in sorted(beats):
        eid = fin[day]
        if eid in existing_beat_el:
            raise ValueError("day %d final element %s already has a hand-written beat" % (day, eid))
        scenes.append({"id": beat_id(day), "kind": "beat", "trigger": "element:" + eid, "lines": beats[day]})
        el_beat[eid] = beat_id(day)
    scenes.extend(panels)
    with open(story_path, "w", encoding="utf-8") as f:
        json.dump(scenes, f, indent=1, ensure_ascii=False)
        f.write("\n")
    el_path = os.path.join(ROOT, "config", "curio_hall_elements.json")
    for e in els:
        if e["id"] in el_beat:
            e["beat"] = el_beat[e["id"]]
    with open(el_path, "w", encoding="utf-8") as f:
        json.dump(els, f, indent=1, ensure_ascii=False)
        f.write("\n")
    print("beats %d, panels %d" % (len(beats), len(panels)))


if __name__ == "__main__":
    main()
