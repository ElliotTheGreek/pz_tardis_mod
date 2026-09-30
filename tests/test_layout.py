"""Checks the generated decks (TARDIS_Layout.lua) and prints each floor plan.

The layout is pure data -- no engine calls -- so it is loaded for real under
lupa and every deck is walked. What this catches that nothing else does:

  * a fitting whose sprite is not in the mod's tile definitions, which in game
    is an empty square and no error anywhere;
  * a container the layout marks `c` whose tile cannot hold anything, or a
    container tile the layout does not mark -- placed, drawn, and it never
    opens (the Shuttlecraft's "Containers built at runtime are not containers");
  * a container nothing stocks, and a stock rule naming a list that does not
    exist;
  * a multi-square piece whose squares disagree with its tiles' SpriteGridPos;
  * a landing that is off the floor, blocked, or walled in;
  * a deck larger than C.RoomSize, which the clearing and deck-finding code
    would not cover.

Run it and **look at the plans**: they are the ship as the game will build it.
"""
import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_tardis_pack as PACK  # noqa: E402

LUA = os.path.join(ROOT, "TARDIS", "42", "media", "lua").replace(os.sep, "/")
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'package.path = "{LUA}/shared/?.lua;" .. package.path')
lua.execute("_G.unpack = _G.unpack or table.unpack")
lua.execute('require "TARDIS/TARDIS_Config"')
lua.execute('require "TARDIS/TARDIS_Layout"')
C = lua.globals().TARDIS.Config
L = lua.globals().TARDIS.Layout

defs = PACK.read_tiledefs(PACK.TILES)
props = {}
for sheet, ts in defs.items():
    for i, p in enumerate(ts["tiles"]):
        if p:
            props["%s_%d" % (sheet, i)] = p


def lst(t):
    return [t[i] for i in range(1, len(t) + 1)] if t else []


uses = {k: dict(v.items()) for k, v in L.uses.items()}
PACKED = {"console": {"gun_cabinet", "steamer_trunk"}, "storage": {"steamer_trunk"}}
HOLD = {k for k, v in C.HoldPieces.items() if v}
SPECIAL = HOLD | {"sonic_case"}
stock = {deck: {k: dict(v.items()) for k, v in rules.items()} for deck, rules in C.Stock.items()}
loot = set(C.Loot.keys()) | {"books"}

failures = []


def fail(msg):
    failures.append(msg)


GLYPH = {"console": "C", "hold_locker": "H", "sonic_case": "S", "bookcase": "b", "bed_double": "B",
         "bed_single": "B", "sickbay_bed": "B", "wardrobe": "w", "clothes_rail": "r", "kitchen_sink": "~",
         "wash_basin": "~", "bathtub": "~", "water_trough": "~", "kitchen_range": "O", "fridge": "F",
         "store_shelf": "s", "tool_locker": "l", "gun_cabinet": "g", "steamer_trunk": "t",
         "dining_table": "T", "writing_desk": "d", "medical_cabinet": "+", "toilet": "u"}

