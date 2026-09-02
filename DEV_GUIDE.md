# Working on this project

Orientation for anyone — human or agent — picking this up in a new session.

`README.md` says what the mod does. `DESIGN.md` says how to change the
interior. **This file says how to work on it without breaking it**, and most
of what follows was learned by breaking it.

---

## First five minutes

```sh
cd C:\Users\Arcade\tardis
python tools/pzcatalog.py build                # ~10s, needed once per machine
python tools/luacheck.py TARDIS/42/media/lua
python tests/test_assets.py
python tests/test_stock.py
python tests/test_layout.py
```

If all five succeed you have a working setup. `test_layout.py` prints the deck
floor plan as ASCII — a good way to see the shape of the thing immediately.

| Where | What |
|---|---|
| `C:\Users\Arcade\tardis` | this repo |
| `C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid` | game install |
| `C:\Users\Arcade\Zomboid\mods\TARDIS` | where `tools/deploy.sh` installs to |
| `C:\Users\Arcade\Zomboid\console.txt` | the game log, **overwritten each launch** |

Target is **build 42.20.4**. Single player only.

---

## The loop

```sh
# 1. edit, then always:
python tools/luacheck.py TARDIS/42/media/lua
python tests/test_assets.py && python tests/test_stock.py && python tests/test_layout.py

# 2. install
sh tools/deploy.sh

# 3. run it
"/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/ProjectZomboid64.exe" -debug

# 4. read what happened
sh tools/readtest.sh
```

**Mod Lua only loads when a world starts**, not at the main menu, and it is
only re-read on game restart. There is no hot reload. Every code change needs
a full restart.

The static checks take seconds; a game round trip takes minutes and needs the
user. Never skip step 1 to save time.

---

## Rules that exist because they were broken

### Verify engine methods before calling them

```sh
python tools/pzapi.py zombie.iso.IsoGridSquare stairs
python tools/pzapi.py zombie.iso.IsoObject container
```

The game ships no `javap`; `tools/pzapi.py` parses the class files out of
`projectzomboid.jar` directly. **Use it.** `props:UnSet(...)` instead of
`props:unset(...)` cost a whole session — see *Black screen* below.

### Batch anything repeated per square

A method that does not exist throws out of Java, and the engine dumps a full
stack trace **for every call**. In a per-square loop that is ~676 dumps per
deck, which locks the game hard enough to look like a crash.

```lua
local join = U.batch("room.addSquare")
for ... do join(function() room:addSquare(sq) end) end
```

`U.batch` stops after the first failure, logs one warning, and lets the pass
continue. The same reasoning applies to anything on `OnTick` — wrap it.

**`U.try` is not a substitute.** It silences the *Lua* warning after the first
failure but keeps calling, and the engine keeps dumping a Java stack trace
every single time. `U.try` is for a call that happens once; `U.batch` is for a
call that repeats. Reaching for the wrong one wrote 1932 stack traces into one
session of `console.txt` — see *A list that is not a list* below.

"Repeated" means per list item too, not only per square. The reads that *find*
things need batching every bit as much as the writes that change them.

### A list that is not a list

`pzapi.py` gives you the *return type*, and it also tells you which class a
method is actually on. Both parts matter.

```
getVehicles()Ljava/util/Set;
```

A `Set` has `size()` but no indexed `get(i)`. So `list:size()` succeeded,
every `list:get(i)` threw, and the sonic screwdriver opened every house on the
street while silently never touching a single vehicle. The game's own Lua in
`ISVehicleBloodUI.lua` calls `vehicles:get(i-1)` — it is a debug UI, and it is
simply broken. **Copying the game's Lua is not verification; the jar is.**

Where a per-square accessor exists, prefer it to walking a global list — it is
usually what the game's own interaction code uses. Vehicles come from
`sq:getVehicleContainer()`, which is how `ISVehicleMenu` finds the vehicle you
right-clicked, and which this mod already used in `Core.canMaterialise`.

The same session turned up the other half of the same lesson. `getPartCount`,
`getPartByIndex`, `getBattery` and `getBatteryCharge` are **not on
`BaseVehicle`** — they are on `VehicleParts`, reached through
`vehicle:getParts()`. `setUsedDelta` is not on `InventoryItem` either; it is on
`DrainableComboItem`. When a call looks like it should exist and `pzapi.py`
comes back empty, the method is usually real and you are asking the wrong
class:

