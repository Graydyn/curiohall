#!/usr/bin/env python3
"""Build a Sectilia job manifest (JSON on stdout) for one kind of Hall art.

usage: art_manifest.py <kind> [--areas 1-12] [--style-jobs-from KEY...]
                       [--style-pass] [--scenes-via generate|background]
kind: exterior-wings | wing-scenes | elements | portraits | panels | ui

Generates take the style refs directly (`generate --style`, sectilia >= 0.5.4).
`--style-pass` keeps the old two-step path (raw generate + style edit).

Style refs are manifest keys (looked up in assets/map/jobs.json by the batch
runner at run time), so manifests can be built before the style jobs exist.
"""
import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402

# Sprites are cut out with a sampled chroma key, which needs a one-colour
# border; the teal palette otherwise tends to paint a gradient backdrop.
BACKDROP = ", isolated on a plain flat pale grey backdrop"
ELEMENT_SUFFIX = (", painted Victorian museum exhibit, soft Ghibli-like light, "
                  "deep teal burgundy cream brass palette, 3/4 top-down view" + BACKDROP)
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


# Sprites: sampled chroma key (removes only edge-connected backdrop).
# Tolerance 60, not the doc's 30: painted backdrops carry a soft vignette and
# 30 failed validation on about half the Atrium elements.
CHROMA = {"type": "chroma_key", "color": None, "tolerance": 60}
# Full-frame art (rooms, panels, framed UI): nothing removed, stays opaque.
KEEP = {"type": "keep"}
# The generator draws about 2:3 portrait; scenes made by generate are drawn at
# this size and cover-fitted (scale + centre crop) to their final size.
SCENE_GEN_CANVAS = [683, 1024]


def spec(canvas, anchor="bottom_center", margin=4, background=CHROMA):
    return {"canvas_size": list(canvas), "style": "painted",
            "background": dict(background) if background else None,
            "anchor": anchor, "alpha_threshold": 8, "palette": None, "margin": margin}


def entry(key, out, cmd, args, source_key=None):
    return {"key": key, "out": out, "cmd": cmd, "args": args, "source_key": source_key}


def with_post(entries, **post):
    """Attach a post-processing step (see sectilia_batch.apply_post) to every
    entry that writes a final asset (not a _raw/ intermediate)."""
    for e in entries:
        if "/_raw/" not in e["out"]:
            e["post"] = dict(e.get("post") or {}, **post)
    return entries


def styled_generate(key, out, args, style_keys, style_pass=False):
    """generate entries get the shared --theme and the locked style refs as
    `--style`. With style_pass (legacy), generate without refs to a raw path,
    then edit it with the refs into the final path. Returns entries; downstream
    edits use `key` as their source either way."""
    args = dict(args, theme=C.STYLE_THEME)
    if not style_pass:
        if style_keys:
            args["style_keys"] = list(style_keys)
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
        sp = spec(fit_canvas(w["exterior_rect"]),
                  background=None if w.get("art_bg") == "soft" else CHROMA)
        rk = "ext_%02d_restored" % a
        subject = w.get("exterior_subject") or (
            "%s, Victorian museum wing facade" % w["name"])
        # Stone walls are pale: strip shadows only in the very bottom band.
        wing_clean = {"clean": {"shadow": True, "ground": 0.86}}
        out += with_post(styled_generate(rk, C.exterior_path(a, "restored"), {
            "subject": subject + ", painted, soft Ghibli-like light, "
                       "deep teal burgundy cream brass palette" + BACKDROP,
            "spec": sp, "facing": "front"}, style_keys, style_pass), **wing_clean)
        if w["structure"] == "interior":
            out += with_post([entry("ext_%02d_boarded" % a, C.exterior_path(a, "boarded"), "edit",
                                    {"instruction": BOARDED, "spec": sp}, rk)],
                             align_to=C.exterior_path(a, "restored"), **wing_clean)
    return out


