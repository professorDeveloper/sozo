#!/usr/bin/env python3
"""Builds a release body from docs/releases/v<version>.md.

Images may be written relative to the notes file. They become links to the
exact commit being released, so they work in a draft before anything reaches
the default branch. An image that is not in the repository is removed and
reported, so a release never shows a broken picture.

<!-- downloads --> becomes a table of the files actually attached.

Exit codes: 0 written, 3 no notes file for this version (the workflow then falls
back to its generated notes).
"""
import argparse
import posixpath
import re
import sys
from pathlib import Path

# Longest suffix first: "tv-arm64-v8a.apk" also ends in "arm64-v8a.apk".
PLATFORMS = (
    ("tv-arm64-v8a.apk", "📺", "Android TV"),
    ("tv-armeabi-v7a.apk", "📺", "Android TV (older 32-bit devices)"),
    ("arm64-v8a.apk", "🟢", "Android (most phones)"),
    ("armeabi-v7a.apk", "🟡", "Android (older 32-bit phones)"),
    ("universal.apk", "🔵", "Android (if you're not sure; larger, works everywhere)"),
    ("x86_64.apk", "⚪", "Android (x86_64 and emulators)"),
    ("Windows-Setup.exe", "🪟", "Windows"),
    ("Windows-portable.zip", "🪟", "Windows (no install)"),
    ("macOS.dmg", "🍎", "macOS 12+"),
    ("Linux-x64.tar.gz", "🐧", "Linux x64"),
    ("iOS.ipa", "📱", "iOS 15+ (install with AltStore, SideStore or Sideloadly)"),
)

IMAGE_BLOCK = re.compile(r'<p[^>]*>\s*(<img\b[^>]*>)\s*</p>\n?', re.I)
HTML_IMG = re.compile(r'<img\b[^>]*?\bsrc="([^"]+)"[^>]*>', re.I)
MD_IMG = re.compile(r'!\[[^\]]*\]\(([^)\s]+)\)')


def is_relative(src):
    return not re.match(r'^(?:[a-z][a-z0-9+.-]*:|//|#|/)', src, re.I)


def rewrite_images(text, notes_path, repo_root, repo, sha, warn):
    base = f"https://raw.githubusercontent.com/{repo}/{sha}/"
    notes_dir = notes_path.parent.relative_to(repo_root).as_posix()

    def target(src):
        path = posixpath.normpath(posixpath.join(notes_dir, src))
        if path.startswith("../") or not (repo_root / path).is_file():
            warn(f"image not found, removed: {src}")
            return None
        return base + path

    def block(match):
        src = HTML_IMG.search(match.group(1))
        if src and is_relative(src.group(1)) and target(src.group(1)) is None:
            return ""
        return match.group(0)

    def html(match):
        src = match.group(1)
        if not is_relative(src):
            return match.group(0)
        url = target(src)
        return match.group(0).replace(src, url, 1) if url else ""

    def markdown(match):
        src = match.group(1)
        if not is_relative(src):
            return match.group(0)
        url = target(src)
        return match.group(0).replace(src, url, 1) if url else ""

    text = IMAGE_BLOCK.sub(block, text)
    # A missing image in a block was already removed and warned about once.
    return MD_IMG.sub(markdown, HTML_IMG.sub(html, text))


def downloads_table(assets, repo, tag, version):
    names = sorted(p.name for p in assets.iterdir()) if assets.is_dir() else []
    rows = []
    for suffix, icon, label in PLATFORMS:
        name = f"Sozo-v{version}-{suffix}"
        if name in names:
            url = f"https://github.com/{repo}/releases/download/{tag}/{name}"
            rows.append(f"| {icon} {label} | [`{name}`]({url}) |")
    if not rows:
        return "The files are attached to this release."
    lines = ["| Platform | File |", "|---|---|", *rows]
    sums = f"Sozo-v{version}-SHA256SUMS.txt"
    if sums in names:
        url = f"https://github.com/{repo}/releases/download/{tag}/{sums}"
        lines += ["", f"🔐 To check a download, compare it with [`{sums}`]({url})."]
    return "\n".join(lines)


def compose(version, sha, repo, tag, assets, repo_root, warn):
    notes = repo_root / "docs" / "releases" / f"v{version}.md"
    if not notes.is_file():
        return None
    text = notes.read_text(encoding="utf-8")
    text = rewrite_images(text, notes, repo_root, repo, sha, warn)
    return text.replace("<!-- downloads -->", downloads_table(assets, repo, tag, version))


def main():
    parser = argparse.ArgumentParser()
    for name in ("version", "sha", "repo", "tag", "assets", "out"):
        parser.add_argument(f"--{name}", required=True)
    parser.add_argument("--root", default=".")
    args = parser.parse_args()
    warn = lambda message: print(f"::warning::{message}")
    body = compose(args.version, args.sha, args.repo, args.tag, Path(args.assets),
                   Path(args.root).resolve(), warn)
    if body is None:
        print(f"No docs/releases/v{args.version}.md")
        return 3
    Path(args.out).write_text(body, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
