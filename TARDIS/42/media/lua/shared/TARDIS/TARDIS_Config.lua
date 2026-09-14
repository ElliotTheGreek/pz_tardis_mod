--[[ TARDIS -- shared configuration.

    Everything the mod hard-codes about the world lives here: where the
    interior is parked, how a deck is laid out, which sprites dress it and
    what gets stocked into the containers.

    Sprite names come from media/newtiledefinitions.tiles.txt and item ids
    from media/scripts/generated/items/, both for build 42.20.
]]

TARDIS = TARDIS or {}

local C = {}
TARDIS.Config = C

C.Version   = "1.9.3"
C.StateKey  = "TARDIS_State_v1"
C.ModPrefix = "[TARDIS]"

-- Bumped whenever a deck needs rebuilding to pick up changes to the way decks
-- are generated. Decks built at an older revision are quietly brought up to
-- date the next time the player stands on them; the rebuild preserves
-- furniture, stored items and crops.
C.BuildRev = 15

-- Radius, in tiles, of the field that holds the dead back from the doors.
C.FieldRadius = 10

-- Flip to true for verbose build logging in console.txt.
C.Debug = false

-- Design-time only. Normally a rebuild leaves every container exactly as the
-- player left it -- a ship in play is meant to be lived in, and what gets
-- eaten stays eaten. With this on, a rebuild restocks as well, which is what
-- you want while iterating on loot lists and what you never want in a world
-- somebody is playing. TARDIS_Rebuild() turns it on for one deck instead.
C.DevRestock = false

---------------------------------------------------------------------------
-- Where the interior lives
---------------------------------------------------------------------------
-- Build 42 cells are 256 squares and vanilla ships cells out to x=77. The
-- Fifth-Wheel RV interior squats on cell 85,40. Cell 92,40 is clear of both,
-- and its y stays under 12000 so it also falls outside the unbounded
-- (x>22500 and y>12000) exit-menu test Project RV Interior applies.
C.InteriorCell = { x = 92, y = 40 }

-- Offset of the deck footprint inside that cell, so nothing touches a cell
-- edge; chunk seams make edge squares awkward to generate reliably.
C.RoomOffset = 16
C.RoomSize   = 25          -- outer footprint, walls included

-- Decks descend a z level at a time, but they are also stepped sideways so
-- that no deck ever sits directly above another.
--
-- This is the whole reason the interior is readable. Project Zomboid draws
-- every z level above the player and only hides the ones overhead when it
-- believes you are inside a building -- and "building" means room metadata
-- baked into a map lotheader, which runtime-generated squares cannot have.
-- Stacking the decks therefore left the top deck drawn over all the rest.
-- Nothing overhead means nothing to hide, so the renderer needs no
-- convincing. The descent through z is real; only the vertical alignment is
-- given up, and no camera angle can show that.
C.DeckSpacing = 80

-- How far beyond the footprint to strip the procedural wilderness the engine
-- grows in unmapped cells. Everything in this ring is removed down to bare
-- nothing, which renders as black void around the ship.
C.ClearMargin = 24

-- Where a player is put down when they arrive on a deck. Decks are joined
-- through the right-click menu, so no stairwell or vestibule is needed and
-- the hall is left open.
--
-- The square and its immediate neighbours are kept clear of furniture, so
-- arriving never drops anyone inside a bookcase.
C.Landing = { x = 12, y = 19, clearance = 1 }

--- True for the landing square and the ring of squares around it.
function C.isLanding(ox, oy)
    return math.abs(ox - C.Landing.x) <= C.Landing.clearance
       and math.abs(oy - C.Landing.y) <= C.Landing.clearance
end

---------------------------------------------------------------------------
-- Decks, top to bottom
---------------------------------------------------------------------------
-- z 5 is the arrival deck and each deck below sits one level down.
C.TopZ = 5

