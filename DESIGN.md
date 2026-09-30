# Designing the TARDIS

How to change the shape, layout and contents of the interior, and the rules
the engine imposes on all of it.

Read [The four constraints](#the-four-constraints) before changing the
layout, and [INTERIOR.md](INTERIOR.md) for how the art and the decks are made.
Every constraint was learned by breaking the mod, and each explains why some
obvious-looking design is not available.

---

## The shape of the thing

The interior is **generated at runtime**, not shipped as a map: the mod writes
floors, walls and furniture into empty world cells the first time a player
stands in them. **What it writes is data** -- `TARDIS_Layout.lua`, generated
from BuildingEd files -- and **every tile is the mod's own**, painted by
Gemini, modelled by TRELLIS and rendered to the game's iso grid by the scripts
in `tools/`. [INTERIOR.md](INTERIOR.md) is that pipeline, end to end.

Six decks, one per storey, descending:

| # | Deck | id | z | col | Rooms |
|---|------|----|---|-----|-------|
| 1 | Console Room | `console` | 5 | 0 | console room, armoury, galley corner |
| 2 | Habitation Deck | `housing` | 4 | 1 | corridor, two bedrooms, bathroom, dormitory, the Wardrobe, guest room |
| 3 | Stores Deck | `storage` | 3 | 2 | storeroom, infirmary, workshop |
| 4 | Library Deck | `library` | 2 | 3 | library, observatory, archive |
| 5 | Galley Deck | `galley` | 1 | 4 | kitchen, dining room, pantry |
| 6 | Gardens | `growing` | 0 | 5 | hydroponic garden, stable |

Each deck is a set of **rectangular rooms with flat walls** -- no chamfers --
at most 25 x 25 (`C.RoomSize`), in a 24-tile ring of stripped void. Decks are
joined through the right-click menu, so there is no stairwell. Each deck's
layout has a **landing**, kept clear of furniture with the ring round it, and
that is where arrivals are put down; on the console deck it is in front of
the police box doors.

**`z` is the storey. `col` is a sideways step.** Deck *n* is one level below
deck *n−1* **and** `DeckSpacing` (80) tiles east of it. The descent is real;
the vertical alignment is deliberately given up. See constraint 2.

```
        z=5   [console]
        z=4          [housing]
        z=3                 [storage]
        z=2                        [library]
        z=1                               [galley]
        z=0                                      [growing]
              |<-- 80 -->|
```

Everything lives in cell **92,40** onward — clear of the vanilla map (which
ends at cell x 77) and of the Fifth-Wheel RV interior at cell 85,40.

---

## The four constraints

### 1. Nothing can be built into a chunk that has not streamed in

Chunks only load around a **player**. The interior is somewhere nobody ever
goes, so until someone is standing there its chunks do not exist —
and `getOrCreateGridSquare` on an absent chunk returns an *orphan* square with
no chunk behind it. The first engine call that touches one (`addFloor`,
`AddTileObject`) throws out of Java.

So the order is always **move the player in first, then build**:

- `U.chunkLoaded(x, y, z)` gates everything; `U.square(..., create=true)`
  returns `nil` rather than an orphan.
- `B.deckReady(deck)` probes the corners, centre and landing.
- `Core.beginArrival` teleports the player, then holds them — invulnerable,
  not falling — until `B.deckCurrent(index)` is true *and* the landing square
  demonstrably has a floor.
- If that never happens, `Core.ejectToOutside` puts them back outside.

**Never build at a location no player is at.**

And the corollary, which is easier to miss: **you cannot un-build there
either.** Anything that reaches for a remembered position — to remove, check
or repair it — gets `nil` back when that chunk is not loaded, and `nil` is not
"there is nothing there". It means "ask again later".

The shell is the worked example. Materialising lifts the box from wherever it
was, but a landing site is by definition nowhere near where the ship has been,
so at that moment the old chunk is never loaded. Treating that failure as "the
old shell is gone" left a second box standing after every flight.
`Core.removeExteriorAt` returns a *reason* rather than a bare boolean for
exactly this, and a position it could not reach goes into `s.ghosts` to be
cleared when the world next streams that spot in.

### 2. Decks may not sit above one another

Project Zomboid draws every z level above the player. It hides the ones
overhead only when it believes you are **inside a building**, and "building"
means `RoomDef` metadata baked into a map lotheader by TileZed. Runtime
squares cannot have it — `sq:setRoom(IsoRoom.new())` reports no error and
never sticks, and `player:getCurrentBuilding()` stays nil.

Stacking the decks therefore left the top deck drawn over all the others,
with no way to see the one you were standing on.

The fix is not to argue with the renderer but to remove what it was drawing:
`col` steps each deck sideways so nothing is ever overhead. The self-test
asserts this directly (`deck.*.nothingOverhead`) because the whole layout
depends on it.

**If you re-stack the decks, the interior becomes unreadable again.** The
decks are authored in BuildingEd as separate buildings for the same reason:
one building with a floor per deck is how BuildingEd would hold them, and how
the game must never build them.

### 3. Unmapped cells grow wilderness

The engine generates procedural forest in cells with no map data, so an
untreated interior reads as a tower standing in a wood. `clearSurroundings`
strips a `ClearMargin` (24) ring down to *nothing* — no objects, no floor —
which renders as black void, the look the Fifth-Wheel RV interior has.

`U.clearSquare` deliberately preserves anything the mod tagged, anything
lying on the ground, and any sown crop, so the pass is safe to repeat as
chunks stream in late.

### 4. A wrong engine method name is not a quiet failure

Calling a method that does not exist throws out of Java, and the engine dumps
a full stack trace **per call**. Inside a per-square loop that is hundreds of
dumps per deck, which freezes the game hard enough to look like a crash. This
cost a whole session: `props:UnSet(...)` instead of `props:unset(...)`.

Two defences, and both matter:

- **Check the name first**: `python tools/pzapi.py zombie.iso.IsoGridSquare stairs`
- **Batch anything repeated**: `U.batch(label)` returns a callable that stops
  after its first failure, logs one warning, and lets the pass continue.

```lua
local join = U.batch("room.addSquare")
for ... do join(function() room:addSquare(sq) end) end
```

`tests/test_build.py` runs the builder against a stub engine and fails on any
warning, which catches a typo in our own Lua; only `pzapi.py` settles whether
the engine has the method.

---

## Changing the design

### Moving or adding furniture

**The decks are authored in BuildingEd**, in `design/buildinged/TARDIS_*.tbx`,
and read at runtime out of `TARDIS_Layout.lua`. To move a bookcase, open the
map editor, not the Lua:

1. Edit the deck in BuildingEd (or its spec in `tools/gen_tardis_decks.py`,
   while the file is still a draft the generator owns).
2. `python tools/gen_tardis_lua.py` -- the layout the game builds from.
3. `python tests/test_layout.py` prints every deck's plan and fails on a
   fitting whose tile is not ours, a container that is not marked one (or the
   other way round), a container nothing stocks, or a blocked landing.

A new *kind* of furniture is a new entry at the **end** of
`tools/tardis_objects.py`, then a concept, a mesh and a render
([INTERIOR.md](INTERIOR.md) section 4).

**Draw the layout before believing it.** `gen_tardis_decks.py` renders every
deck from the real tiles into `design/art/interior/decks/`: a run of
appliances with a second rank of counters in front of it hides everything
behind it, which is obvious in a picture and invisible in the data.

**Tag every object you place.** The builder tags each object with its piece's
name; `U.clearSquare` keeps tagged objects and destroys untagged ones, and
tags drive behaviour: a piece the layout's `uses` marks `water` is refilled.

### What goes in a container

Stock is by **piece and deck**: `C.Stock[deck][piece]`, then
`C.Stock.any[piece]`, in `TARDIS_Config.lua`. `loot` names a `C.Loot` list
(`books` is every volume of every skill book), `amount` is how many picks,
and `cycle` hands consecutive containers of one piece the next list in turn,
so a storeroom's shelves alternate tools, medicine and linen.

Three things are packed rather than seeded, by name in `TARDIS_Build.lua`:

- **the armouries** (`ARMOURY`): the console deck's six gun cabinets and four
  trunks and the stores deck's eleven trunks, each a loot list times a number
  of copies, handed out in layout order;
- **the hold**: `C.ConsoleKit` packed across the console and the six roundel
  lockers, once in the life of a world;
- **the sonic case**: `C.SonicCount` screwdrivers.

**Capacity is a weight, and it binds the player, not the mod.**
`ItemContainer.AddItem` does **no capacity check at all** -- verified by
disassembling it -- so everything the mod puts in goes in. What an over-filled
container costs is the player: they can take out of it and cannot put anything
back. So each armoury list carries the weight of one copy in a comment, and
`copies` is chosen so nothing ends up over about 48 of a 50:

| crate | list | copies | weight |
|---|---|---|---|
| sidearms | `handguns` + `katanas` | 3 | 35.1 |
| long guns | `longarms` | 1 | 42.0 |
| magazines | `gunMags` | 6 | 7.2 |
| pistol ammunition | `pistolAmmo` | 6 | 29.5 |
| optics | `attachments` | 4 | 11.2 |
| holsters | `holsters` | 4 | 8.8 |
| pistol cartons | `pistolCartons` | 1 | 48.0 |
| rifle cartons | `rifleCartons` | 1 | 32.0 |
| 5.56 ×2 | `ammo556` | 8 | 45.9 each |
| katanas | `katanas` | 4 | 8.0 |

The two 5.56 trunks are the M16's: `Base.AssaultRifle` and `Base.JS14_Rifle`
both feed on it, and eight copies of `C.Loot.ammo556` is a little under two
thousand rounds a trunk.

A container's size comes from its tile (`ContainerCapacity`, set per piece in
`gen_tardis_pack.py`, `CAPACITY`): a bookcase 30, a gun cabinet or a trunk 50,
a hold locker 100.

