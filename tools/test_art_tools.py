import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402
import art_manifest as M  # noqa: E402
import sectilia_batch as B  # noqa: E402
import clean_sprite as CS  # noqa: E402
import align_states as AS  # noqa: E402
import lawn_patch as LP  # noqa: E402
import harmonise_wing as HW  # noqa: E402
import check_bands as CBD  # noqa: E402
import place_elements as PE  # noqa: E402

REAL_ROOT = C.ROOT


class ManifestTests(unittest.TestCase):
    def test_elements_area1(self):
        m = M.build("elements", {1}, ["style_core_1"])
        self.assertEqual(len(m), 6)
        keys = {e["key"] for e in m}
        self.assertEqual(len(keys), 6)
        for e in m:
            if e["cmd"] == "edit":
                self.assertTrue(e["source_key"].endswith("_0"))
                self.assertIn(e["source_key"], keys)
            else:
                self.assertEqual(e["cmd"], "generate")
                self.assertEqual(e["args"]["style_keys"], ["style_core_1"])
                self.assertEqual(e["args"]["theme"], C.STYLE_THEME)
                self.assertEqual(e["args"]["spec"]["background"], M.CHROMA)
                self.assertEqual(e["args"]["spec"]["canvas_size"], [384, 384])
        self.assertEqual(m[0]["out"], "assets/map/elements/01/01_001_0.png")

    def test_full_counts(self):
        self.assertEqual(len(M.build("elements")), 4224)
        self.assertEqual(len(M.build("wing-scenes")), 58)
        self.assertEqual(len(M.build("exterior-wings")), 84)
        self.assertEqual(len(M.build("portraits")), 51)  # +1 neutral edit per expressive cast

    def test_exterior_boarded_edits_restored(self):
        m = {e["key"]: e for e in M.build("exterior-wings", {1})}
        self.assertEqual(m["ext_01_boarded"]["source_key"], "ext_01_restored")
        self.assertEqual(m["ext_01_restored"]["args"]["spec"]["canvas_size"],
                         M.fit_canvas(C.wings()[0]["exterior_rect"]))

    def test_style_pass_wires_sources(self):
        m = M.build("elements", {1}, ["style_core_1", "style_core_2"], True)
        self.assertEqual(len(m), 8)
        by = {e["key"]: e for e in m}
        raw = by["el_01_001_0_raw"]
        self.assertEqual(raw["cmd"], "generate")
        self.assertIn("/_raw/", raw["out"])
        styled = by["el_01_001_0"]
        self.assertEqual((styled["cmd"], styled["source_key"]), ("edit", "el_01_001_0_raw"))
        self.assertEqual(styled["args"]["style_keys"], ["style_core_1", "style_core_2"])
        self.assertEqual(styled["out"], "assets/map/elements/01/01_001_0.png")
        self.assertEqual(by["el_01_001_1"]["source_key"], "el_01_001_0")
        order = [e["key"] for e in m]
        self.assertLess(order.index("el_01_001_0_raw"), order.index("el_01_001_0"))
        for kind in ("portraits", "exterior-wings"):
            mm = M.build(kind, {1}, ["s"], True)
            self.assertTrue(any(e["key"].endswith("_raw") for e in mm))

    def test_generate_argv_style_refs(self):
        """Default: generates carry --style refs. Legacy style pass: the raw
        generate has none and the edit carries them."""
        for kind in ("elements", "portraits", "exterior-wings", "ui"):
            for sp in (False, True):
                for e in M.build(kind, {1}, ["s1"], sp):
                    if e["cmd"] == "generate":
                        argv = B.build_argv(e, {"s1": "J"})
                        self.assertIn("--theme", argv)
                        if sp:
                            self.assertNotIn("--style", argv)
                        else:
                            self.assertEqual(argv[argv.index("--style") + 1], "J")
                    elif e["cmd"] == "edit" and e["args"].get("style_keys"):
                        argv = B.build_argv(e, {"s1": "J", e["source_key"]: "S"})
                        self.assertIn("--style", argv)

    def test_scenes_via_generate_keep_and_fit(self):
        m = M.build("wing-scenes", {2}, ["s1"], scenes_via="generate")
        e = m[0]
        self.assertEqual(e["cmd"], "generate")
        self.assertEqual(e["args"]["spec"]["background"], M.KEEP)
        self.assertEqual(e["args"]["spec"]["canvas_size"], M.SCENE_GEN_CANVAS)
        self.assertIn("/_raw/", e["out"])
        self.assertEqual(e["fit"]["out"], C.scene_path(2, 0))
        self.assertLessEqual(len(e["args"]["subject"]), 500)
        self.assertEqual(B.final_out(e), C.scene_path(2, 0))
        self.assertEqual(M.build("wing-scenes", {2})[0]["cmd"], "background")

    def test_ui_pieces(self):
        m = M.build("ui", None, ["s1"])
        outs = {e["out"] for e in m}
        for name in ("scaffold", "society_seal", "nav_button", "task_card_frame",
                     "speech_bubble", "picker_frame"):
            self.assertIn("assets/map/ui/%s.png" % name, outs)

    def test_portraits(self):
        m = M.build("portraits")
        self.assertEqual(sum(1 for e in m if e["cmd"] == "generate"), 11)
        self.assertEqual(m[0]["args"]["facing"], "front")
        self.assertFalse(any("ambrose_happy" in e["key"] for e in m))

    def test_paths_match_hall_art(self):
        self.assertEqual(C.scene_path(3, 1), "assets/map/wings/03/scene_1.png")
        self.assertEqual(C.portrait_path("sam", "happy"), "assets/map/portraits/sam_happy.png")
        self.assertEqual(C.panel_path("s1", 0), "assets/map/panels/s1_0.png")

    def test_parse_areas(self):
        self.assertEqual(C.parse_areas("1-3,7"), {1, 2, 3, 7})
        self.assertIsNone(C.parse_areas(None))


