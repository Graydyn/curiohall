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
        self.assertEqual(len(M.build("portraits")), 41)

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

    def test_local_timeout_records_recovered_job(self):
        import subprocess
        with mock.patch.object(C, "ROOT", REAL_ROOT):
            e = M.build("elements", {1}, ["s1"])[0]
        calls = []

        def runner(argv, timeout):
            calls.append(argv[:2])
            if argv[1] == "generate":
                raise subprocess.TimeoutExpired(argv, timeout)
            import time as _t
            iso = _t.strftime("%Y-%m-%dT%H:%M:%SZ", _t.gmtime(_t.time()))
            return 0, {"jobs": [{"id": "JX", "created_at": iso, "request": {"kind": "generate"}}]}
        noted = []
        with self.assertRaises(B.StopBatch):
            B.run_entry(e, {"s1": "J"}, runner, lambda s: None, None, noted.append)
        self.assertEqual(noted, ["JX"])

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

    def test_newest_job_since(self):
        import time as _t
        now = _t.time()
        iso = _t.strftime("%Y-%m-%dT%H:%M:%SZ", _t.gmtime(now))
        data = {"jobs": [{"id": "J1", "created_at": iso, "request": {"kind": "generate"}}]}
        self.assertEqual(B.newest_job_since(now - 10, "generate", lambda a, t: (0, data)), "J1")
        self.assertIsNone(B.newest_job_since(now + 100, "generate", lambda a, t: (0, data)))
        self.assertIsNone(B.newest_job_since(now - 10, "edit", lambda a, t: (0, data)))

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

        def runner(argv, timeout):
            calls.append(argv)
            return results.pop(0)

        counts, stop = B.run_manifest(entries, limit, self.jobs, runner,
                                      self.sleeps.append, log=lambda m: None,
                                      failed_path=self.failed, retry_failed=retry)
        return counts, stop, calls

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

    def test_local_timeout_stops_cleanly_and_keeps_pending(self):
        import subprocess
        err = {"error": {"job_id": "JX", "detail": {"submitted": True}}}
        results = [(7, err), subprocess.TimeoutExpired("sectilia", 1)]

        def runner(argv, timeout):
            r = results.pop(0)
            if isinstance(r, Exception):
                raise r
            return r
        counts, stop = B.run_manifest([entry("a")], None, self.jobs, runner, lambda s: None,
                                      lambda m: None, self.failed)
        self.assertIn("local timeout", stop)
        self.assertEqual(B.load_jobs(self.jobs)["_pending"], {"a": "JX"})
        # next run resumes with wait, not a resubmit
        calls = []

        def runner2(argv, timeout):
            calls.append(argv)
            return 0, {"id": "JX"}
        counts, stop = B.run_manifest([entry("a")], None, self.jobs, runner2, lambda s: None,
                                      lambda m: None, self.failed)
        self.assertEqual(calls[0][:3], ["sectilia", "wait", "JX"])
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


if __name__ == "__main__":
    unittest.main()
