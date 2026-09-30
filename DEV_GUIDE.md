# Working on this project

Orientation for anyone — human or agent — picking this up in a new session.

`README.md` says what the mod does. `DESIGN.md` says how to change the
interior and `INTERIOR.md` how its art and decks are made. **This file says
how to work on it without breaking it**, and most of what follows was learned
by breaking it -- here, or in the Shuttlecraft mod (`pz_trekship`), whose
interior pipeline this one now uses.

---

## First five minutes

```sh
cd C:\Users\Arcade\tardis
python tools/pzcatalog.py build                # ~10s, needed once per machine
python tools/luacheck.py TARDIS/42/media/lua
python tests/test_assets.py
python tests/test_stock.py
python tests/test_layout.py
python tests/test_build.py
```

If all six succeed you have a working setup. `test_layout.py` prints every
deck's floor plan as text, and `design/art/interior/decks/*.png` are the same
decks drawn from the real tiles — look at both to see the shape of the thing.

The art pipeline needs `numpy`, `trimesh` and `Pillow`; the tests need `lupa`.
Generating new art needs the FlowDot MCP server (Gemini image generation and
fal TRELLIS), see `INTERIOR.md` section 4.

| Where | What |
|---|---|
| `C:\Users\Arcade\tardis` | this repo |
| `C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid` | game install |
| `C:\Users\Arcade\Zomboid\mods\TARDISDev` | where `tools/deploy.sh` installs to, as **TARDIS [DEV]** |
| `C:\Users\Arcade\Zomboid\console.txt` | the game log, **overwritten each launch** |

Target is **build 42.20.4**. Single player only.

---

## The loop

```sh
# 0. if the art or a deck changed (INTERIOR.md, the loop):
python tools/gen_tardis_tiles.py && python tools/gen_tardis_furniture.py
python tools/gen_tardis_decks.py && python tools/gen_tardis_pack.py
python tools/gen_tardis_lua.py

# 1. edit, then always:
python tools/luacheck.py TARDIS/42/media/lua
python tests/test_assets.py && python tests/test_stock.py
python tests/test_layout.py && python tests/test_build.py

# 2. install
sh tools/deploy.sh

# 3. run it
"/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/ProjectZomboid64.exe" -debug

# 4. read what happened
sh tools/readtest.sh
```

`deploy.sh` installs the repo as **TARDIS [DEV]** (id `TARDISDev`), so it
sits beside the Workshop release (id `TARDIS`) in the mod list. Enable one or
the other for a world, **never both**: they share every Lua path, item id and
tile, and would load over each other. The repo's `mod.info` is the release one;
only the installed copy is renamed.

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

### A setter is not proof that anything reads it

`pzapi.py` shows signatures, not bodies. For *what a method does*, decompile
it with CFR and the game's own Java (both run without installing anything):

```sh
J="/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/jre64/bin/java.exe"
JAR="/c/Program Files (x86)/Steam/steamapps/common/ProjectZomboid/projectzomboid.jar"
curl -sL -o cfr.jar https://github.com/leibnitz27/cfr/releases/download/0.152/cfr-0.152.jar
unzip -o -q "$JAR" zombie/iso/IsoGridSquare.class -d x
"$J" -jar cfr.jar x/zombie/iso/IsoGridSquare.class --methodname haveElectricity
```

That is how 2.0.1 found that **the ship never had power**. The builder called
`sq:setHaveElectricity(true)` on every square from the start, and in 42.20
`haveElectricity()` never reads that flag: it asks the square's chunk whether
a generator position on its list is in range. Grid power needs a room, which a
runtime deck cannot have. Nothing threw, nothing warned, and every fridge on
the ship was warm. A player reported it as "the TARDIS has no power".

`B.powerDeck` now registers generator positions on the deck's chunks
(`IsoChunk.addGeneratorPos`) with no generator behind them, so no fuel, noise
or fire. The engine drops such a position whenever a neighbouring chunk loads
(`checkForMissingGenerators`), so they are re-registered from the player
update once a second, like the lamps. `tests/test_build.py` models the
chunks and checks every deck square is in range at three generator ranges.

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

