--[[ TARDIS -- interior construction.

    The interior is generated at runtime in otherwise empty cells rather than
    shipped as a map, so the mod needs no TileZed-built lots. Decks are built
    lazily: the console room goes up on the first entry, and each deck below
    the first time anyone walks down to it.

    A deck is a 25x25 hall with a walled stair core on its east side. Each
    deck sits one z level below the last and one step sideways, so no deck is
    ever directly above another. That sidestep is deliberate: the engine draws
    every level above the player and only hides what is overhead when it
    believes you are inside a building, which requires room metadata baked
    into a map file that runtime squares cannot have. With nothing overhead
    there is nothing to hide, and the descent through z stays real.
]]

require "TARDIS/TARDIS_Config"
require "TARDIS/TARDIS_Util"

TARDIS = TARDIS or {}
local C = TARDIS.Config
local U = TARDIS.Util

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

--- Where a player arriving on a deck is put down. The square and the ring
--- around it are kept clear of furniture by every placement helper.
function B.arrivalSpot(deck)
    local x, y = at(deck, C.Landing.x, C.Landing.y)
    return x, y, deck.z
end

---------------------------------------------------------------------------
-- Clearing the site
---------------------------------------------------------------------------
--- The interior cells are unmapped, so the engine grows procedural
--- wilderness there. Left alone the ship reads as a tower in a forest, so the
--- footprint is stripped before building and a wide margin around it is
--- stripped to nothing at all, which renders as black void.
---
--- Safe to repeat: U.clearSquare keeps anything the mod placed and anything
--- lying on the ground, and sown plots are stepped over so a rebuild never
--- destroys a crop the farming system still has a record of.
local function clearFootprint(deck)
    local cleared = 0
    local farming = SFarmingSystem and SFarmingSystem.instance
    for ox = 0, C.RoomSize do
        for oy = 0, C.RoomSize do
            local x, y = at(deck, ox, oy)
            local sq = U.square(x, y, deck.z, false)
            if sq then
                local hasPlant = false
                if farming then
                    hasPlant = U.try("plantHere", function()
                        return farming:getLuaObjectOnSquare(sq)
                    end) ~= nil
                end
                if not hasPlant then
                    cleared = cleared + U.clearSquare(sq, true)
                end
            end
        end
    end
    U.debug("cleared %d objects from the %s footprint", cleared, deck.id)
end

--- Strips the ring around a deck, on its own level and on the ground below
--- it, where the wilderness actually grows.
local function clearSurroundings(deck)
    local m = C.ClearMargin
    local levels = { deck.z }
    if deck.z ~= 0 then table.insert(levels, 0) end

    local cleared = 0
    for _, z in ipairs(levels) do
        for ox = -m, C.RoomSize + m do
            for oy = -m, C.RoomSize + m do
                local inside = ox >= 0 and ox <= C.RoomSize
                               and oy >= 0 and oy <= C.RoomSize
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
-- Shell
---------------------------------------------------------------------------
--- True when an offset is part of this deck floor plan.
local function inShape(deck, ox, oy)
    return C.inShape(ox, oy, deck.shape, C.RoomSize, deck.chamfer)
end

local function buildFloor(deck)
    local made = 0
    for ox = -1, C.RoomSize + 1 do
        for oy = -1, C.RoomSize + 1 do
            -- Floor the room, and also the squares its walls stand on: a wall
            -- on a midair square behaves badly.
            if inShape(deck, ox, oy)
               or inShape(deck, ox - 1, oy) or inShape(deck, ox + 1, oy)
               or inShape(deck, ox, oy - 1) or inShape(deck, ox, oy + 1) then
                local x, y = at(deck, ox, oy)
                if U.addFloor(x, y, deck.z, deck.floor) then made = made + 1 end
            end
        end
    end
    return made
end