def entry(key, cmd="generate", out=None, source=None):
    return {"key": key, "out": out or "assets/map/_t/%s.png" % key, "cmd": cmd,
            "args": {"subject": "x", "spec": {}, "style_keys": [], "instruction": "i"},
            "source_key": source}


class BatchTests(unittest.TestCase):
    def test_apply_fit_cover_crops(self):
        from PIL import Image
        with tempfile.TemporaryDirectory(dir=C.ROOT) as d:
            rel = os.path.relpath(d, C.ROOT)
            Image.new("RGBA", (200, 300), (10, 20, 30, 255)).save(os.path.join(d, "raw.png"))
            e = {"out": rel + "/raw.png", "fit": {"size": [72, 128], "out": rel + "/fit.png"}}
            B.apply_fit(e)
            im = Image.open(os.path.join(d, "fit.png"))
            self.assertEqual(im.size, (72, 128))
            self.assertEqual(im.mode, "RGB")

    def test_clean_sprite_strips_pale_shadow_only(self):
        from PIL import Image
        im = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
        for x in range(5, 35):
            for y in range(28, 36):
                im.putpixel((x, y), (190, 196, 194, 255))   # pale grey shadow
        for x in range(10, 30):
            for y in range(5, 30):
                im.putpixel((x, y), (40, 90, 95, 255))      # teal subject
        for x in range(14, 18):
            for y in range(10, 14):
                im.putpixel((x, y), (200, 200, 198, 255))   # pale marble inside
        out, n = CS.clean(im)
        self.assertGreater(n, 0)
        self.assertEqual(out.getpixel((6, 32))[3], 0)
        self.assertEqual(out.getpixel((20, 20))[3], 255)
        self.assertEqual(out.getpixel((15, 11))[3], 255)

    def test_clean_sprite_islands_and_specks(self):
        from PIL import Image
        im = Image.new("RGBA", (60, 60), (0, 0, 0, 0))
        for x in range(10, 40):
            for y in range(10, 40):
                im.putpixel((x, y), (120, 40, 30, 255))     # subject
        for x in range(50, 54):
            for y in range(50, 54):
                im.putpixel((x, y), (230, 150, 120, 255))   # detached peach blob
        im.putpixel((2, 2), (10, 10, 10, 12))               # low-alpha speck
        for x in range(40, 44):
            im.putpixel((x, 20), (120, 40, 30, 255))        # attached spur, kept
        out, n = CS.clean(im, shadow=False)
        self.assertEqual(out.getpixel((51, 51))[3], 0)
        self.assertEqual(out.getpixel((2, 2))[3], 0)
        self.assertEqual(out.getpixel((42, 20))[3], 255)
        self.assertEqual(out.getpixel((20, 20))[3], 255)

    def test_clean_sprite_shadow_only_in_ground_band(self):
        from PIL import Image
        im = Image.new("RGBA", (40, 80), (0, 0, 0, 0))
        for x in range(10, 30):
            for y in range(5, 70):
                im.putpixel((x, y), (60, 70, 72, 255))       # dark subject
        for x in range(5, 35):
            for y in range(5, 10):
                im.putpixel((x, y), (190, 190, 186, 255))    # pale cap, top: subject
            for y in range(70, 78):
                im.putpixel((x, y), (190, 190, 186, 255))    # pale shadow, bottom
        out, _ = CS.clean(im)
        self.assertEqual(out.getpixel((7, 7))[3], 255)
        self.assertEqual(out.getpixel((7, 74))[3], 0)
        kept, _ = CS.clean(im, shadow=False)
        self.assertEqual(kept.getpixel((7, 74))[3], 255)

    def test_align_states_matches_source_box(self):
        from PIL import Image
        src = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        src.paste((200, 0, 0, 255), (20, 40, 180, 190))
        st = Image.new("RGBA", (200, 200), (0, 0, 0, 0))
        st.paste((0, 0, 200, 255), (70, 10, 150, 85))       # smaller, shifted up
        out = AS.align(src, st)
        self.assertEqual(out.size, src.size)
        box = AS.subject_box(out)
        self.assertLessEqual(abs(box[3] - 190), 1)          # same ground line
        self.assertLessEqual(abs((box[0] + box[2]) / 2 - 100), 1)
        self.assertLessEqual(abs((box[2] - box[0]) - 160), 2)

    def test_tall_scene_fits_one_screen_then_extends(self):
        from PIL import Image
        e = M.scene_generate("scene_99_0", "assets/map/wings/99/scene_0.png", "room", [720, 2560], [])
        self.assertEqual(e["fit"], {"size": [720, 1280], "out": "assets/map/wings/99/scene_0.png",
                                    "extend": 2560})
        with tempfile.TemporaryDirectory(dir=C.ROOT) as d:
            rel = os.path.relpath(d, C.ROOT)
            Image.new("RGBA", (683, 1024), (10, 20, 30, 255)).save(os.path.join(d, "raw.png"))
            B.apply_fit({"out": rel + "/raw.png",
                         "fit": {"size": [720, 1280], "out": rel + "/tall.png", "extend": 2560}})
            self.assertEqual(Image.open(os.path.join(d, "tall.png")).size, (720, 2560))
        short = M.scene_generate("scene_98_0", "assets/map/wings/98/scene_0.png", "room", [720, 1280], [])
        self.assertNotIn("extend", short["fit"])

    def test_extend_room_keeps_top_and_repeats_floor(self):
        import extend_room as ER
        from PIL import Image
        im = Image.new("RGB", (72, 128), (10, 10, 10))
        im.paste((200, 0, 0), (0, 76, 72, 128))           # "floor" band from row 76
        out = ER.extend(im, 300, strip_top=76, fade=20)
        self.assertEqual(out.size, (72, 300))
        self.assertEqual(out.getpixel((5, 10)), (10, 10, 10))   # far wall untouched
        self.assertEqual(out.getpixel((5, 120)), (200, 0, 0))
        self.assertEqual(out.getpixel((5, 299)), (200, 0, 0))   # floor all the way down
        self.assertEqual(ER.fade_mask(4, 30, 20).getpixel((0, 0)), 0)
        self.assertEqual(ER.fade_mask(4, 30, 20).getpixel((0, 25)), 255)

    def test_extend_room_vary_breaks_the_period_and_mirrors_less(self):
        import extend_room as ER
        from PIL import Image
        im = Image.new("RGB", (72, 128), (10, 10, 10))
        im.paste((200, 0, 0), (0, 76, 72, 128))
        out = ER.extend(im, 600, strip_top=76, fade=10, vary=True)
        self.assertEqual(out.size, (72, 600))
        self.assertEqual(out.getpixel((5, 10)), (10, 10, 10))   # far wall untouched
        self.assertEqual(out.getpixel((5, 599)), (200, 0, 0))   # floor all the way down
        steps = list(zip(range(8), ER.bands(52, True)))
        self.assertGreater(len({o for _k, (o, _m) in steps}), 3)    # band starts differ
        self.assertLess(sum(m for _k, (_o, m) in steps), 4)         # not every other copy
        plain = list(zip(range(3), ER.bands(52, False)))
        self.assertEqual([b for _k, b in plain], [(0, False), (0, True), (0, False)])
        e = M.scene_generate("scene_97_0", "assets/map/wings/97/scene_0.png", "room", [720, 2560], [],
                             {"vary": True, "fade": 260})
        self.assertEqual((e["fit"]["vary"], e["fit"]["fade"], e["fit"]["extend"]), (True, 260, 2560))

    def test_lawn_patch_fills_polygon_only(self):
        from PIL import Image
        base = Image.new("RGB", (120, 80), (200, 200, 200))
        base.paste((30, 120, 40), (0, 0, 120, 30))          # grass sample strip
        out = LP.patch(base, (0, 0, 120, 30), [[60, 40, 110, 40, 110, 75, 60, 75]], feather=0)
        g = out.getpixel((85, 58))
        self.assertGreater(g[1], g[0] + 40)                 # now grass-green
        self.assertEqual(out.getpixel((10, 60)), (200, 200, 200))

    def test_manifest_post_steps(self):
        p = mock.patch.object(C, "ROOT", REAL_ROOT)
        p.start()
        self.addCleanup(p.stop)
        by = {e["key"]: e for e in M.build("exterior-wings", {3}, ["s"])}
        self.assertEqual(by["ext_03_boarded"]["post"]["align_to"], C.exterior_path(3, "restored"))
        self.assertIn("clean", by["ext_03_restored"]["post"])
        els = M.build("elements", {2}, ["s"])
        soft = {e["id"] for e in C.elements() if e.get("art_bg") == "soft"}
        for e in els:
            self.assertEqual(e["post"]["clean"]["shadow"], e["key"][3:9] not in soft)
        for e in M.build("elements", {2}, ["s"], True):
            if "/_raw/" in e["out"]:
                self.assertNotIn("post", e)
        ui = {e["key"]: e for e in M.build("ui", None, ["s"])}
        self.assertTrue(ui["ui_nav_button"]["post"]["clean"]["crop"])

    def test_el_spec_soft(self):
        self.assertIsNone(M.el_spec({"art_bg": "soft"})["background"])
        self.assertEqual(M.el_spec({})["background"], M.CHROMA)

    def test_argv_passes_cli_timeout(self):
        with mock.patch.object(C, "ROOT", REAL_ROOT):
            e = M.build("elements", {1}, ["s1"])[0]
        argv = B.build_argv(e, {"s1": "J"})
        self.assertEqual(argv[argv.index("--timeout") + 1], str(B.CLI_TIMEOUT))

    def test_harmonise_crop_and_mask(self):
        from PIL import Image
        base = Image.new("RGB", (400, 300), (40, 110, 50))
        sprite = Image.new("RGBA", (100, 50), (0, 0, 0, 0))
        sprite.paste((150, 120, 100, 255), (20, 10, 80, 50))
        crop, alpha, meta = HW.make_crop(base, sprite, [100, 100, 200, 100], margin=0.2)
        self.assertEqual(meta["crop_rect"], [60, 80, 280, 140])
        self.assertEqual(crop.size, alpha.size)
        mask = HW.feather_mask(alpha)
        w, h = mask.size
        for pt in ((0, 0), (w - 1, h - 1), (0, h // 2), (w // 2, 0)):
            self.assertEqual(mask.getpixel(pt), 0)            # edges fade out fully
        cx, cy = w // 2, int(h * 0.6)
        self.assertEqual(alpha.getpixel((cx, cy)), 255)
        self.assertGreaterEqual(mask.getpixel((cx, cy)), 250)  # building stays opaque
        out = HW.paste(Image.new("RGB", (w * 2, h * 2), (9, 9, 9)), alpha)
        self.assertEqual(out.size, (w, h))
        self.assertEqual(out.mode, "RGBA")

    def test_harmonise_crop_clamps_and_scales(self):
        cr = HW.crop_rect([0, 0, 2000, 500], 0.2, (2160, 3240))
        self.assertEqual(cr[:2], [0, 0])
        self.assertLessEqual(cr[0] + cr[2], 2160)

    def test_upload_argv_has_no_timeout(self):
        e = {"key": "u", "out": "o.png", "cmd": "upload",
             "args": {"file": "f.png", "spec": {"a": 1}}, "source_key": None}
        argv = B.build_argv(e, {})
        self.assertEqual(argv[:3], ["sectilia", "upload", "f.png"])
        self.assertNotIn("--timeout", argv)

    def test_check_bands_flags_translucent_box_only(self):
        import random
        from PIL import Image
        rnd = random.Random(3)
        w, h = 120, 80
        im = Image.new("RGB", (w, h))
        for y in range(h):
            for x in range(w):
                v = 90 + rnd.randrange(-25, 26)        # brushy grass texture
                im.putpixel((x, y), (v // 2, v, v // 2))
        clean = im.copy()
        for x in range(30, 60):                        # a natural partial-width edge
            for y in range(40, h):
                clean.putpixel((x, y), (200, 200, 190))
        self.assertEqual(CBD.find_bands(clean), [])
        boxed = Image.blend(im, Image.new("RGB", (w, h), (255, 205, 100)), 0.0)
        tint = Image.new("RGB", (w, h), (255, 205, 100))
        mask = Image.new("L", (w, h), 0)
        mask.paste(31, (0, 50, w, h))                  # 12% amber box, hard top edge
        boxed = Image.composite(tint, im, mask)
        bands = CBD.find_bands(boxed)
        self.assertTrue(bands and abs(bands[0][0] - 50) <= 3, bands)

    def test_parse_stdout_pretty_printed(self):
        out = '{\n  "id": "abc",\n  "status": "succeeded"\n}\n'
        self.assertEqual(B.parse_stdout(out)["id"], "abc")
        self.assertEqual(B.parse_stdout("noise\n" + out)["id"], "abc")
        self.assertEqual(B.parse_stdout(""), {})

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.jobs = os.path.join(self.tmp, "jobs.json")
        self.failed = os.path.join(self.tmp, "jobs_failed.json")
        p = mock.patch.object(C, "ROOT", self.tmp)
        p.start()
        self.addCleanup(p.stop)
        self.sleeps = []

    def go(self, entries, results, limit=None, retry=False):
        calls = []

        def runner(argv, timeout, on_job=None):
            calls.append(argv)
            return results.pop(0)

        counts, stop = B.run_manifest(entries, limit, self.jobs, runner,
                                      self.sleeps.append, log=lambda m: None,
                                      failed_path=self.failed, retry_failed=retry, workers=1)
        return counts, stop, calls

    def go_parallel(self, entries, behave, workers=3):
        """behave(key, argv, on_job) -> (code, data); the runner tracks how many
        commands run at once and the order they start/finish in."""
        import threading
        import time as _t
        lock = threading.Lock()
        live, peak, events = [0], [0], []

        def runner(argv, timeout, on_job=None):
            key = argv[argv.index("--out") + 1].rsplit("/", 1)[1][:-4]
            with lock:
                live[0] += 1
                peak[0] = max(peak[0], live[0])
                events.append(("start", key, argv[1]))
            _t.sleep(0.02)
            try:
                return behave(key, argv, on_job)
            finally:
                with lock:
                    live[0] -= 1
                    events.append(("end", key, argv[1]))
        counts, stop = B.run_manifest(entries, None, self.jobs, runner, self.sleeps.append,
                                      log=lambda m: None, failed_path=self.failed,
                                      workers=workers)
        return counts, stop, peak[0], events

    def test_parallel_runs_at_most_three_and_records_every_job(self):
        ents = [entry("g%d" % i) for i in range(9)]
        counts, stop, peak, _ = self.go_parallel(ents, lambda k, a, j: (0, {"id": "J" + k}))
        self.assertIsNone(stop)
        self.assertEqual(peak, 3)
        self.assertEqual(counts, {"done": 9, "skipped": 0, "failed": 0, "remaining": 0})
        jobs = B.load_jobs(self.jobs)
        self.assertEqual({k: jobs[k] for k in jobs if k != "_pending"},
                         {"g%d" % i: "Jg%d" % i for i in range(9)})
        self.assertEqual(jobs["_pending"], {})

    def test_workers_capped_at_three(self):
        ents = [entry("g%d" % i) for i in range(8)]
        _, _, peak, _ = self.go_parallel(ents, lambda k, a, j: (0, {"id": k}), workers=9)
        self.assertEqual(peak, 3)

    def test_edits_start_after_every_generate_and_their_source(self):
        ents = [entry("g1"), entry("e1", "edit", source="g1"), entry("g2"), entry("g3"),
                entry("e2", "edit", source="e1")]
        counts, stop, _, ev = self.go_parallel(ents, lambda k, a, j: (0, {"id": "J" + k}))
        self.assertEqual(counts["done"], 5)
        last_gen_end = max(i for i, x in enumerate(ev) if x[0] == "end" and x[2] == "generate")
        first_edit = min(i for i, x in enumerate(ev) if x[0] == "start" and x[2] == "edit")
        self.assertGreater(first_edit, last_gen_end)
        e1_end = ev.index(("end", "e1", "edit"))
        self.assertGreater(ev.index(("start", "e2", "edit")), e1_end)

    def test_edit_of_failed_generate_is_skipped(self):
        def behave(k, a, j):
            return (5, {"error": {"detail": {}}}) if k == "g1" else (0, {"id": k})
        ents = [entry("g1"), entry("g2"), entry("e1", "edit", source="g1"),
                entry("e2", "edit", source="g2")]
        counts, stop, _, ev = self.go_parallel(ents, behave)
        self.assertEqual((counts["done"], counts["failed"]), (2, 2))
        self.assertNotIn("e1", [x[1] for x in ev])

    def test_stop_lets_running_jobs_finish_and_starts_nothing_new(self):
        def behave(k, a, j):
            return (6, {"error": {"kind": "unavailable"}}) if k == "g0" else (0, {"id": k})
        ents = [entry("g%d" % i) for i in range(8)]
        counts, stop, _, ev = self.go_parallel(ents, behave)
        self.assertIn("unavailable", stop)
        started = [x[1] for x in ev if x[0] == "start"]
        self.assertLess(len(started), 8)
        self.assertEqual(counts["done"] + counts["failed"] + counts["remaining"], 8)
        jobs = B.load_jobs(self.jobs)
        for k in started:
            if k != "g0":
                self.assertEqual(jobs[k], k)

    def test_job_id_from_own_stderr_is_pending_while_running(self):
        seen = {}

        def behave(k, a, j):
            j("JOWN-" + k)
            seen[k] = dict(B.load_jobs(self.jobs)["_pending"])
            return 0, {"id": "JOWN-" + k}
        ents = [entry("g%d" % i) for i in range(3)]
        self.go_parallel(ents, behave)
        for k in ("g0", "g1", "g2"):
            self.assertEqual(seen[k][k], "JOWN-" + k)
        self.assertEqual(B.load_jobs(self.jobs)["_pending"], {})

    def test_submitted_false_job_id_is_never_recorded(self):
        noted = []
        res = [(7, {"error": {"job_id": "OTHER", "detail": {"submitted": False}}}),
               (0, {"id": "J"})]
        jid = B.run_entry(entry("a"), {}, lambda a, t, j=None: res.pop(0), lambda s: None,
                          None, noted.append)
        self.assertEqual((jid, noted), ("J", []))

    def test_run_reads_job_id_from_stderr(self):
        script = ("import sys,json;sys.stderr.write('waiting for earlier job e1e1e1e1-x\\n');"
                  "sys.stderr.write('job 0a1b2c3d-4e5f queued (0m00s)\\n');sys.stderr.flush();"
                  "print(json.dumps({'id': '0a1b2c3d-4e5f'}, indent=2))")
        got = []
        code, data = B.run([sys.executable, "-c", script], 30, got.append)
        self.assertEqual((code, data["id"], got), (0, "0a1b2c3d-4e5f", ["0a1b2c3d-4e5f"]))

    def test_unavailable_after_submit_waits_on_own_job(self):
        calls = []
        res = [(6, {"error": {"kind": "unavailable", "message": "could not download"}}),
               (0, {"id": "JD"})]

        def runner(argv, timeout, on_job=None):
            calls.append(argv[:3])
            if argv[1] == "generate":
                on_job("JD")
            return res.pop(0)
        jid = B.run_entry(entry("a"), {}, runner, self.sleeps.append)
        self.assertEqual((jid, calls[1], len(self.sleeps)), ("JD", ["sectilia", "wait", "JD"], 1))

    # sectilia 0.5.5, a slot still holding an earlier command's job (submit.py
    # _settle_recorded, then waiting.poll on that job):
    EARLIER = ("waiting for earlier job e1e1e1e1-0000-4000-8000-000000000001 to finish\n"
               "job e1e1e1e1-0000-4000-8000-000000000001 running (0m00s)\n")

    def fake_cli(self, stderr, stdout, code):
        """argv for a python process that prints like sectilia and exits `code`."""
        script = ("import sys,json\nsys.stderr.write(%r)\nsys.stderr.flush()\n"
                  "print(json.dumps(%r, indent=2))\nsys.exit(%d)\n" % (stderr, stdout, code))
        return [sys.executable, "-c", script]

    def test_run_skips_earlier_job_from_0_5_5_output(self):
        own = "0a0a0a0a-0000-4000-8000-00000000000a"
        argv = self.fake_cli(self.EARLIER + "job %s queued (0m00s)\n" % own, {"id": own}, 0)
        got = []
        code, data = B.run(argv, 30, got.append)
        self.assertEqual((code, got), (0, [own]))

    def test_exit7_waiting_behind_earlier_job_records_nothing_and_reruns(self):
        earlier = "e1e1e1e1-0000-4000-8000-000000000001"
        own = "0b0b0b0b-0000-4000-8000-00000000000b"
        calls, noted = [], []
        procs = [self.fake_cli(self.EARLIER, {"error": {"kind": "timeout", "job_id": earlier,
                                                        "detail": {"submitted": False}}}, 7),
                 self.fake_cli("job %s queued (0m00s)\n" % own, {"id": own}, 0)]

        def runner(argv, timeout, on_job=None):
            calls.append(argv[:2])
            return B.run(procs.pop(0), 30, on_job)
        jid = B.run_entry(entry("a"), {}, runner, self.sleeps.append, None, noted.append)
        self.assertEqual(jid, own)
        self.assertEqual(noted, [own])
        self.assertEqual([c[1] for c in calls], ["generate", "generate"])

    def test_exit7_drops_an_adopted_earlier_id(self):
        # a pending id equal to the job we were waiting behind is cleared, not waited on
        earlier = "e1e1e1e1-0000-4000-8000-000000000001"
        res = [(7, {"error": {"job_id": earlier, "detail": {"submitted": False}}}),
               (0, {"id": "OWN"})]
        calls, noted = [], []

        def runner(argv, timeout, on_job=None):
            calls.append(argv[:3])
            return res.pop(0)
        jid = B.run_entry(entry("a"), {}, runner, self.sleeps.append, earlier, noted.append)
        self.assertEqual(jid, "OWN")
        self.assertEqual(calls[0], ["sectilia", "wait", earlier])
        self.assertEqual(calls[1][:2], ["sectilia", "generate"])
        self.assertEqual(noted, [None])

    def test_post_error_still_records_the_job(self):
        e = entry("a")
        e["post"] = {"align_to": "x"}
        with mock.patch.object(B, "apply_post", side_effect=RuntimeError("boom")):
            counts, stop, calls = self.go([e], [(0, {"id": "JA"})])
        self.assertEqual(B.load_jobs(self.jobs)["a"], "JA")

    def test_job_id_in(self):
        self.assertEqual(B.job_id_in("job 9e588940-3f8a queued (0m03s)\n"), "9e588940-3f8a")
        self.assertIsNone(B.job_id_in("waiting for earlier job 9e588940-3f8a to finish"))
        self.assertIsNone(B.job_id_in("sectilia: your job queue is full; waiting"))

    def test_skip_existing_and_record(self):
        e1, e2 = entry("a"), entry("b")
        os.makedirs(os.path.join(self.tmp, "assets/map/_t"))
        open(os.path.join(self.tmp, e1["out"]), "w").close()
        counts, stop, calls = self.go([e1, e2], [(0, {"id": "J2"})])
        self.assertEqual(counts, {"done": 1, "skipped": 1, "failed": 0, "remaining": 0})
        self.assertEqual(len(calls), 1)
        self.assertEqual(B.load_jobs(self.jobs)["b"], "J2")

    def test_edit_resolves_source_and_limit(self):
        B.save_jobs({"a": "JA"}, self.jobs)
        counts, _, calls = self.go([entry("e", "edit", source="a"), entry("f")],
                                   [(0, {"id": "JE"})], limit=1)
        self.assertEqual(calls[0][:3], ["sectilia", "edit", "JA"])
        self.assertEqual(counts["remaining"], 1)

    def test_missing_source_fails_entry(self):
        counts, stop, calls = self.go([entry("e", "edit", source="nope")], [])
        self.assertEqual(counts["failed"], 1)
        self.assertEqual(calls, [])

    def test_exit_3_and_6_stop_batch(self):
        for code in (3, 6):
            counts, stop, calls = self.go([entry("a%d" % code), entry("z%d" % code)],
                                          [(code, {"error": {"kind": "x"}})])
            self.assertIsNotNone(stop)
            self.assertEqual(len(calls), 1)
            self.assertEqual(counts["remaining"], 1)

    def test_exit_4_5_skip_without_retry(self):
        counts, stop, calls = self.go(
            [entry("a"), entry("b"), entry("c")],
            [(4, {"error": {"detail": {}}}), (5, {"error": {"detail": {}}}), (0, {"id": "J"})])
        self.assertIsNone(stop)
        self.assertEqual((counts["done"], counts["failed"]), (1, 2))
        self.assertEqual(len(calls), 3)

    def test_insufficient_credits_stops(self):
        counts, stop, _ = self.go([entry("a"), entry("b")],
                                  [(4, {"error": {"detail": {"reason": "insufficient_credits"}}})])
        self.assertIn("credits", stop)

    def test_exit_7_submitted_true_waits(self):
        err = {"error": {"job_id": "JX", "detail": {"submitted": True}}}
        counts, stop, calls = self.go([entry("a")], [(7, err), (0, {"id": "JX"})])
        self.assertEqual(calls[1][:3], ["sectilia", "wait", "JX"])
        self.assertEqual(B.load_jobs(self.jobs)["a"], "JX")
        self.assertEqual(B.load_jobs(self.jobs)["_pending"], {})

    def test_exit_7_submitted_false_reruns_same_command(self):
        err = {"error": {"job_id": "OTHER", "detail": {"submitted": False}}}
        counts, stop, calls = self.go([entry("a")], [(7, err), (0, {"id": "J"})])
        self.assertEqual(calls[0], calls[1])
        self.assertEqual(len(self.sleeps), 1)
        self.assertEqual(counts["done"], 1)

    def test_local_timeout_with_known_job_waits_on_it(self):
        import subprocess
        calls = []
        results = [subprocess.TimeoutExpired("sectilia", 1), (0, {"id": "JX"})]

        def runner(argv, timeout, on_job=None):
            calls.append(argv[:3])
            if argv[1] == "generate":
                on_job("JX")
            r = results.pop(0)
            if isinstance(r, Exception):
                raise r
            return r
        counts, stop = B.run_manifest([entry("a")], None, self.jobs, runner, lambda s: None,
                                      lambda m: None, self.failed)
        self.assertIsNone(stop)
        self.assertEqual(calls[1], ["sectilia", "wait", "JX"])
        self.assertEqual(B.load_jobs(self.jobs)["a"], "JX")

    def test_local_timeout_without_job_id_stops_and_resumes_pending(self):
        import subprocess

        def runner(argv, timeout, on_job=None):
            raise subprocess.TimeoutExpired("sectilia", 1)
        B.save_jobs({"_pending": {"b": "JB"}}, self.jobs)
        counts, stop = B.run_manifest([entry("a")], None, self.jobs, runner, lambda s: None,
                                      lambda m: None, self.failed)
        self.assertIn("local timeout", stop)
        self.assertEqual(B.load_jobs(self.jobs)["_pending"], {"b": "JB"})
        # a pending job resumes with wait, not a resubmit
        calls = []

        def runner2(argv, timeout, on_job=None):
            calls.append(argv)
            return 0, {"id": "JB"}
        counts, stop = B.run_manifest([entry("b")], None, self.jobs, runner2, lambda s: None,
                                      lambda m: None, self.failed)
        self.assertEqual(calls[0][:3], ["sectilia", "wait", "JB"])
        self.assertEqual(counts["done"], 1)
        self.assertEqual(B.load_jobs(self.jobs)["_pending"], {})

    def test_wait_rounds_exceeded_keeps_pending(self):
        err = (7, {"error": {"job_id": "JX", "detail": {"submitted": True}}})
        counts, stop, calls = self.go([entry("a")], [err] * (B.MAX_WAIT_ROUNDS + 1))
        self.assertEqual(counts["failed"], 1)
        self.assertEqual(B.load_jobs(self.jobs)["_pending"], {"a": "JX"})
        counts, _, calls = self.go([entry("a")], [(0, {"id": "JX"})])
        self.assertEqual(calls[0][:3], ["sectilia", "wait", "JX"])

    def test_exit_5_recorded_and_not_resubmitted(self):
        fail = (5, {"error": {"detail": {}}})
        counts, _, calls = self.go([entry("a")], [fail])
        self.assertEqual(counts["failed"], 1)
        self.assertIn("a", B.load_failed(self.failed))
        counts, _, calls = self.go([entry("a")], [])
        self.assertEqual((calls, counts["failed"]), ([], 1))
        counts, _, calls = self.go([entry("a")], [(0, {"id": "J"})], retry=True)
        self.assertEqual((len(calls), counts["done"]), (1, 1))

    def test_dry_run_shows_source_key(self):
        argv = B.build_argv(entry("e", "edit", source="el_x_0"), {}, dry=True)
        self.assertEqual(argv[2], "<job:el_x_0>")


class PlaceElementsTests(unittest.TestCase):
    def els(self, n):
        out = [{"id": "99_%03d" % i, "looks": [], "beat": None} for i in range(n)]
        out[-1]["beat"] = "beat_x"
        return out

    def test_layout_fits_floor_without_overlap_and_star_centred(self):
        floor = (40.0, 400.0, 680.0, 1240.0)
        els = self.els(14)
        rows = PE.layout(els, floor, 330, 16)
        self.assertIsNotNone(rows)
        placed = PE.assign(rows, floor, 16)
        self.assertEqual(len(placed), 14)
        boxes = []
        for e in els:
            cx, by, size = placed[e["id"]]
            w = h = 200.0 * size / 384
            boxes.append((cx - w / 2, by - h, cx + w / 2, by))
            self.assertTrue(floor[0] - 1 <= cx - w / 2 and cx + w / 2 <= floor[2] + 1)
            self.assertTrue(floor[1] - 1 <= by - h and by <= floor[3] + 1)
        for i, a in enumerate(boxes):
            for b in boxes[i + 1:]:
                self.assertFalse(a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3])
        star = placed[els[-1]["id"]]
        self.assertAlmostEqual(star[0], 360, delta=40)

    def test_wall_keeps_back_row_bases_on_floor(self):
        floor = (40.0, 300.0, 680.0, 1240.0)
        els = self.els(14)
        rows = PE.layout(els, floor, 330, 16, wall=520.0)
        placed = PE.assign(rows, floor, 16, wall=520.0)
        self.assertGreaterEqual(min(p[1] for p in placed.values()), 520 - 1)

    def test_hanging_items_go_high_and_star_centred(self):
        floor = (40.0, 500.0, 680.0, 1240.0)
        els = self.els(10)
        hang = {els[2]["id"], els[-1]["id"]}
        placed = PE.place(els, floor, 330, 16, None, hang, (60.0, 400.0), 0)
        for h in hang:
            cx, by, size = placed[h]
            self.assertLessEqual(by, 400 + 1)
            self.assertGreaterEqual(by - 200.0 * size / 384, 60 - 1)
        self.assertAlmostEqual(placed[els[-1]["id"]][0], 360, delta=60)
        for e in els:
            if e["id"] not in hang:
                self.assertGreaterEqual(placed[e["id"]][1], 500)

    def test_star_at_puts_the_star_near_the_back_of_a_tall_room(self):
        floor = (40.0, 400.0, 680.0, 2860.0)
        els = self.els(29)
        placed = PE.place(els, floor, 330, 12, star_at=0.15)
        star_y = placed[els[-1]["id"]][1]
        self.assertLess(star_y, 1280)
        self.assertAlmostEqual(placed[els[-1]["id"]][0], 360, delta=40)
        mid = PE.place(els, floor, 330, 12)
        self.assertGreater(mid[els[-1]["id"]][1], 1280)

    def test_hang_x_limits_the_hanging_row(self):
        floor = (40.0, 500.0, 680.0, 1240.0)
        els = self.els(6)
        hang = {els[0]["id"], els[1]["id"]}
        placed = PE.place(els, floor, 330, 16, None, hang, (60.0, 400.0), 0, hang_x=(60.0, 400.0))
        for h in hang:
            cx, by, size = placed[h]
            self.assertLessEqual(cx + 100.0 * size / 384, 400 + 1)

    def test_min_px_shrinks_gap_first(self):
        floor = (0.0, 0.0, 640.0, 640.0)
        els = self.els(16)
        wide = PE.layout(els, floor, 330, 40)
        placed = PE.place(els, floor, 330, 40, min_px=PE.min_side(wide) + 5)
        sizes = {p[2] for p in placed.values()}
        self.assertGreater(min(sizes) * 200.0 / 384, PE.min_side(wide))

    def test_to_pos_shifts_by_sprite_padding(self):
        # a sprite whose opaque box ends 96 canvas px above the bottom and sits
        # 48 px right of centre: at size 192 (half scale) pos moves 48 down, 24 left
        got = PE.to_pos({"a": (300, 800, 192)}, {"a": (48.0, 96.0)})
        self.assertEqual(got["a"], (276, 848, 192))

    def test_subroom_selects_one_room(self):
        allel = [{"id": "23_001", "area": 23, "subroom": 0}, {"id": "23_002", "area": 23, "subroom": 1},
                 {"id": "24_001", "area": 24, "subroom": 0}]
        self.assertEqual([e["id"] for e in PE.wing_elements(allel, 23, 1)], ["23_002"])
        self.assertEqual([e["id"] for e in PE.wing_elements(allel, 23, 0)], ["23_001"])
        self.assertEqual([e["id"] for e in PE.wing_elements(allel, 23)], ["23_001", "23_002"])

    def test_too_many_for_floor_still_shrinks_to_fit(self):
        rows = PE.layout(self.els(30), (0.0, 0.0, 300.0, 300.0), 330, 8)
        self.assertIsNotNone(rows)


if __name__ == "__main__":
    unittest.main()
