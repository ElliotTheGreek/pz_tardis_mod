--[[ TARDIS -- interior construction.

    The interior is generated at runtime in otherwise empty cells rather than
    shipped as a map, so the mod needs no TileZed-built lots. Decks are built
    lazily: the console room goes up on the first entry, and each deck below
    the first time anyone arrives on it.

    **What a deck is made of is data, not code.** Every wall, door, floor and
    fitting comes from TARDIS_Layout.lua, which tools/gen_tardis_lua.py
    generates from the BuildingEd files in design/buildinged/, and every
    sprite is one of the mod's own tiles (media/texturepacks/tardis_interior
    .pack). To move a bookcase, open BuildingEd, not this file (INTERIOR.md).
    This file places what it is given, stocks it, and keeps it lived in.

    Each deck sits one z level below the last and one step sideways, so no
    deck is ever directly above another. That sidestep is deliberate: the
    engine draws every level above the player and only hides what is overhead
    when it believes you are inside a building, which requires room metadata
    baked into a map file that runtime squares cannot have.
]]

require "TARDIS/TARDIS_Config"
require "TARDIS/TARDIS_Util"
require "TARDIS/TARDIS_Layout"

TARDIS = TARDIS or {}
local C = TARDIS.Config
local U = TARDIS.Util
local L = TARDIS.Layout

local B = {}
TARDIS.Build = B

-- Decks already reported as needing an upgrade, so the message is logged once
-- rather than on every arrival tick while the chunks stream in.
B.upgradeNoted = {}

---------------------------------------------------------------------------
-- Coordinates
---------------------------------------------------------------------------
--- Absolute position of an offset within a deck footprint.
local function at(deck, ox, oy)
    local rx, ry = U.deckOrigin(deck)
    return rx + ox, ry + oy
end

--- A deck's generated layout.
local function layoutOf(deck)
    return deck and L.decks[deck.id]
end
B.layoutOf = layoutOf

--- Where a player arriving on a deck is put down: the layout's landing, in
--- front of the police box doors on the console deck. gen_tardis_decks.py
--- refuses any fitting on it or the ring round it.
function B.arrivalSpot(deck)
    local lay = layoutOf(deck)
    local x, y = at(deck, lay.landing.x, lay.landing.y)
    return x, y, deck.z
end

--- True when a deck offset is inside one of the deck's rooms.
function B.inRoom(deck, ox, oy)
    local lay = layoutOf(deck)
    local row = lay and lay.grid[oy + 1]
    return row ~= nil and (row[ox + 1] or 0) > 0
end

---------------------------------------------------------------------------
-- Clearing the site
---------------------------------------------------------------------------
--- The interior cells are unmapped, so the engine grows procedural
--- wilderness there. Left alone the ship reads as a tower in a forest, so a
--- wide margin around each deck is stripped to nothing at all, which renders
--- as black void.
---
--- Safe to repeat: U.clearSquare keeps anything the mod placed and anything
--- lying on the ground.
local function clearSurroundings(deck)
    local m = C.ClearMargin
    local lay = layoutOf(deck)
    local levels = { deck.z }
    if deck.z ~= 0 then table.insert(levels, 0) end

    local cleared = 0
    for _, z in ipairs(levels) do
        for ox = -m, lay.w + m do
            for oy = -m, lay.h + m do
                local inside = ox >= 0 and ox <= lay.w and oy >= 0 and oy <= lay.h
                if not (inside and z == deck.z) then
                    local x, y = at(deck, ox, oy)
                    local sq = U.square(x, y, z, false)
                    if sq then cleared = cleared + U.clearSquare(sq, true) end
                end
            end
        end
    end
    U.debug("cleared %d objects from the margin around %s", cleared, deck.id)
end

--- Earlier revisions stacked every deck on one footprint. Those levels are
--- still sitting under the console room in any world built that way, so they
--- are cleared out once, the first time the new layout is raised.
local function purgeLegacyStack()
    local s = U.state()
    if s.legacyStackPurged then return end

    local legacy = { col = 0 }
    local m = C.ClearMargin
    local cleared = 0
    for z = 0, C.TopZ - 1 do                 -- z 5 is the console room, keep it
        for ox = -m, C.RoomSize + m do
            for oy = -m, C.RoomSize + m do
                local x, y = at(legacy, ox, oy)
                local sq = U.square(x, y, z, false)
                if sq then cleared = cleared + U.clearSquare(sq, true) end
            end
        end
    end
    s.legacyStackPurged = true
    U.log("cleared %d objects left over from the stacked layout", cleared)
end

