import json
import os
import random
import sys
import tempfile
import unittest
from unittest import mock

from PIL import Image, ImageChops, ImageDraw, ImageEnhance

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_common as C  # noqa: E402
import hall_states as HS  # noqa: E402


def _scene(seed=1, size=(320, 200), dark_windows=False, shift=(0, 0)):
    """A synthetic 'painting': textured lawn, a building block with windows."""
    rnd = random.Random(seed)
    im = Image.new("RGB", size, (60, 110, 60))
    d = ImageDraw.Draw(im)
    for _ in range(400):
        x, y = rnd.randrange(size[0]), rnd.randrange(size[1])
        d.line((x, y, x + 2, y - 4), fill=(40 + rnd.randrange(40), 100 + rnd.randrange(40), 50))
    ox, oy = shift
    d.rectangle((80 + ox, 50 + oy, 240 + ox, 150 + oy), fill=(220, 200, 170))
    d.polygon((70 + ox, 50 + oy, 160 + ox, 15 + oy, 250 + ox, 50 + oy), fill=(30, 90, 90))
    for i in range(5):
        x = 95 + ox + i * 30
        d.rectangle((x, 70 + oy, x + 14, 100 + oy),
                    fill=(40, 35, 30) if dark_windows else (250, 190, 90))
    return im


class HallStatesTests(unittest.TestCase):
    def test_drift_passes_state_change_and_fails_reframe(self):
        src = _scene()
        ok = HS.drift(src, _scene(dark_windows=True))
        self.assertTrue(ok["ok"], ok)
        moved = HS.drift(src, ImageChops.offset(_scene(dark_windows=True), 12, 8))
        self.assertFalse(moved["ok"], moved)
        self.assertGreater(moved["shift_px"], 6)

    def test_drift_fails_global_tone_swallow(self):
        src = _scene()
        dark = ImageEnhance.Brightness(_scene(dark_windows=True)).enhance(0.45)
        self.assertFalse(HS.drift(src, dark)["ok"])

    def test_check_tile_passes_state_edit_fails_reframe(self):
        src = _scene()
        meta = {"name": "t", "rect": [0, 0, 320, 200], "size": [320, 200], "kind": "boarded"}
        wings = [{"area": 9, "exterior_rect": [60, 30, 220, 140]}]
        good = HS.check_tile(meta, src, _scene(dark_windows=True), wings)
        self.assertTrue(good["ok"], good)
        self.assertGreater(good["kept_corr"], 0.95)
        bad = HS.check_tile(meta, src, ImageChops.offset(_scene(dark_windows=True), 12, 8), wings)
        self.assertFalse(bad["ok"], bad)

    def test_correlation_identity(self):
        g = HS.edges(HS._grey(_scene(), 160))
        self.assertAlmostEqual(HS.correlation(g, g), 1.0, places=6)

    def test_change_mask_finds_windows_not_noise(self):
        a, b = _scene(seed=1), _scene(seed=1, dark_windows=True)
        m = HS.change_mask(a, b)
        self.assertGreater(m.getpixel((102, 85)), 200)     # a window
        self.assertEqual(m.getpixel((20, 180)), 0)        # lawn
        self.assertEqual(m.getpixel((160, 130)), 0)       # plain wall

    def test_boarded_mask_ignores_painted_sky(self):
        master = _scene(seed=4)
        locked = _scene(seed=4, dark_windows=True)
        ImageDraw.Draw(locked).rectangle((0, 0, 60, 60), fill=(120, 160, 210))  # sky over lawn
        wings = [{"area": 5, "exterior_rect": [0, 0, 320, 200]}]
        tiles = {"t": {"rect": [0, 0, 320, 200], "kind": "boarded"}}
        base, _, _ = HS.compose(master, wings, tiles, {"t": locked})
        self.assertEqual(base.getpixel((30, 30)), master.getpixel((30, 30)))
        self.assertLess(sum(base.getpixel((102, 85))), 200)

    def test_section_fade_zero_at_edges(self):
        m = HS.section_fade((120, 90))
        for pt in ((0, 0), (119, 89), (0, 45), (60, 0)):
            self.assertLess(m.getpixel(pt), 20)
        self.assertEqual(m.getpixel((60, 45)), 255)

    def test_rect_problems(self):
        rows = [{"area": 1, "exterior_rect": [0, 0, 300, 300]},
                {"area": 2, "exterior_rect": [300, 0, 300, 300]},   # touching is fine
                {"area": 3, "exterior_rect": [250, 250, 300, 300]},  # overlaps 1 and 2
                {"area": 4, "exterior_rect": [900, 0, 150, 400]}]    # too narrow
        probs = HS.rect_problems(rows)
        self.assertIn("areas 1 and 3 overlap", probs)
        self.assertIn("areas 2 and 3 overlap", probs)
        self.assertEqual(sum("smaller" in p for p in probs), 1)
        self.assertEqual(len(probs), 3)

    def test_tile_for_picks_containing_tile_with_most_room(self):
        tiles = {"a": {"rect": [0, 0, 500, 500]}, "b": {"rect": [200, 0, 600, 600]}}
        self.assertEqual(HS.tile_for([350, 250, 100, 100], tiles), "b")
        self.assertEqual(HS.tile_for([10, 10, 100, 100], tiles), "a")
        self.assertIsNone(HS.tile_for([700, 700, 100, 100], tiles))
        # A tile listing its wings serves only those, and wins for them.
        tiles["c"] = {"rect": [300, 100, 120, 120], "areas": [7]}
        self.assertEqual(HS.tile_for([310, 110, 100, 100], tiles, 7), "c")
        self.assertEqual(HS.tile_for([310, 110, 100, 100], tiles, 8), "b")

    def test_compose_restored_over_base_gives_master(self):
        master = _scene(seed=3)
        locked = _scene(seed=3, dark_windows=True)
        wings = [{"area": 5, "exterior_rect": [60, 30, 200, 140]}]
        tiles = {"t": {"rect": [0, 0, 320, 200], "kind": "boarded"}}
        base, restored, rep = HS.compose(master, wings, tiles, {"t": locked})
        self.assertGreater(rep[5]["coverage"], 0.05)
        # Base is boarded inside the wing, master outside it.
        self.assertLess(sum(base.getpixel((102, 85))), 200)
        self.assertEqual(base.getpixel((10, 10)), master.getpixel((10, 10)))
        # Restored drawn over the base brings back the master's windows.
        over = base.convert("RGBA")
        over.alpha_composite(restored[5], (60, 30))
        self.assertGreater(sum(over.getpixel((102, 85))[:3]), 450)
        self.assertEqual(restored[5].size, (200, 140))

    def test_real_config_rects_are_valid(self):
        self.assertEqual(HS.rect_problems(C.wings()), [])

    def test_manifest_upload_then_edit(self):
        with tempfile.TemporaryDirectory() as d:
            with mock.patch.object(HS, "_p", lambda rel: os.path.join(d, os.path.basename(rel))):
                json.dump({"name": "t1", "rect": [0, 0, 10, 10], "size": [10, 10],
                           "kind": "empty"}, open(os.path.join(d, "t1.json"), "w"))
                man = HS.build_manifest(["t1"])
        self.assertEqual([e["cmd"] for e in man], ["upload", "edit"])
        self.assertEqual(man[1]["source_key"], man[0]["key"])
        self.assertEqual(man[1]["args"]["instruction"], HS.INSTR["empty"])
        self.assertEqual(man[1]["key"], "hall_t1_empty")


if __name__ == "__main__":
    unittest.main()
