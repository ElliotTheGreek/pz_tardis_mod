--[[ TARDIS -- the sonic screwdriver.

    Carrying one opens locks. There is nothing to aim and nothing to click:
    while the screwdriver is anywhere in the carrier's inventory, every lock
    within C.SonicRadius of them gives way -- house doors, player-built doors
    and gates, padlocks, keypads, window latches, car doors and boots.

    Two things shape how this is written.

    A sweep looks at every square in a square of side 2r+1, so it has to be
    cheap and it has to be rare. It reads each square's *special* object list
    rather than its full contents -- doors, windows and thumpables all live
    there and most squares have none -- and it only runs when the carrier
    steps onto a new square, never faster than C.SonicInterval ticks apart.

    And every engine call goes inside U.batch. A method name that does not
    exist throws out of Java and the engine dumps a stack trace per call; in
    a loop this size that is hundreds of dumps and a frozen game. One batch
    per object kind means one failure costs one warning and the rest of the
    sweep carries on.

    Locks that have been opened stay open. Nothing is re-locked when the
    screwdriver is put down: the field decides which locks give, not which
    doors stay shut afterwards.
]]

require "TARDIS/TARDIS_Config"
require "TARDIS/TARDIS_Util"

TARDIS = TARDIS or {}
local C = TARDIS.Config
local U = TARDIS.Util

local S = {}
TARDIS.Sonic = S

---------------------------------------------------------------------------
-- Carrying one
---------------------------------------------------------------------------
--- True when the player has a sonic screwdriver anywhere on them, bags
--- included. containsTypeRecurse compares the bare type, not the full id.
function S.carriedBy(player)
    if not player then return false end
    local inv = U.try("sonic.inventory", function() return player:getInventory() end)
    if not inv then return false end
    return U.try("sonic.contains", function()
        return inv:containsTypeRecurse(C.SonicType)
    end) == true
end

---------------------------------------------------------------------------
-- Opening one lock
---------------------------------------------------------------------------
-- Each of these does its whole job inside one batched call: reading the lock
-- state and clearing it are the same trip out to Java, so a wrong method
-- name breaks the batch once instead of throwing per square.

--- Map doors: locked outright, or wanting a key.
local function unlockDoor(o, join)
    return join(function()
        if not (o:isLocked() or o:isLockedByKey()) then return false end
        o:setLockedByKey(false)
        o:setIsLocked(false)
        return true
    end) == true
end

--- Player-built doors, gates and crates: key, padlock or keypad code.
---
--- Cleared the way the vanilla actions clear them -- setLockedByCode(0) and
--- setLockedByPadlock(false) with setKeyId(-1) -- minus the part where they
--- hand the padlock back to the player. The field defeats a lock; it does not
--- unscrew it and give you the hardware.
local function unlockThumpable(o, join)
    return join(function()
        local code = o:getLockedByCode() or 0
        if not (o:isLocked() or o:isLockedByKey() or o:isLockedByPadlock()
                or code > 0) then
            return false
        end
        o:setLockedByKey(false)
        o:setIsLocked(false)
        o:setLockedByPadlock(false)
        o:setKeyId(-1)
        o:setLockedByCode(0)
        return true
    end) == true
end

--- Window latches. A window painted or nailed permanently shut is left
--- alone: that is not a lock, it is how the map says this one never opens.
local function unlockWindow(o, join)
    return join(function()
        if not o:isLocked() then return false end
        o:setIsLocked(false)
        return true
    end) == true
end

--- Vehicle doors and boot. setLocked covers every door in one call, so there
--- is no need to walk the parts to reach them.
local function unlockVehicle(v, join)
    return join(function()
        if not (v:isAnyDoorLocked() or v:isTrunkLocked()) then return false end
        v:setLocked(false)
        v:setTrunkLocked(false)
        return true
    end) == true
end

--- The ignition. `isHotwired()` is exactly what the game's own menu gates
--- "Start Engine" on, so setting it is the whole job.
---
--- Deliberately not `tryHotwire(level)`, which is what the vanilla action
--- calls: that rolls against Electrical skill and, on a failure, sets
--- hotwiredBroken so the car can never be hotwired again. The field does not
--- roll dice, and it clears that flag if a previous attempt by hand set it.
local function hotwireVehicle(v, join)
    if not C.SonicHotwire then return false end
    return join(function()
        if v:isHotwired() and not v:isHotwiredBroken() then return false end
        v:setHotwiredBroken(false)
        v:setHotwired(true)
        return true
    end) == true
end

