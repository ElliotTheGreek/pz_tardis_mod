--[[ TARDIS -- exterior, doors and interior upkeep.

    The shell is a world model dropped on a square rather than a tile sprite,
    which keeps it to a single 1x1 tile and lets it be summoned anywhere the
    player can stand. Entering teleports into the generated interior and
    remembers where the player came from; leaving reverses it, or delivers
    them to wherever the box was flown to in the meantime.

    Arrival is the delicate part. The interior lives in a cell nothing else
    ever visits, so its chunks are not streamed in until a player is standing
    there -- and nothing can be built into a chunk that has not loaded. So the
    player is moved in first and held, unfalling and unhurt, until the deck
    under their feet exists.
]]

require "TARDIS/TARDIS_Config"
require "TARDIS/TARDIS_Util"

TARDIS = TARDIS or {}
local C = TARDIS.Config
local U = TARDIS.Util

local Core = {}
TARDIS.Core = Core

-- How long to wait for the interior chunks before giving up and putting the
-- player back outside. Ticks, so roughly ten seconds.
local ARRIVAL_TIMEOUT = 600

---------------------------------------------------------------------------
-- Finding the shell
---------------------------------------------------------------------------
--- The world item that represents the shell on a square, if it is there.
function Core.exteriorOn(sq)
    if not sq then return nil end
    local found = nil
    U.try("worldObjects", function()
        local objs = sq:getWorldObjects()
        if not objs then return end
        for i = 0, objs:size() - 1 do
            local o = objs:get(i)
            local item = o and o:getItem()
            if item and item:getFullType() == C.ExteriorItem then
                found = o
                return
            end
        end
    end)
    return found
end

--- The shell at its recorded position, when that square is streamed in.
function Core.currentExterior()
    local s = U.state()
    if not s.placed then return nil end
    local sq = U.square(s.x, s.y, s.z, false)
    if not sq then return nil end
    return Core.exteriorOn(sq), sq
end

--- Takes the shell off its square. Returns true if something was removed.
function Core.removeExteriorAt(x, y, z)
    local sq = U.square(x, y, z, false)
    if not sq then return false end
    local obj = Core.exteriorOn(sq)
    if not obj then return false end
    return U.try("removeExterior", function()
        sq:removeWorldObject(obj)
        return true
    end) == true
end

---------------------------------------------------------------------------
-- Materialising
---------------------------------------------------------------------------
--- A square can host the shell if a player could stand on it: a real floor,
--- nothing solid in the way, no vehicle and nobody standing there.
function Core.canMaterialise(sq)
    if not sq then return false end
    if U.isInterior(sq:getX(), sq:getY()) then return false end

    local ok = U.try("canMaterialise", function()
        if not sq:getFloor() then return false end
        if sq:isSolid() or sq:isSolidTrans() then return false end
        if sq:getVehicleContainer() then return false end
        if not sq:isFree(false) then return false end
        return true
    end)
    if ok ~= true then return false end

    -- refuse to bury an existing shell
    if Core.exteriorOn(sq) then return false end
    return true
end

--- Puts the shell on a square, lifting it from wherever it was before.
--- The same call handles first summon and every later recall.
function Core.materialise(sq, player)
    if not Core.canMaterialise(sq) then return false end
    local s = U.state()

    if s.placed then
        Core.removeExteriorAt(s.x, s.y, s.z)
    end
    -- If the player is carrying one, that copy is the one being placed.
    Core.takeFromInventory(player)

    local placed = U.try("placeExterior", function()
        local obj = sq:AddWorldInventoryItem(C.ExteriorItem, 0.5, 0.5, 0.0)
        if obj and obj.setIgnoreRemoveSandbox then
            -- keep the world-item cleanup rules from sweeping it away
            obj:setIgnoreRemoveSandbox(true)
        end
        return obj
    end)
    if not placed then return false end

    s.placed = true
    s.x, s.y, s.z = sq:getX(), sq:getY(), sq:getZ()
    s.destination = nil

    U.log("materialised at %d,%d,%d", s.x, s.y, s.z)
    return true
end

