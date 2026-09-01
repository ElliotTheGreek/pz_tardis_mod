# Designing the TARDIS

How to change the shape, layout and contents of the interior, and the rules
the engine imposes on all of it.

Read [The four constraints](#the-four-constraints) before changing the
layout. Every one of them was learned by breaking the mod, and each explains
why some obvious-looking design is not available.

---

## The shape of the thing

The interior is **generated at runtime**, not shipped as a map. Nothing here
was made in TileZed; the mod writes floors, walls and furniture into empty
world cells the first time a player stands in them.

Six decks, one per storey, descending:

| # | Deck | id | z | col | Contents |
|---|------|----|---|-----|----------|
| 1 | Console Room | `console` | 5 | 0 | Control console, open floor |
| 2 | Habitation Deck | `housing` | 4 | 1 | Bunks, lockers, bathrooms |
| 3 | Stores Deck | `storage` | 3 | 2 | Tools, weapons, ammunition, medicine |
| 4 | Library Deck | `library` | 2 | 3 | Skill books, magazines, tapes |
| 5 | Galley Deck | `galley` | 1 | 4 | Kitchens, cold storage, pantry |
| 6 | Hydroponics Deck | `growing` | 0 | 5 | Crops, seed stores, livestock |

Each deck is a 25×25 **octagonal** hall sitting in a 24-tile ring of stripped
void. The hall is open: decks are joined through the right-click menu, so
there is no stairwell or vestibule taking up floor space. A 3×3 **landing**
is kept clear of furniture, and that is where arrivals are put down.

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

**If you re-stack the decks, the interior becomes unreadable again.**

### 3. Unmapped cells grow wilderness

The engine generates procedural forest in cells with no map data, so an
untreated interior reads as a tower standing in a wood. Two passes handle it:

- `clearFootprint` strips the deck footprint before anything is placed.
- `clearSurroundings` strips a `ClearMargin` (24) ring down to *nothing* — no
  objects, no floor — which renders as black void, the look the Fifth-Wheel
  RV interior has.

`U.clearSquare` deliberately preserves anything the mod tagged, anything
lying on the ground, and any sown crop, so both passes are safe to repeat as
chunks stream in late.

### 4. A wrong engine method name is not a quiet failure

Calling a method that does not exist throws out of Java, and the engine dumps
a full stack trace **per call**. Inside a per-square loop that is 676 dumps
per deck, which freezes the game hard enough to look like a crash. This cost
a whole session: `props:UnSet(...)` instead of `props:unset(...)`.

Two defences, and both matter:

- **Check the name first**: `python tools/pzapi.py zombie.iso.IsoGridSquare stairs`
- **Batch anything repeated**: `U.batch(label)` returns a callable that stops
  after its first failure, logs one warning, and lets the pass continue.

```lua
local join = U.batch("room.addSquare")
for ... do join(function() room:addSquare(sq) end) end
```

---

## Changing the design

### Furnishing a deck

Each deck has one function in `TARDIS_Build.lua`, keyed by `deck.id`:

```lua
furnish.library = function(deck)
    local books = skillBookList()
    for i = 1, 6 do
        line(deck, C.Sprites.bookShelf.S, 2 + (i - 1) * 2, 2, 0, 1, 20,
             { loot = books, amount = 12, tag = "books" })
    end
end
```

`line(deck, sprite, ox, oy, dx, dy, count, opts)` places a run of objects from
an offset inside the deck. `opts` takes:

| key | meaning |
|-----|---------|
| `loot` | a list from `C.Loot`; makes the object a container and stocks it |
| `amount` | items per container |
| `tag` | mod-data tag — **required for anything that should survive a rebuild** |

The armoury on the stores deck is the worked example of a *packed* container
rather than a seeded one: military crates hold fifty, so each is stocked with
30-40 picks from `C.Loot.firearms`, `gunMags`, `gunAmmo` and `attachments`,
which together cover every firearm, magazine, calibre and optic in the build.

**Tag everything you place.** `U.clearSquare` keeps tagged objects and
destroys untagged ones, so an untagged shelf is wiped on the next rebuild.
Tags also drive behaviour: `sink`, `shower` and `toilet` are refilled with
water every ten in-game minutes.

Offsets run `0..25` from the deck's north-west corner. `C.Landing` and its
clearance ring are refused by every placement helper, so nothing can be put
down where a player arrives — you do not have to route around it by hand.

### Loot lists

Lists live in `C.Loot` in `TARDIS_Config.lua`. Every id must exist in the
installed build:

```sh
python tools/pzcatalog.py items "^Book"          # find ids
python tools/pzcatalog.py check Base.Pills,Base.Hammer
```

`U.stock` keeps a **rolling cursor per list**, so consecutive containers
continue through it instead of all starting at the top. This is why the
library covers all ninety skill books rather than repeating the first twelve
a hundred and twenty times. `tests/test_stock.py` guards it.

Long lists spread further than short ones. If you want fuller coverage, make
the list longer or the containers more numerous — not `amount` bigger.

### Choosing sprites

Sprite names come from the installed build; a wrong one fails **silently**,
leaving an empty square and no error anywhere.

```sh
python tools/pzcatalog.py build                       # once, after a game update
python tools/pzcatalog.py sprites container fridge
python tools/pzcatalog.py sprites name furniture_bedding
```

Useful properties: `container` (shelves, crate, locker, fridge, stove,
counter…), `bed`, `lightswitch`, `waterAmount`, `solidfloor`, `wall`.

Wall tilesets follow a pattern: index 0 is the **west** face, 1 the **north**
face, 2 the corner post. Multi-tile furniture is consecutive (a bed is
`furniture_bedding_01_8` head and `_9` foot).

`tests/test_assets.py` checks every sprite name and item id in the Lua
against the catalogue, so a typo fails before the game ever runs.

### Changing the room shape

`C.Shape` is one of `"rect"`, `"octagon"` (default) or `"hexagon"`, with
`C.Chamfer` controlling how deep the corners are cut.

**Project Zomboid has no diagonal wall sprites.** Walls only ever sit on the
north or west edge of a square, so a smooth hexagon or circle is not
available at any size. What *is* available is a stepped chamfer — cut the
corners off the square and let the wall follow the steps — which at deck scale
and the game's camera angle reads clearly as an octagon.

Walls are **derived from the floor plan**, not hard-coded: `buildWalls` walks
every in-shape square and puts a wall wherever its neighbour is outside. So a
new shape is a new `C.inShape` branch and nothing else. Furnishing follows
too — `line()` skips out-of-shape squares, and `wallRing(deck, inset)` returns
the band of squares just inside the wall along with the direction each should
face, so shelves hug all eight walls with no hand-placed coordinates.

`tests/test_layout.py` prints the plan as ASCII and asserts the landing,
alcove doorway and console are all inside it.

### Multi-tile furniture

A bed, wardrobe or desk covers several squares, and **which half goes where is
not guessable** — it comes from the tileset's `SpriteGridPos`. Declare pieces
in `C.Pieces` as `{sprite, dx, dy}`:

```lua
bedS = { { "furniture_bedding_01_9", 0, 0 }, { "furniture_bedding_01_8", 0, 1 } },
```

then place with `place(deck, "bedS", ox, oy, "bed")`, which refuses if any
square it needs falls outside the room.

Getting these backwards is what made the bunks look mismatched: every bed had
its foot laid where its head belonged. `tests/test_layout.py` now checks every
declared offset against `SpriteGridPos` and that all halves face the same way.

### Changing a deck's size

`C.RoomSize` (25) is the outer footprint including walls; `C.RoomOffset` (16)
keeps it off the cell edge. If you change either:

- Keep `C.DeckSpacing` comfortably larger than `RoomSize + 2 * ClearMargin`,
  or neighbouring decks come into view.
- `C.Alcove` offsets are relative to the room origin and must stay inside it.
- Furnishing offsets are absolute within the deck and will need revisiting.
- Bump `C.BuildRev`.

### Adding a deck

1. Add an entry to `C.Decks` with a fresh `id`, the next `z` down and the next
   `col` across. `C.TopZ` is the highest z in use.
2. Add a `furnish.<id>` function.
3. Bump `C.BuildRev`.

z 0 is the ground, so six decks is the limit of a strictly descending stack.
To go further, either start higher (`z` up to 31 — the engine's ceiling, per
`IsoCell.getMaxHeight()`) or let decks share a z and separate them by `col`
alone, which the layout already tolerates.

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
| `C.SonicBox`, `C.SonicCount` | where the case sits in the console room and how many are in it |

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
stack trace each time. That is constraint 4 applied literally: a wrong method name in a loop
this size is hundreds of stack dumps and a frozen game, and this loop is the
largest per-square pass in the mod after deck construction.

**Nothing is ever re-locked.** A lock the field has opened stays open once the
screwdriver is put down. Reverting would mean remembering every object ever
touched and re-locking doors behind a player who walked through them, which is
worse play and much more state. The rule is that the field decides which locks
give, not which doors stay shut afterwards.

A permanently-locked window (`isPermaLocked`) is left alone deliberately: that
is a map saying this window never opens, not a lock.

### The ship is lived in

**A rebuild must never touch what is already in a container.** Once a shelf
exists it is the player's: what they eat stays eaten, what they take stays
taken, and what they put back stays where they put it.

`U.addContainer` returns a second value saying whether it created the
container just now, and `line()` stocks only when it did. Without that gate a
rebuild does not merely refill a shelf — it stocks it *again*, piling a second
helping on top of the first, so loot multiplies with every revision bump.

The corollary is that **changing a loot list does not change any deck that
already exists.** New containers get the new list; old ones keep what they
have. That is correct for play and inconvenient for design, hence the two
escape hatches below.

### Rebuilding while designing

```lua
TARDIS_Rebuild()      -- from the debug console, standing on the deck
```

Tears the deck you are standing on back to bare ground — containers and
contents included — and regenerates it fully stocked. Only the current deck
can be rebuilt, because only its chunks are loaded.

`C.DevRestock = true` does the same thing globally for every rebuild. It is
off by default and should stay off outside design work.

For a wholesale change, a **fresh world** is still the cleanest way to see the
interior as a new player would.

### Build revisions and migrations

`C.BuildRev` is stamped into each deck as it is built. Raising it makes every
deck rebuild the next time a player stands on it — lazily, on arrival, so a
deck nobody visits stays as it was. Rebuilds repair structure (floors, walls,
lighting, the void margin) and preserve tagged furniture, container contents,
dropped items and crops.

Bump it when **generation** changes. It will not restock anything.

**Moving a deck is not a rebuild — it is a migration.** Its old geometry stays
where it was and its container contents do not travel. `purgeLegacyStack()`
is the worked example: it clears the levels left under the console room when
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

The police box and console are **world models** (`.x` meshes plus textures),
not tile sprites — a custom tile would need a TileZed-packed texture pack.
Everything is generated by script; no binary asset is hand-authored.

```sh
python tools/gen_texture.py TARDIS/42     # police box texture + inventory icon
python tools/gen_model.py   TARDIS/42     # police box mesh
python tools/gen_console.py TARDIS/42     # console texture + mesh
python tools/gen_sonic.py   TARDIS/42     # sonic screwdriver inventory icon
```

An item's `Icon = X` resolves to `media/textures/Item_X.png`, and a missing
one shows as a blank square in the inventory and reports nothing anywhere.
`tests/test_assets.py` checks every icon a mod item names against the files
on disk, along with every `TARDIS.*` id the Lua refers to.

Check the result **without launching the game**:

```sh
python tools/preview_model.py TARDIS/42/media/models_X/TARDIS_PoliceBox.x \
       TARDIS/42/media/textures/TARDIS_PoliceBox.png /tmp/preview.png
```

`tools/preview_model.py` is a small software renderer — mesh parser,
z-buffer, per-pixel texture sampling — that draws the model at roughly the
game's camera angle. Use it. It caught the geometry and signage before the
game was ever involved.

Two things to know about the meshes:

- **Y is up.** Project Zomboid world models are Y-up; authoring Z-up lays the
  box on its side. `MeshBuilder(up_axis=...)` handles the swap, and
  `preview_model.py` swaps back so previews stay upright.
- **1 unit is 1 tile**, with `scale = 1.0` in `media/scripts/tardis.txt`.
  That is the number to change if the shell reads too large or small.

---

## The loop

```sh
python tools/luacheck.py TARDIS/42/media/lua   # parses every file
python tests/test_assets.py                    # sprite and item ids resolve
python tests/test_stock.py                     # loot spreads across its list
python tests/test_layout.py                    # floor plan + furniture offsets
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
and inspects every deck in turn: floors, walls, landing, container stocking,
nothing overhead, void margin, water, crops, the repulsion field, exit and
bookmarks.

**Lua version note.** The game runs Kahlua, a Lua 5.1 dialect where `unpack`
is a global. `tools/luacheck.py` and `tests/test_stock.py` use Lua 5.5, which
moved it to `table.unpack`; the test harness stubs it back. Mod code should
use the 5.1 spelling.

---

## Where things live

| File | Holds |
|------|-------|
| `TARDIS_Config.lua` | All layout constants, sprites, loot lists, crops. Start here. |
| `TARDIS_Util.lua` | Safe engine wrappers, state, coordinates, clearing, stocking |
| `TARDIS_Build.lua` | Deck construction and furnishing |
| `TARDIS_Core.lua` | Shell, doors, arrival, water, repulsion field |
| `TARDIS_Travel.lua` | Bookmarks, landing search, flight console, map markers |
| `TARDIS_Sonic.lua` | The sonic screwdriver: the lock-opening sweep |
| `TARDIS_Menu.lua` | Right-click menus |
| `TARDIS_SelfTest.lua` | In-game step machine |

Almost every design change is a change to `TARDIS_Config.lua` plus one
`furnish` function.

---

## Rules of thumb

- Verify an engine method with `tools/pzapi.py` before calling it.
- Wrap anything repeated per-square in `U.batch`.
- Tag every object you place, or a rebuild eats it.
- Never build where no player is standing.
- Never put a deck above another deck.
- Bump `C.BuildRev` when generation changes; write a migration when geometry
  *moves*.
- Run the three static checks before deploying — they are seconds, and a
  game round-trip is minutes.
