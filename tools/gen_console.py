"""Generates the TARDIS control console: hexagonal desk plus time rotor."""
import sys, os, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngwrite import Image, draw_text_centered
from meshbuild import MeshBuilder

TEX = 256
REGIONS = {
    "panel": (0, 0, 128, 96),      # sloped face of the desk
    "top":   (128, 0, 256, 96),    # control surface
    "rotor": (0, 104, 64, 232),    # glass column
    "cap":   (72, 104, 136, 168),  # rotor collar
    "base":  (144, 104, 208, 168), # plinth
}

DARK   = (38, 40, 46, 255)
DARKER = (24, 26, 30, 255)
STEEL  = (96, 100, 110, 255)
BRASS  = (176, 142, 74, 255)
GLASS  = (140, 214, 236, 255)
GLASS2 = (196, 240, 252, 255)
GREEN  = (96, 220, 130, 255)
RED    = (222, 86, 74, 255)
AMBER  = (238, 176, 60, 255)
WHITE  = (232, 232, 224, 255)


def build_texture(path):
    img = Image(TEX, TEX, DARKER)

    # sloped panel: brushed metal with a row of switches and dials
    x0, y0, x1, y1 = REGIONS["panel"]
    img.rect(x0, y0, x1, y1, DARK)
    for i in range(y0, y1, 3):
        img.rect(x0, i, x1, i + 1, DARKER)
    img.frame(x0 + 2, y0 + 2, x1 - 2, y1 - 2, STEEL, 1)
    for i in range(6):
        cx = x0 + 12 + i * 19
        img.rect(cx, y0 + 14, cx + 12, y0 + 26, STEEL)
        img.rect(cx + 2, y0 + 16, cx + 10, y0 + 24,
                 (GREEN, AMBER, RED, GLASS, WHITE, BRASS)[i % 6])
    for i in range(5):
        cx = x0 + 18 + i * 22
        img.rect(cx, y0 + 40, cx + 14, y0 + 44, BRASS)
        img.rect(cx + 5, y0 + 44, cx + 9, y0 + 56, STEEL)
    for i in range(9):
        cx = x0 + 8 + i * 13
        img.rect(cx, y0 + 66, cx + 8, y0 + 78, DARKER)
        img.frame(cx, y0 + 66, cx + 8, y0 + 78, STEEL, 1)

    # control surface: roundel motif and gauges
    x0, y0, x1, y1 = REGIONS["top"]
    img.rect(x0, y0, x1, y1, DARK)
    img.frame(x0 + 2, y0 + 2, x1 - 2, y1 - 2, BRASS, 2)
    for r in range(2):
        for c in range(4):
            cx = x0 + 16 + c * 27
            cy = y0 + 20 + r * 40
            img.rect(cx, cy, cx + 20, cy + 20, DARKER)
            img.frame(cx, cy, cx + 20, cy + 20, STEEL, 2)
            img.rect(cx + 6, cy + 6, cx + 14, cy + 14,
                     (GLASS, AMBER, GREEN, RED)[(r * 4 + c) % 4])

    # rotor: vertical glass column with internal glow bands
    x0, y0, x1, y1 = REGIONS["rotor"]
    img.rect(x0, y0, x1, y1, GLASS)
    for i in range(y0, y1, 8):
        img.rect(x0, i, x1, i + 3, GLASS2)
    img.rect(x0, y0, x0 + 6, y1, GLASS2)
    img.rect(x1 - 6, y0, x1, y1, (108, 176, 200, 255))

    # collar and plinth
    x0, y0, x1, y1 = REGIONS["cap"]
    img.rect(x0, y0, x1, y1, BRASS)
    img.rect(x0 + 4, y0 + 4, x1 - 4, y1 - 4, (140, 112, 58, 255))

    x0, y0, x1, y1 = REGIONS["base"]
    img.rect(x0, y0, x1, y1, DARKER)
    img.rect(x0, y0, x1, y0 + 4, STEEL)
    img.save(path)


