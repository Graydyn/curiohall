"""Prints one line per story day: final element, wing, name, other elements that day."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import story_days as s  # noqa: E402

fin, els, mt = s.day_finals()
W = {w["area"]: w["name"] for w in s.load("curio_hall_wings.json")}
E = {e["id"]: e for e in els}
dayel = {}
for e in els:
    d = int(e["tasks"][0].split("_")[0])
    dayel.setdefault(d, []).append(e["name"])
lo = int(sys.argv[1])
hi = int(sys.argv[2])
for d in range(lo, hi + 1):
    e = E[fin[d]]
    print(d, fin[d], W[e["area"]], "|", e["name"], "|", len(dayel[d]), "el today")
