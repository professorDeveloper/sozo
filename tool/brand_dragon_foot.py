"""Cuts the dragon's raised foot out of the logo artwork, for the splash.

    python3 tool/brand_dragon_foot.py

Reads   assets/brand/sozo_logo_art.png          the logo, 1024 square
Writes  assets/brand/sozo_logo_foot.png         the foot alone, over nothing
        assets/brand/sozo_logo_foot_ground.png  the logo with no foot in it

When the splash has painted the logo in, the dragon plants its raised foot:
the three toes in the right-hand bend lift off the letter's wall and come down
again. A painting cannot move part of itself, so the foot is cut out of it,
and what was under the foot is painted in: the ground plate is the artwork
with the ground carried across where the foot was, and the foot is matted
against that plate so that plate + foot, with the foot at rest, is the
artwork again to within a value or two. The splash can then swap one for the
other without a visible frame.

The cut at the ankle is a hinge. The pivot is on the back of the ankle, and
the cut runs from it straight into the leg along a ray, then round the front
of the ankle as an arc of a circle centred on the pivot. The leg keeps what
is inside that disc below the ray; the foot is everything else of the dragon.

Each part of the cut is there for the way it moves. The arc slides along
itself as the foot turns, so no wedge of ground opens at the front of the
ankle however far it goes. The ray, turning about its own end, swings into
the leg as the foot lifts — foot over leg, orange over orange. And the back
of the ankle, which is all foot from the pivot up, opens from the pivot
itself: a clean V of ground, the way a hinge opens. A disc alone, with no
ray, leaves its own top standing at the back of the ankle when the foot
lifts away from it — a tooth of leg with ground above it that is neither
leg nor foot.

Across the cut the foot is feathered over a band where the plate is still the
leg, and the plate keeps the leg a few degrees further above the ray than
that, for the landing's swing past rest, which turns the ray the other way:
the seam is orange over orange, both ways, and never shows.

The pivot is also, near enough, the centre of the wall's curve in that bend,
which is why the toes can swing a long way without leaving the letter: they
travel along the wall rather than into it.

Needs numpy and Pillow.
"""

from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from brand_dragon_lines import LIMIT, blur

ROOT = Path(__file__).resolve().parent.parent
BRAND = ROOT / "assets" / "brand"

# Everything below is in the artwork's 512 box; the file is 1024, two texels
# a unit. Mirrored in SozoMarkGeometry — change one, change both.

# The foot's patch. Its corners are on multiples of eight texels so that
# every mip level of the patch lines up with the artwork's own.
BOX = (328, 192, 408, 304)

# The pivot: the back of the ankle, where the leg leaves the letter's inner
# edge, and the ball of the joint around it.
PIVOT = (347.0, 256.0)
JOINT = 26.0

# The ray the hinge cuts along, in degrees from the pivot, screen-wise
# (negative is up): through the leg, between its back edge (about -70) and
# the front of the ankle, reaching the joint's rim still inside the leg.
HINGE = -40.0

# How far past rest, against the lift, the plate keeps the leg above the ray.
# The landing overshoots by under three degrees.
KEEP = 7.0

# How wide the feathered band across the joint is, either side of its rim.
FEATHER = 1.25

# Where the foot is. Generous over the ground, which the matte leaves behind
# anyway; exact only where it has to part the foot from the upper arm's
# talons, which reach to within a few units of it and must not come along.
REACH = [
    (350.5, 194.0),
    (372.0, 192.0),
    (408.0, 200.0),
    (408.0, 244.0),
    (372.0, 244.0),
    (347.0, 256.0),
    (350.5, 232.0),
]

# How dragon a pixel is, by its distance from the ground's colour summed over
# channels: none of it below LOW, all of it above HIGH.
LOW, HIGH = 95.0, 165.0

# Channel error the matte may leave rather than raise a pixel's alpha for:
# the ground's red is within a few values of white, and a strict matte would
# make every slightly-brighter ground pixel beside the foot opaque, a peach
# halo that travels with it.
TOLERANCE = 3.0

SS = 4  # supersampling for the polygon's own edges