### A table-top sprite is drawn as though it were on a counter

Counter basins, lamps, radios and microwaves carry `IsTableTop`,
`IsSurfaceOffset` and `Surface = 34`: the art is drawn already raised to
counter height, so on bare floor it floats over the square behind.
`U.addObject` still seats one by `renderYOffset = Surface − whatever it
stands on` -- **not** `under − Surface`, which is what the game's own
`placeMoveableInternal` computes, shipped in 1.9.1, and made the sinks vanish.
It was settled by extracting the sprites from `Tiles2x.pack` and looking at
the pixels (`tools/tileview.py --where`).

The interior no longer places any vanilla table-top sprite -- since 2.0.0
every fitting is our own tile, rendered standing on its square -- but the
lesson stands: **`IsoObject.new` + `AddTileObject` is not the whole of what
the game does to put an object down**, and a picture settles it where three
rounds of reasoning did not.

### A sprite is not the object the engine builds from it

Learned by the Shuttlecraft (its viewscreen was an `IsoObject` wearing a
television's picture for three versions), applied here from the start. The
engine decides an object's class from what built it, not from its sprite:

- the galley ranges are built with `IsoStove.new`, or they cook nothing;
- every container gets `createContainersFromSpriteProperties` (a runtime
  object has no `ItemContainer` otherwise) and `setExplored(true)` (or vanilla
  rolls its own loot into it on first look);
- every water fitting gets a fluid store of its own
  (`ComponentType.FluidContainer`, `GameEntityFactory.AddComponent`) -- a
  sink's `waterAmount` property is not a supply, and
  `createFluidContainersFromSpriteProperties` is empty in build 42;
- doors are `IsoDoor.new` added with `AddSpecialObject`: a closed door only
  blocks from the square's special-object list.

`tests/test_build.py` checks all four against the stub; the self-test checks
the range and the sink in game.

### Never find a door by its sprite

`IsoDoor.ToggleDoor` swaps an open door's sprite for the one two along, so
code that looks for "the door" by its closed sprite finds it only while it is
shut -- and a rebuild would put a second door into every open one. The
builder finds *our door on that edge* (tagged, an `IsoDoor`, `getNorth()`
matching), and so does the self-test.

### Tag every object you place

`U.clearSquare` keeps tagged objects and destroys untagged ones, so an
untagged shelf is wiped on the next rebuild. Tags also drive behaviour
(`sink`/`shower`/`toilet` get refilled).

### Never restock an existing container

The ship is meant to be lived in: what the player eats stays eaten. The
builder stocks a container only on the pass that makes it. Restocking an
existing container does not refill it — it stacks a *second* helping on the
first, so loot multiplies with every rebuild.

### Never throw away what a player might keep

Anything the builder takes away -- a fitting a new layout does not have, an
old deck on the refit, the old console item -- gives up its contents first,
as the **live items**, into the deck's new containers or onto the floor round
the landing. Recreating an item from its id resets a magazine's rounds, which
is the quiet half of losing it. `tests/test_build.py` refits a stub old deck
and counts the items back.

### Bump `C.BuildRev` when the builder changes

Decks rebuild lazily on arrival at a new revision, and also whenever their
layout changes (`L.rev` in `TARDIS_Layout.lua` is a hash of everything
placed). Rebuilds preserve furniture, container contents and crops. **Moving
geometry is a migration, not a rebuild** — `refitLegacy()` (revision 16) and
`purgeLegacyStack()` are the worked examples.

### Move furniture in BuildingEd, not in the Lua

The decks are `design/buildinged/TARDIS_*.tbx`, and `TARDIS_Layout.lua` is
generated from them. **Dead placement code is worse than none**: the
Shuttlecraft once had every hand-written `furnish` function unreachable, and
its layout test busy validating those while the real interior went unchecked.
When the TARDIS moved to generated layouts, every `furnish` function, every
hand-picked vanilla sprite (`C.Sprites`, `C.Pieces`) and the octagon
(`C.inShape`) went with them.

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

Kahlua, where `unpack` is a global and **there is no `goto`**. `tools/
luacheck.py` and the tests use Lua 5.5, which parses both happily, so neither
catches a 5.2+ construct: do not write `table.unpack` or `goto` in mod code.

### Write shell-side patches as script files

Python fed to the shell through a quoted heredoc was mangled twice in the
2.0.0 session (an unbalanced-quote error from text that was balanced). A
patch longer than a line goes into a `.py` file first, then runs.

---

## Failure signatures

Learn these; they map to causes that are not obvious from the symptom.

| What you see | What it usually is |
|---|---|
| **Black screen, character falling, game unresponsive** | An exception thrown inside a per-tick or per-square loop, flooding the log. Look for repeated stack traces in `console.txt`. Has happened three times. |
| **Player falls on entering** | The deck never finished building. Check for `arrival tick N: chunk ... loaded=false` and whether `deck N ... ready` ever appears. |
| **A shelf is empty and nothing is logged** | A sprite name that does not exist. Silent by design in PZ. `tests/test_assets.py` catches these. |
| **Whole decks are bare floor, or nothing at all** | The texture pack or tiledef did not load: `pack=` and `tiledef=` in `mod.info`, `media/texturepacks/tardis_interior.pack`, `media/tardis_interior.tiles`. `tests/test_assets.py` checks all four agree. |
| **A cupboard is drawn and will not open** | A container tile placed without `createContainersFromSpriteProperties`, or a tile whose properties lost `container`. `tests/test_layout.py` cross-checks the layout's `c` against the tiledef both ways. |
| **A chair offers no way to sit on it at all** | Its tile lacks `bed` and `BedType`. Sitting on furniture is the rest action, offered only on `IsoFlagType.bed`, and every vanilla chair and sofa carries both. 2.0.0 shipped its seats without them (`gen_tardis_pack.py`, `SEAT_BEDTYPE`); `tests/test_layout.py` checks every seat tile now. |
| **You sit on the floor beside a chair** | No entry for that tile in `TARDIS/common/media/seating.txt` (and it must be under `common/`). Regenerate with `gen_tardis_pack.py`. |
| **A heap of items by the landing** | A refit or a layout change handed back more than the new containers had room for. Nothing was lost; the log says how much went where. |
| **A container is missing item types** | An id that does not resolve. `ItemContainer.AddItem` looks the id up in the script manager and returns null for one that is missing or `obsolete`, logging a line and nothing else. It does **not** check capacity — that was believed for a long time and is wrong; an over-filled container holds everything and simply refuses what a *player* tries to add. Use `U.stockEach`, which reads the container back and reports what did not land. |
| **Furniture looks mismatched or doubled** | Multi-tile offsets wrong (`SpriteGridPos`), or two placement passes hitting one square. `tests/test_layout.py` checks the first. |
| **A placed object sits in the floor, or floats** | A table-top sprite with no render offset. See *A table-top sprite is drawn as though it were on a counter*. |
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
| `tests/test_layout.py` | every deck: tiles, containers, stock rules, landing, multi-square pieces |
| `tests/test_build.py` | the builder run against a stub engine: any WARN, missing pieces, stock, hold, water, stoves, idempotent rebuild, the refit |
| `tools/tileview.py` | what a vanilla sprite actually *looks* like, without the game |
| `design/art/interior/*.png` | what ours look like: the room preview, the furniture sheet, every deck |

`test_assets.py` also checks the mod's *own* items and tiles: every
`TARDIS.*` id in the Lua must be declared in `media/scripts/tardis.txt`, every
`Icon =` in that file must have a texture on disk, and every
`tardis_interior_*` sprite must be in the tiledef and the pack, which
`mod.info` must name. All fail the same silent way in game as a bad `Base.*`
id does.

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
carrying a screwdriver. (In play the screwdriver is used from the right-click
menu on one door or car; the sweep is the old auto field, `C.SonicAuto`.) `TARDIS_Ghosts()` lists old shells still waiting to be
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

## Publishing

```sh
python tools/package_workshop.py --install   # builds workshop/TARDIS, stages ~/Zomboid/Workshop/TARDIS
```

then in game: Workshop → Create and update items → TARDIS → upload. The
listing text is `workshop/description.txt`; the thumbnail is cut from a clean
render of the console room (`PREVIEW_BOX`).

The published item is **3810732908**, and `WORKSHOP_ID` holds it. For the
record: **after the first upload, the `id=` the game writes into
`~/Zomboid/Workshop/TARDIS/workshop.txt` has to be copied into `WORKSHOP_ID`
in the script.**
That id is the only thing that makes the next upload an update rather than a
second, separate item, and there is no undo. Until it is copied, `--install`
keeps the staged id rather than wiping it.

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
  was an armoury crate stocked with ids that did not resolve. Investigate the
  report, do not explain it away.
- Decks rebuild **lazily on arrival**, so a change to deck 4 shows nothing
  until they walk into deck 4. Worth saying every time.
- **New art is theirs to veto.** Show the room preview, the furniture sheet
  and the deck renders before building on a generated piece.

---

## Assets

**The interior's tiles** are made by the pipeline in `INTERIOR.md`: Gemini
surfaces and concepts, TRELLIS meshes, and the generators --

```sh
python tools/gen_tardis_tiles.py        # walls, floors, doors
python tools/gen_tardis_furniture.py    # every piece in every facing
python tools/gen_tardis_decks.py        # the six decks, .tbx + renders
python tools/gen_tardis_pack.py         # .pack, .tiles, seating.txt
python tools/gen_tardis_lua.py          # TARDIS_Layout.lua
python tools/install_tilezed.py         # the tilesets into BuildingEd
python tools/tardis_jobs.py show        # the ledger of concepts and meshes
```

**The world models** -- the police box, the old console item, the sonic
screwdriver's icon -- are generated, never hand-authored:

```sh
python tools/gen_texture.py TARDIS/42     # police box texture + icon
python tools/gen_model.py   TARDIS/42     # police box mesh
python tools/gen_console.py TARDIS/42     # the old console item (old saves only)
python tools/gen_sonic.py   TARDIS/42     # sonic screwdriver icon
python tools/preview_model.py <mesh> <texture> out.png
```

Vanilla tile sprites can be looked at the same way, which is worth doing
before believing a placement is correct:

```sh
python tools/tileview.py --where fixtures_sinks_01_0     # is it on the floor?
python tools/tileview.py --stack carpentry_02_17 fixtures_sinks_01_0
```

Two things to remember about the world models: **Y is up** (Z-up lays the box
on its side), and **1 unit is 1 tile**, with `scale` set in
`media/scripts/tardis.txt`.

---

## Current state

Version **2.0.1**, build revision **16**.

**2.0.1** answers the first player feedback, and **none of it has been seen in
game yet**:

- **The ship has power** (`B.powerDeck`, see *A setter is not proof that
  anything reads it*). Look for the galley fridges cooling and the range
  heating; no `[TARDIS] WARN (power.` line. No rebuild is needed or triggered:
  the power is registered from the player update on every deck already built.
- **The sonic screwdriver is used from the menu**, not carried as a field:
  right-click a locked door or car, **Use sonic screwdriver on ...**, a timed
  action with a progress bar, then `sonic: used at x,y,z -- ...` in the log.
  The old field is `C.SonicAuto`, off. Check both a door and a car; and that
  walking away mid-action cancels it.

**2.0.0 regenerates the whole interior** with the Shuttlecraft's pipeline
(`INTERIOR.md`): 11 Gemini surfaces, 47 pieces of furniture and wall art
(40 modelled by TRELLIS from Gemini concepts, 7 flat pictures), 184 tiles in
the mod's own texture pack, six decks of rectangular rooms drafted as
BuildingEd files, and a builder that places `TARDIS_Layout.lua` instead of
hand-written `furnish` functions. The octagon, `C.Sprites`, `C.Pieces`,
`C.Landing`, `C.ConsoleHold` and `C.SonicBox` are gone; the console is a tile
and the head of the hold.

**Verified by static checks and the stubbed build only -- none of it has been
seen in game yet.** On the first load, look for:

- **The interior draws at all.** If every deck is floorless void, the pack or
  tiledef did not load: `grep -i "tardis_interior" console.txt` for the
  engine's own complaint. If floors draw and furniture does not, a sprite
  name is wrong in a way the tests could not see.
- **Doors block, open and close**, and the police box doors on the console
  room's north wall are pictures, not doors (the way out is the right-click
  menu, as before).
