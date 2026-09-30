# The interior

How the inside of the ship is made: the art, the tiles, the decks, and how
the game raises them. This file is the working guide to the pipeline; the
design rules the engine imposes are in `DESIGN.md`, and the working habits in
`DEV_GUIDE.md`.

The method is the one the Shuttlecraft mod (`pz_trekship`, `ADIRONDACK.md`)
settled on for the U.S.S. Adirondack, moved across whole: **Gemini paints,
TRELLIS models, the generators do geometry, BuildingEd lays out, and the game
builds from generated data.** It replaced (2.0.0, build revision 16) the
octagonal halls of vanilla furniture that a hand-written `furnish` function
per deck used to put down.

Every tile aboard is the mod's own. The one exception is the soil under the
crop beds (`blends_natural_01_64`), because vanilla recognises diggable soil
by its sprite name and nothing else (`ISShovelGroundCursor.GetDirtGravelSand`).

| Deck | z | Rooms |
|---|---|---|
| Console Room | 5 | the console room (roundel walls, hexagonal console, police box doors, scanner, the hold, the Doctor's corner), an armoury, a galley corner |
| Habitation Deck | 4 | corridor; bedroom, companion's room, bathroom; dormitory, the Wardrobe, guest room |
| Stores Deck | 3 | storeroom, infirmary, workshop |
| Library Deck | 2 | library, observatory, archive |
| Galley Deck | 1 | kitchen, dining room, pantry |
| Gardens | 0 | hydroponic garden (crop beds under grow lamps), stable |

The look is the real ship's sets, squared off: the white roundel walls of the
classic console rooms, walnut panelling and brass from the Victorian and
library rooms, gunmetal service plating, blue and white tiles; the hexagonal
console with its glass time rotor; the police box doors seen from inside.
**Every room is a rectangle and every wall is flat** -- no chamfered corners
-- and every piece of furniture was drawn with square flat edges.

---

## 1. The split

| Piece | Made by | File | Tweaked by |
|---|---|---|---|
| Surface art (walls, floors, the door) | Gemini via FlowDot, vetted | `design/art/interior/*_raw.jpg` | the author: veto and redirect |
| Object concepts | Gemini via FlowDot, vetted | `design/art/interior/objects/*_concept.jpg` | as above |
| Object meshes | fal TRELLIS via FlowDot | `tools/assets/interior/*.glb` | -- regenerate the concept instead |
| Structure tiles | `tools/gen_tardis_tiles.py` | `design/tiles/2x/tardis_interior_01.png` | nobody by hand -- change the generator |
| Furniture tiles | `tools/gen_tardis_furniture.py` | `design/tiles/2x/tardis_interior_02.png` + `.json` | nobody by hand |
| Texture pack, tiledef, seating | `tools/gen_tardis_pack.py` | `TARDIS/42/media/texturepacks/tardis_interior.pack`, `media/tardis_interior.tiles`, `TARDIS/common/media/seating.txt` | -- |
| Decks | `tools/gen_tardis_decks.py` drafts; the author owns after | `design/buildinged/TARDIS_*.tbx` | the author, in BuildingEd |
| What the game builds | `tools/gen_tardis_lua.py` | `TARDIS/42/media/lua/shared/TARDIS/TARDIS_Layout.lua` | nobody -- generated |

**Gemini paints materials; the generators do geometry.** An image model
cannot put a wall edge on the pixel, and a wall that misses its neighbour by
two pixels is a crack down every corridor. So each flat texture is projected
onto the iso face a vanilla tile uses, and every silhouette (wall thickness,
top cap, door opening) is taken from the matching vanilla tile's alpha --
`industry_01` for walls, `fixtures_doors_01` for doors, a vanilla floor for
the diamond.

---

## 2. The loop

After changing art or a deck:

```sh
python tools/gen_tardis_tiles.py        # structure sheet + design/art/interior/room_preview.png
python tools/gen_tardis_furniture.py    # furniture sheet + furniture_sheet.png
python tools/gen_tardis_decks.py        # drafts the .tbx files + design/art/interior/decks/*.png
python tools/gen_tardis_pack.py         # the .pack, the .tiles, seating.txt
python tools/gen_tardis_lua.py          # TARDIS_Layout.lua, from the .tbx files
python tools/install_tilezed.py         # CLOSE TileZed/BuildingEd first
```

then the checks (`DEV_GUIDE.md`, *The loop*). **Look at the pictures before
believing anything**: `room_preview.png` for the walls and floors,
`furniture_sheet.png` for every piece in every facing, `decks/*.png` for each
deck as the game will build it. `python tests/test_layout.py` prints every
deck's plan in text as well.

`gen_tardis_furniture.py name ...` renders only those pieces, into
`furniture_partial*.png`, without touching the sheet -- the way to look at one
new piece. The full run refuses to write a sheet with any piece missing art,
because a piece left out renumbers every piece after it.

**The author's side** (BuildingEd):

1. Open TileZed (`D:\SteamLibrary\steamapps\common\Project Zomboid Modding
   Tools\TileZed\TileZed.exe`), then BuildingEd from it.
2. Open a deck: `design/buildinged/TARDIS_<Deck>.tbx`.
3. The walls are under **walls** (roundel, walnut, service, tiled), the floors
   under **floors**, the roundel door under **doors**, and the furniture in
   the **TARDIS - <area>** groups.
4. Change what you like, save, then run `gen_tardis_lua.py` (and the checks).

**Once the author saves a deck in BuildingEd it is theirs.** The drafting
script writes a `Generator` property into every file it makes and will not
overwrite a file that has lost it (`--force` does). `gen_tardis_lua.py` reads
whatever is in the `.tbx` files, so an edit made in BuildingEd is what gets
built. Keep the `Deck`, `Landing` and (for the gardens) `Beds` properties the
drafts carry: they say which deck a file is, where a player arrives, and
where the crops go.

---

## 3. The structure sheet: `tardis_interior_01`

| Index | Tile |
|---|---|
| 0 1 2 3 4 5 | roundel wall: W, N, NW corner, SE post, W doorway, N doorway |
| 8 .. 13 | walnut panelling, the same six |
| 16 .. 21 | service plating |
| 24 .. 29 | tiled wall |
| 32 .. 37 | floors: console grating, roundel flagstones, parquet, carpet, chequer tile, deck plate |
| 40 41 42 43 | the roundel door: W, N, W open, N open |

Doors are hinged, as vanilla's are: the open leaf stands out from the wall, so
the W door's open tile is drawn on the north-facing plane and the N door's on
the west-facing one (`gen_tardis_tiles.py`).

---

## 4. The objects

Every piece of furniture is one entry in `tools/tardis_objects.py`: its size
in squares, its height, which ways it faces and what the game makes of it
(container type, bed, seat, stove, water, light). From it:

1. **Concept** -- Gemini (`generate-image`, installation 42, model
   `gemini-3-pro-image-preview`), one shared style prompt (`STYLE`), a front
   view on a plain light-grey background. A concept that comes back wrong is
   generated again with the prompt corrected (the fridge first came back as
   two fridges; the console's time rotor ran off the top of the frame).
2. **Mesh** -- fal TRELLIS (`fal-3d-trellis`, installation 39, seed 1963), from
   the concept's public URL; `fal-queue-result` for the mesh once it is done.
3. **Tiles** -- `gen_tardis_furniture.py` fits each mesh into its box, backs it
   onto the wall it faces from, and renders every facing with
   `tools/isorender.py`. Facings are turns of one model, never separate
   drawings.

`tools/tardis_jobs.py` is the ledger: every concept URL, request id and mesh
URL (`design/art/interior/objects/jobs.json`), and `fetch` downloads them. The
raws are vendored: generating again gives a different object.

**Which way is the front.** A TRELLIS mesh faces **+z** with its right along
+x. A concept drawn at an angle makes a mesh that is turned the same way;
`yaw=` in the manifest turns it back. `stretch=True` fits the two floor axes
separately (a single bed drawn as wide as a double still fills its one by
two).

**The console is a 2 x 2 piece at full storey height.** Fitted into 3 x 3 it
filled a square and a third of its footprint -- its height is what binds --
and left an invisible ring round it you could not walk into.

**An image-to-3D mesh can fail quietly.** The first toilet came back as a tall
slatted block: TRELLIS built the concept's back panel and lost the bowl. It
looked like a cabinet in every facing, which only the furniture sheet showed.
The failed pair is kept in `design/art/interior/objects/rejected/`.

**FlowDot's image storage fills up** at about fifty images. Each image is
downloaded into the repo as soon as it is made, a concept is deleted from
FlowDot once its mesh is done, and older images go oldest first (the author's
go-ahead, 2026-09-29).

Pictures on walls (`flat`) need no mesh: the scanner, the police box doors
(one picture cut into two wall sections, `split=`), the roundel light, the
clock (`round=True` cuts it to its circle), a painting and the grow lamps.

---

## 5. The decks

`tools/gen_tardis_decks.py` holds a spec per deck -- rooms as rectangles with
a wall style and a floor, doors on edges, furniture by name, facing and
square -- and checks it before writing anything: furniture off the floor or
across two rooms, two pieces on one square, a door not between two rooms or
opening onto furniture, a picture with no wall behind it, anything on the
landing or the ring round it. Walls come from BuildingEd's rule: a wall on
every edge between two different rooms, or a room and nothing, in the style
of the room on the square it stands on.

Walls only exist on the north and west edges of a square, so anything backed
onto a wall stands against a north or a west one, as vanilla's furniture
does. Tables, chairs, counters and rails turn all four ways.

---

## 6. In the game

`TARDIS_Build.lua` places what `TARDIS_Layout.lua` lists, deck by deck, the
first time a player stands there (`DESIGN.md`, constraint 1):

- **Floors** are laid, or swapped where the layout wants a different one --
  never under a sown plot.
- **Walls, pictures and furniture** are `IsoObject`s wearing our sprites,
  tagged with their piece's name. The range is an `IsoStove`, because the
  engine decides the class from what built the object, not from the sprite.
- **Doors** are `IsoDoor`s added with `AddSpecialObject`: a closed door only
  blocks from the square's special-object list. A door is found again by
  being ours on that edge, never by its sprite -- an open door wears the one
  two along.
- **Containers** get `createContainersFromSpriteProperties` and `setExplored`,
  and are stocked the once, when they are made, by `C.Stock` (by deck, then
  by piece). The armouries are packed crate by crate (`ARMOURY` in
  `TARDIS_Build.lua`), the kit is packed across the hold (the console's four
  squares and six roundel lockers, a hundred apiece), and the sonic case gets
  its three screwdrivers.
- **Water fittings** (sinks, basins, baths, troughs) get a water store of
  their own and are topped up every ten minutes; the ship is not on the
  mains.
- **Lamps** hang at the layout's lamp spots for the deck the player is on,
  and are hung again whenever the engine has dropped one.
- **The gardens** are plowed and sown on every bed square that is not an
  aisle, and the stable gets its livestock once.

A deck is current when its stamp matches both `C.BuildRev` and the layout's
`L.rev`, which changes whenever anything placed changes. A deck built from an
older layout is brought up to date in place: anything we placed that the new
layout does not have is taken away, **with its contents handed back** into the
deck's new containers, or onto the floor round the landing when they are full.

**A deck built by the old generator is refitted once** (`refitLegacy`): every
object on its footprint goes, contents handed back the same way, the old
console item is lifted out and its hold emptied into the new one, and only
what lies on the floor and what grows in the gardens stays. A player loses
nothing; they will find it in the new cupboards, or in a heap by the landing.

---

## 7. What is not done

1. **Nothing of this has been seen in game yet.** The static checks, the
   layout test and the stubbed build (`tests/test_build.py`) all pass; the
   first load is the real test. `DEV_GUIDE.md`, *Current state*, says what to
   look for.
2. The **police box shell and the sonic screwdriver** are the old generated
   models and are unchanged: this was the interior.
3. **Lighting is lampposts**, not fittings with switches: the roundel lights
   and grow lamps are pictures, and the light comes from the layout's spots.
4. **The ship makes its own power** (2.0.1, `B.powerDeck`): generator
   positions registered on each deck's chunks, with no generator behind them.
   `setHaveElectricity`, which this used before, never did anything.
5. **It may rain inside.** A runtime deck has no rooms and no roof, so the
   engine thinks it is outdoors. The Shuttlecraft fixed this with an invisible
   floor one storey up (`U.addRoof`); the TARDIS has not had it yet.
6. **New furniture goes at the end of `tools/tardis_objects.py`.** The sheet
   numbers its tiles in that list's order, and a tile's number is its sprite
   name in every save.