```sh
python tools/pzapi.py zombie.vehicles.BaseVehicle atter    # nothing useful
python tools/pzapi.py zombie.vehicles.VehicleParts         # there it is
```

`media/lua/server/Vehicles/Vehicles.lua` has a `VehicleUtils.chargeBattery`
that calls `vehicle:getBattery()` on a `BaseVehicle`. That method does not
exist. Dead or broken code in the game's own scripts is common enough that it
cannot be used as evidence.

### A zombie's appearance is fixed when it spawns

Daleks were attempted and removed. The verdict is worth keeping, because the
idea is an obvious one and the failure is invisible from every angle but one.

**A zombie that already exists cannot be restyled.** A character's model is
built from its `ItemVisuals`, and those are baked at spawn. Adding a worn item
afterwards succeeds at every single step and never reaches them:

```
-- after AddItem + setWornItem + resetModel, on a live zombie:
itemVisuals = [ Briefs, Vest, Socks, Shoes, Trousers ]     -- and nothing else
```

Nothing throws. The item exists, the clothing definition resolves, the body
location is right, the mesh is on disk and correctly scaled. It simply is not
in the list the renderer draws from, so it was never going to appear.

**And a creature cannot be added.** Non-human models need a rigged skeleton and
an animation set under `media/anims_X`; there are four and all four ship with
the game.

A zombie can be *given* something at creation -- that is what
`AttachedWeaponDefinitions` is for, and it is Lua and mod-extensible -- but it
cannot be turned into something else afterwards.

If this comes up again, check `getItemVisuals():getDescription()` **first**. It
is the only thing in the chain that tells "worn" apart from "drawn". Reaching
for it early would have saved six rounds of fixing real bugs -- a wrongly
driven world item, `setInvisible` that does not hide, an unregistered clothing
GUID -- each of which was a genuine fault, and none of which put anything on
screen. **Fixing a real bug is not the same as the feature working, and only
the thing the renderer reads settles it.**

### Never build where no player is standing

Chunks only stream around a player. `getOrCreateGridSquare` on an unloaded
chunk returns an orphan square, and the first engine call touching it throws.
`U.square(..., create=true)` returns `nil` instead; `U.chunkLoaded` gates
everything. Arrival moves the player **first**, holds them safe, and builds
once the chunks appear.

**The same goes for removing things.** `U.square(x, y, z, false)` returns `nil`
for an unloaded chunk, and a function that reads that as "nothing there" is
wrong: it means "cannot tell yet". Return a reason, not a boolean, and write
the position down to retry when the world catches up — `s.ghosts` and
`Core.sweepGhosts` are the pattern. This is why a second police box stood at
every place the ship had ever been.

### Never put a deck above another deck

PZ draws every level above the player and only hides overhead levels inside a
real building, which needs `RoomDef` metadata from a TileZed map. Runtime
squares cannot have it — `setRoom` silently does nothing. Decks step sideways
(`col`) as they descend for exactly this reason. `deck.*.nothingOverhead` in
the self-test guards it.

### Tag every object you place

`U.clearSquare` keeps tagged objects and destroys untagged ones, so an
untagged shelf is wiped on the next rebuild. Tags also drive behaviour
(`sink`/`shower`/`toilet` get refilled).

### Never restock an existing container

The ship is meant to be lived in: what the player eats stays eaten.
`U.addContainer` returns a `created` flag; stock only when it is true.
Restocking an existing container does not refill it — it stacks a *second*
helping on the first, so loot multiplies with every rebuild.

### Bump `C.BuildRev` when generation changes

Decks rebuild lazily on arrival at the new revision. Rebuilds preserve
furniture, container contents and crops. **Moving geometry is a migration,
not a rebuild** — see `purgeLegacyStack()` for the worked example.

### Write Lua with the Write tool, not shell heredocs

This shell mangles quoted heredocs: an apostrophe in a comment or a `\n` in a
string will break or corrupt the file. Use the `Write`/`Edit` tools for Lua,
or a Python script for surgical patches.

### Translations are one JSON file per category

