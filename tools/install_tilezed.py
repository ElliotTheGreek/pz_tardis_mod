"""Put the TARDIS interior tilesets where the Project Zomboid Modding Tools can use them.

    python tools/install_tilezed.py            # install / refresh
    python tools/install_tilezed.py --check    # report only, change nothing

Close TileZed and BuildingEd first: both read these files when they start and
may write them back when they close, over the top of anything added meanwhile.

What it does, and nothing else (the Shuttlecraft mod's installer, retargeted):

1. copies design/tiles/2x/tardis_interior_01.png and _02.png into the tools'
   Tiles/2x folder, which is where TileZed looks for every tileset;
2. adds both sheets to ~/.TileZed/Tilesets.txt, with DoorW/DoorN meta-enums on
   the two closed doors exactly as vanilla marks fixtures_doors_01;
3. adds BuildingEd entries to ~/.TileZed/BuildingTiles.txt -- the four wall
   styles under both interior and exterior walls, the six floors under
   floors, the roundel door under doors;
4. adds "TARDIS - <area>" groups to ~/.TileZed/BuildingFurniture.txt with every
   piece of furniture in every facing, and the wall pictures on the
   WallFurniture layer as vanilla's wall-hung signs are.

It is idempotent: an entry already present is left alone and our groups are
replaced whole, so running it again after regenerating the art refreshes the
PNGs and any new furniture. The first run keeps a copy of each config file as
<name>.pretardis.
"""
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_tardis_tiles as T  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHEET = "tardis_interior_01"          # structure: walls, floors, doors
FURN = "tardis_interior_02"           # furniture, rendered from models
SHEETS = (SHEET, FURN)
SRCDIR = os.path.join(ROOT, "design", "tiles", "2x")
TOOLS = os.environ.get(
    "PZ_MODDING_TOOLS",
    r"D:/SteamLibrary/steamapps/common/Project Zomboid Modding Tools")
TILES = os.path.join(TOOLS, "Tiles", "2x")
CONF = os.path.join(os.path.expanduser("~"), ".TileZed")


def t(i):
    return "%s_%03d" % (SHEET, i)


def f(i):
    return "%s_%03d" % (FURN, i)


def rows_of(sheet):
    from PIL import Image
    return Image.open(os.path.join(SRCDIR, sheet + ".png")).size[1] // 256