-- col is the sideways step; z is the storey. Both descend together, so the
-- bottom deck sits on the ground at z 0 and the console room is five storeys
-- up, each one its own island.
C.Decks = {
    { id = "console", z = 5, col = 0, name = "Console Room",
      floor = "floors_interior_tilesandwood_01_24" },
    { id = "housing", z = 4, col = 1, name = "Habitation Deck",
      floor = "floors_interior_carpet_01_0" },
    { id = "storage", z = 3, col = 2, name = "Stores Deck",
      floor = "floors_interior_tilesandwood_01_20" },
    { id = "library", z = 2, col = 3, name = "Library Deck",
      floor = "floors_interior_tilesandwood_01_13" },
    { id = "galley",  z = 1, col = 4, name = "Galley Deck",
      floor = "floors_interior_tilesandwood_01_5" },
    { id = "growing", z = 0, col = 5, name = "Hydroponics Deck",
      floor = "floors_exterior_natural_01_0" },
}

-- Positions are resolved in TARDIS_Util, which knows the engine cell size.

---------------------------------------------------------------------------
-- Room shape
---------------------------------------------------------------------------
-- Project Zomboid has no diagonal wall sprites -- walls only ever sit on the
-- north or west edge of a square -- so a smooth hexagon or circle is not
-- available. What is available is a stepped chamfer: cut the corners off the
-- square footprint and let the wall follow the steps. At this size and at the
-- game's camera angle that reads clearly as an octagon, which is the shape
-- the console room wants.
--
-- Shapes: "rect", "octagon", "hexagon". Walls are derived from whichever
-- squares the shape includes, so a new shape needs no other changes.
C.Shape = "octagon"

-- How deep to cut each corner, in squares. Bigger is rounder; past about a
-- third of RoomSize the room stops being usefully square anywhere.
C.Chamfer = 7

--- True when an offset is inside the deck floor plan.
function C.inShape(ox, oy, shape, size, chamfer)
    shape = shape or C.Shape
    size = size or C.RoomSize
    chamfer = chamfer or C.Chamfer
    if ox < 0 or oy < 0 or ox > size or oy > size then return false end

    if shape == "rect" then
        return true
    elseif shape == "octagon" then
        -- cut a right triangle off each corner
        return (ox + oy) >= chamfer
           and (ox + (size - oy)) >= chamfer
           and ((size - ox) + oy) >= chamfer
           and ((size - ox) + (size - oy)) >= chamfer
    elseif shape == "hexagon" then
        -- points east and west, flat north and south
        local half = size / 2
        local taper = math.abs(oy - half) * (chamfer / half)
        return ox >= taper and ox <= size - taper
    end
    return true
end

---------------------------------------------------------------------------
-- Multi-tile furniture
---------------------------------------------------------------------------
-- A bed, wardrobe or desk covers more than one square, and which half goes
-- where is not guessable: it comes from the tileset's SpriteGridPos property,
-- given here as {sprite, dx, dy}. Getting this backwards is what made the
-- bunks look mismatched -- the foot of each bed was laid at its head.
-- tests/test_layout.py checks every offset here against the game data.
C.Pieces = {
    bedS      = { { "furniture_bedding_01_9",  0, 0 }, { "furniture_bedding_01_8",  0, 1 } },
    bedE      = { { "furniture_bedding_01_10", 0, 0 }, { "furniture_bedding_01_11", 1, 0 } },
    bedFancyS = { { "furniture_bedding_01_1",  0, 0 }, { "furniture_bedding_01_0",  0, 1 } },
    bunkS     = { { "furniture_bedding_01_85", 0, 0 }, { "furniture_bedding_01_84", 0, 1 } },
    wardrobeS = { { "furniture_storage_01_2",  0, 0 }, { "furniture_storage_01_3",  1, 0 } },
    wardrobeE = { { "furniture_storage_01_1",  0, 0 }, { "furniture_storage_01_0",  0, 1 } },
    deskS     = { { "furniture_tables_high_01_26", 0, 0 }, { "furniture_tables_high_01_27", 1, 0 } },
    deskE     = { { "furniture_tables_high_01_25", 0, 0 }, { "furniture_tables_high_01_24", 0, 1 } },
}

