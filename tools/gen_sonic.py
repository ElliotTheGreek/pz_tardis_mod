"""Generates the sonic screwdriver inventory icon.

Like every other asset here it is drawn, not hand-authored, so the whole mod
stays reproducible from source. pngwrite gives rectangles and nothing else,
which suits a 64x64 inventory icon: the tool reads as a stack of bands --
emitter, collar, shaft, grip, cap -- with a lit tip.

    python tools/gen_sonic.py TARDIS/42
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngwrite import Image

STEEL      = (176, 180, 188, 255)
STEEL_LITE = (226, 230, 236, 255)
STEEL_DARK = (108, 112, 122, 255)
STEEL_DEEP = (58, 62, 72, 255)
GRIP       = (34, 34, 40, 255)
GRIP_LITE  = (78, 78, 88, 255)
BRASS      = (168, 140, 72, 255)
GLOW       = (255, 96, 40, 255)
GLOW_CORE  = (255, 226, 178, 255)
HALO       = (255, 118, 56)


def halo(img, cx, cy, rx, ry, peak=150):
    """A soft round glow. pngwrite does not blend, so this is written before
    anything solid and the tool is painted straight over the middle of it.
    Drawn per pixel rather than as rectangles: a rectangular halo reads as a
    box behind the tool, which is exactly how the first attempt looked."""
    for y in range(int(cy - ry), int(cy + ry) + 1):
        for x in range(int(cx - rx), int(cx + rx) + 1):
            d = math.hypot((x - cx) / rx, (y - cy) / ry)
            if d >= 1.0:
                continue
            a = int(peak * (1.0 - d) ** 2)
            if a > 0:
                img.set(x, y, HALO + (a,))


def shaft(img, x0, x1, y0, y1):
    """A cylinder: dark right edge, lit left edge, steel between."""
    img.rect(x0, y0, x1, y1, STEEL)
    img.rect(x0, y0, x0 + 2, y1, STEEL_LITE)
    img.rect(x1 - 2, y0, x1, y1, STEEL_DARK)
    img.rect(x1 - 1, y0, x1, y1, STEEL_DEEP)


def collar(img, x0, x1, y0, y1, c=STEEL_DARK):
    img.rect(x0, y0, x1, y1, c)
    img.rect(x0, y0, x0 + 2, y1, STEEL)
    img.rect(x1 - 1, y0, x1, y1, STEEL_DEEP)


def build_icon(path):
    """64x64 inventory icon: the tool stood on end, emitter lit."""
    img = Image(64, 64, (0, 0, 0, 0))

    # --- the glow around the emitter, laid down first so the solid parts
    #     that follow paint straight over it (pngwrite does not blend)
    halo(img, 32, 11, 20, 18, peak=132)

    # --- emitter: two prongs with the lit crystal held between them
    img.rect(26, 4, 29, 18, STEEL)          # left prong
    img.rect(35, 4, 38, 18, STEEL)          # right prong
    img.rect(26, 4, 27, 18, STEEL_LITE)
    img.rect(37, 4, 38, 18, STEEL_DARK)
    img.rect(29, 6, 35, 18, GLOW)           # crystal
    img.rect(30, 8, 34, 15, GLOW_CORE)

    # --- collar the prongs sit in
    collar(img, 24, 40, 18, 24)
    img.rect(24, 22, 40, 23, BRASS)

    # --- upper shaft
    shaft(img, 26, 38, 24, 32)

    # --- grip: black, ridged, where a hand would go
    img.rect(25, 32, 39, 46, GRIP)
    img.rect(25, 32, 27, 46, GRIP_LITE)
    for y in range(34, 46, 3):
        img.rect(27, y, 37, y + 1, GRIP_LITE)

    # --- lower shaft and the switch on it
    shaft(img, 26, 38, 46, 56)
    img.rect(28, 48, 33, 52, BRASS)

    # --- butt cap
    collar(img, 24, 40, 56, 61)
    img.rect(24, 59, 40, 61, STEEL_DEEP)

    img.save(path)
    return img


if __name__ == "__main__":
    root = sys.argv[1]
    build_icon(os.path.join(root, "media", "ui", "TARDIS_Sonic.png"))
    build_icon(os.path.join(root, "media", "textures", "Item_TARDIS_Sonic.png"))
    print("sonic screwdriver icon written")
