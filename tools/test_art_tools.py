import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402
import art_manifest as M  # noqa: E402
import sectilia_batch as B  # noqa: E402


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
                self.assertNotIn("style_keys", e["args"])
                self.assertEqual(e["args"]["theme"], C.STYLE_THEME)
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

    def test_generate_argv_never_has_style(self):
        for kind in ("elements", "portraits", "exterior-wings"):
            for sp in (False, True):
                for e in M.build(kind, {1}, ["s1"], sp):
                    if e["cmd"] == "generate":
                        argv = B.build_argv(e, {"s1": "J"})
                        self.assertNotIn("--style", argv)
                        self.assertIn("--theme", argv)
                    elif e["cmd"] == "edit" and e["args"].get("style_keys"):
                        argv = B.build_argv(e, {"s1": "J", e["source_key"]: "S"})
                        self.assertIn("--style", argv)

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