---------------------------------------------------------------------------
-- Sprites
---------------------------------------------------------------------------
C.Sprites = {
    -- walls: index 0 is the west face, 1 the north face, 2 the corner post
    wallW   = "walls_interior_house_01_0",
    wallN   = "walls_interior_house_01_1",
    wallC   = "walls_interior_house_01_2",

    -- the player-built wooden staircase, the set the carpentry menu uses
    stairW  = { "carpentry_02_88", "carpentry_02_89", "carpentry_02_90" },
    stairN  = { "carpentry_02_96", "carpentry_02_97", "carpentry_02_98" },
    pillarW = "carpentry_02_94",
    pillarN = "carpentry_02_95",

    lamp    = { S = "lighting_indoor_01_32", E = "lighting_indoor_01_8",
                W = "lighting_indoor_01_40", N = "lighting_indoor_01_48" },

    -- Two different things, and the difference matters.
    --
    -- `sink` is a pedestal sink: a whole fixture that stands on the floor,
    -- which is what a wet block wants. `sinkBasin` is a counter basin -- 35x20
    -- of art drawn at counter height with nothing underneath it -- which is
    -- what a kitchen wants, on a counter square.
    --
    -- The mod used the basin for both, standing on bare floor, and a basin
    -- with no counter under it hangs over the square behind and reads as a
    -- sink sunk into the floor. Rendering both out of Tiles2x.pack against a
    -- floor tile is what settled it; see U.addObject.
    sink      = { N = "fixtures_sinks_01_28", E = "fixtures_sinks_01_13",
                  S = "fixtures_sinks_01_12", W = "fixtures_sinks_01_29" },
    sinkBasin = { N = "fixtures_sinks_01_0",  E = "fixtures_sinks_01_1",
                  S = "fixtures_sinks_01_2",  W = "fixtures_sinks_01_3" },
    toilet  = { S = "fixtures_bathroom_01_0", E = "fixtures_bathroom_01_1",
                W = "fixtures_bathroom_01_2", N = "fixtures_bathroom_01_3" },
    shower  = { N = "fixtures_bathroom_01_22", W = "fixtures_bathroom_01_23" },

    -- console-room dressing, from the sets the show actually used: a chair,
    -- a scanner, a ship's radio, a clock, chests and shelves round the walls
    chair    = { E = "furniture_seating_indoor_01_8", S = "furniture_seating_indoor_01_9",
                 W = "furniture_seating_indoor_01_10", N = "furniture_seating_indoor_01_11" },
    scanner  = { E = "appliances_television_01_8", S = "appliances_television_01_9",
                 W = "appliances_television_01_10", N = "appliances_television_01_11" },
    radio    = { S = "appliances_radio_01_8", E = "appliances_radio_01_9",
                 N = "appliances_radio_01_10", W = "appliances_radio_01_11" },
    clock    = { E = "walls_decoration_01_104", S = "walls_decoration_01_105",
                 N = "walls_decoration_01_106", W = "walls_decoration_01_107" },
    chest    = { S = "furniture_storage_02_28", E = "furniture_storage_02_29",
                 N = "furniture_storage_02_30", W = "furniture_storage_02_31" },
    rug      = "floors_rugs_01_16",
    microwave = { S = "appliances_cooking_01_25", E = "appliances_cooking_01_24",
                  W = "appliances_cooking_01_26", N = "appliances_cooking_01_27" },

    metalShelf = { S = "furniture_shelving_01_28", E = "furniture_shelving_01_29",
                   W = "furniture_shelving_01_30", N = "furniture_shelving_01_31" },
    bookShelf  = { S = "furniture_shelving_01_1", E = "furniture_shelving_01_2",
                   W = "furniture_shelving_01_3", N = "furniture_shelving_01_4" },
    magShelf   = { S = "location_shop_generic_01_24", E = "location_shop_generic_01_26",
                   W = "location_shop_generic_01_104", N = "location_shop_generic_01_106" },
    locker     = { S = "furniture_storage_02_8", E = "furniture_storage_02_9",
                   N = "furniture_storage_02_10", W = "furniture_storage_02_11" },
    crate      = "location_military_generic_01_0",
    counter    = { N = "carpentry_02_17", E = "carpentry_02_19" },
    fridge     = { S = "appliances_refrigeration_01_0", E = "appliances_refrigeration_01_1",
                   N = "appliances_refrigeration_01_2", W = "appliances_refrigeration_01_3" },
    oven       = { E = "appliances_cooking_01_0", S = "appliances_cooking_01_1",
                   W = "appliances_cooking_01_2", N = "appliances_cooking_01_3" },
}

