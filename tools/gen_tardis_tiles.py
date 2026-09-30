"""The TARDIS interior's structure tileset: walls, doorways, floors and doors.

    python tools/gen_tardis_tiles.py

Writes design/tiles/2x/tardis_interior_01.png -- a 2x tilesheet, 8 columns of
128x256 cells, laid out the way vanilla's own wall sheets are -- and
design/art/interior/room_preview.png, a small room built from every wall and
floor, to judge the set by before it goes anywhere near the game.

The method is the Shuttlecraft mod's (pz_trekship, gen_adirondack_tiles.py),
and the reasons are the same:

* The SURFACES are Gemini's (design/art/interior/*_raw.jpg): flat, front-on
  textures of the roundel wall, the walnut panelling, the service plating, the
  tiled wall, six floors and a door. An image model is good at what a material
  looks like.
* The GEOMETRY is ours. Each texture is projected onto the exact iso face a
  vanilla tile uses -- a floor is the 128x64 diamond at the foot of the cell,
  a west wall stands on the edge from (0,224) to (64,192) and a north wall on
  the edge from (64,192) to (128,224), both 192 px tall. An image model cannot
  hit those to the pixel, and a wall that misses its neighbour by two pixels
  shows as a crack along every corridor.
* The SILHOUETTES are vanilla's. Every wall and doorway takes its alpha from
  the matching industry_01 tile and every door from fixtures_doors_01, so the
  thickness, the top cap and the door opening are the engine's own shapes.
* North faces are lit about 1.2x west faces in vanilla, so the same factor is
  applied here.

Walls are flat, square-edged panels -- the white roundel walls of the classic
console rooms, the walnut of the library and the Victorian rooms, the plating
of the service decks -- so every face is one flat picture with nothing that has
to line up round a curve.

The sheet:
   0  1  2  3   4  5      roundel wall     W N NW SE, W-doorway N-doorway
   8  9 10 11  12 13      walnut panelling
  16 17 18 19  20 21      service plating
  24 25 26 27  28 29      tiled wall
  32..37                  floors: console grating, corridor stone, parquet,
                          carpet, chequer tile, steel plate
  40 41 42 43             the door: W, N, W open, N open (hinged: the open
                          leaf stands out from the wall, as vanilla's does)
"""
import os
import sys

from PIL import Image, ImageStat

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "design", "art", "interior")
OUT = os.path.join(ROOT, "design", "tiles", "2x")
SHEET = "tardis_interior_01"
VANILLA = os.environ.get(
    "PZ_TILES",
    r"D:/SteamLibrary/steamapps/common/Project Zomboid Modding Tools/Tiles/2x")

CW, CH = 128, 256           # a 2x cell
COLS, ROWS = 8, 6
WEST_LIGHT, NORTH_LIGHT = 0.84, 1.0

# Wall styles: the first index of each block of six, and its raw.
WALLS = {"roundel": 0, "wood": 8, "tech": 16, "tile": 24}
FLOORS = {"console": 32, "corridor": 33, "parquet": 34, "carpet": 35, "tile": 36, "steel": 37}
DOOR = 40


def vanilla_cell(sheet, index):
    im = Image.open(os.path.join(VANILLA, sheet + ".png")).convert("RGBA")
    c, r = index % 8, index // 8
    return im.crop((c * CW, r * CH, c * CW + CW, r * CH + CH))


def mask_of(sheet, index):
    return vanilla_cell(sheet, index).split()[3].point(lambda a: 255 if a > 96 else 0)


def raw(name):
    return Image.open(os.path.join(ART, name + "_raw.jpg")).convert("RGB")


def crop_frac(im, f):
    w, h = im.size
    return im.crop((int(w * f), int(h * f), int(w * (1 - f)), int(h * (1 - f))))


# --- face coordinates -------------------------------------------------------

def uv_west(x, y):
    return x / 64.0, (y - 32 + x / 2.0) / 192.0


def uv_north(x, y):
    return (x - 64) / 64.0, (y - (x - 64) / 2.0) / 192.0