---------------------------------------------------------------------------
-- Handing things back
---------------------------------------------------------------------------
-- **What a player keeps is never ours to throw out.** Anything the builder
-- takes away -- an old deck's shelves on the refit, a fitting the layout no
-- longer has -- gives up its contents first, as the live items (moving the
-- item rather than its id keeps a magazine's rounds and a bottle's water).
-- They go into the deck's new containers where there is room and onto the
-- floor round the landing where there is not.

--- Moves every item out of an object's containers into `into`.
local function emptyInto(obj, into)
    local c = U.containerOf(obj)
    if not c then return 0 end
    local items = {}
    U.try("salvage.list", function()
        local list = c:getItems()
        for i = 0, list:size() - 1 do table.insert(items, list:get(i)) end
    end)
    local take = U.batch("salvage.remove")
    for _, it in ipairs(items) do
        if take(function() c:DoRemoveItem(it); return true end) then
            table.insert(into, it)
        end
    end
    return #items
end

local function holdsAnything(obj)
    local c = U.containerOf(obj)
    return c ~= nil and (U.try("isEmpty", function() return c:getItems():size() end) or 0) > 0
end

--- Puts salvaged items into the given containers, by weight, and drops what
--- is left on the floor round the landing. Returns counts.
local function handBack(deck, salvage, containers)
    if #salvage == 0 then return 0, 0 end
    local placed, dropped = 0, 0
    local put = U.batch("salvage.put")
    local ci = 1
    for _, it in ipairs(salvage) do
        local w = U.try("salvage.weight", function() return it:getWeight() end) or 1
        local done = false
        while not done and ci <= #containers do
            local c = containers[ci]
            local cap = U.try("cap", function() return c:getCapacity() end) or 0
            local have = U.try("have", function() return c:getCapacityWeight() end) or cap
            if have + w <= cap then
                done = put(function() c:AddItem(it); return true end) == true
                if done then placed = placed + 1 end
            else
                ci = ci + 1
            end
        end
        if not done then
            local lay = layoutOf(deck)
            local k = dropped % 9
            local x, y = at(deck, lay.landing.x + (k % 3) - 1, lay.landing.y + math.floor(k / 3) - 1)
            local sq = U.square(x, y, deck.z, false)
            if sq and U.try("salvage.drop", function()
                sq:AddWorldInventoryItem(it, 0.2 + ZombRandFloat(0, 0.6), 0.2 + ZombRandFloat(0, 0.6), 0)
                return true
            end) then dropped = dropped + 1 end
        end
    end
    U.log("%s: handed back %d item(s) into the new fittings, %d onto the floor by the landing",
          deck.name, placed, dropped)
    return placed, dropped
end