def scene_generate(key, final, subject, size, style_keys):
    """A full-frame scene via generate: opaque (keep) at the generator's
    native portrait aspect into _raw/, then cover-fitted to `size` at `final`
    by the batch runner (`fit`)."""
    raw = C.raw_path(final)
    e = entry(key, raw, "generate", {
        "subject": subject[:500], "theme": C.STYLE_THEME,
        "spec": spec(SCENE_GEN_CANVAS, anchor="center", margin=0, background=KEEP),
        "style_keys": list(style_keys)})
    e["fit"] = {"size": list(size), "out": final}
    return e


def wing_scenes(areas, style_keys, style_pass=False, via="background"):
    out = []
    for w in C.wings():
        a = w["area"]
        if areas and a not in areas:
            continue
        for i, sub in enumerate(w["subrooms"]):
            key = "scene_%02d_%d" % (a, i)
            desc = sub.get("description") or "%s, %s, %s" % (w["name"], sub["name"], SCENE_SUFFIX)
            if via == "generate":
                out.append(scene_generate(key, C.scene_path(a, i),
                                          sub.get("subject") or desc, sub["size"], style_keys))
                continue
            out.append(entry(key, C.scene_path(a, i), "background", {
                "description": desc,
                "size": "%dx%d" % (720, sub["size"][1]), "style": "painted",
                "style_keys": style_keys}))
    return out


def el_spec(e):
    """Element sprite spec. `art_bg: "soft"` on a row (glass, smoke, glows)
    uses background null, which keeps soft edges, instead of the chroma key."""
    return spec([384, 384], background=None if e.get("art_bg") == "soft" else CHROMA)


def elements(areas, style_keys, style_pass=False):
    out = []
    for e in C.elements():
        if areas and e["area"] not in areas:
            continue
        k0 = "el_%s_0" % e["id"]
        subject = (e.get("subject") or e["name"]) + ELEMENT_SUFFIX
        clean = {"clean": {"shadow": e.get("art_bg") != "soft"}}
        out += with_post(styled_generate(k0, C.element_path(e["id"], 0), {
            "subject": subject, "spec": el_spec(e)}, style_keys, style_pass), **clean)
        for i in range(1, len(e["looks"])):
            look = e["looks"][i]
            instr = look.get("instruction") or \
                "restyle this exhibit as its '%s' variant, keep the same framing" % look["name"]
            out += with_post([entry("el_%s_%d" % (e["id"], i), C.element_path(e["id"], i), "edit",
                                    {"instruction": instr, "spec": el_spec(e)}, k0)], **clean)
    return out


# Portraits: background null. Tall figures on a painted backdrop failed the
# chroma-key border check (Cornelia, 4 attempts at tolerance 60).
PORTRAIT_SPEC = spec([512, 768], background=None)


def portraits(areas, style_keys, style_pass=False):
    out = []
    for sp in C.CAST:
        nk = "portrait_%s_neutral" % sp
        out += styled_generate(nk, C.portrait_path(sp, "neutral"), {
            "subject": "%s, bust-to-knee character portrait, painted Victorian museum "
                       "style, soft Ghibli-like light" % CAST_DESC[sp] + BACKDROP,
            "spec": PORTRAIT_SPEC, "facing": "front"}, style_keys, style_pass)
        for ex in C.expressions_for(sp):
            if ex == "neutral":
                continue
            out.append(entry("portrait_%s_%s" % (sp, ex), C.portrait_path(sp, ex), "edit",
                             {"instruction": PORTRAIT_EXPR[ex], "spec": PORTRAIT_SPEC,
                              "facing": "front"}, nk))
    return out


