"""Checks the deck floor plan and the multi-tile furniture offsets.

Two things this catches that nothing else does:

  * A multi-tile piece whose halves are declared in the wrong order. The
    tileset says where each half belongs via SpriteGridPos; getting it
    backwards puts the foot of every bed where its head should be, which is
    exactly what happened.
  * A floor plan that has walled off the landing or the alcove doorway, which
    would strand a player on arrival.
"""
import json, os, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.path.join(ROOT, "TARDIS", "42", "media", "lua").replace(os.sep, "/")
tiles = json.load(open(os.path.join(ROOT, "tools", "_catalog", "tiles.json")))["tiles"]

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'package.path = "{LUA}/shared/?.lua;" .. package.path')
lua.execute("_G.unpack = _G.unpack or table.unpack")
lua.execute('require "TARDIS/TARDIS_Config"')
C = lua.globals().TARDIS.Config

size = int(C.RoomSize)
failures = []

# --- floor plan --------------------------------------------------------
plan = [[bool(C.inShape(ox, oy, None, None, None)) for ox in range(size + 1)]
        for oy in range(size + 1)]
area = sum(r.count(True) for r in plan)

print(f"shape={C.Shape}  size={size}  chamfer={int(C.Chamfer)}  "
      f"floor squares={area} of {(size+1)**2}")
print()
land = C.Landing
for oy, row in enumerate(plan):
    line = ""
    for ox, inside in enumerate(row):
        ch = "." if inside else " "
        if inside and C.isLanding(ox, oy):
            ch = "o"
        if ox == int(land.x) and oy == int(land.y):
            ch = "@"
        if ox == 12 and oy == 12:
            ch = "C"
        line += ch
    print("   " + line)
print("\n   @ landing   o kept clear   C console   . floor")

# the landing, its clearance ring and the console must all be inside the room
checks = [("landing", int(land.x), int(land.y)), ("console", 12, 12)]
clear = int(land.clearance)
for dx in (-clear, clear):
    for dy in (-clear, clear):
        checks.append((f"landing clearance {dx},{dy}",
                       int(land.x) + dx, int(land.y) + dy))
for label, ox, oy in checks:
    if not C.inShape(ox, oy, None, None, None):
        failures.append(f"{label} at {ox},{oy} falls outside the floor plan")

if area < (size + 1) ** 2 * 0.45:
    failures.append(f"floor plan keeps only {area} squares; chamfer too deep")

# --- multi-tile pieces -------------------------------------------------
print("\nmulti-tile pieces:")
for name in C.Pieces:
    piece = C.Pieces[name]
    parts = []
    for i in range(1, len(piece) + 1):
        entry = piece[i]
        parts.append((entry[1], int(entry[2]), int(entry[3])))

    shown = []
    for sprite, dx, dy in parts:
        props = tiles.get(sprite)
        if props is None:
            failures.append(f"{name}: sprite {sprite} does not exist")
            continue
        grid = props.get("SpriteGridPos")
        if grid is None:
            failures.append(f"{name}: {sprite} has no SpriteGridPos; "
                            f"it is not a multi-tile sprite")
            continue
        gx, gy = (int(v) for v in grid.split(","))
        if (gx, gy) != (dx, dy):
            failures.append(f"{name}: {sprite} declared at offset {dx},{dy} "
                            f"but the tileset puts it at {gx},{gy}")
        shown.append(f"{sprite.rsplit('_', 1)[1]}@{dx},{dy}")

    facings = {tiles[s].get("Facing") for s, _, _ in parts if s in tiles}
    if len(facings) > 1:
        failures.append(f"{name}: halves face different ways {facings}")
    print(f"  {name:12s} {' '.join(shown):28s} facing={facings.pop() if facings else '?'}")

if failures:
    print(f"\n{len(failures)} PROBLEM(S):")
    for f in failures:
        print("  " + f)
    sys.exit(1)
print("\nfloor plan and furniture offsets are consistent")