def hexagon(radius, z):
    """Six points of a flat-topped hexagon at height z."""
    pts = []
    for i in range(6):
        a = math.pi / 6 + i * math.pi / 3
        pts.append((radius * math.cos(a), radius * math.sin(a), z))
    return pts


def build_model(path):
    mb = MeshBuilder(TEX, TEX, up_axis="y")
    P = lambda p: mb.place(p[0], p[1], p[2])

    R_BOTTOM, R_TOP = 0.62, 0.40
    Z_BASE, Z_DESK, Z_SURF = 0.0, 0.10, 0.62

    low_out = hexagon(R_BOTTOM, Z_BASE)
    low_in = hexagon(R_BOTTOM, Z_DESK)
    up_out = hexagon(R_TOP, Z_SURF)
    inner = hexagon(0.16, Z_SURF)

    for i in range(6):
        j = (i + 1) % 6
        nx = (low_out[i][0] + low_out[j][0]) / 2
        ny = (low_out[i][1] + low_out[j][1]) / 2
        ln = max(1e-6, math.hypot(nx, ny))
        normal = mb.place(nx / ln, ny / ln, 0.35)

        # plinth skirt
        mb.quad(P(low_out[i]), P(low_out[j]), P(low_in[j]), P(low_in[i]),
                REGIONS["base"], normal)
        # sloped control face
        mb.quad(P(low_in[i]), P(low_in[j]), P(up_out[j]), P(up_out[i]),
                REGIONS["panel"], normal)
        # flat surface ring running in to the rotor collar
        mb.quad(P(up_out[i]), P(up_out[j]), P(inner[j]), P(inner[i]),
                REGIONS["top"], mb.place(0, 0, 1))

    # time rotor: hexagonal glass column with a collar top and bottom
    R_ROTOR = 0.15
    Z_ROTOR_TOP = 1.65
    low = hexagon(R_ROTOR, Z_SURF)
    high = hexagon(R_ROTOR, Z_ROTOR_TOP)
    collar_lo = hexagon(R_ROTOR + 0.05, Z_SURF)
    collar_hi = hexagon(R_ROTOR + 0.05, Z_SURF + 0.08)
    cap_lo = hexagon(R_ROTOR + 0.05, Z_ROTOR_TOP - 0.08)
    cap_hi = hexagon(R_ROTOR + 0.05, Z_ROTOR_TOP)

    for i in range(6):
        j = (i + 1) % 6
        nx = (low[i][0] + low[j][0]) / 2
        ny = (low[i][1] + low[j][1]) / 2
        ln = max(1e-6, math.hypot(nx, ny))
        normal = mb.place(nx / ln, ny / ln, 0)
        mb.quad(P(low[i]), P(low[j]), P(high[j]), P(high[i]),
                REGIONS["rotor"], normal)
        mb.quad(P(collar_lo[i]), P(collar_lo[j]), P(collar_hi[j]), P(collar_hi[i]),
                REGIONS["cap"], normal)
        mb.quad(P(cap_lo[i]), P(cap_lo[j]), P(cap_hi[j]), P(cap_hi[i]),
                REGIONS["cap"], normal)

    # close the top of the rotor
    centre = mb.place(0, 0, Z_ROTOR_TOP)
    for i in range(6):
        j = (i + 1) % 6
        mb.tri(centre, P(high[i]), P(high[j]), REGIONS["cap"], mb.place(0, 0, 1))

    return mb.emit(path, "TARDISConsole", "TARDIS_Console.png")


if __name__ == "__main__":
    root = sys.argv[1]
    build_texture(os.path.join(root, "media", "textures", "TARDIS_Console.png"))
    nv, nf = build_model(os.path.join(root, "media", "models_X", "TARDIS_Console.x"))
    print(f"console: {nv} verts, {nf} tris")