--- Walls are derived from the floor plan rather than hard-coded, so changing
--- C.Shape reshapes the room and its walls together.
---
--- A wall lives on the north or west edge of its own square, so a room edge
--- facing east or south is drawn on the square just outside the room.
local function buildWalls(deck)
    local S = C.Sprites
    local z = deck.z
    local placed = 0

    local function wall(ox, oy, sprite)
        local x, y = at(deck, ox, oy)
        if U.addObject(U.square(x, y, z, true), sprite, "wall") then
            placed = placed + 1
        end
    end

    for ox = 0, C.RoomSize do
        for oy = 0, C.RoomSize do
            if inShape(deck, ox, oy) then
                if not inShape(deck, ox - 1, oy) then wall(ox, oy, S.wallW) end
                if not inShape(deck, ox, oy - 1) then wall(ox, oy, S.wallN) end
                if not inShape(deck, ox + 1, oy) then wall(ox + 1, oy, S.wallW) end
                if not inShape(deck, ox, oy + 1) then wall(ox, oy + 1, S.wallN) end
            end
        end
    end
    U.debug("%s: %d wall segments", deck.id, placed)
end

---------------------------------------------------------------------------
-- Lighting and power
---------------------------------------------------------------------------
local function lightDeck(deck)
    local S = C.Sprites
    local z = deck.z
    local cell = U.cell()

    local spots = {
        { 4, 4 }, { 12, 4 }, { 20, 4 },
        { 4, 12 }, { 12, 12 }, { 20, 12 },
        { 4, 20 }, { 12, 20 }, { 20, 20 },
    }
    local lamp = U.batch("light.lamppost")
    for _, p in ipairs(spots) do
        local x, y = at(deck, p[1], p[2])
        local sq = U.square(x, y, z, true)
        if sq then
            U.addObject(sq, S.lamp.S, "lamp")
            if cell then
                lamp(function() cell:addLamppost(x, y, z, 0.95, 0.95, 0.88, 9) end)
            end
        end
    end
end

--- Marks the whole footprint as powered indoor space.
local function powerDeck(deck)
    local power = U.batch("power.setHaveElectricity")
    for ox = 0, C.RoomSize do
        for oy = 0, C.RoomSize do
            local x, y = at(deck, ox, oy)
            local sq = U.square(x, y, deck.z, false)
            if sq then
                power(function() sq:setHaveElectricity(true) end)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Furnishing helpers
---------------------------------------------------------------------------
--- Places a multi-tile piece from C.Pieces at an offset.
---
--- Each half carries its own offset taken from the tileset, so the head and
--- foot of a bed land the right way round. Nothing is placed unless every
--- square the piece needs is inside the room and free of other furniture.
local function place(deck, pieceName, ox, oy, tag)
    local piece = C.Pieces[pieceName]
    if not piece then
        U.warnOnce("piece:" .. tostring(pieceName), "no such piece")
        return false
    end
    for _, part in ipairs(piece) do
        local px, py = ox + part[2], oy + part[3]
        if not inShape(deck, px, py) then return false end
        if C.isLanding(px, py) then return false end
    end
    for _, part in ipairs(piece) do
        local x, y = at(deck, ox + part[2], oy + part[3])
        U.addObject(U.square(x, y, deck.z, true), part[1], tag)
    end
    return true
end

--- True when every square within `inset` of this one is inside the room.
local function inShapeEroded(deck, ox, oy, inset)
    for dx = -inset, inset do
        for dy = -inset, inset do
            if not inShape(deck, ox + dx, oy + dy) then return false end
        end
    end
    return true
end

--- The band of squares `inset` in from the wall, each with the direction it
--- should face to look into the room.
---
--- Furniture placed from this follows whatever shape the deck is, so an
--- octagonal room gets its shelves along all eight walls without anything
--- being positioned by hand.
local function wallRing(deck, inset)
    local ring = {}
    for ox = 0, C.RoomSize do
        for oy = 0, C.RoomSize do
            if inShapeEroded(deck, ox, oy, inset)
               and not inShapeEroded(deck, ox, oy, inset + 1) then
                local facing = "S"
                if not inShapeEroded(deck, ox, oy - 1, inset) then facing = "S"
                elseif not inShapeEroded(deck, ox, oy + 1, inset) then facing = "N"
                elseif not inShapeEroded(deck, ox - 1, oy, inset) then facing = "E"
                elseif not inShapeEroded(deck, ox + 1, oy, inset) then facing = "W"
                end
                table.insert(ring, { ox = ox, oy = oy, facing = facing })
            end
        end
    end
    return ring