### Loot lists

Lists live in `C.Loot` in `TARDIS_Config.lua`. Every id must exist in the
installed build:

```sh
python tools/pzcatalog.py items "^Book"          # find ids
python tools/pzcatalog.py check Base.Pills,Base.Hammer
```

`U.stock` keeps a **rolling cursor per list**, so consecutive containers
continue through it instead of all starting at the top. This is why the
library covers all ninety skill books rather than repeating the first eight a
hundred times over. `tests/test_stock.py` guards it.

### Tiles

Every sprite aboard is one of the mod's own, `tardis_interior_01_*` (walls,
floors, doors) and `tardis_interior_02_*` (furniture), from
`media/texturepacks/tardis_interior.pack` and the tiledef
`media/tardis_interior.tiles`, both named in `mod.info`
(`pack=tardis_interior`, `tiledef=tardis_interior 1963`). The one vanilla tile
is the soil under the crop beds. A sprite the game cannot find fails
**silently**, leaving an empty square and no error anywhere, so
`tests/test_assets.py` checks that the pack, the tiledef and `mod.info` agree,
and every sprite in the Lua against them.

**Properties are copied from a vanilla tile doing the same job**
(`gen_tardis_pack.py`): walls from `industry_01`, floors from
`floors_interior_tilesandwood_01`, doors from `fixtures_doors_01`, beds from
`furniture_bedding_01`, the range from a real oven, the fridge from a real
fridge, lockers and shelves from `furniture_storage_02`. What a vanilla tile
says is what the engine is known to act on. Two are never copied:
`lightswitch` (it turns a sprite into an `IsoLightSwitch` on the next load)
and `CustomItem`.

