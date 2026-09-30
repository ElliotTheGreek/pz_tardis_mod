"""The TARDIS's six decks, drafted as BuildingEd files and checked.

    python tools/gen_tardis_decks.py            # every deck
    python tools/gen_tardis_decks.py console    # just one
    python tools/gen_tardis_decks.py --force    # overwrite files BuildingEd saved

Each deck is a small spec below: rooms as rectangles with a wall style and a
floor, doors on edges, and furniture placed by name and facing. From it this
writes

  design/buildinged/TARDIS_<Deck>.tbx      for BuildingEd; the game's layout
                                           is generated from these files
                                           (tools/gen_tardis_lua.py), so an
                                           edit made there is what gets built
  design/art/interior/decks/<deck>.png     an iso render of it, made of the
                                           real tiles, to vet first

and refuses a spec that does not hold together: furniture off the floor or
across two rooms, two pieces on one square, a door that is not on a wall, a
wall-hung piece with no wall behind it, or anything on a deck's landing.

**Once the author has opened one in BuildingEd it is theirs.** This writes a
`Generator` property into every file and will not overwrite a file that has
lost it -- pass --force to replace it anyway. (The Shuttlecraft mod's
gen_adirondack_sections.py, whose rules these are.)

Coordinates: x runs east, y south, (0,0) is the north-west square. Walls only
exist on the north and west edges of a square (the engine's rule), so
anything backed onto a wall stands against a north or a west one, as vanilla's
own furniture does. Facings are the furniture sheet's: W and N back onto a
wall, E and S face west and north. A door `("N", x, y)` sits on the north edge
of square (x, y); `("W", x, y)` on its west edge.

**Rooms are rectangles and walls are flat.** No chamfers, no stepped
"octagon": every room is a clean box, and every deck is rooms off a corridor
or round a hall, so each has one job and a door to it.
"""
import json
import os
import sys
from xml.sax.saxutils import quoteattr

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_tardis_tiles as T  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TILES = os.path.join(ROOT, "design", "tiles", "2x")
BED = os.path.join(ROOT, "design", "buildinged")
OUT = os.path.join(ROOT, "design", "art", "interior", "decks")
S1, S2 = "tardis_interior_01", "tardis_interior_02"
MARKER = "gen_tardis_decks"
CW, CH = 128, 256
VANILLA = T.VANILLA

# The one vanilla tile aboard: bare soil under the crop beds. Vanilla's own
# dig check knows soil by its sprite name and nothing else
# (ISShovelGroundCursor.GetDirtGravelSand: "blends_natural_01_*"), so a floor
# of our own would grow the ship's first harvest and never let anybody dig it
# again.
SOIL = "blends_natural_01_64"


def room(name, x0, y0, x1, y1, wall, floor, internal="room"):
    """A room covering x0..x1, y0..y1 inclusive, in a wall style
    (gen_tardis_tiles.WALLS) on a floor (FLOORS, or "soil")."""
    return dict(name=name, rect=(x0, y0, x1, y1), wall=wall, floor=floor, internal=internal)


def row(name, facing, xs, y):
    return [(name, facing, x, y) for x in xs]


def col(name, facing, x, ys):
    return [(name, facing, x, y) for y in ys]


DECKS = {}

