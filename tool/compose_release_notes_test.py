import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import datetime as dt
import re

from compose_release_notes import changes, compose, generate, telegram_caption, visible_length
from release_banner import banner_text, render, still

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

    def test_banner_goes_on_top_when_the_notes_have_none(self):
        (self.root / "docs/images/v1/banner.svg").write_text("<svg/>")
        out = self.run_it("<!-- banner\nline1: Hi\n-->\n<p>Body</p>\n")
        self.assertTrue(out.startswith('<p align="center">\n  <img src="' + RAW + 'banner.svg"'))
        self.assertNotIn("line1", out)
        self.assertEqual(out.count("banner.svg"), 1)

    def test_a_banner_the_notes_already_show_is_not_added_twice(self):
        (self.root / "docs/images/v1/banner.svg").write_text("<svg/>")
        out = self.run_it('<img src="../images/v1/banner.svg"/>\n')
        self.assertEqual(out.count("banner.svg"), 1)


LOG = [
    "Sources: show a renamed source under its current name (#76)",
    "chore: 3.2.1+9",
    "Release: put the APKs on the CDN (#74)",
    "Player: skip Matroska on iPhone (#75)",
    "Sozo 3.2.1: corner player and reconnect fixes (#46)",
    "Issue forms: English first (#51)",
    "fix a typo in the reader",
]


class GeneratedTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)
        self.assets = self.root / "rel"
        self.assets.mkdir()
        (self.assets / "Sozo-v3.2.2-arm64-v8a.apk").write_bytes(b"x")

    def test_changes_keep_what_users_see(self):
        got = changes(LOG)
        self.assertEqual([a for a, _, _ in got], ["Improvements", "Highlights", "Player", "Sources"])
        self.assertIn(("Player", "Skip Matroska on iPhone", "75"), got)
        self.assertIn(("Improvements", "Fix a typo in the reader", None), got)

    def test_generated_page_has_the_v320_layout(self):
        out = generate("3.2.2", "s", "o/r", "v3.2.2", "v3.2.1", self.assets, self.root, LOG, "Hotfix.")
        for part in ("is a patch release", "Download_v3.2.2", "Hotfix.", "## ✨ What's new",
                     "### ▶️ Player", "[#75](https://github.com/o/r/pull/75)", "## ⬇ Download",
                     "Sozo-v3.2.2-arm64-v8a.apk", "## 💬 Join the community",
                     "compare/v3.2.1...v3.2.2"):
            self.assertIn(part, out)
        self.assertNotIn("CDN", out)
        self.assertLess(out.index("Highlights"), out.index("Player"))
        self.assertLess(out.index("Sources"), out.index("Improvements"))

    def test_generated_page_shows_the_committed_banner(self):
        (self.root / "docs/images/v3.2.2").mkdir(parents=True)
        (self.root / "docs/images/v3.2.2/banner.svg").write_text("<svg/>")
        out = generate("3.2.2", "s", "o/r", "v3.2.2", "", self.assets, self.root, LOG)
        self.assertTrue(out.startswith('<p align="center">\n  <img src="https://raw.githubusercontent.com/o/r/s/docs/images/v3.2.2/banner.svg"'))
        self.assertNotIn("compare/", out)


NOTES = """<!-- banner
line1: Playback that recovers,
line2: downloads that finish.
-->
| | |
|---|---|
| ⏱️ **No more endless "Video loading"** | A server now has about 25 seconds. |
| 🔌 **Dropped connections** | The player reconnects. |

## ✨ Added
- 🌍 **Vietnamese and Hindi**, so Sozo now has 16 languages.
- 📋 **Sort My List** by recently added.
- **Windows:** Anime4K no longer goes black.

## 💬 Join the community
- 📣 **Telegram**: [@sozoapp](https://telegram.me/sozoapp) for news.
"""

TG_NOTES = NOTES + """<!-- telegram
tagline: Fixes for what you reported.
- No more endless <video> loading, see [the channel](https://t.me/sozoapp).
- **Corner player** on desktop: press **I**.
-->
"""
REL = "https://github.com/o/r/releases/tag/v3.2.1"
TV = "https://github.com/o/tv/releases/tag/v1.0.4"