**A sprite is not the object the engine builds from it.** An `IsoObject`
wearing an oven's picture cooks nothing; the range is built as an `IsoStove`.
A runtime container has no `ItemContainer` until
`createContainersFromSpriteProperties` is called, and vanilla rolls its own
loot into it on first look unless it is `setExplored`. A sink's `waterAmount`
property is not a supply: each water fitting gets a fluid store of its own.

**Where you sit is not a tile property.** Build 42 reads seat positions from
`seating.txt`, and only from a mod's `common/media`. `gen_tardis_pack.py`
writes `TARDIS/common/media/seating.txt`, each of our seats and beds copying
the vanilla entry for the tile it stands in for.

### Changing the room shape

Rooms are rectangles in the deck specs (or whatever you draw in BuildingEd).
**Project Zomboid has no diagonal wall sprites** -- walls only sit on the north
or west edge of a square -- and the old octagonal halls were a stepped chamfer
standing in for one. The redesign gave that up for square rooms with flat
walls, which is what the author asked for and what the engine draws cleanly.

Walls are **derived from the rooms**, by BuildingEd's rule, in
`gen_tardis_lua.py`: a wall on every edge between two different rooms or a
room and nothing, in the style of the room on the square it stands on. A wall
standing outside every room still gets a floor under it: a wall on a midair
square behaves badly.