# --- Deck 1: the console room ----------------------------------------------
# The classic console room: white roundel walls, the hexagonal console and its
# time rotor in the middle of a square chamber, the police box doors in the
# north wall with the scanner beside them. Round the walls, the hold -- six
# roundel lockers -- and the Doctor's corner of books, a Chesterfield and a
# wingback. Off it through two doors in its east wall, the armoury and a
# galley corner, so the deck you arrive on can arm and feed you.
DECKS["console"] = dict(
    title="Console Room", z=5, size=(24, 17), landing=(8, 2),
    rooms=[
        room("Console Room", 0, 0, 16, 16, "roundel", "console", "tardisconsole"),
        room("Armoury", 17, 0, 23, 7, "tech", "steel", "armoury"),
        room("Galley Corner", 17, 8, 23, 16, "tile", "tile", "kitchen"),
    ],
    doors=[("W", 17, 4), ("W", 17, 12)],
    furniture=(
        [("console", "W", 7, 7),
         # The doors out, in the north wall, and the landing in front of them.
         ("main_doors_l", "N", 8, 0), ("main_doors_r", "N", 9, 0),
         ("scanner", "N", 11, 0), ("scanner", "N", 6, 0),
         ("sonic_case", "N", 11, 0), ("wall_clock", "N", 4, 0),
         ("roundel_light", "N", 2, 0), ("roundel_light", "N", 14, 0),
         ("roundel_light", "W", 0, 4), ("roundel_light", "W", 0, 12),
         ("hat_stand", "W", 12, 1), ("potted_fern", "W", 16, 0), ("potted_fern", "W", 0, 0)]
        # The hold, along the west wall.
        + col("hold_locker", "W", 0, (5, 6, 7, 9, 10, 11))
        + [("painting_gallifrey", "W", 0, 8)]
        # The Doctor's corner, south-west: books, a sofa, a chair and a lamp.
        + col("bookcase", "W", 0, (13, 14, 15, 16))
        + [("chesterfield", "S", 2, 16), ("side_table", "W", 4, 16),
           ("wingback_chair", "E", 5, 14), ("wingback_chair", "N", 2, 12)]
        # South and east of the console: somewhere to sit and wait.
        + [("chesterfield", "S", 11, 16), ("side_table", "W", 13, 16),
           ("wingback_chair", "E", 16, 8), ("side_table", "W", 16, 9),
           ("wingback_chair", "E", 16, 10), ("potted_fern", "W", 16, 16)]
        # The armoury: a gun cabinet for each rack of the old bay, trunks of
        # the rest by the door.
        + row("gun_cabinet", "N", range(18, 24), 0)
        + col("steamer_trunk", "W", 17, (1, 2, 6, 7))
        + [("roundel_light", "W", 17, 3)]
        # The galley corner: one run along the north wall -- counter, sink,
        # range, counter -- the cold and the dry stores on the west wall, and a
        # table in the middle with the aisle kept clear.
        + [("kitchen_counter", "N", 18, 8), ("kitchen_sink", "N", 20, 8),
           ("kitchen_range", "N", 21, 8), ("kitchen_counter", "N", 22, 8)]
        + col("fridge", "W", 17, (9, 10))
        + col("pantry_dresser", "W", 17, (14, 15, 16))
        + [("dining_table", "N", 20, 12), ("dining_chair", "N", 20, 11), ("dining_chair", "N", 21, 11),
           ("dining_chair", "S", 20, 13), ("dining_chair", "S", 21, 13),
           ("roundel_light", "W", 17, 11)]
    ))