---------------------------------------------------------------------------
-- Items placed in the interior
---------------------------------------------------------------------------
-- The exterior shell and the control console are world models, defined in
-- media/scripts/tardis.txt.
C.ExteriorItem = "TARDIS.TARDISPoliceBox"

-- The console is a container item, so the model in the middle of the control
-- room opens like a crate: 500 units of hold, declared in tardis.txt and
-- stocked once, when it is first put down, from C.ConsoleKit below.
--
-- It is a different id from the console every world before revision 11 had.
-- The old one was a plain item, and an item saved as one class and reloaded
-- as another reads a container section that was never written to the save.
-- Build lifts the legacy console out and drops this one in its place instead;
-- the old id stays declared so an existing world can still resolve it long
-- enough to be swapped.
C.ConsoleItem       = "TARDIS.TARDISConsoleUnit"
C.LegacyConsoleItem = "TARDIS.TARDISConsole"

-- The hold, which is the console plus a ring of crates around it.
--
-- **A container cannot be made bigger than the engine allows**, and the two
-- ceilings are different. `ItemContainer.getCapacity()` returns
-- min(capacity, 50) when the container belongs to an item and
-- min(capacity, 100) when it belongs to a world object, and
-- `InventoryContainer.getCapacity()` clamps an item's again to 50 minus the
-- item's own weight. So the console itself can never carry more than 49, and
-- the way to a hold worth the name is more containers rather than a bigger
-- one: six crates at 100 apiece, on the rug around the console.
--
-- The spots leave the four squares orthogonally next to the console clear, so
-- the console is still walkable up to from any side.
C.ConsoleHold = {
    capacity = 100,
    name     = "TARDIS Hold",
    spots    = { { 11, 11 }, { 13, 11 }, { 11, 13 }, { 13, 13 },
                 { 10, 12 }, { 14, 12 } },
}

---------------------------------------------------------------------------
-- The sonic screwdriver
---------------------------------------------------------------------------
-- Carrying one opens locks. TARDIS_Sonic.lua sweeps the squares around
-- whoever is holding it and unlocks every door, gate, window and vehicle it
-- finds; it has no other use and needs no action from the player.
--
-- Two names for one item: the engine's inventory search compares the bare
-- type, while anything that spawns or places the item wants the full id.
C.SonicItem = "TARDIS.TARDISSonicScrewdriver"
C.SonicType = "TARDISSonicScrewdriver"

-- How far the field reaches, in tiles, on the carrier's own level. Every
-- square inside it is examined on each sweep, so this is the number that
-- decides what a sweep costs; 15 is a good-sized house in every direction.
C.SonicRadius = 15

-- What the field does to a vehicle once its doors are open. Unlocking alone
-- gets you into a car you still cannot drive, so the field also bypasses the
-- ignition and puts a charge in the battery.
--
-- Hotwiring is what the game itself gates "Start Engine" on. The battery is
-- separate and worth its own switch: most abandoned cars are flat, and a
-- hotwired car with a dead battery still does nothing at all.
--
-- Neither touches fuel. An empty tank stays empty -- that is not a lock and
-- not an ignition, and a car that drives forever on nothing is a different
-- mod.
C.SonicHotwire   = true
C.SonicJumpStart = true

-- Sweeps run when the carrier steps onto a new square, and otherwise no more
-- often than this many ticks apart, so standing still is nearly free.
C.SonicInterval = 120

-- Where the case of screwdrivers sits in the console room, and how many are
-- in it. Just east of the console, off the rug and in plain sight of anyone
-- walking up from the landing.
C.SonicBox   = { x = 15, y = 12 }
C.SonicCount = 3

C.Loot = {}