### Multi-tile furniture

A bed, a desk or the console covers several squares, and **which part goes
where** is its tiles' `SpriteGridPos`, written by `gen_tardis_pack.py` from the
render (`tardis_interior_02.json`). `tests/test_layout.py` checks every square
of every multi-square piece against it and that all its squares face the same
way.

Every square of a multi-square container is a container of its own, as
vanilla's two-square wardrobes are: the console is four.

### Changing a deck's size

A deck is at most `C.RoomSize` (25) squares a side; `C.RoomOffset` (16) keeps
it off the cell edge. `tests/test_layout.py` fails a deck that is larger. Keep
`C.DeckSpacing` comfortably larger than `RoomSize + 2 * ClearMargin`, or
neighbouring decks come into view.

### Adding a deck

1. Add an entry to `C.Decks` with a fresh `id`, the next `z` down and the next
   `col` across. `C.TopZ` is the highest z in use.
2. Add its spec to `DECKS` and `ORDER` in `tools/gen_tardis_decks.py`, and run
   the loop.

z 0 is the ground, so six decks is the limit of a strictly descending stack.
To go further, either start higher (`z` up to 31 — the engine's ceiling, per
`IsoCell.getMaxHeight()`) or let decks share a z and separate them by `col`
alone, which the layout already tolerates.

### The console is the hold

The console in the middle of the console room is a **tile**, not a world item:
the hexagonal console and its time rotor, a 2 x 2 piece whose four squares are
containers of 100 each. With the six roundel lockers along the west wall it
is the ship's hold, and `C.ConsoleKit` -- a packing list: explicit counts, not
a spread -- is packed across them, the console first, the first time the deck
is built.

Before 2.0.0 the console was a *world item* that opened like a crate. The
refit of an old console room lifts that item out and hands its contents to the
new hold; the two old item ids stay declared in `tardis.txt` so an old save
can still load them long enough for that.

### A container cannot be made bigger than the engine allows

Two ceilings, both in `ItemContainer.getCapacity()`, and nothing about them is
visible from the script side:

- a container that belongs to an **item** returns `min(capacity, 50)`, and
  `InventoryContainer.getCapacity()` then clamps that again to
  **50 − the item's own weight**;
- a container that belongs to a world **object** returns `min(capacity, 100)`.

So the old console item's `Capacity = 500` was not a bigger container, it was
a 50 -- and on an item weighing 80 it was **−30**: a hold everything could come
out of and nothing could go into. **The way to a bigger hold is more
containers, not a bigger one** -- and tiles, not items. The hold now is ten
world-object containers at the ceiling of 100 (the console's four squares and
six lockers), their capacity and their name ("TARDIS Console", "TARDIS Hold")
set in the tile definitions.

