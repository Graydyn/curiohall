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
    "cornelia": "Cornelia Wren, the formidable interim curator, all etiquette and steel, "
                "in a severe high-collared Victorian dress with a pocket watch",
    "barnaby": "Barnaby Pluck, a cheerful young porter and jack-of-all-trades, "
               "in a porter's waistcoat and rolled sleeves",
    "aldous": "Professor Aldous Finch, an absent-minded ornithologist, in a rumpled tweed "
              "coat with a field notebook and binoculars",
    "sam": "Sam Vane, a suave rival collector, charming and a little untrustworthy, "
           "in a well-cut dark frock coat",
    "mark": "Mark Bloom, a shy conservatory gardener, in a gardener's apron "
            "with potting soil on his hands",
    "anjali": "Anjali Bose, an expedition chef and confectioner, in a chef's apron "
              "with a tea-room tray of sweets",
    "hugo": "Hugo Pemberton, a clockwork engineer, in a leather apron with brass "
            "tools and goggles pushed up on his forehead",
    "prudence": "Prudence Quill, an exacting archivist, in a neat dark dress with "
                "ink-stained cuffs and a ledger",
    "zephyrine": "Zephyrine Blackwood, a mysterious cartographer just back from the "
                 "unmapped edges of the world, in a travel-worn coat with rolled charts",
    "rosalind": "Rosalind Thorne, a celebrated botanical illustrator and society "
                "patroness, in an elegant gown with a sketchbook and paintbrush",
    "ambrose": "Ambrose Hall, the vanished founder of Curio Hall, painted as a formal "
               "founder's portrait in period Victorian dress",
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


def styled_generate(key, out, args, style_keys, style_pass):
    """generate entries get the shared --theme and never style refs. With
    style_pass, generate to a raw path, then edit it with the locked style refs
    (the only command that accepts them) into the final path. Returns entries;
    downstream edits use `key` as their source either way."""
    args = dict(args, theme=C.STYLE_THEME)
    if not style_pass:
        return [entry(key, out, "generate", args)]
    raw = C.raw_path(out)
    return [entry(key + "_raw", raw, "generate", args),
            entry(key, out, "edit", {"instruction": C.STYLE_INSTRUCTION, "spec": args["spec"],
                                     "facing": args.get("facing"), "style_keys": style_keys},
                  key + "_raw")]


def fit_canvas(rect, max_side=1024):
    w, h = rect[2], rect[3]
    s = max_side / max(w, h)
    return [max(1, round(w * s)), max(1, round(h * s))]


def exterior_wings(areas, style_keys, style_pass=False):
    out = []
    for w in C.wings():
        a = w["area"]
        if areas and a not in areas:
            continue
        sp = spec(fit_canvas(w["exterior_rect"]))
        rk = "ext_%02d_restored" % a
        subject = w.get("exterior_subject") or (
            "%s, Victorian museum wing facade" % w["name"])
        out += styled_generate(rk, C.exterior_path(a, "restored"), {
            "subject": subject + ", painted, soft Ghibli-like light, "
                       "deep teal burgundy cream brass palette",
            "spec": sp}, style_keys, style_pass)
        if w["structure"] == "interior":
            out.append(entry("ext_%02d_boarded" % a, C.exterior_path(a, "boarded"), "edit",
                             {"instruction": BOARDED, "spec": sp}, rk))
    return out


def wing_scenes(areas, style_keys, style_pass=False):
    out = []
    for w in C.wings():
        a = w["area"]
        if areas and a not in areas:
            continue
        for i, sub in enumerate(w["subrooms"]):
            out.append(entry("scene_%02d_%d" % (a, i), C.scene_path(a, i), "background", {
                "description": sub.get("description") or
                               "%s, %s, %s" % (w["name"], sub["name"], SCENE_SUFFIX),
                "size": "%dx%d" % (720, sub["size"][1]), "style": "painted",
                "style_keys": style_keys}))
    return out


def elements(areas, style_keys, style_pass=False):
    out = []
    for e in C.elements():
        if areas and e["area"] not in areas:
            continue
        k0 = "el_%s_0" % e["id"]
        subject = (e.get("subject") or e["name"]) + ELEMENT_SUFFIX
        out += styled_generate(k0, C.element_path(e["id"], 0), {
            "subject": subject, "spec": spec([384, 384])}, style_keys, style_pass)
        for i in range(1, len(e["looks"])):
            look = e["looks"][i]
            instr = look.get("instruction") or \
                "restyle this exhibit as its '%s' variant, keep the same framing" % look["name"]
            out.append(entry("el_%s_%d" % (e["id"], i), C.element_path(e["id"], i), "edit",
                             {"instruction": instr, "spec": spec([384, 384])}, k0))
    return out


def portraits(areas, style_keys, style_pass=False):
    out = []
    for sp in C.CAST:
        nk = "portrait_%s_neutral" % sp
        out += styled_generate(nk, C.portrait_path(sp, "neutral"), {
            "subject": "%s, bust-to-knee character portrait, painted Victorian museum "
                       "style, soft Ghibli-like light" % CAST_DESC[sp],
            "spec": spec([512, 768]), "facing": "front"}, style_keys, style_pass)
        for ex in C.expressions_for(sp):
            if ex == "neutral":
                continue
            out.append(entry("portrait_%s_%s" % (sp, ex), C.portrait_path(sp, ex), "edit",
                             {"instruction": PORTRAIT_EXPR[ex], "spec": spec([512, 768]),
                              "facing": "front"}, nk))
    return out


def panels(areas, style_keys, style_pass=False):
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


def build(kind, areas=None, style_keys=None, style_pass=False):
    return KINDS[kind](areas, list(style_keys or []), style_pass)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("kind", choices=sorted(KINDS))
    ap.add_argument("--areas", help="e.g. 1-12 or 1,3,5-7 (default: all)")
    ap.add_argument("--style-jobs-from", nargs="*", default=[], metavar="KEY",
                    help="jobs.json keys of locked style refs, resolved at run time")
    ap.add_argument("--style-pass", action="store_true",
                    help="generate raw images, then edit each with the style refs "
                         "(generate cannot take style jobs)")
    a = ap.parse_args(argv)
    json.dump(build(a.kind, C.parse_areas(a.areas), a.style_jobs_from, a.style_pass), sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