def tileset_block(sheet):
    """A sheet's Tilesets.txt entry. Its size follows the PNG, which grows."""
    extra = ""
    if sheet == SHEET:
        d = T.DOOR
        extra = ("    tile\n    {\n        xy = %d,%d\n        meta-enum = DoorW\n    }\n"
                 "    tile\n    {\n        xy = %d,%d\n        meta-enum = DoorN\n    }\n"
                 % (d % 8, d // 8, (d + 1) % 8, (d + 1) // 8))
    return "tileset\n{\n    file = %s\n    size = 8,%d\n%s}\n" % (sheet, rows_of(sheet), extra)


def wall_entry(base):
    return (
        "    entry\n    {\n"
        "        West = %s\n        North = %s\n        NorthWest = %s\n"
        "        SouthEast = %s\n        WestWindow = \n        NorthWindow = \n"
        "        WestDoor = %s\n        NorthDoor = %s\n    }\n"
        % (t(base), t(base + 1), t(base + 2), t(base + 3), t(base + 4), t(base + 5)))


WALLS = "".join(wall_entry(b) for b in T.WALLS.values())
BUILDING = {
    "exterior_walls": WALLS,
    "interior_walls": WALLS,
    "floors": "".join("    entry\n    {\n        Floor = %s\n    }\n" % t(i) for i in T.FLOORS.values()),
    "doors": ("    entry\n    {\n        West = %s\n        North = %s\n"
              "        WestOpen = %s\n        NorthOpen = %s\n    }\n"
              % (t(T.DOOR), t(T.DOOR + 1), t(T.DOOR + 2), t(T.DOOR + 3))),
}

AREAS = [("console", "Console Room"), ("armoury", "Armoury"), ("galley", "Galley"),
         ("quarters", "Quarters"), ("stores", "Stores and Infirmary"), ("library", "Library"),
         ("garden", "Gardens"), ("any", "Wall Art")]


def furniture_blocks(names, index):
    """BuildingEd furniture from the render's index: one `furniture` per
    object, one `entry` per facing, one `x,y = tile` per square it covers --
    the layout vanilla's own multi-square pieces use."""
    out = []
    for name in names:
        rec = index[name]
        lines = ["    furniture\n    {\n"]
        if rec["layer"] != "Furniture":
            lines.append("        layer = %s\n" % rec["layer"])
        for facing in "WNES":
            squares = rec["facings"].get(facing)
            if not squares:
                continue
            lines.append("        entry\n        {\n            orient = %s\n" % facing)
            for x, y, idx in squares:
                lines.append("            %d,%d = %s\n" % (x, y, f(idx)))
            lines.append("        }\n")
        lines.append("    }\n")
        out.append("".join(lines))
    return "".join(out)


def furniture_groups():
    path = os.path.join(ROOT, "design", "tiles", FURN + ".json")
    with open(path) as fh:
        index = json.load(fh)
    text = ""
    for area, label in AREAS:
        names = [n for n in sorted(index) if index[n]["area"] == area]
        if names:
            text += ("group\n{\n    label = TARDIS - %s\n" % label
                     + furniture_blocks(names, index) + "}\n")
    return text


# Every group whose label starts "TARDIS - " is ours, and all of them are
# replaced together, so a renamed or emptied group does not linger.
GROUP_RE = re.compile(r"group\n\{\n    label = TARDIS - [^\n]*\n.*?\n\}\n", re.S)


def backup(path):
    b = path + ".pretardis"
    if not os.path.exists(b):
        shutil.copy2(path, b)


def read(path):
    with open(path, "r", newline="") as fh:
        return fh.read()


def write(path, text):
    with open(path, "w", newline="") as fh:
        fh.write(text)


def main():
    check = "--check" in sys.argv
    if not check and os.name == "nt":
        import subprocess
        running = subprocess.run(["tasklist"], capture_output=True, text=True).stdout
        if "TileZed.exe" in running:
            sys.exit("TileZed is running: close it (and BuildingEd) first, or it may "
                     "write its own copy of the config back over this one on exit.")
    for p in [os.path.join(SRCDIR, s + ".png") for s in SHEETS] + [TILES, CONF]:
        if not os.path.exists(p):
            sys.exit("missing: %s" % p)
    report = []

    for sheet in SHEETS:
        dst = os.path.join(TILES, sheet + ".png")
        report.append("png: %s -> %s" % ("would copy" if check else "copied", dst))
        if not check:
            shutil.copy2(os.path.join(SRCDIR, sheet + ".png"), dst)

    path = os.path.join(CONF, "Tilesets.txt")
    text = orig = read(path)
    for sheet in SHEETS:
        block = tileset_block(sheet)
        rx = re.compile(r"tileset\n\{\n    file = %s\n.*?\n\}\n" % re.escape(sheet), re.S)
        if block in text:
            report.append("Tilesets.txt: %s up to date" % sheet)
            continue
        report.append("Tilesets.txt: %s %s" % ("refreshing" if rx.search(text) else "adding", sheet))
        text = rx.sub("", text).rstrip("\n") + "\n" + block
    if text != orig and not check:
        backup(path)
        write(path, text)

    path = os.path.join(CONF, "BuildingTiles.txt")
    text = read(path)
    changed = False
    for cat, block in BUILDING.items():
        m = re.search(r"\n    name = %s\n" % cat, text)
        if not m:
            sys.exit("BuildingTiles.txt has no category %s" % cat)
        end = text.find("\n}\n", m.end())
        if SHEET in text[m.end():end]:
            report.append("BuildingTiles.txt: %s already has ours" % cat)
            continue
        report.append("BuildingTiles.txt: adding to %s" % cat)
        text = text[:m.end()] + block + text[m.end():]
        changed = True
    if changed and not check:
        backup(path)
        write(path, text)

    furniture = furniture_groups()
    path = os.path.join(CONF, "BuildingFurniture.txt")
    text = read(path)
    if furniture in text:
        report.append("BuildingFurniture.txt: groups up to date")
    else:
        had = GROUP_RE.search(text)
        report.append("BuildingFurniture.txt: %s the TARDIS groups" % ("refreshing" if had else "adding"))
        if not check:
            backup(path)
            text = GROUP_RE.sub("", text).rstrip("\n") + "\n" + furniture
            write(path, text)

    print("\n".join(report))


if __name__ == "__main__":
    main()
