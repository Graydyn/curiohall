import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_story  # noqa: E402


def beat(speaker, text):
    return {"lines": [{"speaker": speaker, "expr": "neutral", "text": text}]}


class RepetitionGuardTest(unittest.TestCase):
    def test_flags_repeated_four_word_opener(self):
        entries = [(a, beat("cornelia", "The great hall is quiet today.")) for a in range(1, 4)]
        problems = check_story.repetition_problems(entries)
        self.assertTrue(any("4-word opener" in p for p in problems))

    def test_allows_distinct_openers(self):
        speakers = ["cornelia", "barnaby", "aldous", "sam", "mark"]
        entries = [(1, beat(s, "Opener number %d goes here today." % i)) for i, s in enumerate(speakers)]
        self.assertEqual(check_story.repetition_problems(entries), [])

    def test_flags_dominant_first_speaker_in_a_wing(self):
        entries = [(7, beat("hugo", "Line %d opens differently for testing." % i)) for i in range(6)]
        problems = check_story.repetition_problems(entries)
        self.assertTrue(any("wing 7" in p and "hugo" in p for p in problems))

    def test_small_wings_are_exempt_from_share_check(self):
        entries = [(7, beat("hugo", "Line %d opens differently for testing." % i)) for i in range(4)]
        self.assertEqual(check_story.repetition_problems(entries), [])

    def test_template_opening_detected(self):
        self.assertTrue(check_story.is_template_opening("The Pin Board. Hundreds of pins.", "The Pin Board"))
        self.assertTrue(check_story.is_template_opening("The Founder's Hat Stand. Dark oak.", "The Founder's Hat Stand"))
        self.assertFalse(check_story.is_template_opening("Miss Wren, look at the Pin Board!", "The Pin Board"))
        self.assertFalse(check_story.is_template_opening("The kettle is on. Do come in.", "The Pin Board"))

    def test_template_share_capped(self):
        pairs = [("The Pin Board", beat("cornelia", "The Pin Board. Hundreds of pins."))] * 4
        self.assertTrue(check_story.template_problems(pairs))
        mixed = pairs[:1] + [("The Pin Board", beat("sam", "Do look at this pin board, darling."))] * 4
        self.assertEqual(check_story.template_problems(mixed), [])

    def test_panel_cast_before_arrival_flagged(self):
        first = {13: 44}
        panels = [
            {"id": "chron", "trigger": "task:47_11", "cast": ["zephyrine", "cornelia"],
             "panels": [{"caption": "a"}]},
            {"id": "open13", "trigger": "area_opened:13", "cast": ["cornelia"],
             "panels": [{"caption": "b", "cast": ["prudence"]}]},
            {"id": "arr", "trigger": "day:90", "cast": ["zephyrine"], "panels": [{"caption": "c"}]},
        ]
        problems = check_story.panel_cast_problems(panels, first)
        self.assertEqual(len(problems), 2)
        self.assertIn("chron_0 (day 47) shows zephyrine", problems[0])
        self.assertIn("open13_0 (day 44) shows prudence", problems[1])

    def test_panel_day(self):
        self.assertEqual(check_story.panel_day("day:60", {}), 60)
        self.assertEqual(check_story.panel_day("task:52_11", {}), 52)
        self.assertEqual(check_story.panel_day("area_opened:14", {14: 48}), 48)
        self.assertIsNone(check_story.panel_day("element:02_001", {}))

    def test_real_story_config_has_no_problems(self):
        problems, _beats, _panels = check_story.check()
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
