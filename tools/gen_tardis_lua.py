"""The TARDIS's decks, written out as data the game builds from.

    python tools/gen_tardis_lua.py

Reads design/buildinged/TARDIS_*.tbx -- whatever the author last saved in
BuildingEd, or the drafts tools/gen_tardis_decks.py wrote -- and the tile
definitions tools/gen_tardis_pack.py wrote, and writes

  TARDIS/42/media/lua/shared/TARDIS/TARDIS_Layout.lua

**Every piece is resolved here, in Python, where it can be checked**: which
wall sprite stands on which edge, which doorway gets a door, which objects
hold things, where the lamps hang. The Lua only places what it is given.
Walls follow BuildingEd's rule -- a wall on every edge between two different
rooms, or a room and nothing, in the style of the room on the square it
stands on (else its neighbour's) -- exactly as gen_tardis_decks.preview draws
them. (The Shuttlecraft mod's gen_adirondack_lua.py, whose rules these are.)

**Each deck is still built on its own storey and a step sideways**
(TARDIS_Config, C.Decks): a runtime building has no RoomDefs, so the engine
would draw every deck above the player over the one they stand on.
"""
import hashlib
import json
import os
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_tardis_decks as DECKS  # noqa: E402
import gen_tardis_pack as PACK  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BED = os.path.join(ROOT, "design", "buildinged")
OUT = os.path.join(ROOT, "TARDIS", "42", "media", "lua", "shared", "TARDIS", "TARDIS_Layout.lua")
LAMP_REACH = 5          # every floor square within this of a lamp, per room


def unpad(name):
    """BuildingEd pads sprite indices (_025); the engine does not (_25)."""
    sheet, _, i = name.rpartition("_")
    return "%s_%d" % (sheet, int(i))


def read_tbx(path):
    root = ET.parse(path).getroot()
    W, H = int(root.get("width")), int(root.get("height"))
    props = {p.get("name"): p.get("value") for p in root.iter("property")}
    entries = [dict((t.get("enum"), t.get("tile") or "") for t in te.findall("tile"))
               for te in root.findall("tile_entry")]
    furniture = []
    for fu in root.findall("furniture"):
        furniture.append(dict(
            layer=fu.get("layer") or "Furniture",
            entries={e.get("orient"): [(int(t.get("x")), int(t.get("y")), t.get("name"))
                                       for t in e.findall("tile")] for e in fu.findall("entry")}))
    rooms = [dict(r.attrib) for r in root.findall("room")]
    floors = root.findall("floor")
    if len(floors) != 1:
        raise SystemExit("%s: a deck is one floor, not %d" % (os.path.basename(path), len(floors)))
    fl = floors[0]
    vals = [int(v) for v in (fl.findtext("rooms") or "").replace("\n", "").split(",") if v.strip()]
    grid = [vals[y * W:(y + 1) * W] for y in range(H)]
    objects = [dict(o.attrib) for o in fl.findall("object")]
    return dict(W=W, H=H, props=props, entries=entries, furniture=furniture, rooms=rooms,
                grid=grid, objects=objects, path=path)


def lamp_spots(grid, W, H):
    """Each room gets a lamp at its middle, then one on any square still
    further than LAMP_REACH from a lamp of its own (the Shuttlecraft's
    AC.lampSpots, moved to where it can be looked at)."""
    def rid(x, y):
        return grid[y][x] if 0 <= x < W and 0 <= y < H else 0

    out, seen = [], set()
    for sy in range(H):
        for sx in range(W):
            r = rid(sx, sy)
            if not r or (sx, sy) in seen:
                continue
            squares, stack = [], [(sx, sy)]
            seen.add((sx, sy))
            while stack:
                p = stack.pop()
                squares.append(p)
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (p[0] + dx, p[1] + dy)
                    if rid(*q) == r and q not in seen:
                        seen.add(q)
                        stack.append(q)
            cx = sum(p[0] for p in squares) / len(squares)
            cy = sum(p[1] for p in squares) / len(squares)
            squares.sort(key=lambda p: (p[1], p[0]))
            mine = [min(squares, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)]
            for p in squares:
                if not any(abs(l[0] - p[0]) <= LAMP_REACH and abs(l[1] - p[1]) <= LAMP_REACH for l in mine):
                    dx = 1 if cx > p[0] else (-1 if cx < p[0] else 0)
                    dy = 1 if cy > p[1] else (-1 if cy < p[1] else 0)
                    q = (int(round(p[0] + dx * min(LAMP_REACH, abs(cx - p[0])))),
                         int(round(p[1] + dy * min(LAMP_REACH, abs(cy - p[1])))))
                    mine.append(q if rid(*q) == r else p)
            out += mine
    return out


