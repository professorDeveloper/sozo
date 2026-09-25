"""Traces the dragon in the logo artwork as line drawing, for the splash.

    python3 tool/brand_dragon_lines.py

Reads   assets/brand/sozo_logo_art.png        the logo, 1024 square
        assets/brand/sozo_mark_animated.svg   the letter's spine
Writes  assets/brand/sozo_logo_lines.json     the dragon's contours

The splash draws the logo the way it would be drawn by hand — the letter's
outline, then the dragon's — and only then paints it in. The letter's outline
is already a vector path; the dragon is only a painting. This finds where the
dragon meets the peach ground, as a level set of how dragon-coloured each pixel
is, and writes those edges out as smooth polylines in the artwork's 512 box.

Only dragon against ground. Where the dragon runs to the letter's edge the
letter's own outline is that edge, and tracing it twice would draw a double
line: outside the letter counts as dragon, so no contour forms along it.

Each stroke also carries `along`: where it sits on the letter's spine, 0 at the
top terminal and 1 at the bottom, so the splash can draw the dragon in the
order the letter is written.

Needs numpy and Pillow.
"""

import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "assets" / "brand"

# How far from the ground's colour a pixel is dragon, summed over channels:
# the ground's own texture stays under about 105, the dragon starts near 165.
LIMIT = 110
SPAN = 120

# Strokes shorter than this, in the 512 box, are specks: a speck drawn on reads
# as dust, not as line.
MIN_LENGTH = 14.0


def blur(img: np.ndarray, sigma: float) -> np.ndarray:
    """Gaussian blur by FFT, zero outside the image."""
    h, w = img.shape
    pad = int(sigma * 4)
    fy = np.fft.fftfreq(h + 2 * pad)[:, None]
    fx = np.fft.rfftfreq(w + 2 * pad)[None, :]
    kernel = np.exp(-2 * (np.pi * sigma) ** 2 * (fx**2 + fy**2))
    padded = np.pad(img, pad)
    res = np.fft.irfft2(np.fft.rfft2(padded) * kernel, s=padded.shape)
    return res[pad : pad + h, pad : pad + w]


def marching_squares(field: np.ndarray, level: float) -> list[list[tuple[float, float]]]:
    """The level set of [field] as polylines, in pixel coordinates.

    Each cell's crossing is interpolated along its edges; segments are chained
    through the edges they share, so every polyline is either closed or runs
    to the image's border.
    """
    h, w = field.shape
    above = field > level

    def cross(y0, x0, y1, x1):
        a, b = field[y0, x0], field[y1, x1]
        t = 0.5 if a == b else (level - a) / (b - a)
        return (x0 + (x1 - x0) * t, y0 + (y1 - y0) * t)

    # An edge's key: which cell edge, as a hashable of its two corners.
    segments = []
    for y in range(h - 1):
        row0, row1 = above[y], above[y + 1]
        for x in range(w - 1):
            idx = (row0[x] << 3) | (row0[x + 1] << 2) | (row1[x + 1] << 1) | row1[x]
            if idx == 0 or idx == 15:
                continue
            top = ((y, x), (y, x + 1))
            right = ((y, x + 1), (y + 1, x + 1))
            bottom = ((y + 1, x), (y + 1, x + 1))
            left = ((y, x), (y + 1, x))
            table = {
                1: [(left, bottom)], 2: [(bottom, right)], 3: [(left, right)],
                4: [(top, right)], 5: [(left, top), (bottom, right)], 6: [(top, bottom)],
                7: [(left, top)], 8: [(left, top)], 9: [(top, bottom)],
                10: [(left, bottom), (top, right)], 11: [(top, right)], 12: [(left, right)],
                13: [(bottom, right)], 14: [(left, bottom)],
            }
            for e0, e1 in table[idx]:
                segments.append((e0, e1))

    # Chain: each edge key joins at most two segments.
    ends: dict = {}
    for i, (e0, e1) in enumerate(segments):
        ends.setdefault(e0, []).append(i)
        ends.setdefault(e1, []).append(i)
    used = [False] * len(segments)
    lines = []
    for start in range(len(segments)):
        if used[start]:
            continue
        used[start] = True
        e0, e1 = segments[start]
        chain = [e0, e1]
        # Walk forward from e1, then backward from e0.
        for forward in (True, False):
            key = chain[-1] if forward else chain[0]
            while True:
                nxt = [i for i in ends.get(key, []) if not used[i]]
                if not nxt:
                    break
                i = nxt[0]
                used[i] = True
                a, b = segments[i]
                key = b if a == key else a
                if forward:
                    chain.append(key)
                else:
                    chain.insert(0, key)
        lines.append([cross(*e[0], *e[1]) for e in chain])
    return lines


