import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from compose_release_notes import compose

SHA = "abc123"
REPO = "o/r"
RAW = f"https://raw.githubusercontent.com/{REPO}/{SHA}/docs/images/v1/"


class ComposeTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        (self.root / "docs/releases").mkdir(parents=True)
        (self.root / "docs/images/v1").mkdir(parents=True)
        (self.root / "docs/images/v1/a.png").write_bytes(b"x")
        self.assets = self.root / "rel"
        self.assets.mkdir()
        self.warnings = []

    def run_it(self, text):
        (self.root / "docs/releases/v1.md").write_text(text, encoding="utf-8")
        return compose("1", SHA, REPO, "v1", self.assets, self.root, self.warnings.append)

    def test_no_notes_file(self):
        self.assertIsNone(compose("2", SHA, REPO, "v2", self.assets, self.root, self.warnings.append))

    def test_relative_images_point_at_the_commit(self):
        out = self.run_it('<img src="../images/v1/a.png" alt="A" width="9"/>\n![b](../images/v1/a.png)\n')
        self.assertEqual(out.count(RAW + "a.png"), 2)
        self.assertIn('alt="A" width="9"', out)
        self.assertEqual(self.warnings, [])

    def test_missing_image_block_is_removed_and_reported(self):
        out = self.run_it('Before\n<p align="center">\n  <img src="../images/v1/no.png"/>\n</p>\nAfter\n')
        self.assertEqual(out, "Before\nAfter\n")
        self.assertEqual(len(self.warnings), 1)

    def test_missing_bare_image_is_removed(self):
        self.assertEqual(self.run_it("A ![x](no.png) B"), "A  B")
        self.assertEqual(len(self.warnings), 1)

    def test_image_outside_the_repo_is_refused(self):
        self.assertEqual(self.run_it("![x](../../../../etc/passwd)"), "")

    def test_absolute_images_are_untouched(self):
        text = '<img src="https://x.test/a.png"/> ![b](https://x.test/b.png)'
        self.assertEqual(self.run_it(text), text)
        self.assertEqual(self.warnings, [])

    def test_downloads_list_only_attached_files(self):
        for name in ("arm64-v8a.apk", "tv-arm64-v8a.apk", "SHA256SUMS.txt"):
            (self.assets / f"Sozo-v1-{name}").write_bytes(b"x")
        out = self.run_it("<!-- downloads -->")
        self.assertIn("releases/download/v1/Sozo-v1-arm64-v8a.apk", out)
        self.assertIn("Android TV", out)
        self.assertIn("SHA256SUMS", out)
        self.assertNotIn("Windows", out)
        self.assertLess(out.index("Android TV"), out.index("most phones"))

    def test_downloads_without_files(self):
        self.assertIn("attached", self.run_it("<!-- downloads -->"))


if __name__ == "__main__":
    unittest.main()
