--[[ TARDIS -- the sonic screwdriver.

    Carrying one lets you open locks. Right-click a locked door, gate, window
    or vehicle and choose the sonic screwdriver: the character walks over if
    it is out of reach (C.SonicReach), works at it for a moment with a
    progress bar like any other timed action, and the lock gives way -- house
    doors, player-built doors and gates, padlocks, keypads, window latches,
    car doors and boots, and a vehicle's ignition and battery as well.

    Up to 2.0.0 it was a field: every lock within C.SonicRadius of the carrier
    opened on its own. Players asked for it to be something you *use*, so that
    is now off by default and kept behind C.SonicAuto. The sweep below is what
    the field ran, and TARDIS_Sonic() still runs one from the debug console.

    Two things shape how the sweep is written.

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
require "TimedActions/ISBaseTimedAction"

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
-- Using it on one thing
---------------------------------------------------------------------------
-- Read-only: what the right-click menu needs to decide whether to offer the
-- screwdriver at all. Each read goes through the batch it is given, for the
-- same reason the unlocks do.
local function lockedObject(o, scan)
    return scan(function()
        if instanceof(o, "IsoDoor") then
            return o:isLocked() or o:isLockedByKey()
        elseif instanceof(o, "IsoThumpable") then
            return o:isLocked() or o:isLockedByKey() or o:isLockedByPadlock()
                or (o:getLockedByCode() or 0) > 0
        elseif instanceof(o, "IsoWindow") then
            return o:isLocked()
        end
        return false
    end) == true
end

--- True when the screwdriver has something to do to a vehicle: a lock, the
--- ignition, or a flat battery that is actually fitted.
local function vehicleNeedsWork(v, scan)
    return scan(function()
        if v:isAnyDoorLocked() or v:isTrunkLocked() then return true end
        if C.SonicHotwire and (not v:isHotwired() or v:isHotwiredBroken()) then return true end
        if C.SonicJumpStart and not v:hasLiveBattery() then
            local battery = v:getParts() and v:getParts():getBattery()
            return battery ~= nil and battery:getInventoryItem() ~= nil
        end
        return false
    end) == true
end

--- What a right-click on `sq` could use the screwdriver on. `worldobjects`
--- is the menu's own list of what was clicked; the square's door and special
--- objects are read as well, since a click on a door frame does not always
--- put the door in that list. Vehicles are taken from the clicked square or
--- one next to it -- a car is a big thing to click and an easy one to miss by
--- a square. Returns nil when there is nothing locked there.
function S.targetAt(sq, worldobjects)
    if not sq then return nil end
    local scan = U.batch("sonic.target")
    local locks, seen = {}, {}
    local function consider(o)
        if o and not seen[o] then
            seen[o] = true
            if lockedObject(o, scan) then table.insert(locks, o) end
        end
    end
    for _, o in ipairs(worldobjects or {}) do consider(o) end
    consider(scan(function() return sq:getIsoDoor() end))
    local special = scan(function() return sq:getSpecialObjects() end)
    local n = special and scan(function() return special:size() end) or 0
    for i = 0, n - 1 do consider(scan(function() return special:get(i) end)) end

    local vehicle = scan(function() return sq:getVehicleContainer() end)
    if not vehicle then
        for dx = -1, 1 do
            for dy = -1, 1 do
                local near = not vehicle and U.square(sq:getX() + dx, sq:getY() + dy, sq:getZ(), false)
                if near then vehicle = scan(function() return near:getVehicleContainer() end) end
            end
        end
    end
    if vehicle and not vehicleNeedsWork(vehicle, scan) then vehicle = nil end

    if #locks == 0 and not vehicle then return nil end
    return { sq = sq, locks = locks, vehicle = vehicle }
end

--- Does the work on one target and says what happened. The same unlocks the
--- sweep uses, so the two cannot drift apart.
local function applyTo(player, target)
    local join = batches()
    local t = { doors = 0, found = 0, vehicles = 0, hotwired = 0, jumped = 0, noBattery = 0 }
    for _, o in ipairs(target.locks) do
        if unlockObject(o, join) then t.doors = t.doors + 1 end
    end
    local v = target.vehicle
    if v then
        t.found = 1
        if unlockVehicle(v, join.vehicle) then t.vehicles = 1 end
        if hotwireVehicle(v, join.hotwire) then t.hotwired = 1 end
        local charged, missing = jumpVehicle(v, join.battery)
        if charged then t.jumped = 1 end
        if missing then t.noBattery = 1 end
    end
    U.log("sonic: used at %d,%d,%d -- %d lock(s) opened; vehicle: %d unlocked, "
          .. "%d hotwired, %d jumped, %d with no battery",
          target.sq:getX(), target.sq:getY(), target.sq:getZ(),
          t.doors, t.vehicles, t.hotwired, t.jumped, t.noBattery)
    local text
    if t.hotwired + t.jumped > 0 then
        text = getText("IGUI_TARDIS_SonicVehicleReady", 1)
    elseif t.vehicles > 0 then
        text = getText("IGUI_TARDIS_SonicVehicle", 1)
    elseif t.doors > 0 then
        text = getText("IGUI_TARDIS_SonicOpened", t.doors)
    end
    if text then
        U.try("sonic.note", function() player:setHaloNote(text, 150, 210, 255, 200) end)
    end
    return t
end

-- The timed action: a moment spent working the lock, with the progress bar,
-- the same way moving an item takes a moment. Walking or aiming cancels it.
TARDISSonicAction = ISBaseTimedAction:derive("TARDISSonicAction")

function TARDISSonicAction:isValid()
    if not S.carriedBy(self.character) then return false end
    for _, o in ipairs(self.target.locks) do
        if U.try("sonic.valid", function() return o:getObjectIndex() end) ~= -1 then return true end
    end
    return self.target.vehicle ~= nil
end

function TARDISSonicAction:face()
    local what = self.target.vehicle or self.target.locks[1]
    U.try("sonic.face", function() self.character:faceThisObject(what) end)
end

function TARDISSonicAction:start()
    self:face()
    self:setActionAnim(self.target.vehicle and "VehicleWorkOnMid" or "Loot")
end

function TARDISSonicAction:update()
    self:face()
end

function TARDISSonicAction:stop()
    ISBaseTimedAction.stop(self)
end

function TARDISSonicAction:perform()
    applyTo(self.character, self.target)
    -- A door clicks open the way a key would have opened it.
    local door = self.target.locks[1]
    if door and instanceof(door, "IsoDoor") then
        U.try("sonic.sound", function()
            local props = door:getSprite() and door:getSprite():getProperties()
            local prefix = props and props:has("DoorSound") and props:get("DoorSound") or "WoodDoor"
            self.character:getEmitter():playSound(prefix .. "Unlock")
        end)
    end
    -- needed to remove from queue / start next.
    ISBaseTimedAction.perform(self)
end

function TARDISSonicAction:new(character, target)
    local o = ISBaseTimedAction.new(self, character)
    o.target = target
    o.maxTime = target.vehicle and C.SonicVehicleTime or C.SonicLockTime
    return o
end

--- Queues the screwdriver on a target: a walk first if it is out of reach,
--- then the action itself.
function S.use(player, target)
    local v = target.vehicle
    local far
    if v then
        far = (U.try("sonic.dist", function() return player:DistTo(v) end) or 0) > C.SonicReach
    else
        far = (U.try("sonic.dist", function()
            return player:DistTo(target.sq:getX(), target.sq:getY())
        end) or 0) > C.SonicReach
            or math.floor(player:getZ()) ~= target.sq:getZ()
    end
    ISTimedActionQueue.clear(player)
    if far then
        if v then
            ISTimedActionQueue.add(ISPathFindAction:pathToVehicleAdjacent(player, v))
        elseif not luautils.walkAdjWindowOrDoor(player, target.sq, target.locks[1], true) then
            luautils.walkAdj(player, target.sq, true)
        end
    end
    ISTimedActionQueue.add(TARDISSonicAction:new(player, target))
end

---------------------------------------------------------------------------
-- When to sweep (only with C.SonicAuto)
---------------------------------------------------------------------------
-- Standing still costs one sweep every C.SonicInterval ticks. Walking costs
-- one per square entered, but never two closer together than a fifth of a
-- second, so sprinting past a terrace of houses does not sweep per frame.
local MIN_GAP = 12

local last = { x = nil, y = nil, z = nil, gap = 0, idle = 0 }

local function onPlayerUpdate(player)
    if not player or not C.SonicAuto then return end

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