def simplify(points: np.ndarray, epsilon: float) -> np.ndarray:
    """Ramer–Douglas–Peucker."""
    if len(points) < 3:
        return points
    a, b = points[0], points[-1]
    ab = b - a
    n = np.hypot(*ab)
    if n == 0:
        d = np.hypot(*(points - a).T)
    else:
        d = np.abs(ab[0] * (points[:, 1] - a[1]) - ab[1] * (points[:, 0] - a[0])) / n
    i = int(np.argmax(d))
    if d[i] > epsilon:
        left = simplify(points[: i + 1], epsilon)
        right = simplify(points[i:], epsilon)
        return np.vstack([left[:-1], right])
    return np.vstack([a, b])


def chaikin(points: np.ndarray, closed: bool, rounds: int = 2) -> np.ndarray:
    """Corner cutting, so a traced staircase draws as a curve."""
    for _ in range(rounds):
        p = np.vstack([points, points[:1]]) if closed else points
        q = 0.75 * p[:-1] + 0.25 * p[1:]
        r = 0.25 * p[:-1] + 0.75 * p[1:]
        mid = np.empty((len(q) * 2, 2))
        mid[0::2], mid[1::2] = q, r
        points = mid if closed else np.vstack([points[:1], mid, points[-1:]])
    return points


def spine_points() -> np.ndarray:
    svg = (BRAND / "sozo_mark_animated.svg").read_text()
    d = re.search(r'id="spine"[^>]*\sd="([^"]+)"', svg).group(1)
    nums = [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", d)]
    x, y = nums[0], nums[1]
    out = [(x, y)]
    rest = nums[2:]
    for k in range(0, len(rest), 6):
        x1, y1, x2, y2, x3, y3 = rest[k : k + 6]
        for t in np.linspace(0, 1, 16)[1:]:
            u = 1 - t
            out.append((
                u**3 * x + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t**3 * x3,
                u**3 * y + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t**3 * y3,
            ))
        x, y = x3, y3
    return np.array(out)


def main() -> None:
    art = np.asarray(Image.open(BRAND / "sozo_logo_art.png").convert("RGB"), np.float64)
    letter = art.sum(2) > 200
    closed = blur((blur(letter.astype(np.float64), 3) > 0.1).astype(np.float64), 3) > 0.9
    outside = Image.fromarray((~closed * 255).astype(np.uint8)).copy()
    ImageDraw.floodfill(outside, (0, 0), 128)
    region = np.asarray(outside) != 128

    light = art[letter]
    peach = light[light.sum(1) >= np.percentile(light.sum(1), 85)].mean(0)
    dist = np.abs(art - peach).sum(2)
    dragon = np.clip((dist - LIMIT) / SPAN, 0, 1)
    # Outside the letter counts as dragon, so the level set never runs along
    # the letter's edge; and the "Sozo" in the top stroke is the ground's.
    dragon = np.where(region, dragon, 1.0)
    dragon[284:322, 365:466] = 0
    field = blur(dragon, 1.6)

    lines = marching_squares(field, 0.5)

    spine = spine_points()
    cum = np.concatenate([[0], np.cumsum(np.hypot(*np.diff(spine, axis=0).T))])
    cum /= cum[-1]

    def along(p: np.ndarray) -> float:
        d = np.hypot(spine[:, 0] - p[0], spine[:, 1] - p[1])
        return float(cum[int(np.argmin(d))])

    strokes = []
    for line in lines:
        pts = np.array(line) / 2  # to the 512 box
        if len(pts) < 4:
            continue
        is_closed = np.hypot(*(pts[0] - pts[-1])) < 1.0
        # Contours that touch the image border are the outside, not the dragon.
        if (pts < 1).any() or (pts > 511).any():
            continue
        pts = simplify(pts, 0.35)
        if len(pts) < 3:
            continue
        if is_closed and np.hypot(*(pts[0] - pts[-1])) < 1e-6:
            pts = pts[:-1]
        pts = chaikin(pts, is_closed)
        length = float(np.hypot(*np.diff(pts, axis=0).T).sum())
        if length < MIN_LENGTH:
            continue
        # Start where the letter's writing reaches it first.
        a = np.array([along(p) for p in pts])
        if is_closed:
            k = int(np.argmin(a))
            pts = np.vstack([pts[k:], pts[:k], pts[k : k + 1]])
        elif a[0] > a[-1]:
            pts = pts[::-1]
        strokes.append({
            "along": round(float(a.min()), 4),
            "points": [round(float(v), 2) for v in pts.flatten()],
        })

    strokes.sort(key=lambda s: s["along"])
    (BRAND / "sozo_logo_lines.json").write_text(json.dumps({"strokes": strokes}, separators=(",", ":")))
    total = sum(len(s["points"]) // 2 for s in strokes)
    print(f"{len(strokes)} strokes, {total} points")


if __name__ == "__main__":
    main()