--- Drops any shell the player is carrying, so it cannot be duplicated.
function Core.takeFromInventory(player)
    if not player then return end
    U.try("takeFromInventory", function()
        local inv = player:getInventory()
        if not inv then return end
        local held = inv:FindAndReturn(C.ExteriorItem)
        while held do
            inv:Remove(held)
            held = inv:FindAndReturn(C.ExteriorItem)
        end
    end)
end

---------------------------------------------------------------------------
-- Arrival: holding the player while the deck streams in and is built
---------------------------------------------------------------------------
local arrival = nil   -- { index, x, y, z, tries, player, wasGod, wasNoClip }

local function protect(player, on)
    U.try("protect", function()
        player:setGodMod(on)
        player:setNoClip(on)
        if on then player:setbFalling(false) end
    end)
end

--- Starts an arrival on a deck. When `move` is true the player is teleported
--- to the deck landing first; when false they are already standing there.
function Core.beginArrival(player, index, move)
    if not player then return false end
    local deck = C.Decks[index]
    if not deck then return false end

    local x, y, z = TARDIS.Build.arrivalSpot(deck)

    if arrival then
        -- already holding: just retarget
        arrival.index, arrival.x, arrival.y, arrival.z = index, x, y, z
        arrival.tries = 0
    else
        arrival = {
            index = index, x = x, y = y, z = z, tries = 0, player = player,
            wasGod = U.try("wasGod", function() return player:isGodMod() end) == true,
            wasNoClip = U.try("wasNoClip", function() return player:isNoClip() end) == true,
        }
        protect(player, true)
    end

    if move then U.teleport(player, x, y, z) end
    return true
end

local function endArrival(restorePosition)
    if not arrival then return end
    local player = arrival.player
    local job = arrival
    arrival = nil
    if player then
        U.try("unprotect", function()
            player:setGodMod(job.wasGod == true)
            player:setNoClip(job.wasNoClip == true)
        end)
        if restorePosition then
            U.teleport(player, job.x, job.y, job.z)
        end
    end
end

--- Runs each tick while an arrival is outstanding: pins the player in place,
--- builds the deck the moment its chunks appear, then hands control back.
local function serviceArrival()
    if not arrival then return end
    local player = arrival.player
    if not player then arrival = nil return end

    arrival.tries = arrival.tries + 1

    -- Report what the world is doing, so a stall is diagnosable from the log
    -- rather than just looking like a hang.
    if arrival.tries == 1 or arrival.tries == 120 or arrival.tries == 420 then
        local deck = C.Decks[arrival.index]
        U.log("arrival tick %d: chunk at landing loaded=%s, deck ready=%s",
              arrival.tries,
              tostring(U.chunkLoaded(arrival.x, arrival.y, arrival.z)),
              tostring(TARDIS.Build.deckReady(deck)))
    end

    -- Hold position so the player cannot drift or drop while waiting.
    U.try("hold", function()
        player:setX(arrival.x + 0.5)
        player:setY(arrival.y + 0.5)
        player:setZ(arrival.z)
        player:setbFalling(false)
    end)

    TARDIS.Build.ensureDeck(arrival.index)
    if TARDIS.Build.deckCurrent(arrival.index) then
        local deck = C.Decks[arrival.index]
        -- Built is not the same as safe: only let go of the player once there
        -- is demonstrably a floor under the spot they are being put down on.
        local landing = U.square(arrival.x, arrival.y, arrival.z, false)
        local floored = landing and U.try("landingFloor", function()
            return landing:getFloor() ~= nil
        end) == true
        if not floored then
            if arrival.tries > 180 then
                U.log("deck %d built but the landing has no floor; ejecting", arrival.index)
                Core.ejectToOutside("no floor on the landing square")
            end
            return
        end
        U.log("arrived on %s", deck.name)
        endArrival(true)
        return
    end

    if arrival.tries > ARRIVAL_TIMEOUT then
        Core.ejectToOutside("interior failed to stream in")
    end
end