end

--- Places `count` copies of a sprite along a line, stocking each one.
--- `opts` may carry { loot = list, amount = n, tag = string }.
local function line(deck, sprite, ox, oy, dx, dy, count, opts)
    opts = opts or {}
    local placed = {}
    for i = 0, count - 1 do
        local rx, ry = ox + dx * i, oy + dy * i
        local x, y = at(deck, rx, ry)
        local free = inShape(deck, rx, ry) and not C.isLanding(rx, ry)
        local sq = free and U.square(x, y, deck.z, true) or nil
        if sq then
            local obj, created
            if opts.loot then
                obj, created = U.addContainer(sq, sprite, opts.tag)
                -- Only ever stock a container the moment it is made. A
                -- rebuild leaves a lived-in ship exactly as the player left it.
                if created or C.DevRestock then
                    U.stock(obj, opts.loot, opts.amount or 6)
                end
            else
                obj = U.addObject(sq, sprite, opts.tag)
            end
            if obj then table.insert(placed, obj) end
        end
    end
    return placed
end

--- Every volume of every skill book, so the library is genuinely complete.
local function skillBookList()
    local books = {}
    for _, l in ipairs(C.SkillBookLines) do
        for v = 1, 5 do
            table.insert(books, "Base.Book" .. l .. v)
        end
    end
    return books
end

---------------------------------------------------------------------------
-- Deck dressing
---------------------------------------------------------------------------
local furnish = {}