class TelegramTest(unittest.TestCase):
    def test_hand_written_block_wins(self):
        out = telegram_caption("3.2.1", TG_NOTES, LOG, release_url=REL, tv_url=TV)
        self.assertTrue(out.startswith("🐉 <b>Sozo 3.2.1 is out!</b>\n\n<i>Fixes for what you reported.</i>\n"))
        self.assertIn('- No more endless &lt;video&gt; loading, see <a href="https://t.me/sozoapp">the channel</a>.', out)
        self.assertIn("- <b>Corner player</b> on desktop: press <b>I</b>.", out)
        self.assertNotIn("Dropped connections", out)
        self.assertIn(f'<b>All files</b> (<i>Windows, macOS, Linux, iOS, Android</i>): <a href="{REL}">Link</a>', out)
        self.assertIn(f'<b>TV Side</b>: <a href="{TV}">Link</a>', out)
        self.assertTrue(out.endswith("🛟 <b>Need help? Profile → Help &amp; Support</b>"))

    def test_bold_titles_of_the_notes_otherwise(self):
        out = telegram_caption("3.2.1", NOTES, LOG, release_url=REL)
        self.assertIn("<i>Playback that recovers, downloads that finish.</i>", out)
        self.assertIn('- No more endless "Video loading"\n- Vietnamese and Hindi\n- Dropped connections\n- Sort My List\n\n', out)
        self.assertNotIn("Windows", out.split("All files")[0])
        self.assertNotIn("Telegram", out)
        self.assertNotIn("TV Side", out)

    def test_falls_back_to_the_merged_changes(self):
        out = telegram_caption("3.3.0", "", LOG, "Out today")
        self.assertIn("<i>Out today</i>", out)
        self.assertIn("- Skip Matroska on iPhone", out)
        self.assertNotIn("CDN", out)
        self.assertNotIn("All files", out)

    def test_never_longer_than_a_caption(self):
        notes = NOTES + "<!-- telegram\n" + "\n".join(f"- **N{i}** 🎬 " + "word " * 40 for i in range(40)) + "\n-->\n"
        out = telegram_caption("3.2.1", notes, LOG, release_url=REL, tv_url=TV)
        self.assertLessEqual(visible_length(out), 1024)
        self.assertEqual(out.count("<b>"), out.count("</b>"))
        self.assertIn("TV Side", out)

    def test_one_huge_bullet_is_cut_not_dropped(self):
        notes = "<!-- telegram\n- " + "long " * 400 + "\n-->"
        out = telegram_caption("3.2.1", notes, LOG, release_url=REL)
        self.assertLessEqual(visible_length(out), 1024)
        self.assertIn("…", out)

    def test_length_counts_what_telegram_counts(self):
        self.assertEqual(visible_length('<a href="https://x.y/very/long">Link</a> &amp; 🎬'), len("Link & ") + 2)


TEMPLATE = Path(__file__).resolve().parent.parent / "docs/images/v3.2.0/banner.svg"


class BannerTest(unittest.TestCase):
    def test_text_follows_the_version(self):
        t = banner_text("3.2.4", "", ["Player"], dt.date(2026, 11, 14))
        self.assertEqual(t["eyebrow"], "PATCH RELEASE · NOVEMBER 2026")
        self.assertEqual(t["chips"], ["Player"])
        self.assertEqual(banner_text("4.0.0", "", [], dt.date(2026, 1, 1))["eyebrow"], "NEW RELEASE · JANUARY 2026")

    def test_notes_override_every_line(self):
        t = banner_text("3.2.1", "<!-- banner\neyebrow: HOTFIX\nline1: A\nline2: B\nchips: x | y\n-->", ["Player"],
                        dt.date(2026, 11, 14))
        self.assertEqual((t["eyebrow"], t["line1"], t["line2"], t["chips"]),
                         ("HOTFIX · NOVEMBER 2026", "A", "B", ["x", "y"]))

    @unittest.skipUnless(TEMPLATE.is_file(), "template not checked out")
    def test_render_keeps_the_art_and_swaps_the_words(self):
        template = TEMPLATE.read_text(encoding="utf-8")
        t = banner_text("3.2.10", "", ["Player & <Sources>"] + ["Very long chip name " * 3] * 5)
        svg = render(template, t)
        self.assertEqual(svg[:svg.index('<g transform="translate(640,0)">')],
                         re.sub(r"<title>.*?</title>", "<title>Sozo v3.2.10</title>",
                                template[:template.index('<g transform="translate(640,0)">')]))
        self.assertIn(">v3.2.10</text>", svg)
        self.assertIn("Player &amp; &lt;Sources&gt;", svg)
        self.assertNotIn("Light novels", svg)
        self.assertTrue(svg.rstrip().endswith("</svg>"))
        self.assertIn("@media all{", still(svg))


if __name__ == "__main__":
    unittest.main()