def build_deck(sec, props, piece_of):
    W, H, grid = sec["W"], sec["H"], sec["grid"]

    def room(x, y):
        return grid[y][x] if 0 <= x < W and 0 <= y < H else 0

    def entry(idx, enum):
        return sec["entries"][idx - 1].get(enum, "") if idx else ""

    objs, doors = [], {}
    for o in sec["objects"]:
        x, y = int(o["x"]), int(o["y"])
        if o["type"] == "door":
            doors[(x, y, o["dir"])] = int(o.get("Tile", 0))
        elif o["type"] == "furniture":
            fdef = sec["furniture"][int(o["FurnitureTiles"])]
            for dx, dy, name in fdef["entries"][o["orient"]]:
                sprite = unpad(name)
                p = props.get(sprite)
                if p is None:
                    raise SystemExit("%s: %s is not in the tile definitions" % (sec["path"], sprite))
                if fdef["layer"] == "WallFurniture":
                    kind = "p"
                elif "container" in p:
                    kind = "c"
                else:
                    kind = "f"
                objs.append((x + dx, y + dy, sprite, kind, piece_of.get(sprite, "")))

    structure, extra_floor = [], {}
    for y in range(H + 1):
        for x in range(W + 1):
            here, w_other, n_other = room(x, y), room(x - 1, y), room(x, y - 1)
            west = here != w_other and bool(here or w_other)
            north = here != n_other and bool(here or n_other)
            rid = here or w_other or n_other
            wall = int(sec["rooms"][rid - 1].get("InteriorWall", 0)) if rid else 0
            if (west or north) and not here:
                # A wall on a square outside every room still needs ground
                # under it: a wall on a midair square behaves badly.
                extra_floor[(x, y)] = w_other or n_other
            for d in ("W", "N"):
                if (west if d == "W" else north) and (x, y, d) in doors:
                    structure.append((x, y, unpad(entry(wall, "WestDoor" if d == "W" else "NorthDoor")), "w", ""))
                    structure.append((x, y, unpad(entry(doors[(x, y, d)], "West" if d == "W" else "North")),
                                      "d" + d, "door"))
            west = west and (x, y, "W") not in doors
            north = north and (x, y, "N") not in doors
            if west and north:
                structure.append((x, y, unpad(entry(wall, "NorthWest")), "w", ""))
            elif west:
                structure.append((x, y, unpad(entry(wall, "West")), "w", ""))
            elif north:
                structure.append((x, y, unpad(entry(wall, "North")), "w", ""))
            elif (room(x, y - 1) != room(x - 1, y - 1) and (room(x, y - 1) or room(x - 1, y - 1))
                  and room(x - 1, y) != room(x - 1, y - 1) and (room(x - 1, y) or room(x - 1, y - 1))):
                rid = room(x - 1, y - 1) or room(x, y - 1) or room(x - 1, y)
                wall = int(sec["rooms"][rid - 1].get("InteriorWall", 0))
                structure.append((x, y, unpad(entry(wall, "SouthEast")), "w", ""))
                if not here:
                    extra_floor[(x, y)] = rid
    for (x, y, d) in doors:
        if not any(s[0] == x and s[1] == y and s[3] == "d" + d for s in structure):
            raise SystemExit("%s: the door at %d,%d %s is on no wall" % (sec["path"], x, y, d))
    for s in structure:
        if not s[2] or s[2] not in props and not s[2].startswith("blends_"):
            raise SystemExit("%s: wall sprite %r at %d,%d is not ours" % (sec["path"], s[2], s[0], s[1]))

    def floor_of(rid):
        f = entry(int(sec["rooms"][rid - 1].get("Floor", 0)), "Floor")
        return unpad(f) if f else ""

    floors = {}
    for y in range(H):
        for x in range(W):
            if grid[y][x]:
                floors[(x, y)] = floor_of(grid[y][x])
    for xy, rid in extra_floor.items():
        # Under a wall outside the rooms: the neighbour's floor, but never
        # soil -- a crop sown in the wall's footing would be out of reach.
        f = floor_of(rid)
        floors.setdefault(xy, f if not f.startswith("blends_") else "tardis_interior_01_37")
    return structure, objs, floors


