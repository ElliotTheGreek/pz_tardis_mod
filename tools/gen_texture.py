"""Generates the TARDIS police-box texture atlas and the inventory icon."""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngwrite import Image, draw_text_centered, draw_text, text_width

BLUE      = (0,  59, 111, 255)   # classic police-box blue
BLUE_DARK = (0,  40,  78, 255)
BLUE_DEEP = (0,  28,  55, 255)
BLUE_LITE = (18, 84, 145, 255)
WHITE     = (232, 232, 224, 255)
BLACK     = (12, 12, 14, 255)
PANE      = (46, 66, 88, 255)
PANE_LITE = (76, 102, 128, 255)
LAMP      = (236, 234, 214, 255)
LAMP_DIM  = (168, 166, 148, 255)

# Atlas regions (x0, y0, x1, y1) -- kept in sync with gen_model.py via REGIONS.
REGIONS = {
    "side": (0,   0, 120, 208),
    "door": (128, 0, 248, 208),
    "roof": (0,   216, 64, 248),
    "lamp": (72,  216, 104, 248),
    "base": (112, 216, 176, 248),
    "top":  (184, 216, 248, 248),
}

def panel(img, x0, y0, x1, y1):
    """A recessed blue panel with a lit top-left edge and shadowed inset."""
    img.rect(x0, y0, x1, y1, BLUE_LITE)
    img.rect(x0 + 1, y0 + 1, x1 - 1, y1 - 1, BLUE_DEEP)
    img.rect(x0 + 3, y0 + 3, x1 - 3, y1 - 3, BLUE_DARK)

def wall(img, R, is_door):
    x0, y0, x1, y1 = R
    w = x1 - x0
    img.rect(x0, y0, x1, y1, BLUE)

    # --- sign band ------------------------------------------------------
    img.rect(x0, y0 + 4, x1, y0 + 42, BLUE_DEEP)
    img.rect(x0 + 3, y0 + 6, x1 - 3, y0 + 40, WHITE)
    draw_text_centered(img, "POLICE", x0 + w / 2, y0 + 9, BLACK, scale=2, spacing=1)
    draw_text_centered(img, "PUBLIC CALL BOX", x0 + w / 2, y0 + 27, BLACK, scale=1, spacing=1)

    # --- window ---------------------------------------------------------
    wy0, wy1 = y0 + 48, y0 + 100
    img.rect(x0 + 6, wy0, x1 - 6, wy1, WHITE)
    cols, rows = 3, 2
    cw = (x1 - 12 - (cols + 1) * 3) / cols
    ch = (wy1 - wy0 - (rows + 1) * 3) / rows
    for r in range(rows):
        for c in range(cols):
            px = int(x0 + 6 + 3 + c * (cw + 3))
            py = int(wy0 + 3 + r * (ch + 3))
            img.rect(px, py, int(px + cw), int(py + ch), PANE)
            img.rect(px, py, int(px + cw), py + 2, PANE_LITE)

    # --- lower panels ---------------------------------------------------
    py0 = y0 + 106
    ph = (y1 - py0 - 12) // 2
    for r in range(2):
        for c in range(2):
            px = x0 + 6 + c * ((w - 12) // 2)
            pyy = py0 + r * (ph + 4)
            panel(img, px + 2, pyy, px + (w - 12) // 2 - 2, pyy + ph)

    if is_door:
        # centre seam plus handle and Yale lock on the right leaf
        img.rect(x0 + w // 2 - 1, y0 + 44, x0 + w // 2 + 1, y1, BLUE_DEEP)
        img.rect(x0 + w // 2 + 4, y0 + 118, x0 + w // 2 + 12, y0 + 122, BLACK)
        img.rect(x0 + w // 2 + 5, y0 + 128, x0 + w // 2 + 10, y0 + 133, (150, 140, 90, 255))

def build_atlas(path):
    img = Image(256, 256, BLUE_DEEP)
    wall(img, REGIONS["side"], False)
    wall(img, REGIONS["door"], True)

    x0, y0, x1, y1 = REGIONS["roof"]
    img.rect(x0, y0, x1, y1, BLUE_DARK)
    for i in range(y0, y1, 4):
        img.rect(x0, i, x1, i + 1, BLUE_DEEP)

    x0, y0, x1, y1 = REGIONS["lamp"]
    img.rect(x0, y0, x1, y1, LAMP_DIM)
    img.rect(x0 + 3, y0 + 3, x1 - 3, y1 - 3, LAMP)

    x0, y0, x1, y1 = REGIONS["base"]
    img.rect(x0, y0, x1, y1, BLUE_DEEP)
    img.rect(x0, y0, x1, y0 + 3, BLUE_LITE)

    x0, y0, x1, y1 = REGIONS["top"]
    img.rect(x0, y0, x1, y1, BLUE_DARK)
    img.save(path)
    return img

def build_icon(path):
    """64x64 inventory icon: a small front-on police box."""
    img = Image(64, 64, (0, 0, 0, 0))
    img.rect(18, 6, 46, 12, BLUE_DARK)      # roof
    img.rect(20, 2, 44, 6, BLUE_DEEP)       # lamp housing
    img.rect(30, 0, 34, 3, LAMP)            # lamp
    img.rect(19, 12, 45, 60, BLUE)          # body
    img.rect(21, 14, 43, 22, WHITE)         # sign
    draw_text_centered(img, "POLICE", 32, 16, BLACK, scale=1, spacing=0)
    img.rect(22, 25, 42, 37, WHITE)         # window
    for c in range(3):
        img.rect(24 + c * 6, 27, 28 + c * 6, 35, PANE)
    for r in range(2):                      # panels
        for c in range(2):
            panel(img, 22 + c * 10, 40 + r * 9, 30 + c * 10, 47 + r * 9)
    img.rect(19, 60, 45, 63, BLUE_DEEP)     # plinth
    img.save(path)

if __name__ == "__main__":
    root = sys.argv[1]
    build_atlas(os.path.join(root, "media", "textures", "TARDIS_PoliceBox.png"))
    build_icon(os.path.join(root, "media", "ui", "TARDIS_PoliceBox.png"))
    build_icon(os.path.join(root, "media", "textures", "Item_TARDIS_PoliceBox.png"))
    print("textures written")