# --- Deck 2: habitation -------------------------------------------------------
# A roundel corridor east to west, three rooms north of it and three south:
# two bedrooms and a bathroom, then a dormitory, the Wardrobe (racks of coats
# and scarves round a spiral stair) and a guest room.
DECKS["housing"] = dict(
    title="Habitation Deck", z=4, size=(24, 20), landing=(2, 9),
    rooms=[
        room("Corridor", 0, 8, 23, 10, "roundel", "corridor", "hall"),
        room("Bedroom", 0, 0, 7, 7, "wood", "carpet", "bedroom"),
        room("Companion's Room", 8, 0, 15, 7, "wood", "carpet", "bedroom"),
        room("Bathroom", 16, 0, 23, 7, "tile", "tile", "bathroom"),
        room("Dormitory", 0, 11, 7, 19, "wood", "carpet", "bedroom"),
        room("The Wardrobe", 8, 11, 16, 19, "wood", "parquet", "wardrobe"),
        room("Guest Room", 17, 11, 23, 19, "wood", "carpet", "bedroom"),
    ],
    doors=[("N", 4, 8), ("N", 12, 8), ("N", 20, 8), ("N", 3, 11), ("N", 11, 11), ("N", 19, 11)],
    furniture=(
        # corridor lights
        row("roundel_light", "N", (7, 15), 8)
        + [("potted_fern", "W", 23, 8), ("painting_gallifrey", "N", 9, 8)]
        # bedroom
        + [("bed_double", "N", 1, 0), ("nightstand", "N", 0, 0), ("nightstand", "N", 3, 0),
           ("wardrobe", "N", 5, 0), ("wardrobe", "N", 6, 0), ("painting_gallifrey", "N", 4, 0),
           ("writing_desk", "W", 0, 3), ("dining_chair", "E", 1, 3),
           ("wingback_chair", "S", 6, 7), ("potted_fern", "W", 7, 5), ("roundel_light", "W", 0, 6)]
        # companion's room
        + [("bed_double", "N", 9, 0), ("nightstand", "N", 8, 0), ("nightstand", "N", 11, 0),
           ("wardrobe", "N", 13, 0), ("wardrobe", "N", 14, 0), ("wall_clock", "N", 12, 0),
           ("writing_desk", "W", 8, 3), ("dining_chair", "E", 9, 3),
           ("wingback_chair", "S", 14, 7), ("potted_fern", "W", 15, 5), ("roundel_light", "W", 8, 6)]
        # bathroom
        + [("bathtub", "N", 17, 0), ("bathtub", "N", 21, 0), ("toilet", "N", 20, 0),
           ("toilet", "N", 23, 0)]
        + col("wash_basin", "W", 16, (2, 3, 4, 5))
        + [("potted_fern", "W", 23, 6), ("roundel_light", "N", 19, 0)]
        # dormitory: four singles
        + [("bed_single", "W", 0, 12), ("nightstand", "W", 0, 14), ("bed_single", "W", 0, 15),
           ("bed_single", "W", 0, 17), ("nightstand", "W", 0, 19),
           ("wardrobe", "N", 5, 11), ("wardrobe", "N", 6, 11), ("wardrobe", "N", 7, 11),
           ("dining_table", "N", 4, 16), ("dining_chair", "S", 4, 17), ("dining_chair", "S", 5, 17),
           ("potted_fern", "W", 7, 19)]
        # the Wardrobe
        + row("wardrobe", "N", (8, 9, 10, 12, 13, 14, 15), 11)
        + [("clothes_rail", "N", 9, 13), ("clothes_rail", "N", 12, 13),
           ("clothes_rail", "N", 9, 16), ("clothes_rail", "N", 12, 16),
           ("spiral_stair", "W", 16, 18), ("hat_stand", "W", 15, 18), ("hat_stand", "W", 8, 19),
           ("roundel_light", "W", 8, 15)]
        # guest room
        + [("bed_double", "W", 17, 13), ("nightstand", "W", 17, 12), ("nightstand", "W", 17, 15),
           ("wardrobe", "N", 21, 11), ("wardrobe", "N", 22, 11),
           ("wingback_chair", "S", 21, 19), ("side_table", "W", 22, 19), ("potted_fern", "W", 23, 19)]
    ))

# --- Deck 3: stores ----------------------------------------------------------------
# The storeroom: shelving in aisles, lockers and benches on the north wall, the
# trunks of the heavy armoury along the south. East of it the infirmary and a
# workshop.
DECKS["storage"] = dict(
    title="Stores Deck", z=3, size=(24, 20), landing=(2, 2),
    rooms=[
        room("Storeroom", 0, 0, 15, 19, "tech", "steel", "storage"),
        room("Infirmary", 16, 0, 23, 11, "roundel", "tile", "medical"),
        room("Workshop", 16, 12, 23, 19, "tech", "steel", "workshop"),
    ],
    doors=[("W", 16, 9), ("W", 16, 17)],
    furniture=(
        row("tool_locker", "N", range(1, 7), 0)
        + [("workbench", "N", 8, 0), ("workbench", "N", 11, 0), ("roundel_light", "N", 7, 0),
           ("tool_locker", "N", 13, 0), ("tool_locker", "N", 14, 0), ("tool_locker", "N", 15, 0)]
        + col("store_shelf", "W", 0, range(5, 19))
        + [f for y in (5, 9, 13) for f in row("store_shelf", "N", range(3, 13), y)]
        + row("steamer_trunk", "S", range(2, 13), 19)
        # infirmary
        + [("sickbay_bed", "N", x, 0) for x in (17, 19, 21, 23)]
        + col("medical_cabinet", "W", 16, (3, 4, 5, 6))
        + [("wash_basin", "W", 16, 7), ("medical_cabinet", "N", 18, 0), ("medical_cabinet", "N", 20, 0),
           ("roundel_light", "N", 22, 0), ("potted_fern", "W", 23, 11), ("wingback_chair", "S", 20, 11)]
        # workshop
        + [("workbench", "N", 17, 12), ("workbench", "N", 20, 12), ("tool_locker", "N", 23, 12),
           ("tool_locker", "W", 16, 14), ("tool_locker", "W", 16, 15), ("store_shelf", "W", 16, 19),
           ("roundel_light", "N", 19, 12)]
    ))

