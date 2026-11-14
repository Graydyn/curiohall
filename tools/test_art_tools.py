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
                self.assertEqual(e["args"]["style_keys"], ["style_core_1"])
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
        self.assertEqual(m["ext_01_restored"]["args"]["spec"]["canvas_size"], [1024, 512])

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
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.jobs = os.path.join(self.tmp, "jobs.json")
        p = mock.patch.object(C, "ROOT", self.tmp)
        p.start()
        self.addCleanup(p.stop)
        self.sleeps = []

    def go(self, entries, results, limit=None):
        calls = []

        def runner(argv, timeout):
            calls.append(argv)
            return results.pop(0)

        counts, stop = B.run_manifest(entries, limit, self.jobs, runner,
                                      self.sleeps.append, log=lambda m: None)
        return counts, stop, calls

    def test_skip_existing_and_record(self):
        e1, e2 = entry("a"), entry("b")
        os.makedirs(os.path.join(self.tmp, "assets/map/_t"))
        open(os.path.join(self.tmp, e1["out"]), "w").close()
        counts, stop, calls = self.go([e1, e2], [(0, {"id": "J2"})])
        self.assertEqual(counts, {"done": 1, "skipped": 1, "failed": 0, "remaining": 0})
        self.assertEqual(len(calls), 1)
        self.assertEqual(B.load_jobs(self.jobs), {"b": "J2"})

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
        self.assertEqual(B.load_jobs(self.jobs), {"a": "JX"})

    def test_exit_7_submitted_false_reruns_same_command(self):
        err = {"error": {"job_id": "OTHER", "detail": {"submitted": False}}}
        counts, stop, calls = self.go([entry("a")], [(7, err), (0, {"id": "J"})])
        self.assertEqual(calls[0], calls[1])
        self.assertEqual(len(self.sleeps), 1)
        self.assertEqual(counts["done"], 1)

    def test_dry_run_shows_source_key(self):
        argv = B.build_argv(entry("e", "edit", source="el_x_0"), {}, dry=True)
        self.assertEqual(argv[2], "<job:el_x_0>")


if __name__ == "__main__":
    unittest.main()