### The sonic screwdriver

An item with no use action. All of the behaviour is in `TARDIS_Sonic.lua`,
which sweeps the squares around whoever is carrying one and clears every lock
it finds. The item itself is declared in `media/scripts/tardis.txt` and its
icon is generated by `tools/gen_sonic.py`; neither does anything on its own.

Everything tunable is in `TARDIS_Config.lua`:

| constant | meaning |
|---|---|
| `C.SonicItem` | the full id, for spawning and placing |
| `C.SonicType` | the bare type, which is what the engine's inventory search compares |
| `C.SonicRadius` | how far the field reaches, in tiles, on the carrier's own level |
| `C.SonicInterval` | ticks between sweeps when the carrier is standing still |
| `C.SonicHotwire` | bypass the ignition on vehicles in reach |
| `C.SonicJumpStart` | charge a flat battery on vehicles in reach |
| `C.SonicCount` | how many are in the sonic case beside the police box doors |

Three things decided the shape of it.

**A sweep is expensive, so it has to be rare.** The field covers a square of
side `2r + 1` — nearly a thousand squares at the default radius. Sweeps run
when the carrier steps onto a new square and otherwise no oftener than
`C.SonicInterval`, with a floor of twelve ticks between any two, so sprinting
past a terrace does not sweep per frame and standing still costs almost
nothing.

**Read the special objects, not everything.** Doors, gates and windows all
live in `sq:getSpecialObjects()`, which is empty for almost every square.
Walking that instead of the full contents is what makes a sweep of a thousand
squares affordable; `U.eachObject` is only the fallback.

**Vehicles are found per square, not from a list.** `IsoCell.getVehicles()`
returns a `java.util.Set`, which has `size()` but no indexed `get(i)`; walking
it that way opens every house on the street and silently touches no vehicle at
all. They come from `sq:getVehicleContainer()` on the squares the sweep is
already visiting, which is how the game's own vehicle menu finds them. A truck
covers a dozen squares, so each vehicle is kept in a `seen` table and
considered once.

And there is no `getPartByIndex` on `BaseVehicle` in 42.20.4 — `pzapi.py` says
so, whatever the game's own Lua looks like it is doing — so doors are unlocked
with the one call that covers all of them, `v:setLocked(false)`, plus
`setTrunkLocked`.

The lock kinds and the calls that clear them, all verified with `pzapi.py`:

| object | locked by | cleared with |
|---|---|---|
| `IsoDoor` | outright, or by key | `setIsLocked`, `setLockedByKey` |
| `IsoThumpable` | key, padlock or keypad code | the above plus `setLockedByPadlock`, `setLockedByCode(0)` |
| `IsoWindow` | latch | `setIsLocked` |
| `BaseVehicle` | doors and boot | `setLocked`, `setTrunkLocked` |
| `BaseVehicle` | the ignition | `setHotwired(true)`, `setHotwiredBroken(false)` |
| the battery part | a flat battery | `getParts():getBattery()`, then `setUsedDelta(1)` on its item |

Unlocking a car only gets you into something you still cannot drive, so the
field does the other two as well.

`isHotwired()` is exactly what the game's own menu gates "Start Engine" on, so
setting it is the whole job. Deliberately **not** `tryHotwire(level)`, which is
what the vanilla action calls: that rolls against Electrical skill and, on a
failure, sets `hotwiredBroken` so the car can never be hotwired again. The
field does not roll dice, and clears that flag if a hand attempt set it.

The battery is a separate switch because most abandoned cars are flat and a
hotwired car with a dead battery still does nothing. Watch where these live —
**`getBattery` and `getBatteryCharge` are on `VehicleParts`, not on
`BaseVehicle`**, and `setUsedDelta` is on `DrainableComboItem`, which is what a
car battery is. `hasLiveBattery()` is the one cheap read on the vehicle itself,
and it is false both for a flat battery and for a car with none fitted, so the
sweep reports those two apart.