--- Last resort: get the player out of the interior and back onto real ground.
--- Nothing inside the ship is worth being stuck in the void for.
function Core.ejectToOutside(why)
    local s = U.state()
    local player = arrival and arrival.player or U.player(0)
    U.log("ejecting to outside: %s", tostring(why))
    endArrival(false)
    if not player then return false end

    local bx, by, bz = s.returnX or s.x, s.returnY or s.y, s.returnZ or s.z
    if not bx then return false end
    local target = Core.landingBeside(bx, by, bz) or { x = bx, y = by, z = bz }
    U.teleport(player, target.x, target.y, target.z)
    s.inside = false
    U.try("ejectMsg", function()
        player:setHaloNote(getText("IGUI_TARDIS_ArrivalFailed"), 255, 60, 60, 300)
    end)
    return true
end

---------------------------------------------------------------------------
-- Doors
---------------------------------------------------------------------------
--- Moves the player into the console room, remembering the way back.
function Core.enter(player)
    if not player then return false end
    local s = U.state()
    if U.isInteriorPlayer(player) then return false end

    s.returnX, s.returnY, s.returnZ = s.x, s.y, s.z
    s.inside = true

    -- Move first, build second: the deck cannot be built until the player
    -- standing there has caused its chunks to stream in.
    Core.beginArrival(player, 1, true)
    U.log("entering interior")
    return true
end

--- Puts the player back outside, at the destination if one was set from the
--- console, otherwise where they came in.
function Core.exit(player)
    if not player then return false end
    local s = U.state()
    endArrival(false)

    if s.destination then
        return TARDIS.Travel.land(player, s.destination)
    end

    local x, y, z = s.returnX, s.returnY, s.returnZ
    if not x then x, y, z = s.x, s.y, s.z end
    if not x then
        U.log("no exit position recorded")
        return false
    end

    -- Clear the ring before the doors open, not a fifth of a second after.
    Core.repelZombies()

    -- Step out beside the shell rather than inside it.
    local target = Core.landingBeside(x, y, z) or { x = x, y = y, z = z }
    if not U.teleport(player, target.x, target.y, target.z) then return false end
    s.inside = false
    U.log("exited to %d,%d,%d", target.x, target.y, target.z)
    return true
end

--- First walkable square next to the shell.
function Core.landingBeside(x, y, z)
    local offsets = { {1,0}, {-1,0}, {0,1}, {0,-1}, {1,1}, {-1,-1}, {1,-1}, {-1,1} }
    for _, o in ipairs(offsets) do
        local sq = U.square(x + o[1], y + o[2], z, false)
        if sq then
            local ok = U.try("landingBeside", function()
                return sq:getFloor() ~= nil and not sq:isSolid() and sq:isFree(false)
            end)
            if ok == true then
                return { x = x + o[1], y = y + o[2], z = z }
            end
        end
    end
    return nil
end

---------------------------------------------------------------------------
-- Moving between decks
---------------------------------------------------------------------------
--- Index of the deck a player is standing on, or nil when outside.
function Core.deckIndexOf(player)
    if not player or not U.isInteriorPlayer(player) then return nil end
    local _, index = U.deckAt(player:getX(), player:getY(), player:getZ())
    return index
end

--- Menu shortcut for the staircase. The generated flights are real stairs,
--- but this also guarantees the silo stays navigable while a deck is still
--- being raised.
function Core.changeDeck(player, delta)
    local index = Core.deckIndexOf(player)
    if not index then return false end
    local target = index + delta
    if not C.Decks[target] then return false end
    return Core.beginArrival(player, target, true)
end

---------------------------------------------------------------------------
-- Upkeep
---------------------------------------------------------------------------
--- Sinks and taps inside the ship never run dry.
function Core.refillWater()
    local s = U.state()
    local count = 0
    for i = 1, #C.Decks do
        if s.builtDecks[tostring(i)] then
            local deck = C.Decks[i]
            local rx, ry = U.deckOrigin(deck)
            for ox = 0, C.RoomSize do
                for oy = 0, C.RoomSize do
                    local sq = U.square(rx + ox, ry + oy, deck.z, false)
                    if sq then
                        U.eachObject(sq, function(o)
                            local md = o:getModData()
                            local tag = md and md.TARDIS
                            if tag == "sink" or tag == "shower" or tag == "toilet" then
                                U.try("refill", function()
                                    local cap = o:getFluidCapacity()
                                    if cap and cap > 0 then
                                        local have = o:getFluidAmount() or 0
                                        if have < cap then
                                            o:addFluid(FluidType.Water, cap - have)
                                        end
                                    end
                                end)
                                count = count + 1
                            end
                        end)
                    end
                end
            end
        end
    end
    U.debug("topped up %d water fixtures", count)