def main():
    defs = PACK.read_tiledefs(PACK.TILES)
    props = {}
    for sheet, ts in defs.items():
        for i, p in enumerate(ts["tiles"]):
            props["%s_%d" % (sheet, i)] = p
    with open(os.path.join(ROOT, "design", "tiles", PACK.SHEETS[1] + ".json")) as f:
        index = json.load(f)
    piece_of = {}
    uses = {}
    for pname, rec in index.items():
        uses[pname] = rec.get("use", {})
        for squares in rec["facings"].values():
            for _, _, i in squares:
                piece_of["%s_%d" % (PACK.SHEETS[1], i)] = pname

    files = [os.path.join(BED, f) for f in os.listdir(BED) if f.startswith("TARDIS_") and f.endswith(".tbx")]
    decks = {}
    for path in files:
        sec = read_tbx(path)
        key = sec["props"].get("Deck")
        if key not in DECKS.ORDER:
            raise SystemExit("%s names no deck of the ship (Deck=%r)" % (path, key))
        decks[key] = sec
    missing = [k for k in DECKS.ORDER if k not in decks]
    if missing:
        raise SystemExit("no .tbx for: " + ", ".join(missing))

    def q(s):
        return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')

    body = []
    body.append("-- What each piece does, from the manifest (tools/tardis_objects.py).")
    body.append("L.uses = {")
    for pname in sorted(uses):
        u = uses[pname]
        fields = []
        for k in sorted(u):
            v = u[k]
            fields.append("%s = %s" % (k, "true" if v is True else q(str(v))))
        body.append("  %s = { %s }," % (pname, ", ".join(fields)))
    body.append("}")
    body.append("L.decks = {")
    total = 0
    for key in DECKS.ORDER:
        sec = decks[key]
        structure, objs, floors = build_deck(sec, props, piece_of)
        total += len(structure) + len(objs)
        lx, ly = (int(v) for v in sec["props"]["Landing"].split(","))
        if not sec["grid"][ly][lx]:
            raise SystemExit("%s: the landing is off the floor" % key)
        body.append("  %s = {" % key)
        body.append("    w = %d, h = %d, landing = { x = %d, y = %d }," % (sec["W"], sec["H"], lx, ly))
        if "Beds" in sec["props"]:
            x0, y0, x1, y1 = (int(v) for v in sec["props"]["Beds"].split(","))
            body.append("    beds = { x0 = %d, y0 = %d, x1 = %d, y1 = %d }," % (x0, y0, x1, y1))
        body.append("    rooms = { %s }," % ", ".join(q(r["Name"]) for r in sec["rooms"]))
        body.append("    -- Room index per square, one row per line: %d rows of %d." % (sec["H"], sec["W"]))
        body.append("    grid = {")
        for rw in sec["grid"]:
            body.append("      { %s }," % ", ".join(str(v) for v in rw))
        body.append("    },")
        body.append("    floors = {")
        for (x, y), s in sorted(floors.items(), key=lambda kv: (kv[0][1], kv[0][0])):
            body.append("      { %d, %d, %s }," % (x, y, q(s)))
        body.append("    },")
        body.append("    -- x, y, sprite, kind (w wall, dW/dN door, f furniture, c container, p picture), piece.")
        body.append("    objects = {")
        for o in structure + objs:
            x, y, s, k, piece = o
            tail = (", " + q(piece)) if piece else ""
            body.append("      { %d, %d, %s, %s%s }," % (x, y, q(s), q(k), tail))
        body.append("    },")
        lamps = lamp_spots(sec["grid"], sec["W"], sec["H"])
        body.append("    lamps = { %s }," % ", ".join("{ %d, %d }" % p for p in lamps))
        body.append("  },")
    body.append("}")
    digest = hashlib.sha1("\n".join(body).encode()).hexdigest()
    out = ["-- GENERATED by tools/gen_tardis_lua.py from design/buildinged/TARDIS_*.tbx.",
           "-- Do not edit: change a deck in BuildingEd (or tools/gen_tardis_decks.py) and generate again.",
           "local L = {}",
           "-- Changes whenever anything placed changes; a deck built by another is brought up to date.",
           "L.rev = %d" % int(digest[:7], 16)]
    out += body
    out.append("TARDIS = TARDIS or {}")
    out.append("TARDIS.Layout = L")
    out.append("return L")
    with open(OUT, "w", newline="\n") as f:
        f.write("\n".join(out) + "\n")
    print("wrote %s: %d decks, %d objects, rev %d" % (os.path.relpath(OUT, ROOT), len(decks), total,
                                                      int(digest[:7], 16)))


if __name__ == "__main__":
    main()