def project(tex, side):
    """The texture laid across the whole face of one side, in a full cell."""
    tw, th = tex.size
    if side == "W":
        data = (tw / 64.0, 0, 0, th / 384.0, th / 192.0, -32 * th / 192.0)
    else:
        data = (tw / 64.0, 0, -tw, -th / 384.0, th / 192.0, 32 * th / 192.0)
    return tex.transform((CW, CH), Image.AFFINE, data, resample=Image.BICUBIC)


def shade(im, k):
    return im.point(lambda v: max(0, min(255, int(v * k))))


def face_tile(tex, mask, sides, cap):
    """Paint a wall silhouette: the face where the face is, cap colour elsewhere."""
    faces = {s: shade(project(tex, s), WEST_LIGHT if s == "W" else NORTH_LIGHT)
             for s in sides}
    out = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    src = out.load()
    m = mask.load()
    fp = {s: f.load() for s, f in faces.items()}
    top = tuple(min(255, int(c * 1.15)) for c in cap)
    for y in range(CH):
        for x in range(CW):
            if not m[x, y]:
                continue
            side = sides[0] if len(sides) == 1 else ("W" if x < 64 else "N")
            u, v = (uv_west if side == "W" else uv_north)(x, y)
            if 0.0 <= u <= 1.0 and 0.0 <= v <= 1.0:
                r, g, b = fp[side][x, y]
                src[x, y] = (r, g, b, 255)
            elif v < 0.0:
                src[x, y] = top + (255,)
            else:
                src[x, y] = tuple(int(c * 0.8) for c in cap) + (255,)
    return out


def inset_tile(tex, mask, side, urange=None, vrange=None):
    """A texture fitted to the uv bounds of a silhouette on one face."""
    uvf = uv_west if side == "W" else uv_north
    m = mask.load()
    us, vs = [], []
    for y in range(CH):
        for x in range(CW):
            if m[x, y]:
                u, v = uvf(x, y)
                us.append(u)
                vs.append(v)
    u0, u1 = urange or (min(us), max(us))
    v0, v1 = vrange or (min(vs), max(vs))
    tw, th = tex.size
    k = WEST_LIGHT if side == "W" else NORTH_LIGHT
    t = shade(tex, k).load()
    out = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    o = out.load()
    for y in range(CH):
        for x in range(CW):
            if not m[x, y]:
                continue
            u, v = uvf(x, y)
            if not (u0 <= u <= u1 and v0 <= v <= v1):
                continue
            tx = min(tw - 1, max(0, int((u - u0) / (u1 - u0) * tw)))
            ty = min(th - 1, max(0, int((v - v0) / (v1 - v0) * th)))
            r, g, b = t[tx, ty]
            o[x, y] = (r, g, b, 255)
    return out


def floor_tile(tex, mask):
    tw, th = tex.size
    data = (tw / 128.0, tw / 64.0, -3.5 * tw, -th / 128.0, th / 64.0, -2.5 * th)
    f = tex.transform((CW, CH), Image.AFFINE, data, resample=Image.BICUBIC)
    out = Image.new("RGBA", (CW, CH), (0, 0, 0, 0))
    out.paste(f, (0, 0), mask)
    return out


