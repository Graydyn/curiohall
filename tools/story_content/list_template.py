"""Lists day beats whose first line uses the "The <element name>." opening template."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import check_story  # noqa: E402
import story_days  # noqa: E402

fin, els, _mt = story_days.day_finals()
E = {e["id"]: e for e in els}
by_trig = {s["trigger"]: s for s in story_days.load("curio_hall_story.json") if s["kind"] == "beat"}
for d in sorted(fin):
    e = E[fin[d]]
    b = by_trig["element:" + fin[d]]
    first = b["lines"][0]
    if check_story.is_template_opening(first["text"], e["name"]):
        print(d, first["speaker"][:2], len(b["lines"]), e["name"], "|", b["lines"][1]["speaker"][:2], b["lines"][1]["text"][:50])
