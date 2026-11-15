#!/usr/bin/env python3
"""Check Hall element content: no placeholders, distinct names, sane looks."""
import json
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def main():
    with open(os.path.join(ROOT, "config", "curio_hall_elements.json")) as f:
        els = json.load(f)
    bad = 0
    seen = {}
    for e in els:
        n = e["name"]
        if n.startswith("Exhibit ") or not n:
            print("placeholder", e["id"]); bad += 1
        if n.lower() in seen:
            print("duplicate name", n, e["id"], seen[n.lower()]); bad += 1
        seen[n.lower()] = e["id"]
        if len(e["subject"]) < 30:
            print("short subject", e["id"]); bad += 1
        lk = e["looks"]
        if lk[0]["instruction"] is not None or not lk[1]["instruction"] or not lk[2]["instruction"]:
            print("bad instructions", e["id"]); bad += 1
        if len({l["name"].lower() for l in lk}) != 3 or any(l["name"].startswith("Look ") for l in lk):
            print("bad look names", e["id"]); bad += 1
        if len(e["subject"].split()) < 11:
            print("thin subject", e["id"], e["name"]); bad += 1
        for l in lk[1:]:
            if len(l["instruction"].split()) < 15 or l["instruction"].lower().startswith("make it "):
                print("thin look", e["id"], e["name"], "|", l["name"]); bad += 1
        if lk[1]["instruction"] == lk[2]["instruction"]:
            print("same looks", e["id"]); bad += 1
    print("%d elements, %d problems" % (len(els), bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