for d in lst(C.Decks):
    deck_id = d.id
    lay = L.decks[deck_id]
    W, H = int(lay.w), int(lay.h)
    grid = [lst(r) for r in lst(lay.grid)]
    objs = [lst(o) for o in lst(lay.objects)]
    floors = {(int(f[1]), int(f[2])): f[3] for f in lst(lay.floors)}
    lx, ly = int(lay.landing.x), int(lay.landing.y)
    if W > int(C.RoomSize) or H > int(C.RoomSize):
        fail(f"{deck_id}: {W}x{H} is larger than C.RoomSize {int(C.RoomSize)}")

    def room(x, y):
        return grid[y][x] if 0 <= x < W and 0 <= y < H else 0

    cells = {}
    solid = set()
    seen_pieces = {}
    for o in objs:
        x, y, sprite, kind = int(o[0]), int(o[1]), o[2], o[3]
        piece = o[4] if len(o) > 4 else None
        p = props.get(sprite)
        if sprite.startswith("tardis_interior_") and p is None:
            fail(f"{deck_id}: {sprite} at {x},{y} is not in the tile definitions")
            continue
        if (x, y) not in floors:
            fail(f"{deck_id}: {piece or sprite} at {x},{y} stands on no floor")
        if kind in ("f", "c"):
            if (x, y) in solid:
                fail(f"{deck_id}: two pieces on {x},{y}")
            solid.add((x, y))
            cells[(x, y)] = GLYPH.get(piece, "#" if kind == "c" else "*")
        if kind == "c" and "container" not in p:
            fail(f"{deck_id}: {piece} at {x},{y} is marked a container but its tile holds nothing")
        if kind in ("f", "p") and p and "container" in p:
            fail(f"{deck_id}: {piece} at {x},{y} is a container tile the layout does not mark")
        if piece and piece in uses:
            u = uses[piece]
            if u.get("water") and "waterPiped" not in p:
                fail(f"{deck_id}: {piece} is a water fitting whose tile is not plumbed")
            if kind == "c":
                seen_pieces[piece] = seen_pieces.get(piece, 0) + 1
    # every container is stocked by something, and every rule names a list
    for piece, n in seen_pieces.items():
        rule = stock.get(deck_id, {}).get(piece) or stock["any"].get(piece)
        if piece in SPECIAL or piece in PACKED.get(deck_id, set()) or uses.get(piece, {}).get("stove"):
            continue
        if not rule:
            fail(f"{deck_id}: {n} {piece}(s) that nothing stocks")
            continue
        names = [rule["loot"]] if "loot" in rule else lst(rule.get("cycle"))
        for name in names:
            if name not in loot:
                fail(f"{deck_id}: {piece} is stocked from C.Loot.{name}, which does not exist")

    # the landing: on the floor, and it and the ring round it clear
    if not room(lx, ly):
        fail(f"{deck_id}: the landing {lx},{ly} is off the floor")
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if (lx + dx, ly + dy) in solid:
                fail(f"{deck_id}: something stands on the landing ring at {lx + dx},{ly + dy}")

    # the plan
    beds = set()
    if lay.beds:
        b = lay.beds
        beds = {(x, y) for x in range(int(b.x0), int(b.x1) + 1) for y in range(int(b.y0), int(b.y1) + 1)
                if x % 3 != 0}
    print(f"\n{d.name}  ({deck_id}, z {int(d.z)}, {W}x{H}, {len(objs)} objects, "
          f"{len(lst(lay.lamps))} lamps; rooms: {', '.join(lst(lay.rooms))})")
    doors = {(int(o[0]), int(o[1])) for o in objs if o[3] in ("dW", "dN")}
    for y in range(H):
        line = ""
        for x in range(W):
            ch = " " if not room(x, y) else "."
            if (x, y) in beds:
                ch = ","
            ch = cells.get((x, y), ch)
            if (x, y) in doors:
                ch = "D"
            if (x, y) == (lx, ly):
                ch = "@"
            line += ch
        print("   " + line)

print("\n   @ landing  D door  C console  H hold  S sonic case  b books  B bed  w wardrobe"
      "\n   r rail  ~ water  O range  F fridge  s shelf  l locker  g guns  t trunk  T table"
      "\n   d desk  + medicine  u toilet  , crop bed  # other container  * other fitting")

# multi-square pieces: every square of a piece must carry the SpriteGridPos
# its offset says, and all its squares must face the same way
for name, rec in __import__("json").load(open(os.path.join(ROOT, "design", "tiles", "tardis_interior_02.json"))).items():
    for facing, squares in rec["facings"].items():
        faces = set()
        for x, y, i in squares:
            p = props.get("tardis_interior_02_%d" % i, {})
            faces.add(p.get("Facing"))
            if len(squares) > 1 and p.get("SpriteGridPos") != "%d,%d" % (x, y):
                fail(f"{name} {facing}: tile {i} is at {x},{y} but says {p.get('SpriteGridPos')}")
        if len(faces) > 1:
            fail(f"{name} {facing}: squares face different ways {faces}")

# Every seat must be restable: sitting on furniture is the rest action, which
# the engine offers only on a tile with `bed` (vanilla gives every chair a
# BedType), and it needs a chair flag for the way it faces.
for name, rec in __import__("json").load(open(os.path.join(ROOT, "design", "tiles", "tardis_interior_02.json"))).items():
    if not rec.get("use", {}).get("seat"):
        continue
    for facing, squares in rec["facings"].items():
        for x, y, i in squares:
            p = props.get("tardis_interior_02_%d" % i, {})
            if "bed" not in p or "BedType" not in p:
                fail(f"{name} {facing}: tile {i} is a seat without bed/BedType -- nobody can sit on it")
            if not any(k in p for k in ("chairN", "chairS", "chairE", "chairW")):
                fail(f"{name} {facing}: tile {i} is a seat with no chair facing")

if failures:
    print(f"\n{len(failures)} PROBLEM(S):")
    for f in failures:
        print("  " + f)
    sys.exit(1)
print("\nevery deck is consistent with its tiles, its stock rules and its landing")