def polygon_mask(points, size, scale):
    """[points], in 512 units, filled at [size] texels with anti-aliased edges."""
    big = Image.new("L", (size * SS, size * SS), 0)
    ImageDraw.Draw(big).polygon([(x * scale * SS, y * scale * SS) for x, y in points], fill=255)
    return np.asarray(big.resize((size, size), Image.BOX), np.float64) / 255


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def main() -> None:
    art = np.asarray(Image.open(BRAND / "sozo_logo_art.png").convert("RGB"), np.float64)
    n = art.shape[0]
    t = n / 512  # texels per unit

    letter = art.sum(2) > 200
    closed = blur((blur(letter.astype(np.float64), 3) > 0.1).astype(np.float64), 3) > 0.9
    outside = Image.fromarray((~closed * 255).astype(np.uint8)).copy()
    ImageDraw.floodfill(outside, (0, 0), 128)
    region = (np.asarray(outside) != 128).astype(np.float64)
    # Clear of the letter's bevelled rim: a toe that touches the wall must not
    # carry a piece of the wall away with it.
    inner = np.clip((blur(region, 2.0) - 0.97) / 0.03, 0, 1)

    light = art[letter]
    peach = light[light.sum(1) >= np.percentile(light.sum(1), 85)].mean(0)
    dist = np.abs(art - peach).sum(2)
    dragon = smoothstep(LOW, HIGH, dist)

    ys, xs = np.mgrid[0:n, 0:n]
    dx, dy = (xs + 0.5) / t - PIVOT[0], (ys + 0.5) / t - PIVOT[1]
    r = np.hypot(dx, dy)
    reach = polygon_mask(REACH, n, t)
    # Distance above the hinge's line, towards the back of the ankle, and how
    # far round from the ray that way, in degrees. The line's far half, behind
    # the pivot, is outside REACH: only the ray is a cut.
    h = np.radians(HINGE)
    above = dx * np.sin(h) - dy * np.cos(h)
    turned = (HINGE - np.degrees(np.arctan2(dy, dx))) % 360
    beyond = 1 - (
        (1 - smoothstep(JOINT - FEATHER, JOINT + FEATHER, r))
        * (1 - smoothstep(-FEATHER, FEATHER, above))
    )

    alpha = dragon * inner * reach * beyond

    # The plate is cut where the foot is fully itself — past the feathered
    # band, where it has to be replaced by ground — widened by a texel or two
    # so the foot's softened edge goes with it. Into the rim, too, where a toe
    # touches the wall: the rim there is tinted by the toe, and left in the
    # plate it is a sliver of toe on the wall after the foot has gone.
    # Inside the joint, only clear of the ray by more than the landing turns
    # it back: under the ray and just above it the plate stays the leg.
    swung = (turned > KEEP) & (turned < 180) & (above > FEATHER + 0.5)
    hole = (
        (blur((alpha > 0.04).astype(np.float64), 1.5) > 0.02)
        & ((r > JOINT + FEATHER) | swung)
        & (reach > 0)
    )

    # The ground, carried in from around the hole: a normalised blur of the
    # ground's own pixels, widest where the hole is deepest.
    ground = (region > 0.5) & (dist < LIMIT) & ~hole
    fill = np.zeros_like(art)
    done = np.zeros(hole.shape, bool)
    for sigma in (3.0, 8.0, 20.0, 48.0):
        w = blur(ground.astype(np.float64), sigma)
        num = np.stack([blur(art[..., c] * ground, sigma) for c in range(3)], -1)
        ok = (w > 0.15) & ~done
        fill[ok] = num[ok] / w[ok, None]
        done |= ok
    fill[~done] = peach

    # And the wall, where a toe was touching it: the letter's own rim over
    # bare ground, which is sharp — peach to the black it is cut from within
    # two texels. Without it the ground runs flat to the edge and stops, and
    # the splash, which filters ground and foot each on its own, lights the
    # letter's outermost pixels where the toes meet the wall the moment the
    # two stand in for the artwork.
    black = art[:40, :40].reshape(-1, 3).mean(0)
    wall = np.clip((blur(region, 1.0) - 0.2) / 0.8, 0, 1)[..., None]
    fill = black + (fill - black) * wall
    plate = np.where(hole[..., None], fill, art)

    # The matte: at rest, plate × (1 - a) + foot × a is the artwork.
    diff = art - plate
    room = np.where(diff > 0, 255 - plate, plate)
    need = np.where(room > 0, np.maximum(np.abs(diff) - TOLERANCE, 0) / np.maximum(room, 1e-6), 0).max(2)
    a = np.clip(np.maximum(alpha, np.where(hole, need, 0)), 0, 1)
    colour = np.where(a[..., None] > 1e-3, plate + diff / np.maximum(a, 1e-3)[..., None], art)
    colour = np.clip(colour, 0, 255)

    rest = plate * (1 - a[..., None]) + colour * a[..., None]
    err = np.abs(rest - art)
    print(f"peach {peach.round(1)}  hole {hole.sum()} texels  "
          f"at rest: max error {err.max():.2f}, mean {err[hole].mean():.3f} in the hole")

    x0, y0, x1, y1 = (int(v * t) for v in BOX)
    assert a[:y0].max() + a[y1:].max() + a[:, :x0].max() + a[:, x1:].max() == 0, "foot outside BOX"
    edge = np.concatenate([a[y0, x0:x1], a[y1 - 1, x0:x1], a[y0:y1, x0], a[y0:y1, x1 - 1]])
    assert edge.max() == 0, "foot touches the edge of BOX"

    foot = np.dstack([colour, a * 255])[y0:y1, x0:x1]
    Image.fromarray(np.round(foot).astype(np.uint8)).save(BRAND / "sozo_logo_foot.png", optimize=True)
    Image.fromarray(np.round(plate).astype(np.uint8)).save(BRAND / "sozo_logo_foot_ground.png", optimize=True)


if __name__ == "__main__":
    main()