- **Chairs and beds sit you on them** (`seating.txt` under `common/`).
- **The range cooks and the sinks give water** (`TARDIS-TEST galley.*`,
  `water.*`).
- `[TARDIS] <deck> ready ... placed, ... containers stocked` once per deck,
  and no `[TARDIS] WARN`.
- **An existing world** is refitted deck by deck as each is visited:
  `refitted from the old layout -- N objects cleared, M items to hand back`
  and `handed back ... into the new fittings, ... onto the floor by the
  landing`. Whatever was in the old shelves is in the new ones or in a heap
  by the landing. **A fresh world is the clean way to see the new ship.**

Working and confirmed in game before 2.0.0, and not changed by it: summoning,
enter/exit, travel by map, bookmarks, the void margin, the repulsion field,
the sonic screwdriver's unlocks themselves (locks, vehicle unlocking,
hotwiring, the battery jump) -- the calls are unchanged in 2.0.1; only how
they are triggered is new.

Daleks were attempted and removed -- see *A zombie's appearance is fixed when
it spawns*. `tools/gen_dalek.py` is kept: the model itself was good and
previews correctly, so it would serve as a static prop if one is ever wanted.

Revisions 10 to 15 dressed the old octagonal console room (the sonic case, the
console as a container item, the hold ring, the galley corner and its sinks);
their lessons are in *A table-top sprite is drawn as though it were on a
counter* and DESIGN.md, *A container cannot be made bigger than the engine
allows*. The code they describe is gone.