Build 42 reads `media/lua/shared/Translate/EN/<Category>.json`, and the
category is part of the path, not the key. Item names go in `ItemName.json`
keyed by the bare full id (`"TARDIS.TARDISConsole"`), tooltips in
`Tooltip.json` keyed `Tooltip_*`, and only `IGUI_*` strings belong in
`IG_UI.json`.

An `"ItemName_TARDIS.TARDISConsole"` key inside `IG_UI.json` resolves to
nothing at all, silently — and it looked fine for six versions because
`DisplayName` in `media/scripts/tardis.txt` is the fallback the game shows
when the lookup misses.

### The game runs Lua 5.1

Kahlua, where `unpack` is a global. `tools/luacheck.py` and the tests use Lua
5.5 and stub it back. Do not write `table.unpack` in mod code.

---

## Failure signatures

Learn these; they map to causes that are not obvious from the symptom.

| What you see | What it usually is |
|---|---|
| **Black screen, character falling, game unresponsive** | An exception thrown inside a per-tick or per-square loop, flooding the log. Look for repeated stack traces in `console.txt`. Has happened three times. |
| **Player falls on entering** | The deck never finished building. Check for `arrival tick N: chunk ... loaded=false` and whether `deck N ... ready` ever appears. |
| **A shelf is empty and nothing is logged** | A sprite name that does not exist. Silent by design in PZ. `tests/test_assets.py` catches these. |
| **A container is missing item types** | Container capacity. `AddItems` drops items silently once full. Use `U.stockEach`, which reads the container back and reports what did not land. |
| **Furniture looks mismatched or doubled** | Multi-tile offsets wrong (`SpriteGridPos`), or two placement passes hitting one square. `tests/test_layout.py` checks the first. |
| **Interior looks like a tower in a forest** | The margin clearing did not run or the chunks streamed in late. It re-runs on every rebuild. |
| **Half a feature works and the other half is silent** | A wrong engine call on the silent path. One `[TARDIS] WARN` line names it, and the Java stack traces under it give the file and line. `grep -E "\[TARDIS\] WARN" console.txt` first, always — it is one line and it is the answer. |
| **Two of something that should be unique** | Something was removed at a position whose chunk was not loaded, and the failure was read as success. `TARDIS_Ghosts()` lists shells known to be pending and forces a sweep. |

---

## Testing

### Static, no game needed

| Check | Catches |
|---|---|
| `tools/luacheck.py` | Lua syntax, via a real Lua VM |
| `tests/test_assets.py` | sprite names and item ids that do not exist in this build |
| `tests/test_stock.py` | loot that does not spread across its list |
| `tests/test_layout.py` | floor plan errors; multi-tile offsets vs `SpriteGridPos` |

`test_assets.py` also checks the mod's *own* items: every `TARDIS.*` id in the
Lua must be declared in `media/scripts/tardis.txt`, and every `Icon =` in that
file must have a texture on disk. Both fail the same silent way in game as a
bad `Base.*` id does.

These have caught more real bugs than the in-game test has. Extend them in
preference to adding in-game checks.

### In game

Launch with `-debug` and load a **fresh** world; the self-test runs itself and
writes `TARDIS-TEST` lines. On a world where the ship is already in use it
deliberately stays out of the way — it flies the character through every deck,
which is unwelcome mid-game. `TARDIS_SelfTest()` from the debug console forces
it. `TARDIS_Rebuild()` tears down and regenerates the deck you are standing on,
fully restocked, for design iteration. `TARDIS_Sonic()` forces one lock sweep
where you stand and reports how many locks gave way, without needing to be
carrying a screwdriver. `TARDIS_Ghosts()` lists old shells still waiting to be
cleared and sweeps up any near you.

### Watching the log

A `Monitor` on `console.txt` is useful, but **filter tightly**:

```sh
tail -F -n 0 "/c/Users/Arcade/Zomboid/console.txt" \
  | grep -E --line-buffered "TARDIS-TEST (FAIL|====)|\[TARDIS\] (WARN|deck [0-9]|ejecting)"
```

A broad filter like `TARDIS|ERROR` matches every frame of every Java stack
trace and will flood the conversation — that happened, and the monitor had to
be killed.