---------------------------------------------------------------------------
-- The refit: a deck built by the old generator
---------------------------------------------------------------------------
--- Every deck built before revision 16 is the octagonal hall of vanilla
--- furniture the hand-placed builder made. **Moving geometry is a migration,
--- not a rebuild** -- a rebuild keeps everything tagged, which would leave
-- the old shelves standing in the new rooms -- so an old deck is cleared
--- once, whole, before the layout goes down: every object on its footprint
--- goes, its contents into `salvage`, and the old console item (a world
--- item that opened like a crate) is lifted out the same way.
---
--- Kept: anything lying on the floor, and on the gardens every sown plot --
--- the farming system has a record of each, and a plant is not ours to pull.
local function refitLegacy(deck, salvage)
    local cleared = 0
    local farming = SFarmingSystem and SFarmingSystem.instance
    local drop = U.batch("refit.remove")
    for ox = -1, C.RoomSize + 1 do
        for oy = -1, C.RoomSize + 1 do
            local x, y = at(deck, ox, oy)
            local sq = U.square(x, y, deck.z, false)
            if sq then
                local plant = farming and U.try("plantHere", function()
                    return farming:getLuaObjectOnSquare(sq)
                end) ~= nil
                local doomed, consoles = {}, {}
                U.eachObject(sq, function(o)
                    if instanceof(o, "IsoWorldInventoryObject") then
                        local item = U.try("worldItem", function() return o:getItem() end)
                        local id = item and item:getFullType()
                        if id == C.ConsoleItem or id == C.LegacyConsoleItem then
                            table.insert(consoles, { obj = o, item = item })
                        end
                        return
                    end
                    if plant then return end
                    table.insert(doomed, o)
                end)
                for _, cn in ipairs(consoles) do
                    local inv = U.try("consoleInv", function() return cn.item:getInventory() end)
                    if inv then
                        U.try("consoleEmpty", function()
                            local list = inv:getItems()
                            local items = {}
                            for i = 0, list:size() - 1 do table.insert(items, list:get(i)) end
                            for _, it in ipairs(items) do
                                inv:DoRemoveItem(it)
                                table.insert(salvage, it)
                            end
                        end)
                    end
                    drop(function() sq:removeWorldObject(cn.obj) end)
                    U.log("lifted the old console item out; its contents go to the hold")
                end
                for _, o in ipairs(doomed) do
                    emptyInto(o, salvage)
                    if drop(function() sq:RemoveTileObjectErosionNoRecalc(o); return true end) then
                        cleared = cleared + 1
                    end
                end
            end
        end
    end
    U.log("%s: refitted from the old layout -- %d objects cleared, %d items to hand back",
          deck.name, cleared, #salvage)
end

---------------------------------------------------------------------------
-- Placing the layout
---------------------------------------------------------------------------
local function isDoorKind(kind) return kind == "dW" or kind == "dN" end

local function spriteOf(o)
    return U.try("spriteName", function()
        local spr = o:getSprite()
        return spr and spr:getName()
    end)
end

local function tagOf(o)
    return U.try("md", function() return o:getModData().TARDIS end)
end

--- Our door on this square's north (or west) edge, whatever it looks like.
--- **Never find a door by its sprite**: an open door wears the sprite two
--- along, so a builder asking for the closed one misses every door somebody
--- has walked through, and puts a second one in it.
local function ourDoor(sq, north)
    local found = nil
    U.try("ourDoor", function()
        local list = sq:getSpecialObjects()
        for i = 0, list:size() - 1 do
            local o = list:get(i)
            if instanceof(o, "IsoDoor") and tagOf(o) ~= nil and o:getNorth() == north then
                found = o
                return
            end
        end
    end)
    return found
end

--- What a layout entry has standing for it on this square already, if anything.
local function standing(sq, o)
    if isDoorKind(o[4]) then return ourDoor(sq, o[4] == "dN") end
    return U.findSprite(sq, o[3])
end

--- A water store of its own, full: vanilla's addWaterContainer. A sink's
--- sprite properties are not a supply -- `createFluidContainersFromSprite
--- Properties` is empty in build 42 -- and the ship is not on the mains.
local function addWaterStore(obj)
    local f = ComponentType.FluidContainer:CreateComponent()
    f:setCapacity(20)
    f:addFluid(FluidType.Water, 20)
    GameEntityFactory.AddComponent(obj, true, f)
end

--- Makes one layout object. Returns it, or nil.
local function make(sq, o)
    local sprite, kind, piece = o[3], o[4], o[5]
    local use = (piece and L.uses[piece]) or {}
    local tag = piece or (isDoorKind(kind) and "door" or "wall")
    if isDoorKind(kind) then
        local door = U.try("IsoDoor.new", function()
            -- The String constructor: it starts closed, and is never locked
            -- at random (the IsoSprite one rolls against the locked-houses
            -- sandbox option).
            return IsoDoor.new(getCell(), sq, sprite, kind == "dN")
        end)
        if not door then return nil end
        U.try("tag", function() door:getModData().TARDIS = tag end)
        -- A closed door only blocks from the square's special-objects list.
        if U.try("AddSpecialObject", function() sq:AddSpecialObject(door); return true end) then
            return door
        end
        return nil
    end

    local obj
    if use.stove then
        -- A real stove: the engine decides the class from what built the
        -- object, not from the sprite, and a range that is an IsoObject
        -- wearing an oven's picture cooks nothing.
        obj = U.try("IsoStove.new", function() return IsoStove.new(getCell(), sq, getSprite(sprite)) end)
    end
    obj = obj or U.try("IsoObject.new", function() return IsoObject.new(sq, sprite, "") end)
    if not obj then return nil end
    U.try("tag", function() obj:getModData().TARDIS = tag end)
    if kind == "c" or use.stove then
        -- A map-loaded object gets its container for free; a runtime one
        -- does not. Explored, or vanilla rolls its own loot into it.
        U.try("containers", function()
            obj:createContainersFromSpriteProperties()
            local c = U.containerOf(obj)
            if c then c:setExplored(true) end
        end)
    end
    if use.water then U.try("water:" .. tostring(piece), addWaterStore, obj) end
    if not U.try("AddTileObject", function() sq:AddTileObject(obj); return true end) then
        return nil
    end
    return obj
end

--- Floors: laid where there are none, and replaced where the layout wants a
--- different one -- except under a sown plot, which keeps whatever it grows in.
local function layFloors(deck, lay)
    local laid = 0
    local farming = SFarmingSystem and SFarmingSystem.instance
    local swap = U.batch("floor.swap")
    for _, f in ipairs(lay.floors) do
        local x, y = at(deck, f[1], f[2])
        local sq = U.square(x, y, deck.z, true)
        if sq then
            local floor = U.try("getFloor", function() return sq:getFloor() end)
            local name = floor and spriteOf(floor)
            if name ~= f[3] then
                local plant = floor and farming and U.try("plantHere", function()
                    return farming:getLuaObjectOnSquare(sq)
                end) ~= nil
                if not plant then
                    if floor then swap(function() sq:RemoveTileObjectErosionNoRecalc(floor) end) end
                    if U.try("addFloor", function() sq:addFloor(f[3]); return true end) then
                        laid = laid + 1
                    end
                end
            end
        end
    end
    return laid
end

--- Takes away what the layout no longer puts on a square: a fitting we
--- placed that is not in it any more. Its contents go to `salvage`.
local function stripStale(deck, lay, salvage)
    local want = {}
    for _, o in ipairs(lay.objects) do
        local key = o[1] .. "," .. o[2]
        want[key] = want[key] or {}
        if isDoorKind(o[4]) then
            want[key][o[4]] = true
        else
            want[key][o[3]] = true
        end
    end
    local removed = 0
    local drop = U.batch("stale.remove")
    for ox = -1, lay.w + 1 do
        for oy = -1, lay.h + 1 do
            local x, y = at(deck, ox, oy)
            local sq = U.square(x, y, deck.z, false)
            if sq then
                local here = want[ox .. "," .. oy] or {}
                local doomed = {}
                U.eachObject(sq, function(o)
                    if instanceof(o, "IsoWorldInventoryObject") then return end
                    if tagOf(o) == nil then return end
                    if instanceof(o, "IsoDoor") then
                        local north = U.try("north", function() return o:getNorth() end) == true
                        if here[north and "dN" or "dW"] then return end
                    elseif here[spriteOf(o)] then
                        return
                    end
                    table.insert(doomed, o)
                end)
                for _, o in ipairs(doomed) do
                    emptyInto(o, salvage)
                    if drop(function() sq:RemoveTileObjectErosionNoRecalc(o); return true end) then
                        removed = removed + 1
                    end
                end
            end
        end
    end
    if removed > 0 then U.log("%s: took away %d fitting(s) the layout no longer has", deck.name, removed) end
end

---------------------------------------------------------------------------
-- Stocking
---------------------------------------------------------------------------
-- **A container is stocked once, ever: the moment it is made.** Once a shelf
-- exists it is the player's -- what they eat stays eaten -- and stocking an
-- existing one again would pile a second helping on the first.

--- Every volume of every skill book, so the library is genuinely complete.
local BOOKS = {}
for _, l in ipairs(C.SkillBookLines) do
    for v = 1, 5 do table.insert(BOOKS, "Base.Book" .. l .. v) end
end

local function lootList(name)
    if name == "books" then return BOOKS end
    return C.Loot[name]
end

-- The armouries: crates packed rather than seeded -- every firearm the build
-- ships, every magazine, every calibre in every packaging, the optics to go on
-- them, and holsters. A container that far over capacity is one the player can
-- only take out of, so `copies` is chosen against each list's weight (the
-- numbers beside the lists in TARDIS_Config) and the 50 a cabinet or a trunk
-- holds. Handed out in layout order to the pieces named.
local ARMOURY = {
    { loot = C.Loot.sidearms,    copies = 3 },   -- 35.1
    { loot = C.Loot.longarms,    copies = 1 },   -- 42.0
    { loot = C.Loot.gunMags,     copies = 6 },   --  7.2
    { loot = C.Loot.pistolAmmo,  copies = 6 },   -- 29.5
    { loot = C.Loot.attachments, copies = 4 },   -- 11.2
    { loot = C.Loot.holsters,    copies = 4 },   --  8.8
}
local ARMOURY_TRUNKS = {
    { loot = C.Loot.katanas,     copies = 4 },   --  8.0
    { loot = C.Loot.rifleAmmo,   copies = 6 },   -- 20.3
    { loot = C.Loot.pistolAmmo,  copies = 6 },   -- 29.5
    { loot = C.Loot.gunMags,     copies = 8 },   --  9.6
}
local ARMOURY_STORES = {}
for _, spec in ipairs(ARMOURY) do table.insert(ARMOURY_STORES, spec) end
for _, spec in ipairs({
    { loot = C.Loot.pistolCartons, copies = 1 },  -- 48.0
    { loot = C.Loot.rifleCartons,  copies = 1 },  -- 32.0
    { loot = C.Loot.ammo556,       copies = 8 },  -- 45.9
    { loot = C.Loot.ammo556,       copies = 8 },  -- 45.9
    { loot = C.Loot.katanas,       copies = 4 },  --  8.0
}) do table.insert(ARMOURY_STORES, spec) end