--- Console room.
---
--- The show settled early on a large room with a hexagonal console and a
--- glass column at its centre, roundel walls, and furniture and antiques
--- strewn about the edges -- a bookshelf, a chair, a lamp, a clock, chests,
--- a scanner. Roundels have no equivalent in the tileset, but the rest does,
--- so the console stands alone in the middle and everything else is arranged
--- around the octagonal wall.
---
--- It is also somewhere the Doctor lives, so there is a bed, a desk and real
--- storage rather than a bare control deck.
furnish.console = function(deck)
    local S = C.Sprites

    -- the console itself, centred, on a rug
    local cx, cy = 12, 12
    local x, y = at(deck, cx, cy)
    local sq = U.square(x, y, deck.z, true)
    if sq then
        local already = false
        U.try("scanConsole", function()
            local items = sq:getWorldObjects()
            if items then
                for i = 0, items:size() - 1 do
                    local it = items:get(i)
                    local item = it and it:getItem()
                    if item and item:getFullType() == C.ConsoleItem then already = true end
                end
            end
        end)
        if not already then
            U.try("addConsole", function()
                sq:AddWorldInventoryItem(C.ConsoleItem, 0.5, 0.5, 0.0)
            end)
        end
    end

    -- a floor covering under and around the console
    for dx = -2, 2 do
        for dy = -2, 2 do
            if not (dx == 0 and dy == 0) then
                local rx, ry = at(deck, cx + dx, cy + dy)
                U.addObject(U.square(rx, ry, deck.z, true), S.rug, "rug")
            end
        end
    end

    -- Dress the wall. The ring follows the octagon, so this fills all eight
    -- walls without a single hand-placed coordinate.
    local ring = wallRing(deck, 1)
    local pattern = {
        { kind = "shelf", loot = C.Loot.magazines, amount = 6 },
        { kind = "chest", loot = C.Loot.tools, amount = 8 },
        { kind = "chair" },
        { kind = "shelf", loot = C.Loot.media, amount = 5 },
        { kind = "lamp" },
        { kind = "chest", loot = C.Loot.medical, amount = 6 },
        { kind = "gap" },
        { kind = "shelf", loot = C.Loot.magazines, amount = 6 },
        { kind = "radio" },
        { kind = "gap" },
    }
    for i, spot in ipairs(ring) do
        if not C.isLanding(spot.ox, spot.oy) then
            local entry = pattern[((i - 1) % #pattern) + 1]
            local f = spot.facing
            local sx, sy = at(deck, spot.ox, spot.oy)
            local square = U.square(sx, sy, deck.z, true)
            if entry.kind == "shelf" then
                local obj, made = U.addContainer(square, S.bookShelf[f] or S.bookShelf.S, "books")
                if made or C.DevRestock then U.stock(obj, entry.loot, entry.amount) end
            elseif entry.kind == "chest" then
                local obj, made = U.addContainer(square, S.chest[f] or S.chest.S, "chest")
                if made or C.DevRestock then U.stock(obj, entry.loot, entry.amount) end
            elseif entry.kind == "chair" then
                U.addObject(square, S.chair[f] or S.chair.S, "chair")
            elseif entry.kind == "lamp" then
                U.addObject(square, S.lamp[f] or S.lamp.S, "lamp")
            elseif entry.kind == "radio" then
                U.addObject(square, S.radio[f] or S.radio.S, "radio")
            end
        end
    end

    -- The lived-in corner: a bed, a desk and a wardrobe in the north-west of
    -- the chamber, well clear of the console and the doorway.
    place(deck, "bedFancyS", 5, 5, "bed")
    local nsx, nsy = at(deck, 6, 5)
    local night, madeNight = U.addContainer(U.square(nsx, nsy, deck.z, true),
                                            S.chest.S, "chest")
    if madeNight or C.DevRestock then U.stock(night, C.Loot.linen, 3) end

    place(deck, "wardrobeS", 8, 4, "wardrobe")
    place(deck, "deskS", 5, 9, "desk")
    local chx, chy = at(deck, 5, 10)
    U.addObject(U.square(chx, chy, deck.z, true), S.chair.N, "chair")

    -- the scanner, and a clock, on the wall opposite the doors
    local scx, scy = at(deck, 12, 4)
    U.addObject(U.square(scx, scy, deck.z, true), S.scanner.S, "scanner")
    local clx, cly = at(deck, 14, 4)
    U.addObject(U.square(clx, cly, deck.z, true), S.clock.S, "clock")

    -- large stores, the things a traveller actually hauls about
    line(deck, S.crate, 17, 20, 1, 0, 4,
         { loot = C.Loot.tools, amount = 10, tag = "crate" })
    line(deck, S.metalShelf.N, 8, 20, 1, 0, 5,
         { loot = C.Loot.food, amount = 8, tag = "rack" })
end

--- Habitation.
---
--- Laid out as proper cabins rather than a dormitory: each berth is a bed
--- with its own nightstand, a wardrobe shared between pairs, and a reading
--- lamp, in two ranks with a walking aisle between them. The wet block runs
--- along the west wall.
---
--- Beds go down through C.Pieces, which carries the per-half offsets from the
--- tileset. Placing the two halves by hand is what made the old bunks look
--- mismatched: every bed had its foot laid where its head should be.
furnish.housing = function(deck)
    local S = C.Sprites

    local berths = 0
    for rank = 0, 1 do
        local ox = 7 + rank * 7
        for i = 0, 3 do
            local oy = 5 + i * 4
            if place(deck, "bedS", ox, oy, "bed") then
                berths = berths + 1

                local nx, ny = at(deck, ox + 1, oy)
                local night, made = U.addContainer(U.square(nx, ny, deck.z, true),
                                                   S.chest.S, "nightstand")
                if made or C.DevRestock then U.stock(night, C.Loot.linen, 3) end

                if i % 2 == 0 then
                    place(deck, "wardrobeS", ox + 2, oy, "wardrobe")
                end

                local lx, ly = at(deck, ox - 1, oy)
                U.addObject(U.square(lx, ly, deck.z, true), S.lamp.E, "lamp")
            end
        end
    end
    U.debug("housing: %d berths", berths)

    -- Wet block along the west wall: basins, cubicles, then showers.
    line(deck, S.sink.W, 2, 4, 0, 1, 5, { tag = "sink" })
    line(deck, S.toilet.W, 2, 11, 0, 1, 5, { tag = "toilet" })
    line(deck, S.shower.W, 2, 17, 0, 1, 4, { tag = "shower" })

    -- Linen stores against the east wall.
    line(deck, S.metalShelf.W, 20, 8, 0, 1, 8,
         { loot = C.Loot.linen, amount = 8, tag = "rack" })

    -- A pair of chairs, so the deck is not purely functional.
    for _, ox in ipairs({ 12, 14 }) do
        local cx, cy = at(deck, ox, 21)
        U.addObject(U.square(cx, cy, deck.z, true), S.chair.N, "chair")
    end
end

--- Stores, with the armoury along its south side.
---
--- The armoury is five military crates, deliberately packed rather than
--- sprinkled: every firearm the build ships, every magazine, every calibre in
--- every packaging, and the optics to go on them. Crates hold fifty, so each
--- one is filled rather than seeded.
furnish.storage = function(deck)
    local S = C.Sprites

    -- general stores: six aisles of shelving running north to south
    local racks = {
        { C.Loot.tools, 10 }, { C.Loot.tools, 10 }, { C.Loot.medical, 10 },
        { C.Loot.medical, 10 }, { C.Loot.tools, 10 }, { C.Loot.linen, 8 },
    }
    for i, spec in ipairs(racks) do
        local ox = 3 + (i - 1) * 2
        line(deck, S.metalShelf.S, ox, 3, 0, 1, 19,
             { loot = spec[1], amount = spec[2], tag = "rack" })
    end

    -- lockers of medical supplies by the landing
    line(deck, S.locker.S, 16, 4, 0, 2, 6,
         { loot = C.Loot.medical, amount = 8, tag = "locker" })

    ---------------------------------------------------------------------
    -- The armoury
    ---------------------------------------------------------------------
    local armoury = {
        { loot = C.Loot.firearms,    amount = 34, tag = "armoury.guns" },
        { loot = C.Loot.firearms,    amount = 34, tag = "armoury.guns" },
        { loot = C.Loot.gunMags,     amount = 36, tag = "armoury.mags" },
        { loot = C.Loot.gunAmmo,     amount = 42, tag = "armoury.ammo" },
        { loot = C.Loot.gunAmmo,     amount = 42, tag = "armoury.ammo" },
        { loot = C.Loot.attachments, amount = 24, tag = "armoury.optics" },
    }
    local placed = 0
    for i, spec in ipairs(armoury) do
        local ox, oy = 5 + (i - 1) * 3, 23
        local x, y = at(deck, ox, oy)
        if inShape(deck, ox, oy) and not C.isLanding(ox, oy) then
            local obj, made = U.addContainer(U.square(x, y, deck.z, true),
                                             S.crate, spec.tag)
            if obj then
                placed = placed + 1
                if made or C.DevRestock then
                    U.stock(obj, spec.loot, spec.amount)
                end
            end
        end
    end

    -- gun racks on the wall behind the crates
    line(deck, S.metalShelf.N, 6, 21, 2, 0, 6,
         { loot = C.Loot.firearms, amount = 8, tag = "armoury.rack" })
    line(deck, S.locker.N, 18, 21, 1, 0, 3,
         { loot = C.Loot.gunAmmo, amount = 20, tag = "armoury.locker" })

    U.debug("storage: %d armoury crates", placed)
end

--- Library: skill books, magazines and tapes.
furnish.library = function(deck)
    local S = C.Sprites
    local books = skillBookList()
    for i = 1, 6 do
        local ox = 2 + (i - 1) * 2
        line(deck, S.bookShelf.S, ox, 2, 0, 1, 20,
             { loot = books, amount = 12, tag = "books" })
    end
    line(deck, S.magShelf.S, 14, 3, 0, 2, 9,
         { loot = C.Loot.magazines, amount = 10, tag = "magazines" })
    line(deck, S.magShelf.N, 2, 23, 2, 0, 7,
         { loot = C.Loot.media, amount = 8, tag = "tapes" })
end

--- Galley: counters, cold storage and ovens, all stocked.
furnish.galley = function(deck)
    local S = C.Sprites
    line(deck, S.counter.N, 2, 2, 1, 0, 12,
         { loot = C.Loot.cookware, amount = 6, tag = "counter" })
    line(deck, S.counter.N, 2, 23, 1, 0, 12,
         { loot = C.Loot.cookware, amount = 6, tag = "counter" })
    line(deck, S.fridge.S, 2, 6, 2, 0, 6,
         { loot = C.Loot.food, amount = 12, tag = "fridge" })
    line(deck, S.fridge.S, 2, 18, 2, 0, 6,
         { loot = C.Loot.food, amount = 12, tag = "fridge" })
    line(deck, S.oven.S, 2, 10, 2, 0, 5, { tag = "oven" })
    line(deck, S.counter.N, 2, 14, 1, 0, 12,
         { loot = C.Loot.food, amount = 10, tag = "pantry" })
    line(deck, S.sink.W, 1, 3, 0, 1, 3, { tag = "sink" })
end

--- Hydroponics: sown plots under grow lamps, with seed stores and taps.
furnish.growing = function(deck)
    local S = C.Sprites
    line(deck, S.metalShelf.S, 15, 3, 0, 2, 8,
         { loot = C.Loot.seeds, amount = 10, tag = "seeds" })
    line(deck, S.sink.W, 1, 3, 0, 1, 4, { tag = "sink" })
    B.sowPlots(deck)
    B.stockAnimals(deck)
end

---------------------------------------------------------------------------
-- Farming and livestock
---------------------------------------------------------------------------
--- Plows and sows the growing deck. SFarmingSystem is the server-side owner
--- of plants even in single player, so everything goes through it.
function B.sowPlots(deck)
    if not SFarmingSystem or not SFarmingSystem.instance then
        U.warnOnce("farming", "SFarmingSystem unavailable; plots left bare")
        return 0
    end
    local sown = 0
    local n = #C.Crops
    local plow = U.batch("farm.plow")
    for ox = 2, 13 do
        for oy = 2, 21 do
            if (ox % 3) ~= 0 then          -- leave walkable aisles
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

--- Adds livestock if the build exposes the animal API. Purely a bonus: a
--- failure here must never stop the deck from finishing.
function B.stockAnimals(deck)
    if not addAnimal or not AnimalDefinitions then
        U.warnOnce("animals", "animal API unavailable; livestock skipped")
        return 0
    end
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
        local def = U.try("animalDef:" .. kind, function()
            return AnimalDefinitions.getDef(kind)
        end)
        if def then
            -- Breed names differ per species, so take whichever the
            -- definition lists first rather than guessing at names.
            local breed = U.try("animalBreed:" .. kind, function()
                local all = def:getBreeds()
                if all and all:size() > 0 then return all:get(0) end
                return nil
            end)
            if breed then
                for _ = 1, count do
                    local x, y = at(deck, 17 + (made % 5), 18 + math.floor(made / 5))
                    local ok = spawn(function()
                        local a = addAnimal(U.cell(), x, y, deck.z, kind, breed)
                        if a then a:addToWorld() end
                        return a
                    end)
                    if ok then made = made + 1 end
                end
            end
        end
    end
    U.debug("spawned %d animals", made)
    return made
end

---------------------------------------------------------------------------
-- Build entry points
---------------------------------------------------------------------------
--- True when the deck footprint is streamed in, so construction will not
--- touch an orphan square. Chunks only stream around a player, so this stays
--- false until somebody is standing in the interior.
function B.deckReady(deck)
    local size = C.RoomSize
    local probes = {
        { 0, 0 }, { size, 0 }, { 0, size }, { size, size },
        { math.floor(size / 2), math.floor(size / 2) },
        { C.Landing.x, C.Landing.y },
    }
    for _, p in ipairs(probes) do
        local x, y = at(deck, p[1], p[2])
        if not U.chunkLoaded(x, y, deck.z) then return false end
    end
    return true
end

--- Builds one deck by index (1 is the console room). Idempotent: every step
--- checks for what it would add before adding it. Returns false, and builds
--- nothing, while the deck footprint is still streaming in.
function B.buildDeck(index)
    local deck = C.Decks[index]
    if not deck then return false end

    if not B.deckReady(deck) then
        U.debug("deck %d (%s) not streamed in yet", index, deck.id)
        return false
    end

    U.debug("building deck %d (%s) at z=%d col=%d", index, deck.id, deck.z, deck.col)
    local s = U.state()

    -- Order matters. The footprint is stripped and floored first so a player
    -- standing here has ground under them as early as possible; clearing the
    -- surrounding void is left until last. Every phase is isolated, so one
    -- failing step cannot leave a deck half-built with the player in mid-air.
    local phases = {
        { "purgeLegacy",    function() if index == 1 then purgeLegacyStack() end end },
        { "clearFootprint", function() clearFootprint(deck) end },
        { "buildFloor",     function() buildFloor(deck) end },
        { "buildWalls",     function() buildWalls(deck) end },
        { "powerDeck",      function() powerDeck(deck) end },
        { "lightDeck",      function() lightDeck(deck) end },
        { "furnish",        function()
                                U.resetStockCursors()
                                local dress = furnish[deck.id]
                                if dress then dress(deck) end
                            end },
        { "clearMargin",    function() clearSurroundings(deck) end },
    }
    for _, phase in ipairs(phases) do
        U.try(phase[1] .. ":" .. deck.id, phase[2])
    end

    s.builtDecks[tostring(index)] = true
    s.deckRev = s.deckRev or {}
    s.deckRev[tostring(index)] = C.BuildRev
    U.log("deck %d (%s) ready at z=%d", index, deck.name, deck.z)
    return true
end

--- True when a deck exists and was generated by the current revision.
function B.deckCurrent(index)
    local s = U.state()
    local key = tostring(index)
    return s.builtDecks[key] == true and (s.deckRev or {})[key] == C.BuildRev
end

--- Builds a deck once and remembers it, and rebuilds one that was generated
--- by an older revision of the mod. Safe to call every time a player arrives.
function B.ensureDeck(index)
    local s = U.state()
    s.deckRev = s.deckRev or {}
    local key = tostring(index)
    if s.builtDecks[key] and s.deckRev[key] == C.BuildRev then
        return false
    end
    -- ensureDeck is called on every arrival tick while the chunks stream in,
    -- so say this once rather than once per frame.
    if s.builtDecks[key] and not B.upgradeNoted[key] then
        B.upgradeNoted[key] = true
        U.log("deck %d was built by an older revision; bringing it up to date", index)
    end
    return B.buildDeck(index)
end

--- Forces a full rebuild of every deck; used by the self-test.
function B.buildAll()
    for i = 1, #C.Decks do
        B.buildDeck(i)
    end
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
                -- clear everything this time, our own work included
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

    local wasDev = C.DevRestock
    C.DevRestock = true
    local ok = B.buildDeck(index)
    C.DevRestock = wasDev

    U.log("forceRebuild: wiped %d objects and regenerated %s", wiped, deck.name)
    U.teleport(player, B.arrivalSpot(deck))
    return ok
end

--- Exposed for the debug console: TARDIS_Rebuild()
function TARDIS_Rebuild(index)
    return B.forceRebuild(index)
end

return B