C.Loot.tools = {
    "Base.Hammer", "Base.Saw", "Base.Screwdriver", "Base.Wrench",
    "Base.PipeWrench", "Base.Crowbar", "Base.Axe", "Base.HandAxe",
    "Base.Shovel", "Base.MasonsTrowel", "Base.Sledgehammer", "Base.Scissors",
    "Base.DuctTape", "Base.Nails", "Base.Screws", "Base.Rope", "Base.Twine",
    "Base.Needle", "Base.Thread", "Base.Lighter", "Base.Torch", "Base.Battery",
    "Base.Extinguisher", "Base.Sheet",
}

C.Loot.weapons = {
    "Base.Axe", "Base.BaseballBat", "Base.Machete", "Base.Katana",
    "Base.Crowbar", "Base.Shotgun", "Base.Pistol", "Base.VarmintRifle",
    "Base.HuntingRifle",
}

C.Loot.ammo = {
    "Base.ShotgunShells", "Base.Bullets9mm", "Base.Bullets9mmBox",
    "Base.Bullets38", "Base.Bullets44",
}

C.Loot.medical = {
    "Base.Bandage", "Base.Antibiotics", "Base.Pills", "Base.Disinfectant",
    "Base.FirstAidKit", "Base.PillsVitamins", "Base.PillsBeta",
    "Base.PillsSleepingTablets", "Base.AlcoholBandage",
}

C.Loot.food = {
    "Base.Bread", "Base.Cheese", "Base.Butter", "Base.Flour2", "Base.Sugar",
    "Base.Rice", "Base.Pasta", "Base.Salt", "Base.Potato", "Base.Carrots",
    "Base.Onion", "Base.Tomato", "Base.Egg", "Base.Milk", "Base.Steak",
    "Base.Chicken",
}

C.Loot.cookware = {
    "Base.Pan", "Base.Pot", "Base.Saucepan", "Base.Bowl", "Base.BreadKnife",
    "Base.ButterKnife", "Base.CheeseGrater",
}

C.Loot.seeds = {
    "Base.CarrotSeed", "Base.PotatoSeed", "Base.CabbageSeed",
    "Base.TomatoSeed", "Base.BroccoliSeed", "Base.CornSeed",
    "Base.OnionSeed", "Base.BasilSeed", "Base.ChivesSeed",
}

C.Loot.media = { "Base.VHS_Home", "Base.VHS_Retail" }

---------------------------------------------------------------------------
-- The armoury
---------------------------------------------------------------------------
-- Every firearm the build ships, every magazine, every calibre in every
-- packaging, the optics to go on them, and somewhere to hang a pistol.
--
-- The lists are split by what a crate is *for* rather than by what an item
-- is, because a container has a weight capacity and AddItems drops the
-- overflow in silence once it is reached. A military crate holds 50, a
-- locker 40, a set of metal shelves 30, and the numbers beside each list
-- below are what one copy of it weighs, straight out of
-- media/scripts/generated/items. Anything heavier than its crate never lands
-- whole, which is how an armoury meant to hold every calibre used to end up
-- short of 5.56 and .45.
--
-- Cartons are the reason for most of the splitting: one carton of .44 weighs
-- twelve, which is a quarter of a crate on its own.

C.Loot.handguns = {                                             -- 9.7
    "Base.Pistol", "Base.Pistol2", "Base.Pistol3",
    "Base.Revolver", "Base.Revolver_Long", "Base.Revolver_Short",
}

-- Not a firearm, but it belongs in the same crate: what you reach for when
-- the shooting is a bad idea.
C.Loot.katanas = { "Base.Katana" }                              -- 2.0

C.Loot.sidearms = {}                                            -- 11.7

C.Loot.longarms = {                                             -- 42.0
    "Base.Shotgun", "Base.ShotgunSawnoff",
    "Base.DoubleBarrelShotgun", "Base.DoubleBarrelShotgunSawnoff",
    "Base.VarmintRifle", "Base.HuntingRifle",
    "Base.AssaultRifle", "Base.AssaultRifle2",
    "Base.MSR7T_Rifle", "Base.JS14_Rifle", "Base.L94_Rifle",
}

-- Every gun in the build, for the wall racks. The crates take the two halves
-- above separately; 42 of longarms is already most of a crate.
C.Loot.firearms = {}

