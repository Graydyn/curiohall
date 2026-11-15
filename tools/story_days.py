"""Maps each story day to its final element (the one that carries the day's beat)."""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def load(name):
    with open(os.path.join(ROOT, "config", name)) as f:
        return json.load(f)


def day_finals():
    """Returns ({day: final element id}, elements, main tasks)."""
    els = load("curio_hall_elements.json")
    mt = load("MainTaskConfig.json")
    last = {}
    for t in mt:
        last[t["day"]] = max(last.get(t["day"], 0), t["id"])
    by_key = {k: e for e in els for k in e["tasks"]}
    return {d: by_key["%d_%d" % (d, i)]["id"] for d, i in last.items()}, els, mt


if __name__ == "__main__":
    fin, els, mt = day_finals()
    print(len(els), len(mt), len(fin), len(set(fin.values())), max(fin))
    print([d for d in fin if fin[d] in ("02_001", "02_016")])
    print([(d, fin[d]) for d in range(1, 8)])
    print(sum(1 for e in els if e["beat"]))