def cornice(tex):
    band = tex.crop((0, 0, tex.width, max(2, tex.height // 30)))
    return tuple(int(c) for c in ImageStat.Stat(band).mean[:3])


# --- the sheet ---------------------------------------------------------------

def wall_texture(name):
    """One wall section's picture, 72 x 216 (a face is 64 wide and 192 tall;
    the margin is what the silhouette's cap and ends sample)."""
    return raw(name).resize((72, 216), Image.LANCZOS)


def build():
    tiles = {}
    for style, base in WALLS.items():
        tex = wall_texture("wall_" + style)
        cap = cornice(raw("wall_" + style))
        for k, sides in ((0, ("W",)), (1, ("N",)), (2, ("W", "N")), (3, ("W",))):
            tiles[base + k] = face_tile(tex, mask_of("industry_01", k), sides, cap)
        tiles[base + 4] = face_tile(tex, mask_of("industry_01", 10), ("W",), cap)
        tiles[base + 5] = face_tile(tex, mask_of("industry_01", 11), ("N",), cap)

    floor_mask = mask_of("floors_interior_tilesandwood_01", 18)
    # How much of each raw is one square: the tile and the corridor stone
    # were drawn as a grid of slabs, and one square is one slab or two.
    crops = {"console": 0.25, "corridor": 0.0, "parquet": 0.25, "carpet": 0.3,
             "tile": 0.25, "steel": 0.25}
    for name, idx in FLOORS.items():
        tex = crop_frac(raw("floor_" + name), crops[name]).resize((128, 128), Image.LANCZOS)
        tiles[idx] = floor_tile(tex, floor_mask)

    door = raw("door").resize((64, 180), Image.LANCZOS)
    # Closed: the leaf in the doorway, on the face it closes. Open: vanilla's
    # own open silhouette, which stands out from the wall at right angles --
    # so the W door's open leaf is drawn on the north-facing plane and the
    # N door's on the west-facing one.
    tiles[DOOR + 0] = inset_tile(door, mask_of("fixtures_doors_01", 0), "W")
    tiles[DOOR + 1] = inset_tile(door, mask_of("fixtures_doors_01", 1), "N")
    tiles[DOOR + 2] = inset_tile(door, mask_of("fixtures_doors_01", 2), "N")
    tiles[DOOR + 3] = inset_tile(door, mask_of("fixtures_doors_01", 3), "W")
    return tiles


# --- the room preview ------------------------------------------------------

def put(canvas, tile, ox, oy, tx, ty):
    canvas.alpha_composite(tile, (ox + (tx - ty) * 64 - 64, oy + (tx + ty) * 32))


def preview(tiles, path):
    """Four little rooms side by side, one per wall style, each on a
    different floor, with a door in its west wall."""
    W, H = 4, 4
    rooms = [("roundel", "console"), ("wood", "parquet"), ("tech", "steel"),
             ("tile", "tile"), ("roundel", "corridor"), ("wood", "carpet")]
    cw = 64 * (W + H) + 160
    canvas = Image.new("RGBA", (cw * len(rooms) // 2, 2 * (32 * (W + H) + 300)), (20, 20, 26, 255))
    for n, (style, floor) in enumerate(rooms):
        ox = (n % 3) * cw + 64 * H + 64
        oy = (n // 3) * (32 * (W + H) + 300) + 230
        base = WALLS[style]
        for ty in range(H):
            for tx in range(W):
                put(canvas, tiles[FLOORS[floor]], ox, oy, tx, ty)
        for ty in range(H):
            for tx in range(W):
                if tx == 0 and ty == 0:
                    put(canvas, tiles[base + 2], ox, oy, tx, ty)
                elif ty == 0:
                    put(canvas, tiles[base + 1], ox, oy, tx, ty)
                elif tx == 0:
                    if ty == 2:
                        put(canvas, tiles[base + 4], ox, oy, tx, ty)
                        put(canvas, tiles[DOOR + (2 if n % 2 else 0)], ox, oy, tx, ty)
                    else:
                        put(canvas, tiles[base + 0], ox, oy, tx, ty)
    canvas.save(path)


def main():
    tiles = build()
    sheet = Image.new("RGBA", (CW * COLS, CH * ROWS), (0, 0, 0, 0))
    for i, t in tiles.items():
        sheet.paste(t, ((i % COLS) * CW, (i // COLS) * CH))
    os.makedirs(OUT, exist_ok=True)
    out = os.path.join(OUT, SHEET + ".png")
    sheet.save(out)
    preview(tiles, os.path.join(ART, "room_preview.png"))
    for i in sorted(tiles):
        if tiles[i].split()[3].getbbox() is None:
            sys.exit("tile %d came out empty" % i)
    print("wrote %s (%d tiles) and room_preview.png" % (out, len(tiles)))


if __name__ == "__main__":
    main()
