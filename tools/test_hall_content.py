import json
import os
import unittest

import check_hall_content as c

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def look(name, body):
    return {"name": name, "instruction": (body + c.SUFFIX) if body else None}


def element(i, name="The Test Thing", subject=None, area=5, l1=None, l2=None):
    subject = subject or "a small carved oak box with a brass hinge and a worn velvet lining, resting on its own"
    l1 = l1 or look("Rosewood %d" % i, "make the box dark polished rosewood with a pearl inlaid lid and tidy green velvet %d" % i)
    l2 = l2 or look("Painted %d" % i, "make the box painted deep teal with tiny cream flowers and a bright brass catch %d" % i)
    return {"id": "%02d_%03d" % (area, i), "area": area, "name": "%s %d" % (name, i), "subject": subject,
            "looks": [look("Plain oak", None), l1, l2]}


class CheckHallContentTest(unittest.TestCase):
    def test_clean_elements_pass(self):
        problems, stats = c.check([element(1), element(2)])
        self.assertEqual(problems, [])
        self.assertEqual(stats["metal_looks"], 0)

    def test_both_metal_swaps_fail(self):
        gild = look("Gilded", "make the box gilded with a gold trim and a ruby latch on its lid and hinges")
        silver = look("Silver", "make the box polished silver with a fine blue enamel band and clasp")
        problems, stats = c.check([element(1, l1=gild, l2=silver)])
        self.assertEqual(stats["both_metal_elements"], 1)
        self.assertTrue(any("both looks are metal" in p for p in problems))

    def test_both_looks_mentioning_gold_or_silver_fail(self):
        a = look("Ruby", "make the box deep ruby red lacquer with a gold line round the lid and tidy hinges")
        b = look("Teal", "make the box deep teal with tiny cream flowers and a silver catch on the front")
        problems, _ = c.check([element(1, l1=a, l2=b)])
        self.assertTrue(any("both looks mention gold or silver" in p for p in problems))

    def test_metal_share_cap(self):
        gild = look("Gilded", "make the box gilded with a gold trim and a ruby latch on its lid and hinges")
        els = [element(i, l1=gild) for i in range(1, 6)] + [element(i) for i in range(6, 9)]
        problems, stats = c.check(els)
        self.assertGreater(stats["metal_share"], c.MAX_METAL_LOOK_SHARE)
        self.assertTrue(any("metal-swap looks" in p for p in problems))

    def test_area_two_is_exempt(self):
        gild = look("Gilded", "make it gold")
        silver = look("Silver", "make it silver")
        problems, _ = c.check([element(1, area=2, l1=gild, l2=silver, subject="a bust of a man")])
        self.assertEqual(problems, [])

    def test_thin_look_and_subject(self):
        short = look("Short", "make the box red and shiny")
        problems, stats = c.check([element(1, l1=short, subject="a small oak box")])
        self.assertEqual(stats["thin_looks"], 1)
        self.assertEqual(stats["thin_subjects"], 1)
        self.assertTrue(any(p.startswith("thin look") for p in problems))
        self.assertTrue(any(p.startswith("thin subject") for p in problems))

    def test_scene_subject_fails(self):
        scene = "a small carved oak box on a table by a window with a long street seen beyond the glass"
        problems, stats = c.check([element(1, subject=scene)])
        self.assertEqual(stats["scene_subjects"], 1)
        self.assertTrue(any("scene word" in p for p in problems))

    def test_placement_phrases_fail(self):
        base = "a small carved oak box with a brass hinge and a worn velvet lining, %s"
        for phrase in ["at the foot of a stone stair", "beside a tall brass lamp", "leaning against a wall",
                       "next to a pile of crates", "set into a stone floor", "in a corner of the room",
                       "surrounded by bookshelves", "on the floor"]:
            problems, stats = c.check([element(1, subject=base % phrase)])
            self.assertEqual(stats["scene_subjects"], 1, phrase)
        problems, stats = c.check([element(1, subject=base % "resting on its own small wooden stand")])
        self.assertEqual(stats["scene_subjects"], 0)

    def test_placement_families_fail(self):
        base = "a small carved oak box with a brass hinge and a worn velvet lining, %s"
        families = {
            "floor": ["on a sawdust floor", "set in the floor", "onto the floor", "across the ground", "in the grass"],
            "surface": ["on a table", "on a small library table", "pinned flat on a desk", "on a shelf"],
            "corner": ["in a quiet corner", "in an alcove", "in a stone niche", "in a stone arch", "in a shadowy corner"],
            "water": ["by the water", "at the water's edge", "near the water", "beside the pool"],
            "stairs": ["halfway up the tower stair", "at the foot of a stair", "above the stairwell", "on the stair"],
            "companion": ["with a brush beside it", "with a cup next to it", "laid alongside a cloth", "with a jug nearby"],
        }
        for family, phrases in families.items():
            for phrase in phrases:
                _, stats = c.check([element(1, subject=base % phrase)])
                self.assertEqual(stats["scene_subjects"], 1, family + ": " + phrase)

    def test_object_with_own_base_passes(self):
        base = "a small carved oak box with a brass hinge and a worn velvet lining, %s"
        for phrase in ["on a square stone plinth", "on its own small wooden stand", "on a short pedestal",
                       "with a brass catch tied to its lid", "mounted on a round iron base plate"]:
            _, stats = c.check([element(1, subject=base % phrase)])
            self.assertEqual(stats["scene_subjects"], 0, phrase)

    def test_people_word_fails(self):
        subject = "a small carved oak box with a brass hinge and a woman's glove folded on top of its lid"
        problems, _ = c.check([element(1, subject=subject)])
        self.assertTrue(any("people word" in p for p in problems))

    def test_look_name_cap_and_duplicate_instruction(self):
        els = [element(i, l1=look("Same name", "make the box %s with a brass latch and a tidy velvet lining" % w))
               for i, w in enumerate(["red", "blue", "green", "white"], 1)]
        problems, _ = c.check(els)
        self.assertTrue(any("look name used 4 times" in p for p in problems))
        dup = [element(1), element(2)]
        for e in dup:
            e["looks"][1] = look("Rosewood", "make the box dark polished rosewood with a pearl inlaid lid and tidy green velvet")
        problems, _ = c.check(dup)
        self.assertTrue(any("identical look instruction" in p for p in problems))

    def test_real_config_is_clean(self):
        with open(os.path.join(ROOT, "config", "curio_hall_elements.json")) as f:
            els = json.load(f)
        problems, stats = c.check(els)
        self.assertEqual(problems, [])
        self.assertEqual(stats["elements"], 1408)


if __name__ == "__main__":
    unittest.main()