end

---------------------------------------------------------------------------
-- The field around the doors
---------------------------------------------------------------------------
--- Pushes the dead back out of a ring around the shell, so stepping outside
--- is never an ambush and nothing can crowd the doors while it sits there.
---
--- They are shoved to the edge of the field rather than killed: no free
--- experience, no free loot, and they are still waiting when the field is
--- somewhere else.
function Core.repelZombies()
    local s = U.state()
    if not s.placed then return 0 end

    local cell = U.cell()
    if not cell then return 0 end
    local zombies = U.try("getZombieList", function() return cell:getZombieList() end)
    if not zombies then return 0 end

    local n = U.try("zombieCount", function() return zombies:size() end) or 0
    if n == 0 then return 0 end

    local radius = C.FieldRadius
    local pushed = 0
    for i = 0, n - 1 do
        local z = U.try("zombieAt", function() return zombies:get(i) end)
        if z then
            U.try("repel", function()
                if math.floor(z:getZ()) ~= s.z then return end
                local dx, dy = z:getX() - s.x, z:getY() - s.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist > radius then return end

                -- straight overhead: pick a direction rather than divide by zero
                if dist < 0.01 then dx, dy, dist = 1, 0, 1 end
                local scale = (radius + 1.5) / dist
                local nx, ny = s.x + dx * scale, s.y + dy * scale

                z:setX(nx) z:setY(ny)
                z:setLastX(nx) z:setLastY(ny)
                z:setTarget(nil)
                z:setStaggerBack(true)
                pushed = pushed + 1
            end)
        end
    end
    if pushed > 0 then U.debug("field pushed back %d zombies", pushed) end
    return pushed
end

--- Anyone standing in the ship on a deck that has not been raised yet gets
--- the same held arrival as somebody coming through the doors. That covers
--- walking down the stairs into a deck nobody has visited before.
local function onPlayerUpdate(player)
    if not player then return end
    if arrival then return end
    if not U.isInteriorPlayer(player) then return end

    local index = Core.deckIndexOf(player)
    if not index then
        -- somewhere in the interior cell but off the deck stack entirely
        Core.beginArrival(player, 1, true)
        return
    end

    if not TARDIS.Build.deckCurrent(index) then
        Core.beginArrival(player, index, false)
        return
    end

    -- Built, but the player is over a hole with nothing under them.
    local sq = U.square(player:getX(), player:getY(), math.floor(player:getZ()), false)
    if sq and sq:getFloor() then
        Core.voidStrikes = 0
        return
    end

    local deck = C.Decks[index]
    local x, y, z = TARDIS.Build.arrivalSpot(deck)
    local landing = U.square(x, y, z, false)
    if landing and landing:getFloor() then
        Core.voidStrikes = 0
        U.teleport(player, x, y, z)
        return
    end

    -- Nothing under the player and nothing under the landing either: the deck
    -- is not habitable, so stop shuffling them around inside it.
    Core.voidStrikes = (Core.voidStrikes or 0) + 1
    if Core.voidStrikes >= 5 then
        Core.voidStrikes = 0
        Core.ejectToOutside("deck has no floor to stand on")
    end
end

Events.OnTick.Add(serviceArrival)
Events.EveryTenMinutes.Add(Core.refillWater)

local rescueTick = 0
local fieldTick = 0
Events.OnPlayerUpdate.Add(function(player)
    rescueTick = rescueTick + 1
    if rescueTick >= 10 then
        rescueTick = 0
        onPlayerUpdate(player)
    end
    -- The field runs whether or not anyone is aboard, so the doors stay clear
    -- and nothing gathers around the shell while it is parked.
    fieldTick = fieldTick + 1
    if fieldTick >= 20 then
        fieldTick = 0
        Core.repelZombies()
    end
end)

return Core
