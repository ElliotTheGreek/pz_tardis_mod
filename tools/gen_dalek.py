"""Generates the Dalek world model: texture, mesh and inventory icon.

Authored the same way as the police box and the console -- Z up here, swapped
to Y up on the way out, 1 unit to a tile. A Dalek is shorter than a police
box, so it tops out around 1.45 against the box's 1.72.

There is only one mesh. A Dalek glides rather than walks, so it needs no
animation, and it does not need a mesh per facing either: a dropped world item
carries `setWorldZRotation`, which is what makes litter lie at angles, so the
model is turned to face wherever its zombie is heading.

The famous skirt hemispheres are painted, not modelled. At the game's camera
angle and this size they read exactly the same and cost nothing.

    python tools/gen_dalek.py TARDIS/42
    python tools/preview_model.py TARDIS/42/media/models_X/TARDIS_Dalek.x \
           TARDIS/42/media/textures/TARDIS_Dalek.png out.png
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngwrite import Image
from meshbuild import MeshBuilder

TEX = 256

# Every body region is **one repeating unit**, not a sheet of them. Each of the
# twelve side faces maps a whole region across itself, so a region holding six
# hemispheres would put six on every face -- seventy-two round the skirt, which
# renders as stripes. One column per region, twelve columns round the body.
REGIONS = {
    "skirt":    (0, 0, 32, 96),      # one column of four hemispheres
    "slats":    (32, 0, 64, 96),     # one slat and its gap
    "shoulder": (64, 0, 96, 96),     # one shoulder panel
    "neck":     (96, 0, 128, 96),    # one bar of the cage
    "dome":     (128, 0, 192, 96),
    "metal":    (192, 0, 224, 32),
    "eye":      (192, 32, 256, 96),
    "gun":      (128, 96, 192, 160),
}

BRONZE      = (150, 106, 46, 255)
BRONZE_LITE = (198, 152, 78, 255)
BRONZE_PALE = (226, 186, 114, 255)
BRONZE_DARK = (96, 66, 28, 255)
BRONZE_DEEP = (56, 38, 16, 255)
SLAT        = (34, 30, 26, 255)
STEEL       = (108, 110, 118, 255)
STEEL_LITE  = (168, 172, 180, 255)
EYE_BLUE    = (128, 206, 238, 255)
EYE_PALE    = (216, 244, 252, 255)

N = 12          # sides round the body; enough to read as round at this size


# ---------------------------------------------------------------------------
# Texture
# ---------------------------------------------------------------------------
def disc(img, cx, cy, r, colour, hilite=None):
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            d = math.hypot(x - cx, y - cy)
            if d <= r:
                c = colour
                if hilite and d <= r * 0.55 and (x - cx) + (y - cy) < 0:
                    c = hilite
                img.set(x, y, c)


def build_texture(path):
    img = Image(TEX, TEX, BRONZE_DEEP)

    # --- skirt: one column of four hemispheres, repeated round the body --
    x0, y0, x1, y1 = REGIONS["skirt"]
    w = x1 - x0
    img.rect(x0, y0, x1, y1, BRONZE)
    img.rect(x0, y0, x0 + 2, y1, BRONZE_DARK)      # seam between columns
    for r in range(4):
        disc(img, x0 + w / 2 + 1, y0 + 13 + r * 22, 9, BRONZE_DARK, BRONZE_LITE)
    img.rect(x0, y1 - 7, x1, y1, BRONZE_DARK)      # bottom rail

    # --- slats: one dark slat and its gap --------------------------------
    x0, y0, x1, y1 = REGIONS["slats"]
    img.rect(x0, y0, x1, y1, SLAT)
    img.rect(x0 + 8, y0 + 4, x1 - 8, y1 - 4, (62, 56, 50, 255))
    img.rect(x0 + 8, y0 + 4, x0 + 12, y1 - 4, (86, 78, 70, 255))
    img.rect(x0, y0, x1, y0 + 4, BRONZE_DARK)
    img.rect(x0, y1 - 4, x1, y1, BRONZE_DARK)

    # --- shoulders: one panel -------------------------------------------
    x0, y0, x1, y1 = REGIONS["shoulder"]
    img.rect(x0, y0, x1, y1, BRONZE)
    img.rect(x0 + 3, y0 + 6, x1 - 3, y1 - 8, BRONZE_LITE)
    img.rect(x0 + 3, y0 + 6, x1 - 3, y0 + 9, BRONZE_PALE)
    img.rect(x0, y0, x0 + 2, y1, BRONZE_DARK)
    img.rect(x0, y1 - 5, x1, y1, BRONZE_DARK)

    # --- neck: one bar of the open cage ----------------------------------
    x0, y0, x1, y1 = REGIONS["neck"]
    img.rect(x0, y0, x1, y1, BRONZE_DEEP)
    img.rect(x0 + 9, y0, x1 - 9, y1, BRONZE)
    img.rect(x0 + 9, y0, x0 + 13, y1, BRONZE_LITE)
    img.rect(x0, y0, x1, y0 + 5, BRONZE_DARK)
    img.rect(x0, y1 - 5, x1, y1, BRONZE_DARK)

    # --- dome ------------------------------------------------------------
    x0, y0, x1, y1 = REGIONS["dome"]
    img.rect(x0, y0, x1, y1, BRONZE_LITE)
    img.rect(x0, y0, x0 + 2, y1, BRONZE)           # panel seam
    img.rect(x0, y1 - 6, x1, y1, BRONZE)           # base shadow
    img.rect(x0, y0, x1, y0 + 10, BRONZE_PALE)     # lit crown

    # --- plain metal for the stalks --------------------------------------
    x0, y0, x1, y1 = REGIONS["metal"]
    img.rect(x0, y0, x1, y1, STEEL)
    img.rect(x0, y0, x0 + 3, y1, STEEL_LITE)

    # --- the eye ---------------------------------------------------------
    x0, y0, x1, y1 = REGIONS["eye"]
    img.rect(x0, y0, x1, y1, BRONZE_DARK)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    disc(img, cx, cy, 22, STEEL)
    disc(img, cx, cy, 15, EYE_BLUE, EYE_PALE)
    disc(img, cx, cy, 6, (24, 40, 60, 255))

    # --- the gun lattice --------------------------------------------------
    x0, y0, x1, y1 = REGIONS["gun"]
    img.rect(x0, y0, x1, y1, (40, 40, 44, 255))
    for i in range(x0 + 2, x1 - 2, 6):
        img.rect(i, y0 + 2, i + 3, y1 - 2, STEEL)
    for j in range(y0 + 2, y1 - 2, 6):
        img.rect(x0 + 2, j, x1 - 2, j + 3, (64, 64, 70, 255))

    img.save(path)


# ---------------------------------------------------------------------------
# Mesh
# ---------------------------------------------------------------------------
def ring(r, z, n=N, spin=0.0):
    return [(r * math.cos(spin + i * 2 * math.pi / n),
             r * math.sin(spin + i * 2 * math.pi / n), z) for i in range(n)]


def tube(mb, P, lower, upper, region):
    """Side wall between two rings of the same point count."""
    n = len(lower)
    for i in range(n):
        j = (i + 1) % n
        nx = (lower[i][0] + lower[j][0]) / 2
        ny = (lower[i][1] + lower[j][1]) / 2
        ln = max(1e-6, math.hypot(nx, ny))
        mb.quad(P(lower[i]), P(lower[j]), P(upper[j]), P(upper[i]),
                region, mb.place(nx / ln, ny / ln, 0.2))


def annulus(mb, P, inner, outer, region, up=1):
    """Flat ring closing the step between two radii at one height."""
    n = len(inner)
    normal = mb.place(0, 0, up)
    for i in range(n):
        j = (i + 1) % n
        if up > 0:
            mb.quad(P(inner[i]), P(inner[j]), P(outer[j]), P(outer[i]), region, normal)
        else:
            mb.quad(P(outer[i]), P(outer[j]), P(inner[j]), P(inner[i]), region, normal)


def fan(mb, P, edge, apex, region):
    """Closes a ring to a point -- the top of the dome."""
    n = len(edge)
    for i in range(n):
        j = (i + 1) % n
        mb.tri(P(edge[i]), P(edge[j]), P(apex), region, mb.place(0, 0, 1))


def rod(mb, P, cx, cz, y0, y1, t, region, tip_region=None, tip=None):
    """A square-section stalk running forward along +y."""
    c = [(cx - t, y0, cz - t), (cx + t, y0, cz - t),
         (cx + t, y0, cz + t), (cx - t, y0, cz + t)]
    d = [(p[0], y1, p[2]) for p in c]
    for i in range(4):
        j = (i + 1) % 4
        nx = (c[i][0] + c[j][0]) / 2 - cx
        nz = (c[i][2] + c[j][2]) / 2 - cz
        ln = max(1e-6, math.hypot(nx, nz))
        mb.quad(P(c[i]), P(c[j]), P(d[j]), P(d[i]), region,
                mb.place(nx / ln, 0, nz / ln))
    # the business end, facing forward
    if tip_region:
        h = tip or t * 2.2
        f = [(cx - h, y1, cz - h), (cx + h, y1, cz - h),
             (cx + h, y1, cz + h), (cx - h, y1, cz + h)]
        g = [(p[0], y1 + h * 0.5, p[2]) for p in f]
        for i in range(4):
            j = (i + 1) % 4
            mb.quad(P(f[i]), P(f[j]), P(g[j]), P(g[i]), tip_region, mb.place(0, 1, 0))
        mb.quad(P(g[0]), P(g[1]), P(g[2]), P(g[3]), tip_region, mb.place(0, 1, 0))
    else:
        mb.quad(P(d[0]), P(d[1]), P(d[2]), P(d[3]), region, mb.place(0, 1, 0))


# --- worn (bone-attached) variant -----------------------------------------
# The casing is also emitted as a static clothing model bolted to
# Bip01_Pelvis, which is how the game itself hangs a holster off a hip and how
# every zombie-appearance mod works. That mesh lives in *bone space*, which is
# neither the same scale nor the same origin as a world model:
#
#   * Scale. Measured off the vanilla static clothes -- Bob_Greave_BodyArmour_L
#     spans 0.199 units along a shin, so one unit is roughly two metres and a
#     whole character stands about 0.9 units tall. A world model uses one unit
#     to a tile, so everything has to come down by about half.
#   * Origin. The mesh hangs off the bone, so its origin is the pelvis rather
#     than the ground, and the Dalek has to be dropped to stand on its base.
#
# Both are single numbers on purpose: if the casing floats, sinks or comes out
# the wrong size, this is where it is corrected and nothing else changes.
WORN_SCALE = 0.54     # 1.45 units tall becomes about 0.78, near enough 1.55 m
WORN_DROP = 0.50      # pelvis sits about a metre up, so half a unit


def build_model(path, scale=1.0, drop=0.0, name="TARDIS_Dalek"):
    mb = MeshBuilder(TEX, TEX, up_axis="y")
    # Author everything at world scale and let this fold in the bone-space
    # transform, so the shape is described once.
    P = lambda p: mb.place(p[0] * scale, p[1] * scale, p[2] * scale - drop)
    R = REGIONS

    # profile, bottom to top
    skirt_lo = ring(0.46, 0.00)
    skirt_hi = ring(0.30, 0.56)
    slat_hi  = ring(0.30, 0.78)
    sh_lo    = ring(0.35, 0.78)
    sh_hi    = ring(0.32, 1.02)
    neck_lo  = ring(0.20, 1.02)
    neck_hi  = ring(0.20, 1.20)
    dome_lo  = ring(0.24, 1.20)

    tube(mb, P, skirt_lo, skirt_hi, R["skirt"])        # flared base
    tube(mb, P, skirt_hi, slat_hi, R["slats"])         # dark slatted band
    annulus(mb, P, slat_hi, sh_lo, R["shoulder"])      # shoulder lip
    tube(mb, P, sh_lo, sh_hi, R["shoulder"])           # shoulders
    annulus(mb, P, neck_lo, sh_hi, R["shoulder"])      # shoulder top
    tube(mb, P, neck_lo, neck_hi, R["neck"])           # the cage
    annulus(mb, P, neck_hi, dome_lo, R["dome"])        # dome shoulder

    # dome: quarter-sphere in three bands, then closed to a point
    prev = dome_lo
    steps = 3
    for k in range(1, steps + 1):
        a = (k / steps) * (math.pi / 2)
        r = 0.24 * math.cos(a)
        z = 1.20 + 0.24 * math.sin(a)
        cur = ring(r, z) if r > 0.02 else None
        if cur is None:
            fan(mb, P, prev, (0, 0, z), R["dome"])
            break
        tube(mb, P, prev, cur, R["dome"])
        prev = cur
    else:
        fan(mb, P, prev, (0, 0, 1.44), R["dome"])

    # eyestalk, out of the dome front, with the lens on the end
    rod(mb, P, 0.0, 1.30, 0.10, 0.56, 0.035, R["metal"], R["eye"], tip=0.075)

    # the two arms: gunstick to one side, plunger to the other
    rod(mb, P, -0.15, 0.92, 0.24, 0.58, 0.030, R["metal"], R["gun"], tip=0.055)
    rod(mb, P, 0.15, 0.92, 0.24, 0.54, 0.032, R["metal"], R["metal"], tip=0.075)

    # dome lights
    for sx in (-0.13, 0.13):
        lo = [(sx - 0.035, 0.02 - 0.035, 1.42), (sx + 0.035, 0.02 - 0.035, 1.42),
              (sx + 0.035, 0.02 + 0.035, 1.42), (sx - 0.035, 0.02 + 0.035, 1.42)]
        hi = [(p[0], p[1], 1.50) for p in lo]
        for i in range(4):
            j = (i + 1) % 4
            mb.quad(P(lo[i]), P(lo[j]), P(hi[j]), P(hi[i]), R["metal"],
                    mb.place(0, 0, 1))
        mb.quad(P(hi[0]), P(hi[1]), P(hi[2]), P(hi[3]), R["eye"], mb.place(0, 0, 1))

    mb.emit(path, name, "TARDIS_Dalek.png", frame_name=name)
    return mb


# ---------------------------------------------------------------------------
# Inventory icon
# ---------------------------------------------------------------------------
def build_icon(path):
    img = Image(64, 64, (0, 0, 0, 0))
    img.rect(26, 6, 38, 18, BRONZE_LITE)            # dome
    img.rect(28, 3, 36, 7, BRONZE_LITE)
    img.rect(29, 1, 31, 4, EYE_BLUE)                # lights
    img.rect(33, 1, 35, 4, EYE_BLUE)
    img.rect(38, 10, 52, 13, STEEL)                 # eyestalk
    img.rect(50, 8, 55, 15, EYE_BLUE)
    img.rect(27, 18, 37, 24, BRONZE_DEEP)           # neck cage
    for i in range(28, 37, 3):
        img.rect(i, 18, i + 1, 24, BRONZE)
    img.rect(23, 24, 41, 34, BRONZE_LITE)           # shoulders
    img.rect(41, 27, 54, 30, STEEL)                 # gun
    img.rect(41, 31, 52, 33, STEEL)                 # plunger
    img.rect(24, 34, 40, 42, SLAT)                  # slats
    for i in range(25, 40, 3):
        img.rect(i, 35, i + 2, 41, (58, 52, 46, 255))
    img.rect(20, 42, 44, 62, BRONZE)                # skirt
    for r in range(2):
        for c in range(4):
            disc(img, 24 + c * 6, 47 + r * 9, 2.6, BRONZE_DARK, BRONZE_PALE)
    img.rect(19, 60, 45, 63, BRONZE_DARK)
    img.save(path)


if __name__ == "__main__":
    root = sys.argv[1]
    build_texture(os.path.join(root, "media", "textures", "TARDIS_Dalek.png"))
    # the world model, for the casing lying on the ground and in the icon
    build_model(os.path.join(root, "media", "models_X", "TARDIS_Dalek.x"))
    # and the worn model, in bone space, for the clothing item
    # Under Static/Clothes with the Frame and Mesh named after the file, which
    # is how every vanilla static garment is laid out.
    worn_dir = os.path.join(root, "media", "models_X", "Static", "Clothes")
    os.makedirs(worn_dir, exist_ok=True)
    build_model(os.path.join(worn_dir, "TARDIS_DalekWorn.x"),
                scale=WORN_SCALE, drop=WORN_DROP, name="TARDIS_DalekWorn")
    build_icon(os.path.join(root, "media", "ui", "TARDIS_Dalek.png"))
    build_icon(os.path.join(root, "media", "textures", "Item_TARDIS_Dalek.png"))
    print("dalek model, texture and icon written")