C.Loot.gunMags = {                                              -- 1.2
    "Base.9mmClip", "Base.44Clip", "Base.45Clip",
    "Base.556Clip", "Base.M14Clip", "Base.JS14_Clip",
}

-- Loose rounds and boxes: light enough that a shelf or a locker can carry a
-- spread of them.
C.Loot.pistolAmmo = {                                           -- 4.91
    "Base.Bullets9mm", "Base.Bullets9mmBox",
    "Base.Bullets38", "Base.Bullets38Box",
    "Base.Bullets44", "Base.Bullets44Box",
    "Base.Bullets45", "Base.Bullets45Box",
    "Base.Bullets357", "Base.Bullets357Box",
}

C.Loot.rifleAmmo = {                                            -- 3.38
    "Base.308Bullets", "Base.308Box",
    "Base.3030Bullets", "Base.3030Box",
    "Base.556Bullets", "Base.556Box",
    "Base.ShotgunShells", "Base.ShotgunShellsBox",
}

-- The bulk packaging, one crate each. A carton is twelve boxes.
C.Loot.pistolCartons = {                                        -- 48.0
    "Base.Bullets9mmCarton", "Base.Bullets38Carton",
    "Base.Bullets44Carton", "Base.Bullets45Carton",
    "Base.Bullets357Carton",
}

C.Loot.rifleCartons = {                                         -- 32.0
    "Base.308Carton", "Base.3030Carton", "Base.556Carton",
    "Base.ShotgunShellsCarton",
}

-- 5.56 on its own, because it is what the M16 (Base.AssaultRifle) and the
-- JS-14 both feed on and there is never enough of it. Two crates of this,
-- eight copies each: eight cartons is nearly two thousand rounds per crate,
-- and at 5.74 a copy the crate fills to 46 of its 50 without dropping any.
C.Loot.ammo556 = {                                              -- 5.74
    "Base.556Carton", "Base.556Box", "Base.556Bullets", "Base.556Clip",
}

-- What the shelves and lockers get: everything except the cartons, which are
-- too heavy to spread across furniture this size.
C.Loot.gunAmmo = {}

C.Loot.holsters = {                                             -- 2.2
    "Base.HolsterSimple", "Base.HolsterSimple_Black",
    "Base.HolsterSimple_Brown", "Base.HolsterSimple_Green",
    "Base.HolsterDouble", "Base.HolsterShoulder", "Base.HolsterAnkle",
    "Base.Holster_DuctTape", "Base.Holster_Hide",
}

C.Loot.attachments = {                                          -- 2.8
    "Base.x2Scope", "Base.x4Scope", "Base.x8Scope", "Base.RedDot",
    "Base.Laser", "Base.RecoilPad", "Base.ChokeTubeFull",
    "Base.ChokeTubeImproved",
}

-- The joined lists, built rather than written out twice so an id only ever
-- appears in one place.
local function appendTo(dest, ...)
    for _, list in ipairs({ ... }) do
        for _, id in ipairs(list) do table.insert(dest, id) end
    end
    return dest
end

appendTo(C.Loot.sidearms, C.Loot.handguns, C.Loot.katanas)
appendTo(C.Loot.firearms, C.Loot.handguns, C.Loot.longarms)
appendTo(C.Loot.gunAmmo, C.Loot.pistolAmmo, C.Loot.rifleAmmo)

