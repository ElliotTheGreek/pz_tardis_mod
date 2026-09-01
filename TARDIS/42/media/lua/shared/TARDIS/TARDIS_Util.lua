--[[ TARDIS -- shared helpers.

    The build code touches a lot of engine surface at once, and a single nil
    from one call should never take down a whole deck. Everything here is
    defensive on purpose: wrapped calls, tolerant square lookups and one
    place that owns the persisted state.
]]

require "TARDIS/TARDIS_Config"

TARDIS = TARDIS or {}
local C = TARDIS.Config

local U = {}
TARDIS.Util = U

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
function U.log(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        local ok, formatted = pcall(string.format, fmt, ...)
        if ok then msg = formatted end
    end
    print(C.ModPrefix .. " " .. tostring(msg))
end

function U.debug(fmt, ...)
    if C.Debug then U.log(fmt, ...) end
end

-- Errors are noisy the first time and silent afterwards, so a per-tick
-- failure cannot flood console.txt.
local reported = {}
function U.warnOnce(key, fmt, ...)
    if reported[key] then return end
    reported[key] = true
    U.log("WARN (" .. tostring(key) .. ") " .. tostring(fmt), ...)
end

--- Guards a call that is about to be repeated over thousands of squares.
---
--- Returns a callable that stops trying after its first failure. This matters
--- more than it looks: a wrong method name inside a per-square loop does not
--- fail quietly, it throws out of Java and the engine dumps a stack trace for
--- every single square. At deck scale that is hundreds of dumps, which locks
--- the game up hard enough to look like a crash. One failure, one warning,
--- then the pass carries on without that step.
function U.batch(label)
    local broken = false
    return function(fn)
        if broken then return nil end
        local ok, result = pcall(fn)
        if not ok then
            broken = true
            U.warnOnce(label, tostring(result))
            return nil
        end
        return result
    end
end

--- Runs fn, logs the first failure under `label` and returns nil on error.
function U.try(label, fn, ...)
    local args = { ... }
    local ok, result = pcall(function() return fn(unpack(args)) end)
    if not ok then
        U.warnOnce(label, tostring(result))
        return nil
    end
    return result
end

---------------------------------------------------------------------------
-- Persisted state
---------------------------------------------------------------------------
-- One table, saved with the world, holding where the box is, where the
-- player came in from, which decks are built and the bookmark list.
function U.state()
    local s = ModData.getOrCreate(C.StateKey)
    -- Every field below falls back to what is already there, so raising the
    -- schema re-runs this block without losing anything. Schema 2 added
    -- `ghosts`: shells left standing somewhere whose chunk was not loaded at
    -- the time, to be swept up when the world next streams that spot in.
    if s.schema ~= 2 then
        s.schema      = 2
        s.version     = C.Version
        s.placed      = s.placed == true
        s.x           = s.x or 0
        s.y           = s.y or 0
        s.z           = s.z or 0
        s.inside      = s.inside == true
        s.returnX     = s.returnX or nil
        s.returnY     = s.returnY or nil
        s.returnZ     = s.returnZ or nil
        s.builtDecks  = s.builtDecks or {}
        s.bookmarks   = s.bookmarks or {}
        s.destination = s.destination or nil
        s.ghosts      = s.ghosts or {}
    end
    -- Belt and braces: a world saved by a build between the two schemas can
    -- have schema 2 and no ghosts list, and every read of it assumes a table.
    s.ghosts = s.ghosts or {}
    return s
end

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------
function U.cellSize()
    if getCellSizeInSquares then
        local n = U.try("cellSize", getCellSizeInSquares)
        if n and n > 0 then return n end
    end
    return 256
end

--- North-west corner of one deck. Decks step sideways as they descend, so
--- each has its own footprint rather than sharing one.
function U.deckOrigin(deck)
    -- Called with nothing, this used to throw. Inside a per-tick handler that
    -- is not a small mistake: it floods the log and freezes the game. Warn and
    -- fall back rather than take the session down.
    if not deck then
        U.warnOnce("deckOrigin", "called with no deck; using the first")
        deck = C.Decks[1]
    end
    local size = U.cellSize()
    return C.InteriorCell.x * size + C.RoomOffset + (deck.col or 0) * C.DeckSpacing,
           C.InteriorCell.y * size + C.RoomOffset
end

--- The deck a world position belongs to, margin included. Position alone
--- identifies a deck now that no two share a footprint.
function U.deckAt(x, y, z)
    if not x or not y or not z then return nil, nil end
    for i, d in ipairs(C.Decks) do
        if math.floor(z) == d.z then
            local ox0, oy0 = U.deckOrigin(d)
            local ox, oy = x - ox0, y - oy0
            if ox >= -C.ClearMargin and ox <= C.RoomSize + C.ClearMargin and
               oy >= -C.ClearMargin and oy <= C.RoomSize + C.ClearMargin then
                return d, i
            end
        end
    end
    return nil, nil
end

--- True when the coordinates fall anywhere in the strip of world the ship
--- occupies. Covers every deck and its void margin, whatever z they are on.
function U.isInterior(x, y)
    if not x or not y then return false end
    local size = U.cellSize()
    local cx = C.InteriorCell.x * size + C.RoomOffset
    local cy = C.InteriorCell.y * size + C.RoomOffset
    local lastCol = 0
    for _, d in ipairs(C.Decks) do
        if (d.col or 0) > lastCol then lastCol = d.col end
    end
    local x1 = cx + lastCol * C.DeckSpacing + C.RoomSize + C.ClearMargin
    local y1 = cy + C.RoomSize + C.ClearMargin
    return x >= cx - C.ClearMargin and x <= x1
       and y >= cy - C.ClearMargin and y <= y1
end

function U.isInteriorPlayer(player)
    if not player then return false end
    return U.isInterior(player:getX(), player:getY())
end

---------------------------------------------------------------------------
-- Squares
---------------------------------------------------------------------------
function U.cell()
    return U.try("getCell", getCell)
end

--- True when the chunk that owns this square is streamed in.
---
--- This gates every piece of construction. A square handed back by
--- getOrCreateGridSquare for a chunk the world has not loaded is an orphan:
--- it has no chunk behind it, and the first engine call that touches it --
--- addFloor, AddTileObject -- throws out of Java. The interior sits in a cell
--- nothing else ever visits, so the only thing that streams it in is a player
--- standing there, and nothing may be built until that has happened.
function U.chunkLoaded(x, y, z)
    local cell = U.cell()
    if not cell then return false end
    local chunk = U.try("getChunkForGridSquare", function()
        return cell:getChunkForGridSquare(math.floor(x), math.floor(y), math.floor(z or 0))
    end)
    return chunk ~= nil
end

--- Grid square lookup. With create=true a square is made if its chunk is
--- loaded; if the chunk is absent this returns nil rather than an orphan.
function U.square(x, y, z, create)
    x, y, z = math.floor(x), math.floor(y), math.floor(z)
    local cell = U.cell()
    if not cell then return nil end

    local sq = U.try("getGridSquare", function() return cell:getGridSquare(x, y, z) end)
    if sq or not create then return sq end

    if not U.chunkLoaded(x, y, z) then return nil end

    return U.try("getOrCreateGridSquare", function()
        return cell:getOrCreateGridSquare(x, y, z)
    end)
end

--- Iterates the objects on a square, tolerating a nil list.
function U.eachObject(sq, fn)
    if not sq then return end
    local objs = U.try("getObjects", function() return sq:getObjects() end)
    if not objs then return end
    local n = U.try("objects.size", function() return objs:size() end) or 0
    for i = 0, n - 1 do
        local o = U.try("objects.get", function() return objs:get(i) end)
        if o then
            if fn(o, i) == false then return end
        end
    end
end

--- Every object on the square whose sprite matches `name`.
function U.findSprite(sq, name)
    local found = nil
    U.eachObject(sq, function(o)
        local spr = o:getSprite()
        if spr and spr:getName() == name then
            found = o
            return false
        end
    end)
    return found
end

--- Adds an IsoObject with the given sprite unless one is already there.
--- Returns the object (existing or new) and whether it was created now.
function U.addObject(sq, sprite, tag)
    if not sq or not sprite then return nil, false end
    local existing = U.findSprite(sq, sprite)
    if existing then return existing, false end

    local obj = U.try("IsoObject.new", function()
        return IsoObject.new(sq, sprite, tag or "")
    end)
    if not obj then return nil, false end

    U.try("AddTileObject", function() sq:AddTileObject(obj) end)
    if tag then
        local md = U.try("obj.getModData", function() return obj:getModData() end)
        if md then md.TARDIS = tag end
    end
    return obj, true
end

--- Strips a square back to nothing. Used to carve the interior out of the
--- procedural wilderness the engine grows in unmapped cells: without this the
--- ship reads as a tower standing in a forest.
function U.clearSquare(sq, removeFloor)
    if not sq then return 0 end
    local doomed = {}
    U.eachObject(sq, function(o)
        local md = U.try("md", function() return o:getModData() end)
        if md and md.TARDIS then return end          -- never strip our own work
        -- Dropped items and the world models we place as items live here too;
        -- stripping those would eat the console and anything a player put down.
        if instanceof(o, "IsoWorldInventoryObject") then return end
        if not removeFloor then
            local floor = U.try("floor", function() return sq:getFloor() end)
            if floor and o == floor then return end
        end
        table.insert(doomed, o)
    end)
    local removed = 0
    for _, o in ipairs(doomed) do
        if U.try("removeObject", function()
            sq:RemoveTileObjectErosionNoRecalc(o)
            return true
        end) then removed = removed + 1 end
    end
    return removed
end

--- Adds the floor for a square, creating the square if needed.
function U.addFloor(x, y, z, sprite)
    local sq = U.square(x, y, z, true)
    if not sq then return nil end
    local floor = U.try("getFloor", function() return sq:getFloor() end)
    if not floor then
        U.try("addFloor", function() sq:addFloor(sprite) end)
    end
    return sq
end

--- Container objects need their ItemContainer built from the sprite
--- properties; map-loaded objects get this for free, runtime ones do not.
--- Returns the container object and whether it was created just now.
---
--- The second return matters: a rebuild must not touch the contents of a
--- container that already exists. The ship is meant to be lived in -- what
--- the player eats stays eaten -- and stocking an existing shelf again would
--- both refill it and pile a second helping on top of the first.
function U.addContainer(sq, sprite, tag)
    local obj, created = U.addObject(sq, sprite, tag)
    if not obj then return nil, false end
    if created then
        U.try("createContainers", function()
            obj:createContainersFromSpriteProperties()
        end)
    end
    return obj, created
end

function U.containerOf(obj)
    if not obj then return nil end
    local c = U.try("getContainer", function() return obj:getContainer() end)
    if c then return c end
    return U.try("getItemContainer", function() return obj:getItemContainer() end)
end

-- Where each loot list got to, so the next container carries on from there.
local stockCursor = {}

--- Fills a container with `count` picks from `list`.
---
--- Each list keeps a rolling position, so consecutive containers continue
--- through it rather than all starting at the top. Without this every shelf
--- on a deck holds an identical dozen items -- the whole library was Aiming
--- and Blacksmith volumes, a hundred and twenty times over -- and most of the
--- list never appears in the world at all.
function U.stock(obj, list, count)
    local container = U.containerOf(obj)
    if not container or not list or #list == 0 then return 0 end

    local key = tostring(list)
    local start = stockCursor[key] or 0
    local added = 0
    for i = 0, count - 1 do
        local id = list[((start + i) % #list) + 1]
        local ok = U.try("AddItems:" .. id, function()
            return container:AddItems(id, 1)
        end)
        if ok then added = added + 1 end
    end
    stockCursor[key] = (start + count) % #list
    return added
end

--- Resets the rolling positions. Called before a deck is dressed so a
--- rebuild lays the same items out the same way.
function U.resetStockCursors()
    stockCursor = {}
end

--- Puts `copies` of every entry in `list` into a container, then checks what
--- actually arrived and returns the ids that did not.
---
--- U.stock walks a list and hopes; this guarantees coverage and then proves
--- it. Containers have a capacity, and once it is reached the engine drops
--- further items without raising anything, so a crate meant to hold every
--- calibre can quietly end up holding a handful. Anything that fails to land
--- is returned so the caller can log it rather than leave a hole nobody
--- notices until they go looking for 5.56 and it is not there.
function U.stockEach(obj, list, copies)
    local container = U.containerOf(obj)
    if not container or not list then return {}, list or {} end
    copies = copies or 1

    for _, id in ipairs(list) do
        for _ = 1, copies do
            U.try("AddItems:" .. id, function() return container:AddItems(id, 1) end)
        end
    end

    local present = {}
    U.try("readBack", function()
        local items = container:getItems()
        if not items then return end
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            if it then
                local t = it:getFullType()
                present[t] = (present[t] or 0) + 1
            end
        end
    end)

    local missing = {}
    for _, id in ipairs(list) do
        if not present[id] then table.insert(missing, id) end
    end
    return present, missing
end

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------
function U.player(index)
    if index then
        return U.try("getSpecificPlayer", function() return getSpecificPlayer(index) end)
    end
    return U.try("getPlayer", getPlayer)
end

--- Moves a character without leaving the old position behind, which the
--- engine otherwise interpolates towards and reads as a fall.
function U.teleport(player, x, y, z)
    if not player then return false end
    return U.try("teleport", function()
        player:setX(x + 0.5)
        player:setY(y + 0.5)
        player:setZ(z)
        player:setLastX(x + 0.5)
        player:setLastY(y + 0.5)
        player:setLastZ(z)
        return true
    end) == true
end

function U.dist2(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return dx * dx + dy * dy
end

return U