**Fuel is not touched.** An empty tank stays empty: that is neither a lock nor
an ignition, and a car that drives forever on nothing is a different mod.

Every one of those calls sits inside a `U.batch`, one batch per kind of call
per sweep, and each does its reading and its writing in the same batched call.
The batches cover the reads that *find* things — the door accessor, the
special-object list, the vehicle accessor — and not only the writes, because
`U.try` in a loop keeps calling after it warns and the engine keeps dumping a
stack trace each time. That is constraint 4 applied literally.

**Nothing is ever re-locked.** A lock the field has opened stays open once the
screwdriver is put down. The rule is that the field decides which locks give,
not which doors stay shut afterwards.

A permanently-locked window (`isPermaLocked`) is left alone deliberately: that
is a map saying this window never opens, not a lock.

### The ship is lived in

**A rebuild must never touch what is already in a container.** Once a shelf
exists it is the player's: what they eat stays eaten, what they take stays
taken, and what they put back stays where they put it. A container is stocked
once, ever: on the pass that makes it. Without that gate a rebuild does not
merely refill a shelf — it stocks it *again*, piling a second helping on top
of the first, so loot multiplies with every revision.

And a rebuild that takes something away -- a fitting the layout no longer
has, or a whole old deck on the refit -- **hands its contents back**: into the
deck's new containers where there is room, onto the floor round the landing
where there is not. The live items move, not their ids, so a magazine keeps
its rounds. A container that took salvage is not stocked on top of it.

The corollary is that **changing a loot list does not change any deck that
already exists.** New containers get the new list; old ones keep what they
have. That is correct for play and inconvenient for design, hence the escape
hatch below.

### Rebuilding while designing

```lua
TARDIS_Rebuild()      -- from the debug console, standing on the deck
```

Tears the deck you are standing on back to bare ground — containers and
contents included — and regenerates it fully stocked. Only the current deck
can be rebuilt, because only its chunks are loaded. For a wholesale change, a
**fresh world** is still the cleanest way to see the interior as a new player
would.

### Build revisions and migrations

A deck is stamped with `C.BuildRev` and the layout's `L.rev` as it is built.
`L.rev` is a hash of everything placed, so any change to a deck's layout makes
that deck update itself the next time a player stands on it -- lazily, on
arrival, so a deck nobody visits stays as it was. An update places what is
missing, takes away what we placed and the layout no longer has (contents
handed back), and never touches a container that is still wanted.

Bump `C.BuildRev` when the **builder** changes in a way every deck needs.

**Moving geometry is a migration, not a rebuild.** Revision 16 is the worked
example: every deck built before it is an old octagonal hall of vanilla
furniture, and `refitLegacy` clears such a deck whole, once, before the new
layout goes down ([INTERIOR.md](INTERIOR.md) section 6). `purgeLegacyStack()`
is the older example: it clears the levels left under the console room when
the decks stopped being stacked.

### Travel and the map

Choosing a destination stores it; the ship arrives when the player next steps
outside. That indirection is not incidental: a far-off destination is in a
chunk that has not streamed in, so there is nothing to inspect until the
player is standing there (constraint 1 again). `T.land` teleports first, then
retries `findLandingSite` on a tick job until the world catches up.

The flight console re-centres the map on the ship and hides the character
marker, because the character is in the interior cell and nowhere the map
depicts.

---

## Assets

The interior is **tiles**: our own texture pack, made by the pipeline in
[INTERIOR.md](INTERIOR.md) from Gemini art and TRELLIS meshes. The police box
shell and the sonic screwdriver are **world models** and icons, generated by
script:

```sh
python tools/gen_texture.py TARDIS/42     # police box texture + inventory icon
python tools/gen_model.py   TARDIS/42     # police box mesh
python tools/gen_console.py TARDIS/42     # the old console item's mesh, kept for old saves
python tools/gen_sonic.py   TARDIS/42     # sonic screwdriver inventory icon
```