--- The battery. A hotwired car with a flat battery still does nothing, and
--- most abandoned cars are flat, so the field puts a full charge in.
---
--- Note where these live: `getBattery` and `getBatteryCharge` are on
--- **VehicleParts**, not on BaseVehicle, and `setUsedDelta` is on
--- DrainableComboItem, which is what a car battery is. `hasLiveBattery` is
--- the one cheap read on the vehicle itself, and it is false both for a flat
--- battery and for a car that has none fitted -- hence the two return values.
local function jumpVehicle(v, join)
    if not C.SonicJumpStart then return false, false end
    local charged, missing = false, false
    join(function()
        if v:hasLiveBattery() then return false end
        local parts = v:getParts()
        local battery = parts and parts:getBattery()
        local item = battery and battery:getInventoryItem()
        if not item then
            -- No battery fitted at all. Nothing to charge; the player needs
            -- to find one, and the log says so rather than staying quiet.
            missing = true
            return false
        end
        item:setUsedDelta(1.0)
        v:transmitPartUsedDelta(battery)
        charged = true
        return true
    end)
    return charged, missing
end

---------------------------------------------------------------------------
-- A sweep
---------------------------------------------------------------------------
--- One batch per kind of call, made fresh for each sweep. A batch that has
--- failed stays failed, which is what we want inside a sweep and not what we
--- want forever.
---
--- `scan` covers the reads that find things -- the door accessor, the special
--- object list -- and not just the writes that unlock them. U.try is not
--- enough for those: it silences the *Lua* warning after the first failure
--- but keeps calling, and the engine keeps dumping a Java stack trace every
--- time. One bad call in this loop wrote 1932 of them before it was caught.
local function batches()
    return {
        scan    = U.batch("sonic.scan"),
        door    = U.batch("sonic.door"),
        thump   = U.batch("sonic.thumpable"),
        window  = U.batch("sonic.window"),
        vehicle = U.batch("sonic.vehicle"),
        hotwire = U.batch("sonic.hotwire"),
        battery = U.batch("sonic.battery"),
    }
end

local function unlockObject(o, join)
    -- Order matters: IsoThumpable is not an IsoDoor, but check the specific
    -- types before falling through to anything broader.
    if instanceof(o, "IsoDoor") then
        return unlockDoor(o, join.door)
    elseif instanceof(o, "IsoThumpable") then
        return unlockThumpable(o, join.thump)
    elseif instanceof(o, "IsoWindow") then
        return unlockWindow(o, join.window)
    end
    return false
end

--- Doors, gates and windows live in a square's special-object list, which is
--- empty for almost every square. Walking that instead of the full contents
--- is what makes a sweep of a thousand squares affordable.
local function unlockSquare(sq, join, tally)
    -- A square's own door accessor, checked as well as the special list.
    -- Belt and braces on purpose: if a door were ever *not* in the special
    -- objects the whole feature would do nothing and report nothing, which is
    -- the worst failure this codebase has. unlockDoor is idempotent, so a
    -- door reached both ways is opened once and counted once.
    local door = join.scan(function() return sq:getIsoDoor() end)
    if door and unlockDoor(door, join.door) then tally.doors = tally.doors + 1 end

    -- Vehicles are found the same way the game's own vehicle menu finds them:
    -- every square a vehicle stands on reports it. Walking the cell's vehicle
    -- list is not an option -- getVehicles() hands back a java.util.Set, which
    -- has no indexed get() whatever the game's own Lua looks like it is doing.
    --
    -- A truck covers a dozen squares and so is offered here a dozen times.
    -- Keyed on the vehicle itself, so each is considered once and the log can
    -- say how many were *found* as well as how many were opened -- which is
    -- the difference between "the sweep never saw your truck" and "your truck
    -- was not locked in the first place".
    local vehicle = join.scan(function() return sq:getVehicleContainer() end)
    if vehicle and not tally.seen[vehicle] then
        tally.seen[vehicle] = true
        tally.found = tally.found + 1
        if unlockVehicle(vehicle, join.vehicle) then
            tally.vehicles = tally.vehicles + 1
        end
        if hotwireVehicle(vehicle, join.hotwire) then
            tally.hotwired = tally.hotwired + 1
        end
        local charged, missing = jumpVehicle(vehicle, join.battery)
        if charged then tally.jumped = tally.jumped + 1 end
        if missing then tally.noBattery = tally.noBattery + 1 end
    end

    local special = join.scan(function() return sq:getSpecialObjects() end)
    if not special then
        -- Odd squares, or a scan batch that has already given up.
        U.eachObject(sq, function(o)
            if unlockObject(o, join) then tally.doors = tally.doors + 1 end
        end)
        return
    end

    local n = join.scan(function() return special:size() end) or 0
    for i = 0, n - 1 do
        local o = join.scan(function() return special:get(i) end)
        if o and unlockObject(o, join) then tally.doors = tally.doors + 1 end
    end
