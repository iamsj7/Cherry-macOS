import importlib.util
import pathlib
import unittest


SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "scripts" / "release_notes.py"
SPEC = importlib.util.spec_from_file_location("release_notes", SCRIPT)
release_notes = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_notes)


class LatestReleaseTests(unittest.TestCase):
    def test_no_version_does_not_publish(self):
        self.assertIsNone(release_notes.latest_release("# Changelog\n\nNo entries yet.\n"))

    def test_newest_entry_supplies_version_and_notes(self):
        changelog = """# Changelog

## [0.2.0] - 2026-10-03

- New port filter.

## [0.1.0] - 2026-10-01

- Initial release.
"""
        self.assertEqual(
            release_notes.latest_release(changelog),
            ("0.2.0", "- New port filter."),
        )

    def test_empty_entry_is_rejected(self):
        with self.assertRaises(ValueError):
            release_notes.latest_release("## [0.2.0] - 2026-10-03\n")


if __name__ == "__main__":
    unittest.main()