# --- Deck 4: the library --------------------------------------------------------------
# Walnut and books: shelves round the walls and four ranks of stacks, a
# reading corner; east of it an observatory and the archive of records and tapes.
DECKS["library"] = dict(
    title="Library Deck", z=2, size=(24, 20), landing=(12, 2),
    rooms=[
        room("Library", 0, 0, 15, 19, "wood", "parquet", "library"),
        room("Observatory", 16, 0, 23, 11, "roundel", "carpet", "observatory"),
        room("Archive", 16, 12, 23, 19, "wood", "carpet", "archive"),
    ],
    doors=[("W", 16, 6), ("W", 16, 18)],
    furniture=(
        row("bookcase", "N", range(0, 7), 0)
        + [("wall_clock", "N", 7, 0), ("painting_gallifrey", "N", 8, 0)]
        + row("bookcase", "N", range(9, 15), 0)
        + [("gramophone", "N", 15, 0)]
        + col("bookcase", "W", 0, range(1, 20))
        + [f for y in (5, 9, 13, 17) for f in row("bookcase", "N", range(3, 9), y)]
        # the reading corner
        + [("globe", "W", 11, 6), ("telescope", "W", 14, 5),
           ("writing_desk", "N", 11, 10), ("dining_chair", "S", 11, 11), ("dining_chair", "S", 12, 11),
           ("chesterfield", "S", 11, 19), ("side_table", "W", 13, 19),
           ("wingback_chair", "E", 15, 15), ("wingback_chair", "E", 15, 17), ("side_table", "W", 15, 16),
           ("potted_fern", "W", 15, 19)]
        # observatory
        + [("telescope", "W", 19, 3), ("telescope", "W", 22, 3), ("globe", "W", 20, 7),
           ("wingback_chair", "S", 18, 11), ("wingback_chair", "S", 21, 11), ("side_table", "W", 19, 11),
           ("scanner", "N", 20, 0), ("roundel_light", "N", 17, 0), ("roundel_light", "N", 23, 0)]
        # archive: records and tapes
        + row("gramophone", "N", (17, 18, 19), 12)
        + row("bookcase", "N", (20, 21, 22, 23), 12)
        + col("bookcase", "W", 16, (13, 14, 15, 16))
        + [("wingback_chair", "S", 20, 19), ("side_table", "W", 21, 19), ("roundel_light", "W", 16, 17)]
    ))

# --- Deck 5: the galley ------------------------------------------------------------------
DECKS["galley"] = dict(
    title="Galley Deck", z=1, size=(24, 18), landing=(5, 12),
    rooms=[
        room("Kitchen", 0, 0, 11, 17, "tile", "tile", "kitchen"),
        room("Dining Room", 12, 0, 23, 10, "wood", "parquet", "dining"),
        room("Pantry", 12, 11, 23, 17, "tech", "steel", "pantry"),
    ],
    doors=[("W", 12, 4), ("W", 12, 14)],
    furniture=(
        [("kitchen_counter", "N", 0, 0), ("kitchen_sink", "N", 2, 0), ("kitchen_range", "N", 3, 0),
         ("kitchen_range", "N", 4, 0), ("kitchen_counter", "N", 5, 0), ("kitchen_sink", "N", 7, 0),
         ("kitchen_counter", "N", 8, 0), ("fridge", "N", 10, 0), ("fridge", "N", 11, 0)]
        + col("fridge", "W", 0, (2, 3, 4))
        + col("pantry_dresser", "W", 0, (6, 7, 8, 9, 10))
        # a back-to-back island
        + [("kitchen_counter", "N", 4, 5), ("kitchen_counter", "S", 4, 6),
           ("kitchen_counter", "N", 7, 5), ("kitchen_counter", "S", 7, 6),
           ("roundel_light", "W", 0, 12), ("potted_fern", "W", 11, 17)]
        # dining room: two long tables
        + [f for tx in (14, 19) for ty in (3, 7)
           for f in (("dining_table", "N", tx, ty), ("dining_chair", "N", tx, ty - 1),
                     ("dining_chair", "N", tx + 1, ty - 1), ("dining_chair", "S", tx, ty + 1),
                     ("dining_chair", "S", tx + 1, ty + 1))]
        + [("painting_gallifrey", "N", 17, 0), ("wall_clock", "N", 21, 0),
           ("pantry_dresser", "N", 13, 0), ("pantry_dresser", "N", 23, 0),
           ("potted_fern", "W", 23, 10), ("potted_fern", "W", 12, 10)]
        # pantry
        + row("store_shelf", "N", range(13, 24), 11)
        + [("store_shelf", "W", 12, 12), ("store_shelf", "W", 12, 16), ("store_shelf", "W", 12, 17)]
        + row("store_shelf", "N", range(15, 22), 14)
        + row("fridge", "N", (22, 23), 14)
    ))

