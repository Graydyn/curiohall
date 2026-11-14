#!/usr/bin/env python3
"""List every Hall art file implied by the configs that is missing on disk.

usage: check_art.py [--summary] [--areas 1-12]
Exit 1 when anything is missing. --summary prints counts per kind only.
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

KIND_ORDER = ["exterior wings", "wing scenes", "elements", "portraits", "panels"]


def missing_by_kind(areas=None):
    total, missing = {}, {}
    for kind, rel in C.expected_paths(areas):
        total[kind] = total.get(kind, 0) + 1
        if not os.path.exists(os.path.join(C.ROOT, rel)):
            missing.setdefault(kind, []).append(rel)
    return total, missing


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--summary", action="store_true")
    ap.add_argument("--areas")
    a = ap.parse_args(argv)
    total, missing = missing_by_kind(C.parse_areas(a.areas))
    if a.summary:
        for k in KIND_ORDER:
            print("%-15s missing %5d / %d" % (k, len(missing.get(k, [])), total.get(k, 0)))
    else:
        for k in KIND_ORDER:
            for rel in missing.get(k, []):
                print(rel)
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