local PACKED = {
    console = { gun_cabinet = ARMOURY, steamer_trunk = ARMOURY_TRUNKS },
    storage = { steamer_trunk = ARMOURY_STORES },
}

--- Packs C.ConsoleKit across the hold's containers in order, moving on to the
--- next when one is full. Returns the kit entries that did not all land.
local function packKit(containers)
    local ci, short = 1, {}
    local add = U.batch("kit.AddItem")
    for _, entry in ipairs(C.ConsoleKit) do
        local id, want = entry[1], entry[2] or 1
        local got = 0
        for _ = 1, want do
            local placed = false
            while not placed and ci <= #containers do
                local c = containers[ci]
                local it = add(function() return c:AddItem(id) end)
                if not it then break end
                local cap = U.try("kit.cap", function() return c:getCapacity() end) or 0
                local have = U.try("kit.have", function() return c:getCapacityWeight() end) or 0
                if have > cap and ci < #containers then
                    U.try("kit.move", function() c:DoRemoveItem(it) end)
                    ci = ci + 1
                else
                    placed = true
                end
            end
            if placed then got = got + 1 else break end
        end
        if got < want then table.insert(short, string.format("%s %d/%d", id, got, want)) end
    end
    return short
end

--- Stocks the containers made on this pass. `made` is a list of
--- { obj = ..., piece = ... } in layout order.
local function stockDeck(deck, made)
    local s = U.state()
    local rules = C.Stock[deck.id] or {}
    local packed = PACKED[deck.id] or {}
    local seen, hold = {}, {}
    for _, m in ipairs(made) do
        local piece = m.piece
        seen[piece] = (seen[piece] or 0) + 1
        local n = seen[piece]
        if C.HoldPieces[piece] then
            table.insert(hold, U.containerOf(m.obj))
        elseif piece == "sonic_case" then
            local present = U.stockEach(m.obj, { C.SonicItem }, C.SonicCount)
            if (present[C.SonicItem] or 0) < C.SonicCount then
                U.log("sonic case holds %d of %d screwdrivers", present[C.SonicItem] or 0, C.SonicCount)
            end
        elseif packed[piece] then
            local spec = packed[piece][n]
            if spec then
                local _, missing = U.stockEach(m.obj, spec.loot, spec.copies)
                if #missing > 0 then
                    U.log("%s %s %d could not hold: %s", deck.id, piece, n, table.concat(missing, ", "))
                end
            end
        else
            local rule = rules[piece] or C.Stock.any[piece]
            if rule then
                local name = rule.loot or (rule.cycle and rule.cycle[((n - 1) % #rule.cycle) + 1])
                local list = name and lootList(name)
                if list then
                    U.stock(m.obj, list, rule.amount or 6)
                else
                    U.warnOnce("loot:" .. tostring(name), "no C.Loot list named " .. tostring(name))
                end
            end
        end
    end
    -- The kit goes aboard once in the life of a world. A world that had the
    -- old console item already has it (the refit handed it back).
    if #hold > 0 and not s.kitPacked then
        local short = packKit(hold)
        s.kitPacked = true
        if #short > 0 then U.log("the hold is short of: %s", table.concat(short, ", ")) end
    end
end

---------------------------------------------------------------------------
-- Farming and livestock
---------------------------------------------------------------------------
--- Plows and sows the crop beds: every square of the layout's `beds` that is
--- not an aisle (every third column). SFarmingSystem is the server-side owner
--- of plants even in single player, so everything goes through it.
function B.sowPlots(deck)
    local lay = layoutOf(deck)
    if not lay.beds then return 0 end
    if not SFarmingSystem or not SFarmingSystem.instance then
        U.warnOnce("farming", "SFarmingSystem unavailable; beds left bare")
        return 0
    end
    local sown = 0
    local n = #C.Crops
    local plow = U.batch("farm.plow")
    local b = lay.beds
    for ox = b.x0, b.x1 do
        for oy = b.y0, b.y1 do
            if (ox % 3) ~= 0 then
                local x, y = at(deck, ox, oy)
                local sq = U.square(x, y, deck.z, true)
                if sq then
                    local existing = U.try("plantAt", function()
                        return SFarmingSystem.instance:getLuaObjectOnSquare(sq)
                    end)
                    if not existing then
                        plow(function() SFarmingSystem.instance:plow(sq) end)
                        local plant = U.try("plantAt2", function()
                            return SFarmingSystem.instance:getLuaObjectOnSquare(sq)
                        end)
                        if plant then
                            local crop = C.Crops[(sown % n) + 1]
                            U.try("seed", function() plant:seed(crop, 10) end)
                            sown = sown + 1
                        end
                    end
                end
            end
        end
    end
    U.debug("sowed %d plots", sown)
    return sown
end

--- The free squares of the room called `name` on a deck.
local function roomSquares(deck, name)
    local lay = layoutOf(deck)
    local rid
    for i, r in ipairs(lay.rooms) do if r == name then rid = i end end
    local taken = {}
    for _, o in ipairs(lay.objects) do
        if o[4] == "f" or o[4] == "c" then taken[o[1] .. "," .. o[2]] = true end
    end
    local out = {}
    for oy = 1, lay.h do
        for ox = 1, lay.w do
            if lay.grid[oy][ox] == rid and not taken[(ox - 1) .. "," .. (oy - 1)] then
                table.insert(out, { ox - 1, oy - 1 })
            end
        end
    end
    return out
end

--- Livestock in the stable, once. Purely a bonus: a failure here must never
--- stop the deck from finishing.
function B.stockAnimals(deck)
    local s = U.state()
    if s.animalsStocked then return 0 end
    if not addAnimal or not AnimalDefinitions then
        U.warnOnce("animals", "animal API unavailable; livestock skipped")
        return 0
    end
    local spots = roomSquares(deck, "Stable")
    if #spots == 0 then return 0 end
    -- Animal types are per sex in build 42 (hen and cockerel, ewe and ram),
    -- not one entry per species.
    local wanted = {
        { "hen", 4 }, { "cockerel", 1 },
        { "ewe", 3 }, { "ram", 1 },
        { "cow", 2 }, { "sow", 2 },
    }
    local made = 0
    local spawn = U.batch("animals.add")
    for _, spec in ipairs(wanted) do
        local kind, count = spec[1], spec[2]
        local def = U.try("animalDef:" .. kind, function() return AnimalDefinitions.getDef(kind) end)
        local breed = def and U.try("animalBreed:" .. kind, function()
            local all = def:getBreeds()
            if all and all:size() > 0 then return all:get(0) end
            return nil
        end)
        if breed then
            for _ = 1, count do
                local p = spots[((made * 7) % #spots) + 1]
                local x, y = at(deck, p[1], p[2])
                if spawn(function()
                    local a = addAnimal(U.cell(), x, y, deck.z, kind, breed)
                    if a then a:addToWorld() end
                    return a
                end) then made = made + 1 end
            end
        end
    end
    s.animalsStocked = true
    U.debug("spawned %d animals", made)
    return made
end

---------------------------------------------------------------------------
-- Lighting and power
---------------------------------------------------------------------------
-- The ship's own power. Until 2.0.1 this called sq:setHaveElectricity(true)
-- on every square, which does nothing: in 42.20 IsoGridSquare.haveElectricity
-- never reads that flag. It asks the square's chunk whether any generator
-- position on the chunk's list reaches it (IsoChunk.isGeneratorPoweringSquare
-- -> IsoGenerator.isPoweringSquare, a plain distance test against the
-- GeneratorTileRange and GeneratorVerticalPowerRange sandbox options). Grid
-- power is no way round it either: it needs a room, and a runtime deck cannot
-- have one. So the fridges, freezers and range were dead in every world.
--
-- The ship therefore registers generator positions of its own on the chunks
-- under each deck. There is no IsoGenerator behind them, so no fuel, no
-- noise, no fumes and no fire. The engine does drop a position with no running
-- generator on it whenever a neighbouring chunk loads
-- (IsoChunk.checkForMissingGenerators), so, like the lamps, they are put back
-- from the player update; addGeneratorPos ignores one already listed.
--
-- Points sit on a grid spaced so every square is within the generator range
-- of one. Each covers one grid cell, no wider than a chunk, so registering it
-- on the chunks of that cell's four corners reaches every square it powers.
local powerCheck = 0

local function powerPoints(lay)
    local r = tonumber(SandboxVars and SandboxVars.GeneratorTileRange) or 20
    local step = math.max(1, math.min(8, math.floor(r * 1.4)))
    local half = math.floor(step / 2)
    local pts = {}
    for ox = 0, lay.w, step do
        for oy = 0, lay.h, step do
            table.insert(pts, { ox, oy, math.min(ox + half, lay.w), math.min(oy + half, lay.h),
                                math.min(ox + step - 1, lay.w), math.min(oy + step - 1, lay.h) })
        end
    end
    return pts
end

--- Powers a deck. Cheap enough to call every tick: it does its work once a
--- second unless `now` is set, which the build does.
function B.powerDeck(index, now)
    local deck = C.Decks[index]
    local lay = layoutOf(deck)
    local cell = U.cell()
    if not lay or not cell then return end
    if not now then
        powerCheck = powerCheck + 1
        if powerCheck < 60 then return end
    end
    powerCheck = 0
    if SandboxVars and SandboxVars.AllowExteriorGenerator == false then
        U.warnOnce("power.exterior", "the sandbox option AllowExteriorGenerator is off; "
                   .. "any deck square the engine counts as outdoors will have no power")
    end
    local join = U.batch("power.addGeneratorPos")
    for _, p in ipairs(powerPoints(lay)) do
        local px, py = at(deck, p[3], p[4])
        for _, corner in ipairs({ { p[1], p[2] }, { p[5], p[2] }, { p[1], p[6] }, { p[5], p[6] } }) do
            local x, y = at(deck, corner[1], corner[2])
            if U.chunkLoaded(x, y, deck.z) then
                join(function()
                    cell:getChunkForGridSquare(x, y, deck.z):addGeneratorPos(px, py, deck.z)
                end)
            end
        end
    end
end

-- Local light sources, hung for the deck the player is on at the layout's
-- lamp spots (a lamp in the middle of every room, and more until every
-- square is within three of one). Lampposts are not saved and the engine
-- drops them outside the loaded area, so they are hung again whenever one is
-- missing -- which is also what makes the ship lit after a reload.
local lamps = {}        -- "deck,x,y" -> IsoLightSource
local lampCheck = 0

function B.lightDeck(index)
    local deck = C.Decks[index]
    local lay = layoutOf(deck)
    local cell = U.cell()
    if not lay or not cell then return end
    lampCheck = lampCheck + 1
    if lampCheck >= 10 then
        lampCheck = 0
        local list = U.try("light.list", function() return cell:getLamppostPositions() end)
        if list then
            for key, light in pairs(lamps) do
                if U.try("light.contains", function() return list:contains(light) end) ~= true then
                    lamps[key] = nil
                end
            end
        end
    end
    local c = C.DeckLight
    local hang = U.batch("light.addLamppost")
    for _, p in ipairs(lay.lamps) do
        local key = deck.id .. "," .. p[1] .. "," .. p[2]
        if not lamps[key] then
            local x, y = at(deck, p[1], p[2])
            if U.chunkLoaded(x, y, deck.z) then
                lamps[key] = hang(function() return cell:addLamppost(x, y, deck.z, c[1], c[2], c[3], c[4]) end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Build entry points
---------------------------------------------------------------------------
--- True when the deck footprint is streamed in, so construction will not
--- touch an orphan square. Chunks only stream around a player, so this stays
--- false until somebody is standing in the interior.
function B.deckReady(deck)
    local lay = layoutOf(deck)
    if not lay then return false end
    local probes = {
        { -1, -1 }, { lay.w + 1, -1 }, { -1, lay.h + 1 }, { lay.w + 1, lay.h + 1 },
        { math.floor(lay.w / 2), math.floor(lay.h / 2) },
        { lay.landing.x, lay.landing.y },
    }
    for _, p in ipairs(probes) do
        local x, y = at(deck, p[1], p[2])
        if not U.chunkLoaded(x, y, deck.z) then return false end
    end
    return true
end

--- True when a deck was last built by the old hand-placed generator.
local function builtByOldGenerator(index)
    local s = U.state()
    local key = tostring(index)
    if not s.builtDecks[key] then return false end
    local rev = (s.deckRev or {})[key]
    return rev == nil or rev < C.LayoutRev
end

--- Builds one deck by index (1 is the console room). Idempotent: every step
--- looks before it adds. Returns false, and builds nothing, while the deck
--- footprint is still streaming in.
function B.buildDeck(index)
    local deck = C.Decks[index]
    local lay = layoutOf(deck)
    if not lay then return false end
    if not B.deckReady(deck) then
        U.debug("deck %d (%s) not streamed in yet", index, deck.id)
        return false
    end

    local s = U.state()
    local salvage = {}
    local legacy = builtByOldGenerator(index)
    if legacy then s.kitPacked = true end      -- the old console had the kit
    local made = {}
    local counts = { placed = 0 }

    -- Order matters. The floor goes down first so a player standing here has
    -- ground under them as early as possible; clearing the surrounding void
    -- is left until last. Every phase is isolated, so one failing step cannot
    -- leave a deck half-built with the player in mid-air.
    local phases = {
        { "purgeLegacy", function() if index == 1 then purgeLegacyStack() end end },
        { "refit",       function() if legacy then refitLegacy(deck, salvage) end end },
        { "stale",       function() if not legacy then stripStale(deck, lay, salvage) end end },
        { "floors",      function() layFloors(deck, lay) end },
        { "objects",     function()
            for _, o in ipairs(lay.objects) do
                local x, y = at(deck, o[1], o[2])
                local sq = U.square(x, y, deck.z, true)
                if sq and not standing(sq, o) then
                    local obj = make(sq, o)
                    if obj then
                        counts.placed = counts.placed + 1
                        if o[4] == "c" then table.insert(made, { obj = obj, piece = o[5], sq = sq }) end
                    end
                end
            end
        end },
        { "power",       function() B.powerDeck(index, true) end },
        { "handBack",    function()
            -- Salvage goes into the new containers first; the ones it fills
            -- are the player's own things again and are not stocked on top.
            if #salvage == 0 then return end
            local into = {}
            for _, m in ipairs(made) do
                if not C.HoldPieces[m.piece] or legacy then
                    local c = U.containerOf(m.obj)
                    if c then table.insert(into, c) end
                end
            end
            handBack(deck, salvage, into)
            local rest = {}
            for _, m in ipairs(made) do
                if not holdsAnything(m.obj) then table.insert(rest, m) end
            end
            made = rest
        end },
        { "stock",       function() U.resetStockCursors(); stockDeck(deck, made) end },
        { "garden",      function()
            if lay.beds then B.sowPlots(deck) end
            if deck.id == "growing" then B.stockAnimals(deck) end
        end },
        { "light",       function() B.lightDeck(index) end },
        { "clearMargin", function() clearSurroundings(deck) end },
    }
    for _, phase in ipairs(phases) do
        U.try(phase[1] .. ":" .. deck.id, phase[2])
    end

    s.builtDecks[tostring(index)] = true
    s.deckRev = s.deckRev or {}
    s.deckRev[tostring(index)] = C.BuildRev
    s.layoutRev = s.layoutRev or {}
    s.layoutRev[tostring(index)] = L.rev
    U.log("deck %d (%s) ready at z=%d: %d placed, %d containers stocked",
          index, deck.name, deck.z, counts.placed, #made)
    return true
end

--- True when a deck exists and was generated from the current layout.
function B.deckCurrent(index)
    local s = U.state()
    local key = tostring(index)
    return s.builtDecks[key] == true and (s.deckRev or {})[key] == C.BuildRev
       and (s.layoutRev or {})[key] == L.rev
end

--- Builds a deck once and remembers it, and brings up to date one that was
--- generated from an older layout. Safe to call every time a player arrives.
function B.ensureDeck(index)
    if B.deckCurrent(index) then return false end
    local s = U.state()
    local key = tostring(index)
    -- ensureDeck is called on every arrival tick while the chunks stream in,
    -- so say this once rather than once per frame.
    if s.builtDecks[key] and not B.upgradeNoted[key] then
        B.upgradeNoted[key] = true
        U.log("deck %d was built from an older layout; bringing it up to date", index)
    end
    return B.buildDeck(index)
end

--- Forces a full rebuild of every deck; used by the self-test.
function B.buildAll()
    for i = 1, #C.Decks do B.buildDeck(i) end
    return true
end

---------------------------------------------------------------------------
-- Design-time rebuilding
---------------------------------------------------------------------------
--- Tears a deck back to bare ground and regenerates it, restocked.
---
--- This is the one operation that deliberately destroys what is there,
--- including containers and their contents. An ordinary rebuild never does:
--- a ship in play is meant to be lived in, and what the player eats stays
--- eaten. Use this while designing a deck, not on a world being played.
---
--- Only the deck the player is standing on can be rebuilt, because only its
--- chunks are streamed in.
function B.forceRebuild(index)
    local player = U.player(0)
    if not player then return false end

    local _, here = U.deckAt(player:getX(), player:getY(), player:getZ())
    index = index or here
    local deck = C.Decks[index]
    if not deck then
        U.log("forceRebuild: stand on the deck you want rebuilt")
        return false
    end
    if index ~= here then
        U.log("forceRebuild: can only rebuild the deck you are standing on (%s)",
              C.Decks[here] and C.Decks[here].name or "none")
        return false
    end

    local wiped = 0
    for ox = -2, C.RoomSize + 2 do
        for oy = -2, C.RoomSize + 2 do
            local x, y = at(deck, ox, oy)
            local sq = U.square(x, y, deck.z, false)
            if sq then
                local doomed = {}
                U.eachObject(sq, function(o) table.insert(doomed, o) end)
                for _, o in ipairs(doomed) do
                    if U.try("wipe", function()
                        sq:RemoveTileObjectErosionNoRecalc(o); return true
                    end) then wiped = wiped + 1 end
                end
            end
        end
    end

    local s = U.state()
    s.builtDecks[tostring(index)] = nil
    if s.deckRev then s.deckRev[tostring(index)] = nil end
    if s.layoutRev then s.layoutRev[tostring(index)] = nil end
    if index == 1 then s.kitPacked = nil end
    local ok = B.buildDeck(index)
    U.log("forceRebuild: wiped %d objects and regenerated %s", wiped, deck.name)
    U.teleport(player, B.arrivalSpot(deck))
    return ok
end

--- Exposed for the debug console: TARDIS_Rebuild()
function TARDIS_Rebuild(index)
    return B.forceRebuild(index)
end

return B
