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

C.Version   = "1.6.0"
C.StateKey  = "TARDIS_State_v1"
C.ModPrefix = "[TARDIS]"

-- Bumped whenever a deck needs rebuilding to pick up changes to the way decks
-- are generated. Decks built at an older revision are quietly brought up to
-- date the next time the player stands on them; the rebuild preserves
-- furniture, stored items and crops.
C.BuildRev = 8

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

    sink    = { N = "fixtures_sinks_01_0",  E = "fixtures_sinks_01_1",
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
C.ConsoleItem  = "TARDIS.TARDISConsole"

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

-- The armoury. Every firearm the build ships, every magazine, every calibre
-- of ammunition in every packaging, and the optics and muzzle fittings to go
-- with them.
C.Loot.firearms = {
    "Base.Pistol", "Base.Pistol2", "Base.Pistol3",
    "Base.Revolver", "Base.Revolver_Long", "Base.Revolver_Short",
    "Base.Shotgun", "Base.ShotgunSawnoff",
    "Base.DoubleBarrelShotgun", "Base.DoubleBarrelShotgunSawnoff",
    "Base.VarmintRifle", "Base.HuntingRifle",
    "Base.AssaultRifle", "Base.AssaultRifle2",
    "Base.MSR7T_Rifle", "Base.JS14_Rifle", "Base.L94_Rifle",
}

C.Loot.gunMags = {
    "Base.9mmClip", "Base.44Clip", "Base.45Clip",
    "Base.556Clip", "Base.M14Clip", "Base.JS14_Clip",
}

C.Loot.gunAmmo = {
    "Base.Bullets9mm", "Base.Bullets9mmBox", "Base.Bullets9mmCarton",
    "Base.Bullets38", "Base.Bullets38Box", "Base.Bullets38Carton",
    "Base.Bullets44", "Base.Bullets44Box", "Base.Bullets44Carton",
    "Base.Bullets45", "Base.Bullets45Box", "Base.Bullets45Carton",
    "Base.Bullets357", "Base.Bullets357Box", "Base.Bullets357Carton",
    "Base.308Bullets", "Base.556Bullets", "Base.3030Bullets",
    "Base.ShotgunShells", "Base.ShotgunShellsBox", "Base.ShotgunShellsCarton",
}

C.Loot.attachments = {
    "Base.x2Scope", "Base.x4Scope", "Base.x8Scope", "Base.RedDot",
    "Base.Laser", "Base.RecoilPad", "Base.ChokeTubeFull",
    "Base.ChokeTubeImproved",
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
