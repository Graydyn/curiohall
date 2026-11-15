"""Shared path rules and config loading for the Hall art tools.

Path rules mirror view/hall_art.gd (base dir assets/map/).
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BASE = "assets/map"
JOBS_PATH = os.path.join(ROOT, BASE, "jobs.json")
FAILED_PATH = os.path.join(ROOT, BASE, "jobs_failed.json")

# `sectilia generate` has no --style (only edit does), so generates carry the
# shared look through --theme.
# Not "gaslamp": the generator took that literally and added an oil lamp to
# almost every subject (elephant, ledger, bust).
STYLE_THEME = ("painted Victorian storybook illustration, soft Ghibli-like light, warm "
               "evening glow, deep teal burgundy cream brass palette, calm and dreamy, "
               "no text or lettering")
STYLE_INSTRUCTION = ("match the style of the reference images; keep the subject, "
                     "framing and viewpoint identical")


def raw_path(rel):
    """Intermediate (style-pass raw, or a scene before fitting):
    assets/map/_raw/<path under assets/map>, so names never collide."""
    sub = rel[len(BASE) + 1:] if rel.startswith(BASE + "/") else os.path.basename(rel)
    return "%s/_raw/%s" % (BASE, sub)

CAST = ["cornelia", "barnaby", "aldous", "sam", "mark", "anjali", "hugo",
        "prudence", "zephyrine", "rosalind", "ambrose"]
EXPRESSIONS = ["neutral", "happy", "surprised", "worried"]
# Ambrose only ever appears neutral (controller ruling): 10*4 + 1 = 41.
EXPR_ONLY = {"ambrose": ["neutral"]}


def load_json(name):
    with open(os.path.join(ROOT, "config", name), encoding="utf-8") as f:
        return json.load(f)


def wings():
    return load_json("curio_hall_wings.json")


def elements():
    return load_json("curio_hall_elements.json")


def story():
    return load_json("curio_hall_story.json")


def parse_areas(text):
    """'1-12' or '1,3,5-7' -> set of ints; empty -> None (all)."""
    if not text:
        return None
    out = set()
    for part in text.split(","):
        part = part.strip()
        if "-" in part:
            a, b = part.split("-", 1)
            out.update(range(int(a), int(b) + 1))
        elif part:
            out.add(int(part))
    return out


def expressions_for(speaker):
    return EXPR_ONLY.get(speaker, EXPRESSIONS)


def exterior_states(wing):
    return ["restored", "boarded"] if wing["structure"] == "interior" else ["restored"]


def exterior_path(area, state):
    return "%s/exterior/wing_%02d_%s.png" % (BASE, area, state)


def scene_path(area, sub):
    return "%s/wings/%02d/scene_%d.png" % (BASE, area, sub)


def element_path(eid, look):
    area = int(eid.split("_")[0])
    return "%s/elements/%02d/%s_%d.png" % (BASE, area, eid, look)


def portrait_path(speaker, expr):
    return "%s/portraits/%s_%s.png" % (BASE, speaker, expr)


def panel_path(scene_id, index):
    return "%s/panels/%s_%d.png" % (BASE, scene_id, index)


def panel_scenes():
    return [s for s in story() if s.get("kind") == "panel"]


def expected_paths(areas=None):
    """Yield (kind, relative path) for every asset the configs imply."""
    for w in wings():
        if areas and w["area"] not in areas:
            continue
        for st in exterior_states(w):
            yield "exterior wings", exterior_path(w["area"], st)
        for i, _ in enumerate(w["subrooms"]):
            yield "wing scenes", scene_path(w["area"], i)
    for e in elements():
        if areas and e["area"] not in areas:
            continue
        for look in range(len(e["looks"])):
            yield "elements", element_path(e["id"], look)
    for sp in CAST:
        for ex in expressions_for(sp):
            yield "portraits", portrait_path(sp, ex)
    for s in panel_scenes():
        for i, _ in enumerate(s.get("panels", [])):
            yield "panels", panel_path(s["id"], i)