# --- Deck 6: the gardens --------------------------------------------------------------------
# Crop beds on bare soil under grow lamps (planted by TARDIS_Build, not placed
# here: every square of GARDEN_BEDS that is not an aisle), the potting bench and
# the seed cabinets, and a stable for the livestock.
DECKS["growing"] = dict(
    title="Gardens", z=0, size=(25, 20), landing=(15, 10),
    rooms=[
        room("Hydroponic Garden", 0, 0, 16, 19, "wood", "soil", "garden"),
        room("Stable", 17, 0, 24, 19, "tech", "steel", "stable"),
    ],
    doors=[("W", 17, 10)],
    beds=(2, 2, 13, 17),
    furniture=(
        row("grow_lamp", "N", (2, 4, 6, 8, 10, 12, 14), 0)
        + col("grow_lamp", "W", 0, (3, 7, 11, 15))
        + [("seed_cabinet", "N", 0, 0), ("seed_cabinet", "N", 1, 0),
           ("potting_bench", "N", 15, 0), ("water_trough", "W", 0, 18),
           ("garden_bench", "S", 5, 19), ("garden_bench", "S", 9, 19),
           ("potted_fern", "W", 16, 19), ("potted_fern", "W", 0, 1), ("seed_cabinet", "W", 0, 5)]
        + [("water_trough", "N", 18, 0), ("water_trough", "N", 21, 0), ("store_shelf", "N", 23, 0),
           ("store_shelf", "N", 24, 0), ("roundel_light", "W", 17, 5), ("roundel_light", "W", 17, 15)]
    ))

ORDER = ["console", "housing", "storage", "library", "galley", "growing"]


# --- the furniture the specs can name --------------------------------------------------

def catalogue():
    with open(os.path.join(ROOT, "design", "tiles", S2 + ".json")) as f:
        index = json.load(f)
    cat = {}
    for name, rec in index.items():
        cat[name] = dict(layer=rec["layer"], use=rec.get("use", {}),
                         facings={fc: [(x, y, "%s_%03d" % (S2, i)) for x, y, i in sq]
                                  for fc, sq in rec["facings"].items()})
    return cat


def t1(i):
    return "%s_%03d" % (S1, i)


def floor_tile(name):
    if name == "soil":
        return SOIL
    return t1(T.FLOORS[name])


# --- checking a deck ----------------------------------------------------------------

def grid_of(key, sec):
    W, H = sec["size"]
    g = [[0] * W for _ in range(H)]
    for k, r in enumerate(sec["rooms"], start=1):
        x0, y0, x1, y1 = r["rect"]
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if not (0 <= x < W and 0 <= y < H):
                    raise SystemExit("%s: room %s leaves the deck" % (key, r["name"]))
                if g[y][x]:
                    raise SystemExit("%s: room %s overlaps another" % (key, r["name"]))
                g[y][x] = k
    return g


def at(g, x, y):
    return g[y][x] if 0 <= y < len(g) and 0 <= x < len(g[0]) else 0


def bed_squares(sec, g):
    """The crop beds: every square in the rectangle that is not an aisle
    (every third column is left to walk down)."""
    if "beds" not in sec:
        return []
    x0, y0, x1, y1 = sec["beds"]
    return [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1) if x % 3 != 0]


