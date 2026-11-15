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

    def test_real_story_config_has_no_problems(self):
        problems, _beats, _panels = check_story.check()
        self.assertEqual(problems, [])


if __name__ == "__main__":
    unittest.main()