Known limits are listed at the bottom of `README.md`, and what the interior
still lacks at the end of `INTERIOR.md`.

---

## Layout

```
TARDIS/42/media/lua/shared/TARDIS/TARDIS_Config.lua   decks, loot, stock rules — start here
TARDIS/42/media/lua/shared/TARDIS/TARDIS_Layout.lua   every deck as data (GENERATED)
TARDIS/42/media/lua/shared/TARDIS/TARDIS_Util.lua     safe wrappers, state, geometry
TARDIS/42/media/lua/client/TARDIS/TARDIS_Build.lua    places the layout, stocks it, the refit
TARDIS/42/media/lua/client/TARDIS/TARDIS_Core.lua     shell, doors, arrival, field
TARDIS/42/media/lua/client/TARDIS/TARDIS_Travel.lua   map, bookmarks, landing
TARDIS/42/media/lua/client/TARDIS/TARDIS_Sonic.lua    sonic screwdriver: menu targets, timed action, sweep
TARDIS/42/media/lua/client/TARDIS/TARDIS_Menu.lua     right-click menus
TARDIS/42/media/lua/client/TARDIS/TARDIS_SelfTest.lua in-game step machine
TARDIS/42/media/texturepacks/tardis_interior.pack    the interior's tiles (GENERATED)
TARDIS/42/media/tardis_interior.tiles                 their properties (GENERATED)
TARDIS/common/media/seating.txt                       where you sit on them (GENERATED)
design/art/interior/                                  Gemini raws and concepts, renders
design/tiles/                                         the tile sheets and the furniture index
design/buildinged/                                    the decks, for BuildingEd
tools/assets/interior/                                TRELLIS meshes
```

Almost every change is an edit in BuildingEd (or a deck spec in
`tools/gen_tardis_decks.py`) and `gen_tardis_lua.py`, plus perhaps a stock
rule in `TARDIS_Config.lua`.