end

--- Opens every lock within reach of a position, and makes every vehicle in
--- reach drivable. Returns a tally rather than a row of numbers, because the
--- counts are the diagnostic: `found` against `vehicles` separates "never saw
--- your truck" from "your truck was not locked", and `noBattery` explains a
--- car that still will not start.
---
---     doors      fixed locks opened -- doors, gates, windows
---     found      vehicles the sweep saw
---     vehicles   of those, ones that were locked and now are not
---     hotwired   of those, ones whose ignition was bypassed
---     jumped     of those, ones whose flat battery was charged
---     noBattery  of those, ones with no battery fitted at all
function S.sweepAt(px, py, pz)
    local join = batches()
    local tally = {
        doors = 0, found = 0, vehicles = 0,
        hotwired = 0, jumped = 0, noBattery = 0, seen = {},
    }
    local r = C.SonicRadius

    for dx = -r, r do
        for dy = -r, r do
            local sq = U.square(px + dx, py + dy, pz, false)
            if sq then unlockSquare(sq, join, tally) end
        end
    end

    return tally
end

--- Sweeps around a player, if they are carrying a screwdriver.
function S.sweep(player)
    if not player then return 0 end
    if not S.carriedBy(player) then return 0 end
    -- Nothing aboard the ship is locked, and its decks are the most expensive
    -- squares in the world to walk.
    if U.isInteriorPlayer(player) then return 0 end

    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local pz = math.floor(player:getZ())
    local t = S.sweepAt(px, py, pz)
    local cars = t.vehicles + t.hotwired + t.jumped
    local opened = t.doors + cars

    if opened > 0 then
        U.log("sonic: %d lock(s) opened; of %d vehicle(s): %d unlocked, %d hotwired, "
              .. "%d jumped, %d with no battery -- around %d,%d,%d",
              t.doors, t.found, t.vehicles, t.hotwired, t.jumped, t.noBattery,
              px, py, pz)
        local text = getText("IGUI_TARDIS_SonicOpened", t.doors)
        if cars > 0 then
            -- A car that was hotwired or jumped is ready to drive, which is
            -- the thing worth saying; being unlocked is only half of it.
            local ready = math.max(t.hotwired, t.jumped)
            text = ready > 0 and getText("IGUI_TARDIS_SonicVehicleReady", ready)
                   or getText("IGUI_TARDIS_SonicVehicle", t.vehicles)
        end
        U.try("sonic.note", function()
            player:setHaloNote(text, 150, 210, 255, 200)
        end)
    end

    -- Worth its own line: the field did everything it could and the car still
    -- will not go, because there is no battery in it to charge.
    if t.noBattery > 0 and cars == 0 then
        U.log("sonic: %d vehicle(s) have no battery fitted; nothing to charge",
              t.noBattery)
    end
    return opened
end

---------------------------------------------------------------------------
-- When to sweep
---------------------------------------------------------------------------
-- Standing still costs one sweep every C.SonicInterval ticks. Walking costs
-- one per square entered, but never two closer together than a fifth of a
-- second, so sprinting past a terrace of houses does not sweep per frame.
local MIN_GAP = 12

local last = { x = nil, y = nil, z = nil, gap = 0, idle = 0 }

local function onPlayerUpdate(player)
    if not player then return end

    last.gap = last.gap + 1
    last.idle = last.idle + 1

    local x = math.floor(player:getX())
    local y = math.floor(player:getY())
    local z = math.floor(player:getZ())
    local moved = x ~= last.x or y ~= last.y or z ~= last.z

    if moved then
        if last.gap < MIN_GAP then return end
    elseif last.idle < C.SonicInterval then
        return
    end

    last.x, last.y, last.z = x, y, z
    last.gap, last.idle = 0, 0
    S.sweep(player)
end

Events.OnPlayerUpdate.Add(onPlayerUpdate)

--- Exposed for the debug console: TARDIS_Sonic()
function TARDIS_Sonic()
    local player = U.player(0)
    if not player then return 0 end
    local t = S.sweepAt(math.floor(player:getX()), math.floor(player:getY()),
                        math.floor(player:getZ()))
    -- Stand beside the thing that will not go and run this. `found` says
    -- whether the sweep saw it at all; the rest says what it did about it.
    U.log("sonic: forced sweep -- %d lock(s) opened; %d vehicle(s) found, "
          .. "%d unlocked, %d hotwired, %d jumped, %d with no battery",
          t.doors, t.found, t.vehicles, t.hotwired, t.jumped, t.noBattery)
    return t.doors + t.vehicles + t.hotwired + t.jumped
end

return S