**Check the timestamp before drawing conclusions.** `console.txt` is
overwritten each launch, so `head -1` gives the session start time. Reading a
stale log and reporting it as the current run is a mistake worth avoiding —
it has been made here.

---

## Working with the user

They run the game and report what they see; that is the only way most of this
gets verified. Practical notes:

- **Be explicit about what is verified and what is not.** Static checks
  passing is not the same as it working in game. Say which is which.
- **Warn before destructive rebuilds.** Moving a deck loses its container
  contents. Say so *before* they load in, not after.
- **They will spot real bugs from symptoms.** "The beds are weird and
  mismatched" was a genuine `SpriteGridPos` inversion; "only two rounds found"
  was container capacity silently dropping items. Investigate the report,
  do not explain it away.
- Decks rebuild **lazily on arrival**, so a change to deck 4 shows nothing
  until they walk into deck 4. Worth saying every time.

---

## Assets

Meshes and textures are **generated, never hand-authored**:

```sh
python tools/gen_texture.py TARDIS/42     # police box texture + icon
python tools/gen_model.py   TARDIS/42     # police box mesh
python tools/gen_console.py TARDIS/42     # console texture + mesh
python tools/gen_sonic.py   TARDIS/42     # sonic screwdriver icon
python tools/preview_model.py <mesh> <texture> out.png
```

`preview_model.py` is a small software renderer — parser, z-buffer, per-pixel
texture sampling — so a model can be checked without launching the game. It
verified the police box before the game was ever involved.

Two things to remember: **Y is up** for PZ world models (Z-up lays the box on
its side), and **1 unit is 1 tile**, with `scale` set in
`media/scripts/tardis.txt`.

---

## Current state

Version **1.8.1**, build revision **10**.

Working and confirmed in game: summoning, enter/exit, all six decks
generating, container stocking, water, crops, travel by map, bookmarks, the
void margin, the repulsion field.

Confirmed in game since: the sonic screwdriver's item, its case beside the
console, the lock sweep on doors, vehicle unlocking, hotwiring and the battery
jump.

1.8.1 fixes the shell not being lifted when the ship moved somewhere its old
chunk was not loaded — every flight left a police box behind. Worlds played
before the fix have strays nothing wrote down; `Core.sweepStrays` removes them
when a player walks within ten tiles, and `TARDIS_Ghosts()` forces it.

Daleks were attempted and removed -- see *A zombie's appearance is fixed when
it spawns*. `tools/gen_dalek.py` is kept: the model itself was good and
previews correctly, so it would serve as a static prop if one is ever wanted.

Confirmed by static checks but **not yet seen in game at the time of writing**:
the octagonal room shape, the redressed console room, the armoury, the galley
corner, the removal of the alcove, the fog-of-war lift, and the vehicle
hotwire and battery jump. `TARDIS-TEST sonic.vehicleHotwired` and
`sonic.vehicleBattery` cover those two in game, and `TARDIS_Sonic()` from the
debug console reports what a sweep found and what it did to it.

Revision 10 adds the sonic case to the console room, so **an existing world
rebuilds the console deck the next time the player stands on it.** That
preserves everything already in the room; it does not restock it.

Known limits are listed at the bottom of `README.md`.

---

## Layout

```
TARDIS/42/media/lua/shared/TARDIS/TARDIS_Config.lua   all constants — start here
TARDIS/42/media/lua/shared/TARDIS/TARDIS_Util.lua     safe wrappers, state, geometry
TARDIS/42/media/lua/client/TARDIS/TARDIS_Build.lua    deck construction, furnishing
TARDIS/42/media/lua/client/TARDIS/TARDIS_Core.lua     shell, doors, arrival, field
TARDIS/42/media/lua/client/TARDIS/TARDIS_Travel.lua   map, bookmarks, landing
TARDIS/42/media/lua/client/TARDIS/TARDIS_Sonic.lua    sonic screwdriver, lock sweep
TARDIS/42/media/lua/client/TARDIS/TARDIS_Menu.lua     right-click menus
TARDIS/42/media/lua/client/TARDIS/TARDIS_SelfTest.lua in-game step machine
```

Almost every change is `TARDIS_Config.lua` plus one `furnish` function.