def check(key, sec, cat):
    g = grid_of(key, sec)
    problems, taken = [], {}
    lx, ly = sec["landing"]
    landing = {(lx + dx, ly + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)}
    if not at(g, lx, ly):
        problems.append("the landing %d,%d is off the floor" % (lx, ly))
    for sq in bed_squares(sec, g):
        taken[sq] = "a crop bed"
    walled = set()
    for name, facing, x, y in sec["furniture"]:
        if name not in cat:
            problems.append("%s is not in the furniture sheet" % name)
            continue
        if facing not in cat[name]["facings"]:
            problems.append("%s has no %s facing" % (name, facing))
            continue
        layer = cat[name]["layer"]
        squares = [(x + dx, y + dy) for dx, dy, _ in cat[name]["facings"][facing]]
        rooms = {at(g, sx, sy) for sx, sy in squares}
        if 0 in rooms:
            problems.append("%s %s at %d,%d is off the floor" % (name, facing, x, y))
        elif len(rooms) > 1:
            problems.append("%s %s at %d,%d straddles two rooms" % (name, facing, x, y))
        if layer in ("WallFurniture", "Walls"):
            nx, ny = (x - 1, y) if facing == "W" else (x, y - 1)
            if at(g, nx, ny) == at(g, x, y):
                problems.append("%s %s at %d,%d has no wall behind it" % (name, facing, x, y))
            if (x, y, facing) in walled:
                problems.append("two pictures on the %s wall of %d,%d" % (facing, x, y))
            walled.add((x, y, facing))
            continue
        for sq in squares:
            if sq in taken:
                problems.append("%s at %d,%d and %s share square %d,%d" % (name, x, y, taken[sq], sq[0], sq[1]))
            if sq in landing:
                problems.append("%s at %d,%d stands on the landing" % (name, x, y))
            taken[sq] = name
    for d, x, y in sec["doors"]:
        a, b = at(g, x, y), (at(g, x - 1, y) if d == "W" else at(g, x, y - 1))
        if a == b or not a or not b:
            problems.append("door %s at %d,%d is not between two rooms" % (d, x, y))
        for sq in ((x, y), (x - 1, y) if d == "W" else (x, y - 1)):
            if sq in taken:
                problems.append("door at %d,%d opens onto %s" % (x, y, taken[sq]))
        if (x, y, d) in walled:
            problems.append("door at %d,%d has a picture on it" % (x, y))
    if problems:
        raise SystemExit("%s:\n  " % key + "\n  ".join(problems))
    return g


# --- the .tbx --------------------------------------------------------------------------

WALL_ENUMS = (("West", 0), ("North", 1), ("NorthWest", 2), ("SouthEast", 3),
              ("WestWindow", None), ("NorthWindow", None), ("WestDoor", 4), ("NorthDoor", 5))


def tbx(key, sec, cat, g):
    """One building, one floor. Tile entries are numbered from 1 in the order
    written: a walls entry per style, a floor entry per floor, the door."""
    W, H = sec["size"]
    used = []
    for name, _, _, _ in sec["furniture"]:
        if name not in used:
            used.append(name)
    fidx = {n: k for k, n in enumerate(used)}
    entries, eidx = [], {}

    def entry(key_, category, tiles):
        entries.append((category, tiles))
        eidx[key_] = len(entries)

    for style, base in T.WALLS.items():
        entry(("wall", style), "interior_walls",
              [(enum, t1(base + i) if i is not None else "") for enum, i in WALL_ENUMS])
    floors = sorted({r["floor"] for r in sec["rooms"]})
    for f in floors:
        entry(("floor", f), "floors", [("Floor", floor_tile(f))])
    entry(("door",), "doors", [("West", t1(T.DOOR)), ("North", t1(T.DOOR + 1)),
                               ("WestOpen", t1(T.DOOR + 2)), ("NorthOpen", t1(T.DOOR + 3))])
    first_wall = eidx[("wall", sec["rooms"][0]["wall"])]
    out = ["<?xml version='1.0' encoding='UTF-8'?>",
           '<building version="3" width="%d" height="%d" ExteriorWall="%d" ExteriorWallTrim="0" '
           'Door="%d" DoorFrame="0" Window="0" Curtains="0" Shutters="0" Stairs="0" RoofCap="0" '
           'RoofSlope="0" RoofTop="0" GrimeWall="0">' % (W, H, first_wall, eidx[("door",)]),
           " <properties>",
           '  <property name="Description" value=%s />' % quoteattr(
               "The TARDIS: %s. Drafted by tools/gen_tardis_decks.py; see INTERIOR.md" % sec["title"]),
           '  <property name="Mod" value="TARDIS" />',
           '  <property name="Generator" value="%s" />' % MARKER,
           '  <property name="Deck" value="%s" />' % key,
           '  <property name="Landing" value="%d,%d" />' % sec["landing"],
           '  <property name="Z" value="%d" />' % sec["z"]]
    if "beds" in sec:
        out.append('  <property name="Beds" value="%d,%d,%d,%d" />' % sec["beds"])
    out.append(" </properties>")
    for category, tiles in entries:
        out.append(' <tile_entry category="%s">' % category)
        for enum, tile in tiles:
            out.append('  <tile enum="%s" tile="%s" />' % (enum, tile))
        out.append(" </tile_entry>")
    for name in used:
        c = cat[name]
        layer = "" if c["layer"] == "Furniture" else ' layer="%s"' % c["layer"]
        out.append(" <furniture%s>" % layer)
        for fc in "WNES":
            if fc in c["facings"]:
                out.append('  <entry orient="%s">' % fc)
                for x, y, tile in c["facings"][fc]:
                    out.append('   <tile x="%d" y="%d" name="%s" />' % (x, y, tile))
                out.append("  </entry>")
        out.append(" </furniture>")
    out.append(" <user_tiles />")
    out.append(" <used_tiles>%s</used_tiles>" % " ".join(str(i + 1) for i in range(len(entries))))
    out.append(" <used_furniture>%s</used_furniture>" % " ".join(str(i) for i in range(len(used))))
    for r in sec["rooms"]:
        out.append(' <room Name=%s InternalName="%s" Color="%s" InteriorWall="%d" InteriorWallTrim="0" '
                   'Floor="%d" GrimeFloor="0" GrimeWall="0" />'
                   % (quoteattr(r["name"]), r["internal"], color_of(r),
                      eidx[("wall", r["wall"])], eidx[("floor", r["floor"])]))
    out.append(" <floor>")
    out.append("  <rooms>")
    out.append(",\n".join(",".join(str(v) for v in rw) for rw in g))
    out.append("</rooms>")
    for d, x, y in sec["doors"]:
        out.append('  <object type="door" x="%d" y="%d" dir="%s" Tile="%d" FrameTile="0" />'
                   % (x, y, d, eidx[("door",)]))
    for name, facing, x, y in sec["furniture"]:
        out.append('  <object type="furniture" FurnitureTiles="%d" orient="%s" x="%d" y="%d" />'
                   % (fidx[name], facing, x, y))
    out.append(" </floor>")
    out.append("</building>")
    return "\n".join(out) + "\n"


