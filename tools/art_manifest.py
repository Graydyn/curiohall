#!/usr/bin/env python3
"""Build a Sectilia job manifest (JSON on stdout) for one kind of Hall art.

usage: art_manifest.py <kind> [--areas 1-12] [--style-jobs-from KEY...]
kind: exterior-wings | wing-scenes | elements | portraits | panels

Style refs are manifest keys (looked up in assets/map/jobs.json by the batch
runner at run time), so manifests can be built before the style jobs exist.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

ELEMENT_SUFFIX = (", painted Victorian museum exhibit, soft Ghibli-like light, "
                  "deep teal burgundy cream brass palette, 3/4 top-down view")
BOARDED = ("board up the windows and doors with weathered planks, dust sheets, "
           "dark unlit windows, keep everything else identical")
SCENE_SUFFIX = ("interior seen from 3/4 top-down, open floor space for exhibits, "
                "soft gaslight, calm")
CAST_DESC = {
    "cornelia": "Cornelia Wren, a young museum curator in a teal waistcoat",
    "barnaby": "Barnaby Pluck, a cheerful stout caretaker",
    "aldous": "Professor Aldous Finch, an elderly scholar with round spectacles",
    "sam": "Sam Vane, a lanky young courier",
    "mark": "Mark Bloom, a gardener with a straw hat",
    "anjali": "Anjali Bose, a keen field naturalist",
    "hugo": "Hugo Pemberton, a pompous collector in a burgundy coat",
    "prudence": "Prudence Quill, a precise archivist with ink-stained fingers",
    "zephyrine": "Zephyrine Blackwood, a bold aviator with goggles",
    "rosalind": "Rosalind Thorne, an elegant patron of the Society",
    "ambrose": "Ambrose Hall, the founder of Curio Hall, grey-bearded and kindly",
}
PORTRAIT_EXPR = {
    "happy": "make the expression happy and smiling, keep everything else identical",
    "surprised": "make the expression surprised, eyebrows raised, keep everything else identical",
    "worried": "make the expression worried, brows knitted, keep everything else identical",
}


def spec(canvas, anchor="bottom_center", margin=4):
    return {"canvas_size": list(canvas), "style": "painted", "background": None,
            "anchor": anchor, "alpha_threshold": 8, "palette": None, "margin": margin}


def entry(key, out, cmd, args, source_key=None):
    return {"key": key, "out": out, "cmd": cmd, "args": args, "source_key": source_key}


def fit_canvas(rect, max_side=1024):
    w, h = rect[2], rect[3]
    s = max_side / max(w, h)
    return [max(1, round(w * s)), max(1, round(h * s))]


def exterior_wings(areas, style_keys):
    out = []
    for w in C.wings():
        a = w["area"]
        if areas and a not in areas:
            continue
        sp = spec(fit_canvas(w["exterior_rect"]))
        rk = "ext_%02d_restored" % a
        out.append(entry(rk, C.exterior_path(a, "restored"), "generate", {
            "subject": "%s, Victorian museum wing facade, painted, soft Ghibli-like light, "
                       "deep teal burgundy cream brass palette" % w["name"],
            "spec": sp, "style_keys": style_keys}))
        if w["structure"] == "interior":
            out.append(entry("ext_%02d_boarded" % a, C.exterior_path(a, "boarded"), "edit",
                             {"instruction": BOARDED, "spec": sp}, rk))
    return out


def wing_scenes(areas, style_keys):
    out = []
    for w in C.wings():
        a = w["area"]
        if areas and a not in areas:
            continue
        for i, sub in enumerate(w["subrooms"]):
            out.append(entry("scene_%02d_%d" % (a, i), C.scene_path(a, i), "background", {
                "description": "%s, %s, %s" % (w["name"], sub["name"], SCENE_SUFFIX),
                "size": "%dx%d" % (720, sub["size"][1]), "style": "painted",
                "style_keys": style_keys}))
    return out


def elements(areas, style_keys):
    out = []
    for e in C.elements():
        if areas and e["area"] not in areas:
            continue
        k0 = "el_%s_0" % e["id"]
        subject = (e.get("subject") or e["name"]) + ELEMENT_SUFFIX
        out.append(entry(k0, C.element_path(e["id"], 0), "generate", {
            "subject": subject, "spec": spec([384, 384]), "style_keys": style_keys}))
        for i in range(1, len(e["looks"])):
            look = e["looks"][i]
            instr = look.get("instruction") or \
                "restyle this exhibit as its '%s' variant, keep the same framing" % look["name"]
            out.append(entry("el_%s_%d" % (e["id"], i), C.element_path(e["id"], i), "edit",
                             {"instruction": instr, "spec": spec([384, 384])}, k0))
    return out


def portraits(areas, style_keys):
    out = []
    for sp in C.CAST:
        nk = "portrait_%s_neutral" % sp
        out.append(entry(nk, C.portrait_path(sp, "neutral"), "generate", {
            "subject": "%s, bust-to-knee character portrait, painted Victorian museum "
                       "style, soft Ghibli-like light" % CAST_DESC[sp],
            "spec": spec([512, 768]), "facing": "front", "style_keys": style_keys}))
        for ex in C.expressions_for(sp):
            if ex == "neutral":
                continue
            out.append(entry("portrait_%s_%s" % (sp, ex), C.portrait_path(sp, ex), "edit",
                             {"instruction": PORTRAIT_EXPR[ex], "spec": spec([512, 768]),
                              "facing": "front"}, nk))
    return out


def panels(areas, style_keys):
    out = []
    for s in C.panel_scenes():
        cast = [c for c in s.get("cast", []) if c in C.CAST]
        for i, p in enumerate(s.get("panels", [])):
            pc = [c for c in p.get("cast", cast) if c in C.CAST]
            desc = p.get("caption", "")
            if pc:
                desc += ". Featuring " + "; ".join(CAST_DESC[c] for c in pc)
            desc += ". Painted Victorian museum storybook illustration, soft Ghibli-like light"
            out.append(entry("panel_%s_%d" % (s["id"], i), C.panel_path(s["id"], i), "background", {
                "description": desc, "size": "720x960", "style": "painted",
                "style_keys": style_keys + ["portrait_%s_neutral" % c for c in pc]}))
    return out


KINDS = {"exterior-wings": exterior_wings, "wing-scenes": wing_scenes,
         "elements": elements, "portraits": portraits, "panels": panels}


def build(kind, areas=None, style_keys=None):
    return KINDS[kind](areas, list(style_keys or []))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("kind", choices=sorted(KINDS))
    ap.add_argument("--areas", help="e.g. 1-12 or 1,3,5-7 (default: all)")
    ap.add_argument("--style-jobs-from", nargs="*", default=[], metavar="KEY",
                    help="jobs.json keys of locked style refs, resolved at run time")
    a = ap.parse_args(argv)
    json.dump(build(a.kind, C.parse_areas(a.areas), a.style_jobs_from), sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