An item's `Icon = X` resolves to `media/textures/Item_X.png`, and a missing
one shows as a blank square in the inventory and reports nothing anywhere.
`tests/test_assets.py` checks every icon a mod item names against the files
on disk, along with every `TARDIS.*` id the Lua refers to.

Check a model **without launching the game**:

```sh
python tools/preview_model.py TARDIS/42/media/models_X/TARDIS_PoliceBox.x \
       TARDIS/42/media/textures/TARDIS_PoliceBox.png /tmp/preview.png
```

- **Y is up.** Project Zomboid world models are Y-up; authoring Z-up lays the
  box on its side.
- **1 unit is 1 tile**, with `scale = 1.0` in `media/scripts/tardis.txt`.

---

## The loop

```sh
python tools/luacheck.py TARDIS/42/media/lua   # parses every file
python tests/test_assets.py                    # sprites, items, icons, pack and tiledef
python tests/test_stock.py                     # loot spreads across its list
python tests/test_layout.py                    # every deck, printed and checked
python tests/test_build.py                     # the builder, run against a stub engine
sh tools/deploy.sh                             # copy into Zomboid/mods
```

Then launch with `-debug`. On a **fresh** world the self-test runs itself and
writes `TARDIS-TEST` lines to `Zomboid/console.txt`; on a world where the ship
is already in use it stays out of the way, and `TARDIS_SelfTest()` from the
debug console forces it.

```sh
sh tools/readtest.sh
```

The self-test is a step machine, not a straight function, because most steps
have to wait for the world. It materialises the shell, boards it, then builds
and inspects every deck in turn -- every layout object read back off its
square, floors, the landing, container stocking, nothing overhead, void
margin -- then the hold, the sonic case, the galley range and sink, water,
crops, the repulsion field, exit and bookmarks.

**Lua version note.** The game runs Kahlua, a Lua 5.1 dialect where `unpack`
is a global and there is no `goto`. `tools/luacheck.py` and the tests use Lua
5.5, which accepts both; the harness stubs `unpack` back. Mod code uses the
5.1 spelling.

---

## Where things live

| File | Holds |
|------|-------|
| `TARDIS_Config.lua` | Decks, loot lists, stock rules, crops, the kit. Start here. |
| `TARDIS_Layout.lua` | Every deck as data -- GENERATED by `tools/gen_tardis_lua.py`, do not edit |
| `TARDIS_Util.lua` | Safe engine wrappers, state, coordinates, clearing, stocking |
| `TARDIS_Build.lua` | Places the layout: floors, walls, doors, fittings, stock, water, lamps, the refit |
| `TARDIS_Core.lua` | Shell, doors, arrival, water, repulsion field |
| `TARDIS_Travel.lua` | Bookmarks, landing search, flight console, map markers |
| `TARDIS_Sonic.lua` | The sonic screwdriver: the lock-opening sweep |
| `TARDIS_Menu.lua` | Right-click menus |
| `TARDIS_SelfTest.lua` | In-game step machine |

Almost every design change is an edit in BuildingEd (or a deck spec) plus
`gen_tardis_lua.py`, and perhaps a stock rule in `TARDIS_Config.lua`.

---

## Rules of thumb

- Verify an engine method with `tools/pzapi.py` before calling it.
- Wrap anything repeated per-square in `U.batch`.
- Tag every object you place, or a rebuild eats it.
- Move furniture in BuildingEd, never in the Lua; regenerate the layout.
- Look at the picture: the room preview, the furniture sheet, the deck renders.
- Never build, or un-build, where no player is standing.
- Never put a deck above another deck.
- Never throw away what a player might keep: hand it back.
- Bump `C.BuildRev` when the builder changes; write a migration when geometry
  *moves*.
- Run the static checks before deploying — they are seconds, and a game
  round-trip is minutes.
