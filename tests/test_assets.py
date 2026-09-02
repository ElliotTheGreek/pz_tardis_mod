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
MOD_ITEM = re.compile(r"^TARDIS\.([A-Za-z0-9_]+)$")

# The mod's own items, declared in media/scripts/tardis.txt. A Lua reference
# to one that is not declared there resolves to nothing, exactly as silently
# as a bad Base id does.
script = open(os.path.join(MOD, "media", "scripts", "tardis.txt"),
              encoding="utf-8").read()
mod_items = set(re.findall(r"^\s*item\s+([A-Za-z0-9_]+)", script, re.M))
mod_icons = set(re.findall(r"^\s*Icon\s*=\s*([A-Za-z0-9_]+)\s*,", script, re.M))

failures, checked_sprites, checked_items = [], 0, 0

# Clothing items are resolved by GUID through media/fileGuidTable.xml. A
# clothing XML with no entry there loads as nothing at all, silently: the item
# exists, is worn, and shows no model. That cost a whole evening, so it is
# checked here instead of in game.
CLOTHING_DIR = os.path.join(MOD, "media", "clothing", "clothingItems")
GUID_TABLE = os.path.join(MOD, "media", "fileGuidTable.xml")
if os.path.isdir(CLOTHING_DIR):
    table = open(GUID_TABLE, encoding="utf-8").read() if os.path.exists(GUID_TABLE) else ""
    listed = dict(zip(re.findall(r"<path>([^<]+)</path>", table),
                      re.findall(r"<guid>([^<]+)</guid>", table)))
    for fn in sorted(os.listdir(CLOTHING_DIR)):
        if not fn.endswith(".xml"):
            continue
        body = open(os.path.join(CLOTHING_DIR, fn), encoding="utf-8").read()
        m = re.search(r"<m_GUID>([^<]+)</m_GUID>", body)
        want = f"media/clothing/clothingItems/{fn}"
        if not m:
            failures.append(f"{fn} has no <m_GUID>")
        elif want not in listed:
            failures.append(f"{fn} is not listed in media/fileGuidTable.xml; "
                            f"it will load as nothing")
        elif listed[want] != m.group(1):
            failures.append(f"{fn} guid {m.group(1)} does not match "
                            f"fileGuidTable.xml entry {listed[want]}")
        # and every model it names has to be on disk
        for mdl in re.findall(r"<m_(?:Male|Female)Model>([^<]+)</m_", body):
            rel = mdl.replace("\\", "/").replace("media/", "", 1)
            if rel and not os.path.exists(os.path.join(MOD, "media", rel)):
                failures.append(f"{fn} names model {mdl} which does not exist")

# Every icon a mod item names has to exist as a file. A missing one shows as
# a blank square in the inventory and reports nothing anywhere.
for icon in sorted(mod_icons):
    candidates = [os.path.join(MOD, "media", "textures", f"Item_{icon}.png"),
                  os.path.join(MOD, "media", "ui", f"{icon}.png")]
    if not any(os.path.exists(p) for p in candidates):
        failures.append(f"tardis.txt: Icon = {icon} has no texture; "
                        f"expected media/textures/Item_{icon}.png")

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
                m = MOD_ITEM.match(lit)
                if m:
                    checked_items += 1
                    if m.group(1) not in mod_items:
                        failures.append(f"{fn}:{lineno} {lit} is not declared "
                                        f"in media/scripts/tardis.txt")
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

print(f"checked {checked_sprites} sprite names and {checked_items} item ids, "
      f"{len(mod_items)} mod items and {len(mod_icons)} icons")
if failures:
    print(f"\n{len(failures)} PROBLEM(S):")
    for f in failures:
        print("  " + f)
    sys.exit(1)
print("all asset references resolve")