def panels(areas, style_keys, style_pass=False, via="background"):
    out = []
    for s in C.panel_scenes():
        cast = [c for c in s.get("cast", []) if c in C.CAST]
        for i, p in enumerate(s.get("panels", [])):
            pc = [c for c in p.get("cast", cast) if c in C.CAST]
            desc = p.get("caption", "")
            if pc:
                desc += ". Featuring " + "; ".join(CAST_DESC[c] for c in pc)
            desc += ". Painted Victorian museum storybook illustration, soft Ghibli-like light"
            refs = style_keys + ["portrait_%s_neutral" % c for c in pc]
            if via == "generate":
                subject = p.get("subject") or desc
                out.append(scene_generate("panel_%s_%d" % (s["id"], i), C.panel_path(s["id"], i),
                                          subject, [720, 960], refs[:8]))
                continue
            out.append(entry("panel_%s_%d" % (s["id"], i), C.panel_path(s["id"], i), "background", {
                "description": desc, "size": "720x960", "style": "painted",
                "style_keys": refs}))
    return out


# name -> (subject, canvas, background). Frames are drawn whole and nine-sliced
# in CurioTheme.art_box, so they keep a plain flat centre.
UI_PIECES = {
    "scaffold": ("a wooden scaffolding frame with ladders, planks and a draped canvas dust "
                 "sheet, seen straight on, open in the middle", [512, 512], CHROMA),
    "society_seal": ("a round brass wax-seal style emblem of a Victorian expedition society: "
                     "a compass rose over a globe, laurel border, deep teal enamel", [256, 256], CHROMA),
    "badge_glow": ("a soft round warm amber gaslight halo badge with a brass rim", [256, 256], None),
    "nav_button": ("a wide flat rectangular brass name plate, four times wider than tall, seen "
                   "perfectly straight on with no perspective, engraved filigree at the corners, "
                   "a plain flat deep teal enamel centre", [512, 128], CHROMA),
    "task_card_frame": ("an ornate rectangular brass picture frame with filigree corners around a "
                        "plain flat cream parchment panel, seen straight on", [512, 384], CHROMA),
    "speech_bubble": ("a rounded rectangular cream parchment speech panel with a thin brass "
                      "border and small filigree corners, plain flat centre, seen straight on",
                      [512, 256], CHROMA),
    "picker_frame": ("a wide flat rectangular ornate brass picture frame seen perfectly straight "
                     "on with no perspective, filigree corners, a plain flat deep teal velvet "
                     "centre", [512, 320], CHROMA),
}


def ui(areas, style_keys, style_pass=False):
    out = []
    for name, (subject, canvas, bg) in UI_PIECES.items():
        out += with_post(styled_generate("ui_%s" % name, "%s/ui/%s.png" % (C.BASE, name), {
            "subject": subject, "spec": spec(canvas, anchor="center", margin=0, background=bg)},
            style_keys, style_pass), clean={"shadow": False, "crop": True})
    return out


KINDS = {"exterior-wings": exterior_wings, "wing-scenes": wing_scenes,
         "elements": elements, "portraits": portraits, "panels": panels, "ui": ui}
SCENE_KINDS = ("wing-scenes", "panels")


def build(kind, areas=None, style_keys=None, style_pass=False, scenes_via="background"):
    if kind in SCENE_KINDS:
        return KINDS[kind](areas, list(style_keys or []), style_pass, scenes_via)
    return KINDS[kind](areas, list(style_keys or []), style_pass)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("kind", choices=sorted(KINDS))
    ap.add_argument("--areas", help="e.g. 1-12 or 1,3,5-7 (default: all)")
    ap.add_argument("--style-jobs-from", nargs="*", default=[], metavar="KEY",
                    help="jobs.json keys of locked style refs, resolved at run time")
    ap.add_argument("--style-pass", action="store_true",
                    help="legacy: generate raw images without refs, then edit each with "
                         "the style refs (default passes refs to generate directly)")
    ap.add_argument("--scenes-via", choices=["background", "generate"], default="background",
                    help="wing-scenes/panels: `background` jobs, or opaque generates "
                         "cover-fitted to size")
    a = ap.parse_args(argv)
    json.dump(build(a.kind, C.parse_areas(a.areas), a.style_jobs_from, a.style_pass,
                    a.scenes_via), sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