COLORS = {"roundel": "220 210 180", "wood": "120 80 50", "tech": "110 115 120", "tile": "170 190 220"}


def color_of(r):
    return COLORS.get(r["wall"], "160 160 160")


# --- the preview -------------------------------------------------------------------------

_SHEETS = {}


def tile_image(name):
    sheet, i = name.rsplit("_", 1)
    if sheet not in _SHEETS:
        local = os.path.join(TILES, sheet + ".png")
        _SHEETS[sheet] = Image.open(local if os.path.exists(local)
                                    else os.path.join(VANILLA, sheet + ".png")).convert("RGBA")
    im, i = _SHEETS[sheet], int(i)
    return im.crop(((i % 8) * CW, (i // 8) * CH, (i % 8) * CW + CW, (i // 8) * CH + CH))


def structure(sec, g):
    """Every wall and door, BuildingEd's rule: a wall on every edge between two
    different rooms, or a room and nothing, in the style of the room on the
    square it stands on (else the neighbour's). Returns [(x, y, tile, kind)]
    with kind "w" (wall), "dW"/"dN" (a door, to be built as an IsoDoor)."""
    W, H = sec["size"]
    doors = {(x, y, d) for d, x, y in sec["doors"]}
    out = []
    for y in range(H + 1):
        for x in range(W + 1):
            here, w_other, n_other = at(g, x, y), at(g, x - 1, y), at(g, x, y - 1)
            west = here != w_other and bool(here or w_other)
            north = here != n_other and bool(here or n_other)
            rid = here or w_other or n_other
            base = T.WALLS[sec["rooms"][rid - 1]["wall"]] if rid else 0
            if west and (x, y, "W") in doors:
                out.append((x, y, t1(base + 4), "w"))
                out.append((x, y, t1(T.DOOR), "dW"))
                west = False
            if north and (x, y, "N") in doors:
                out.append((x, y, t1(base + 5), "w"))
                out.append((x, y, t1(T.DOOR + 1), "dN"))
                north = False
            if west and north:
                out.append((x, y, t1(base + 2), "w"))
            elif west:
                out.append((x, y, t1(base + 0), "w"))
            elif north:
                out.append((x, y, t1(base + 1), "w"))
            elif (at(g, x, y - 1) != at(g, x - 1, y - 1) and (at(g, x, y - 1) or at(g, x - 1, y - 1))
                  and at(g, x - 1, y) != at(g, x - 1, y - 1) and (at(g, x - 1, y) or at(g, x - 1, y - 1))):
                # The corner post where a wall from the north meets one from
                # the west and neither carries on across this square.
                rid = at(g, x - 1, y - 1) or at(g, x, y - 1) or at(g, x - 1, y)
                out.append((x, y, t1(T.WALLS[sec["rooms"][rid - 1]["wall"]] + 3), "w"))
    return out


def preview(key, sec, cat, g, path, marks=True):
    W, H = sec["size"]
    ox, oy = 64 * H + 64, 260
    canvas = Image.new("RGBA", (64 * (W + H) + 256, 32 * (W + H) + 460), (8, 8, 12, 255))
    layers = {}

    def add(x, y, tile, order):
        layers.setdefault((x, y), []).append((order, tile))

    for x, y, tile, kind in structure(sec, g):
        add(x, y, tile, 0 if kind == "w" else 0.5)
    for name, facing, x, y in sec["furniture"]:
        c = cat[name]
        for dx, dy, tile in c["facings"][facing]:
            add(x + dx, y + dy, tile, {"WallFurniture": 3}.get(c["layer"], 2))
    beds = set(bed_squares(sec, g))
    for y in range(H):
        for x in range(W):
            if g[y][x]:
                ft = floor_tile(sec["rooms"][g[y][x] - 1]["floor"])
                canvas.alpha_composite(tile_image(ft), (ox + 64 * (x - y) - 64, oy + 32 * (x + y) - 192))
    d = ImageDraw.Draw(canvas)
    for (x, y) in (beds if marks else ()):
        # A crop bed, as a green diamond: the plants are sown at build time.
        cx, cy = ox + 64 * (x - y), oy + 32 * (x + y) + 32
        d.polygon([(cx, cy - 22), (cx + 44, cy), (cx, cy + 22), (cx - 44, cy)], fill=(70, 120, 50, 255))
    lx, ly = sec["landing"]
    cx, cy = ox + 64 * (lx - ly), oy + 32 * (lx + ly) + 32
    if marks:
        d.polygon([(cx, cy - 26), (cx + 52, cy), (cx, cy + 26), (cx - 52, cy)], outline=(255, 200, 60, 255), width=3)
    # A dollhouse view, as the game's cutaway gives: the outer walls on the
    # south and east are left off, and inner walls are drawn see-through, so
    # every room can be judged from one picture.
    for (x, y) in sorted(layers, key=lambda k: (k[0] + k[1], k[0])):
        for order, tile in sorted(layers[(x, y)]):
            if order < 1 and (x == W or y == H):
                continue
            img = tile_image(tile)
            if order < 1 and 0 < x < W and 0 < y < H:
                img.putalpha(img.split()[3].point(lambda v: v * 45 // 100))
            canvas.alpha_composite(img, (ox + 64 * (x - y) - 64, oy + 32 * (x + y) - 192))
    if marks:
        d.text((16, 16), "TARDIS -- %s  (%d x %d, z %d)" % (sec["title"], W, H, sec["z"]), fill=(230, 230, 230, 255))
    bbox = canvas.getbbox()
    canvas = canvas.crop(bbox) if bbox else canvas
    canvas.save(path)


def main():
    force = "--force" in sys.argv
    wanted = [a for a in sys.argv[1:] if not a.startswith("--")] or ORDER
    cat = catalogue()
    os.makedirs(OUT, exist_ok=True)
    os.makedirs(BED, exist_ok=True)
    for key in wanted:
        sec = DECKS[key]
        g = check(key, sec, cat)
        path = os.path.join(BED, "TARDIS_%s.tbx" % sec["title"].replace(" ", ""))
        write = True
        if os.path.exists(path) and not force:
            with open(path, encoding="utf-8") as f:
                if MARKER not in f.read():
                    print("%s: %s has been saved by BuildingEd -- not overwriting (use --force)"
                          % (key, os.path.basename(path)))
                    write = False
        if write:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(tbx(key, sec, cat, g))
        preview(key, sec, cat, g, os.path.join(OUT, key + ".png"))
        print("%-8s %-28s %d rooms, %d doors, %3d pieces" % (
            key, os.path.basename(path), len(sec["rooms"]), len(sec["doors"]), len(sec["furniture"])))


if __name__ == "__main__":
    main()