---------------------------------------------------------------------------
-- What the console holds
---------------------------------------------------------------------------
-- A packing list rather than a loot list: explicit counts, put in once when
-- the console is first placed and never topped up again. This is the ship's
-- own store -- the thing you open before stepping out somewhere bad -- so it
-- is deliberately generous and deliberately finite.
--
-- The hold takes 500 weight units. This list is 679 items and 395 of them,
-- which leaves room for the player to put their own things in. Anything past
-- the capacity would be dropped in silence, so if you add to this, take
-- something out: U.stockKit reads the hold back afterwards and logs whatever
-- did not fit.
--
-- Weights, for arithmetic: a canned good is 0.8, a carton of 5.56 is 5, of
-- 9mm 8, of .44 12; bandages and pills are 0.1 to 0.2; rice and pasta are 2.
C.ConsoleKit = {
    -- to hand
    { "Base.Katana", 3 },
    { C.SonicItem, 3 },

    -- sidearms and what feeds them: the M9 for capacity, the Magnum for
    -- everything the M9 does not stop
    { "Base.Pistol", 2 },
    { "Base.Pistol3", 2 },
    { "Base.9mmClip", 4 },
    { "Base.44Clip", 4 },
    { "Base.Bullets9mmCarton", 3 },
    { "Base.Bullets44Carton", 2 },
    { "Base.HolsterSimple", 2 },
    { "Base.HolsterDouble", 2 },
    { "Base.HolsterShoulder", 2 },

    -- the M16, with six cartons and ten boxes of 5.56 behind it: a carton is
    -- twelve boxes of twenty, so this is a little under sixteen hundred
    -- rounds
    { "Base.AssaultRifle", 2 },
    { "Base.556Clip", 6 },
    { "Base.556Carton", 6 },
    { "Base.556Box", 10 },

    -- an infirmary in a drawer
    { "Base.Bandage", 100 },
    { "Base.AlcoholBandage", 50 },
    { "Base.Antibiotics", 50 },
    { "Base.Pills", 50 },
    { "Base.Disinfectant", 20 },
    { "Base.AlcoholWipes", 20 },
    { "Base.SutureNeedle", 20 },
    { "Base.SutureNeedleHolder", 2 },
    { "Base.Tweezers", 2 },
    { "Base.Splint", 5 },
    { "Base.CottonBalls", 10 },
    { "Base.FirstAidKit", 4 },
    { "Base.PillsVitamins", 20 },
    { "Base.PillsBeta", 10 },
    { "Base.PillsSleepingTablets", 10 },

    -- tins, and the one thing that makes tins food
    { "Base.TinOpener", 1 },
    { "Base.CannedBolognese", 15 },
    { "Base.CannedChili", 15 },
    { "Base.CannedCornedBeef", 15 },
    { "Base.CannedCorn", 15 },
    { "Base.CannedCarrots", 15 },
    { "Base.CannedPeaches", 15 },
    { "Base.CannedFruitCocktail", 15 },
    { "Base.CannedMushroomSoup", 15 },
    { "Base.TinnedBeans", 15 },
    { "Base.TinnedSoup", 15 },
    { "Base.CannedPotato2", 15 },
    { "Base.CannedPeas", 15 },
    { "Base.CannedTomato", 15 },
    { "Base.CannedMilk", 15 },

    -- dry stores, which keep as long as the tins do
    { "Base.Rice", 10 },
    { "Base.Pasta", 10 },
    { "Base.Flour2", 5 },
    { "Base.Sugar", 5 },
    { "Base.Salt", 5 },
    { "Base.BeefJerky", 10 },
}

-- Every skill book line in the game; all five volumes of each are shelved.
C.SkillBookLines = {
    "Aiming", "Blacksmith", "Butchering", "Carpentry", "Carving", "Cooking",
    "Electrician", "Farming", "Fishing", "Foraging", "Husbandry", "Masonry",
    "Maintenance", "Mechanic", "Pottery", "Reloading", "Tailoring",
    "Trapping",
}

C.Loot.magazines = {
    "Base.Magazine", "Base.MagazineCrossword", "Base.MagazineWordsearch",
    "Base.Magazine_Art", "Base.Magazine_Business", "Base.Magazine_Car",
    "Base.Magazine_Cinema", "Base.Magazine_Crime", "Base.Magazine_Fashion",
    "Base.Magazine_Firearm", "Base.ComicBook", "Base.Book",
}

C.Loot.linen = { "Base.Sheet", "Base.Pillow" }

---------------------------------------------------------------------------
-- Crops sown on the hydroponics deck
---------------------------------------------------------------------------
C.Crops = {
    "Potatoes", "Carrots", "Cabbages", "Tomato", "Broccoli", "Corn",
    "Radishes",
}

---------------------------------------------------------------------------
-- Travel
---------------------------------------------------------------------------
C.MaxBookmarks        = 40
C.LandingSearchRadius = 24   -- squares to spiral out from a chosen landing site

return C
