"""Static checks against the live build 42 data.

Catches the failure mode that costs the most time in game: a sprite or item
id that looks plausible, silently resolves to nothing, and leaves a deck
half-dressed with no error in the log.
"""
import json, re, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "tools", "_catalog")
MOD = os.path.join(ROOT, "TARDIS", "42")

tiles = set(json.load(open(os.path.join(CATALOG, "tiles.json")))["tiles"])
items = set(json.load(open(os.path.join(CATALOG, "items.json")))["Base"])

# a tile sprite looks like  some_tileset_name_01_42
SPRITE = re.compile(r"^[a-z][a-z0-9]*(?:_[a-z0-9]+)*_\d+$")
ITEM = re.compile(r"^Base\.([A-Za-z0-9_]+)$")

failures, checked_sprites, checked_items = [], 0, 0

for dp, _, fns in os.walk(os.path.join(MOD, "media", "lua")):
    for fn in fns:
        if not fn.endswith(".lua"):
            continue
        path = os.path.join(dp, fn)
        for lineno, line in enumerate(open(path, encoding="utf-8"), 1):
            if line.strip().startswith("--"):
                continue
            for lit in re.findall(r'"([^"]+)"', line):
                m = ITEM.match(lit)
                if m:
                    checked_items += 1
                    if m.group(1) not in items:
                        failures.append(f"{fn}:{lineno} unknown item {lit}")
                    continue
                if SPRITE.match(lit) and not lit.startswith("Base"):
                    checked_sprites += 1
                    if lit not in tiles:
                        failures.append(f"{fn}:{lineno} unknown sprite {lit}")

# skill books are built by concatenation, so expand them the same way
cfg = open(os.path.join(MOD, "media", "lua", "shared", "TARDIS",
                        "TARDIS_Config.lua"), encoding="utf-8").read()
block = re.search(r"C\.SkillBookLines = \{(.*?)\}", cfg, re.S)
for line in re.findall(r'"([A-Za-z]+)"', block.group(1)):
    for vol in range(1, 6):
        checked_items += 1
        if f"Book{line}{vol}" not in items:
            failures.append(f"skill book Base.Book{line}{vol} does not exist")

# crops must match farming_vegetableconf keys
CONF = r"C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid\media\lua\server\Farming"
crops_defined = set()
for fn in os.listdir(CONF):
    if fn.startswith("farming_vegetableconf"):
        src = open(os.path.join(CONF, fn), encoding="utf-8", errors="replace").read()
        crops_defined |= set(re.findall(r"props\.([A-Za-z]+)\s*=", src))
        crops_defined |= set(re.findall(r'props\["([A-Za-z]+)"\]', src))
block = re.search(r"C\.Crops = \{(.*?)\}", cfg, re.S)
for crop in re.findall(r'"([A-Za-z]+)"', block.group(1)):
    if crop not in crops_defined:
        failures.append(f"crop {crop} is not defined in farming_vegetableconf")

print(f"checked {checked_sprites} sprite names and {checked_items} item ids")
if failures:
    print(f"\n{len(failures)} PROBLEM(S):")
    for f in failures:
        print("  " + f)
    sys.exit(1)
print("all asset references resolve")
