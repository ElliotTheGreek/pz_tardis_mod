--[[ TARDIS -- in-game self test.

    Only runs when the game is started with -debug, so ordinary play never
    sees it. Run it by hand from the debug Lua console with TARDIS_SelfTest().

    It has to be a step machine rather than a straight function: decks cannot
    be built until the player is standing in the interior and its chunks have
    streamed in, so most steps have to wait for the world before they can
    check anything. Each step returns done, wait or fail, and the runner
    advances one step per tick.
]]

require "TARDIS/TARDIS_Config"
require "TARDIS/TARDIS_Util"

TARDIS = TARDIS or {}
local C = TARDIS.Config
local U = TARDIS.Util

local DONE, WAIT, FAIL = "done", "wait", "fail"
local STEP_TIMEOUT = 900          -- ticks any single step may wait

local run = nil

local function check(name, condition, detail)
    if condition then
        run.pass = run.pass + 1
        print("TARDIS-TEST PASS  " .. name)
    else
        run.fail = run.fail + 1
        print("TARDIS-TEST FAIL  " .. name .. "  " .. tostring(detail or ""))
    end
    return condition and true or false
end

local function info(fmt, ...)
    local msg = fmt
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, fmt, ...)
        if ok then msg = s end
    end
    print("TARDIS-TEST INFO  " .. msg)
end

---------------------------------------------------------------------------
-- Checks used by the steps
---------------------------------------------------------------------------
local function checkDeckShell(index)
    local deck = C.Decks[index]
    local rx, ry = U.deckOrigin(deck)
    local id = deck.id

    -- Only sample squares the floor plan actually includes: the chamfered
    -- corners of an octagonal deck are meant to be empty.
    local missing, sampled = 0, 0
    for ox = 1, C.RoomSize - 1, 2 do
        for oy = 1, C.RoomSize - 1, 2 do
            if C.inShape(ox, oy, deck.shape, C.RoomSize, deck.chamfer) then
                sampled = sampled + 1
                local sq = U.square(rx + ox, ry + oy, deck.z, false)
                if not sq or not sq:getFloor() then missing = missing + 1 end
            end
        end
    end
    check("deck." .. id .. ".floor", missing == 0,
          missing .. " of " .. sampled .. " in-shape squares lack floor")

    -- Walk east along the middle row to the first square inside the room;
    -- its west edge is the west wall, wherever the chamfer put it.
    local wallOK = false
    for ox = 0, C.RoomSize do
        if C.inShape(ox, 12, deck.shape, C.RoomSize, deck.chamfer) then
            local sq = U.square(rx + ox, ry + 12, deck.z, false)
            wallOK = sq ~= nil and U.findSprite(sq, C.Sprites.wallW) ~= nil
            break
        end
    end
    check("deck." .. id .. ".wallW", wallOK, "no wall on the western edge")

    -- Decks are joined by the context menu, not by geometry, so what has to
    -- hold is that the landing and the alcove doorway are both walkable.
    local ax, ay, az = TARDIS.Build.arrivalSpot(deck)
    local land = U.square(ax, ay, az, false)
    check("deck." .. id .. ".landing", land ~= nil and land:getFloor() ~= nil,
          "no floor on the arrival spot at " .. ax .. "," .. ay)

    -- The landing and the ring around it must stay walkable: arriving into a
    -- bookcase, or onto a square with no floor, is the one failure that
    -- strands a player.
    local blocked = 0
    for dx = -C.Landing.clearance, C.Landing.clearance do
        for dy = -C.Landing.clearance, C.Landing.clearance do
            local lx, ly = rx + C.Landing.x + dx, ry + C.Landing.y + dy
            local sq = U.square(lx, ly, deck.z, false)
            if not sq or not sq:getFloor() or sq:isSolid() then
                blocked = blocked + 1
            end
        end
    end
    check("deck." .. id .. ".landingClear", blocked == 0,
          blocked .. " squares around the landing are blocked or floorless")
end

local function checkDeckContents(index)
    local deck = C.Decks[index]
    local rx, ry = U.deckOrigin(deck)
    local containers, stocked, items = 0, 0, 0

    for ox = 0, C.RoomSize do
        for oy = 0, C.RoomSize do
            local sq = U.square(rx + ox, ry + oy, deck.z, false)
            if sq then
                U.eachObject(sq, function(o)
                    local c = U.containerOf(o)
                    if c then
                        containers = containers + 1
                        local n = U.try("items", function() return c:getItems():size() end)
                        if n and n > 0 then
                            stocked = stocked + 1
                            items = items + n
                        end
                    end
                end)
            end
        end
    end

    if deck.id ~= "console" then
        check("deck." .. deck.id .. ".containers", containers > 0, "no containers placed")
        check("deck." .. deck.id .. ".stocked", stocked > 0,
              containers .. " containers, none stocked")
    end
    info("deck %s: %d containers, %d stocked, %d items", deck.id, containers, stocked, items)
end

--- Nothing may sit above a deck, or the engine draws it over the player --
--- that is the whole reason the decks step sideways as they descend. And the
--- ring around each deck must be stripped bare, or the ship reads as a tower
--- standing in a forest.
local function checkDeckSite(index)
    local deck = C.Decks[index]
    local rx, ry = U.deckOrigin(deck)

    -- every level above this deck, across its whole footprint, must be empty
    local overhead = 0
    for z = deck.z + 1, C.TopZ do
        for ox = 0, C.RoomSize, 6 do
            for oy = 0, C.RoomSize, 6 do
                local sq = U.square(rx + ox, ry + oy, z, false)
                if sq and sq:getFloor() then overhead = overhead + 1 end
            end
        end
    end
    check("deck." .. deck.id .. ".nothingOverhead", overhead == 0,
          overhead .. " floored squares found above this deck")

    -- sample the margin: nothing at all should be left out there
    local leftovers, sampled = 0, 0
    local m = C.ClearMargin
    for _, off in ipairs({ -m + 2, -4, C.RoomSize + 4, C.RoomSize + m - 2 }) do
        for oy = -m + 2, C.RoomSize + m - 2, 6 do
            local sq = U.square(rx + off, ry + oy, deck.z, false)
            if sq then
                sampled = sampled + 1
                if sq:getFloor() then leftovers = leftovers + 1 end
            end
        end
    end
    if sampled > 0 then
        check("deck." .. deck.id .. ".voidMargin", leftovers == 0,
              leftovers .. " of " .. sampled .. " sampled margin squares still have ground")
    end
end

---------------------------------------------------------------------------
-- Steps
---------------------------------------------------------------------------
local function buildSteps(player)
    local steps = {}

    local function add(name, fn) table.insert(steps, { name = name, fn = fn }) end

    add("config", function()
        check("config.decks", #C.Decks == 6, "expected 6 decks, got " .. #C.Decks)
        local rx, ry = U.deckOrigin(C.Decks[1])
        check("config.origin", rx > 0 and ry > 0, rx .. "," .. ry)
        check("config.interiorTest", U.isInterior(rx + 5, ry + 5), "origin not inside cell")
        check("config.exteriorTest", not U.isInterior(10000, 10000), "false positive")
        return DONE
    end)

    add("materialise", function()
        local px, py, pz = player:getX(), player:getY(), math.floor(player:getZ())
        local target = nil
        for r = 1, 8 do
            for dx = -r, r do
                for dy = -r, r do
                    local sq = U.square(px + dx, py + dy, pz, false)
                    if not target and sq and TARDIS.Core.canMaterialise(sq) then
                        target = sq
                    end
                end
            end
        end
        if not check("doors.landingSquare", target ~= nil, "nowhere to materialise") then
            return FAIL
        end
        check("doors.materialise", TARDIS.Core.materialise(target, player) == true,
              "materialise returned false")
        check("doors.exteriorPresent", TARDIS.Core.exteriorOn(target) ~= nil,
              "shell not on the square afterwards")
        return DONE
    end)

    -- Materialising again must lift the old shell, not leave it standing.
    -- Two halves, because they fail for different reasons: the ordinary move,
    -- and the repair path for a shell whose chunk was not loaded at the time.
    add("rematerialise", function()
        local s = U.state()
        local oldX, oldY, oldZ = s.x, s.y, s.z

        -- somewhere else nearby to move it to
        local target = nil
        for r = 2, 8 do
            for dx = -r, r do
                for dy = -r, r do
                    local sq = U.square(oldX + dx, oldY + dy, oldZ, false)
                    if not target and sq and (sq:getX() ~= oldX or sq:getY() ~= oldY)
                       and TARDIS.Core.canMaterialise(sq) then
                        target = sq
                    end
                end
            end
        end
        if not target then
            info("rematerialise: nowhere else to move the shell to")
            return DONE
        end

        check("doors.rematerialise",
              TARDIS.Core.materialise(target, player) == true, "returned false")

        local oldSq = U.square(oldX, oldY, oldZ, false)
        check("doors.oldShellGone",
              oldSq ~= nil and TARDIS.Core.exteriorOn(oldSq) == nil,
              "a shell is still standing at " .. oldX .. "," .. oldY)

        -- and exactly one in the whole area, not two
        local shells = 0
        for dx = -12, 12 do
            for dy = -12, 12 do
                local sq = U.square(oldX + dx, oldY + dy, oldZ, false)
                if sq and TARDIS.Core.exteriorOn(sq) then shells = shells + 1 end
            end
        end
        check("doors.oneShell", shells == 1, shells .. " shells found, expected 1")

        -- The repair path. Stand a decoy shell somewhere the ship is not,
        -- write it down the way a flight would, and prove the sweep clears
        -- it. This is the half that was broken: an unreachable shell used to
        -- be forgotten rather than remembered.
        local decoy = nil
        for r = 2, 8 do
            for dx = -r, r do
                for dy = -r, r do
                    local sq = U.square(s.x + dx, s.y + dy, s.z, false)
                    if not decoy and sq and TARDIS.Core.canMaterialise(sq) then
                        decoy = sq
                    end
                end
            end
        end
        if not decoy then
            info("rematerialise: no room to stand a decoy shell")
            return DONE
        end

        U.try("decoy", function()
            decoy:AddWorldInventoryItem(C.ExteriorItem, 0.5, 0.5, 0.0)
        end)
        local dx, dy, dz = decoy:getX(), decoy:getY(), decoy:getZ()
        check("doors.decoyPlaced", TARDIS.Core.exteriorOn(decoy) ~= nil,
              "could not stand a decoy shell to test the sweep")

        TARDIS.Core.forgetExterior(dx, dy, dz)
        local pending = #s.ghosts
        check("doors.ghostRecorded", pending > 0, "the shell was not written down")

        TARDIS.Core.sweepGhosts()
        check("doors.ghostSwept", TARDIS.Core.exteriorOn(decoy) == nil,
              "the sweep left the shell at " .. dx .. "," .. dy)
        check("doors.ghostListCleared", #s.ghosts == 0,
              #s.ghosts .. " entries left in the ghost list")
        return DONE
    end)

    add("enter", function()
        check("doors.enter", TARDIS.Core.enter(player) == true, "enter returned false")
        return DONE
    end)

    -- One pair of steps per deck: wait for it to be built, then inspect it.
    for i = 1, #C.Decks do
        local index = i
        local deck = C.Decks[index]

        if index > 1 then
            add("descend to " .. deck.id, function()
                check("doors.descend." .. deck.id,
                      TARDIS.Core.changeDeck(player, 1) == true, "changeDeck failed")
                return DONE
            end)
        end

        add("build " .. deck.id, function(elapsed)
            local built = U.state().builtDecks[tostring(index)]
            if not built then
                if elapsed == 1 then
                    info("waiting for %s chunks to stream in", deck.id)
                end
                return WAIT
            end
            check("deck." .. deck.id .. ".built", true)
            check("deck." .. deck.id .. ".playerZ",
                  math.floor(player:getZ()) == deck.z,
                  "expected z " .. deck.z .. ", got " .. player:getZ())
            checkDeckShell(index)
            checkDeckContents(index)
            checkDeckSite(index)
            return DONE
        end)

        -- Only checkable while the console deck is the one streamed in, so
        -- it rides along with that deck rather than waiting until the end.
        if index == 1 then
            add("sonic case", function()
                local rx, ry = U.deckOrigin(deck)
                local sq = U.square(rx + C.SonicBox.x, ry + C.SonicBox.y, deck.z, false)
                local held = 0
                if sq then
                    U.eachObject(sq, function(o)
                        local md = o:getModData()
                        if not (md and md.TARDIS == "sonic") then return end
                        local c = U.containerOf(o)
                        if not c then return end
                        U.try("sonicItems", function()
                            local items = c:getItems()
                            for i = 0, items:size() - 1 do
                                local it = items:get(i)
                                if it and it:getFullType() == C.SonicItem then
                                    held = held + 1
                                end
                            end
                        end)
                    end)
                end
                check("sonic.case", held == C.SonicCount,
                      "expected " .. C.SonicCount .. " screwdrivers beside the console, found "
                      .. held)
                return DONE
            end)
        end
    end

    add("water", function()
        TARDIS.Core.refillWater()
        local found, filled = 0, 0
        for _, idx in ipairs({ 2, 5, 6 }) do
            local deck = C.Decks[idx]
            local rx, ry = U.deckOrigin(deck)
            for ox = 0, C.RoomSize do
                for oy = 0, C.RoomSize do
                    local sq = U.square(rx + ox, ry + oy, deck.z, false)
                    if sq then
                        U.eachObject(sq, function(o)
                            local md = o:getModData()
                            if md and md.TARDIS == "sink" then
                                found = found + 1
                                local a = U.try("amt", function() return o:getFluidAmount() end)
                                if a and a > 0 then filled = filled + 1 end
                            end
                        end)
                    end
                end
            end
        end
        check("water.fixtures", found > 0, "no sinks found")
        check("water.filled", filled > 0, found .. " sinks, none holding water")
        info("water: %d sinks, %d holding water", found, filled)
        return DONE
    end)

    add("crops", function()
        if not SFarmingSystem or not SFarmingSystem.instance then
            info("crops: farming system unavailable")
            return DONE
        end
        local deck = C.Decks[6]
        local rx, ry = U.deckOrigin(deck)
        local plants = 0
        for ox = 2, 13 do
            for oy = 2, 21 do
                local sq = U.square(rx + ox, ry + oy, deck.z, false)
                if sq then
                    local p = U.try("cropAt", function()
                        return SFarmingSystem.instance:getLuaObjectOnSquare(sq)
                    end)
                    if p then plants = plants + 1 end
                end
            end
        end
        check("crops.sown", plants > 0, "no plots on the hydroponics deck")
        info("crops: %d plots", plants)
        return DONE
    end)

    add("ascend", function()
        check("doors.ascend", TARDIS.Core.changeDeck(player, -1) == true, "changeDeck up failed")
        return DONE
    end)

    add("exit", function()
        check("doors.exit", TARDIS.Core.exit(player) == true, "exit returned false")
        return DONE
    end)

    add("outside", function()
        if U.isInteriorPlayer(player) then return WAIT end
        check("doors.outside", true)
        return DONE
    end)

    -- Prove the field actually turns a lock. It has to run out here: nothing
    -- inside the ship is locked, so there is nothing in there to open.
    add("sonic field", function()
        local px = math.floor(player:getX())
        local py = math.floor(player:getY())
        local pz = math.floor(player:getZ())

        -- One pass for both: the nearest door to lock and test with, and any
        -- vehicle in reach to assert the state of afterwards.
        local door, car = nil, nil
        for r = 1, C.SonicRadius do
            for dx = -r, r do
                for dy = -r, r do
                    local dsq = (not door or not car)
                                and U.square(px + dx, py + dy, pz, false) or nil
                    if dsq and not door then
                        door = U.try("sonicDoor", function()
                            return dsq:getIsoDoor()
                        end) or nil
                    end
                    if dsq and not car then
                        car = U.try("sonicCar", function()
                            return dsq:getVehicleContainer()
                        end) or nil
                    end
                end
            end
        end

        if not door then
            info("sonic: no door within %d tiles to test against", C.SonicRadius)
            return DONE
        end

        U.try("sonicLock", function() door:setLockedByKey(true) end)
        local before = U.try("sonicWasLocked", function()
            return door:isLockedByKey()
        end) == true
        local t = TARDIS.Sonic.sweepAt(px, py, pz)
        local after = U.try("sonicNowLocked", function()
            return door:isLockedByKey() or door:isLocked()
        end) == true

        check("sonic.locks", before, "could not lock a door to test with")
        check("sonic.unlocks", before and not after,
              "still locked after a sweep that opened " .. t.doors)
        info("sonic: sweep opened %d lock(s) within %d tiles; %d vehicle(s) found, "
             .. "%d unlocked, %d hotwired, %d jumped",
             t.doors, C.SonicRadius, t.found, t.vehicles, t.hotwired, t.jumped)

        -- Assert the vehicle's *state*, not what this sweep changed: a
        -- passive sweep may well have got to it first, which would leave the
        -- deltas at zero with everything working perfectly.
        if car then
            local locked = U.try("carLocked", function()
                return car:isAnyDoorLocked()
            end) == true
            check("sonic.vehicleUnlocked", not locked, "vehicle still locked")

            if C.SonicHotwire then
                local wired = U.try("carHotwired", function()
                    return car:isHotwired() and not car:isHotwiredBroken()
                end) == true
                check("sonic.vehicleHotwired", wired, "vehicle ignition not bypassed")
            end
            if C.SonicJumpStart then
                local live = U.try("carBattery", function()
                    return car:hasLiveBattery()
                end) == true
                -- A car with no battery fitted cannot be jumped, and that is
                -- not a failure of the field.
                check("sonic.vehicleBattery", live or t.noBattery > 0,
                      "battery still flat and one is fitted")
            end
        else
            info("sonic: no vehicle within %d tiles to test against", C.SonicRadius)
        end
        return DONE
    end)

    add("field", function()
        local s = U.state()
        local pushed = TARDIS.Core.repelZombies()
        info("field: pushed %d zombies out of %d tiles", pushed, C.FieldRadius)

        local cell = U.cell()
        local intruders = 0
        U.try("fieldCheck", function()
            local list = cell:getZombieList()
            for i = 0, list:size() - 1 do
                local z = list:get(i)
                if z and math.floor(z:getZ()) == s.z then
                    local dx, dy = z:getX() - s.x, z:getY() - s.y
                    if math.sqrt(dx * dx + dy * dy) <= C.FieldRadius then
                        intruders = intruders + 1
                    end
                end
            end
        end)
        check("field.clear", intruders == 0,
              intruders .. " zombies still inside the field")
        return DONE
    end)

    add("bookmarks", function()
        local s = U.state()
        local before = #s.bookmarks
        check("bookmark.add", TARDIS.Travel.addBookmark("selftest") == true, "add failed")
        check("bookmark.stored", #s.bookmarks == before + 1, "list did not grow")
        local last = s.bookmarks[#s.bookmarks]
        check("bookmark.position", last and last.x == s.x and last.y == s.y,
              "bookmark does not match the ship position")
        check("bookmark.destination",
              TARDIS.Travel.setDestination(last.x, last.y, last.z) == true, "set failed")
        check("bookmark.destinationStored", s.destination ~= nil, "destination missing")
        s.destination = nil
        TARDIS.Travel.removeBookmark(#s.bookmarks)
        check("bookmark.remove", #s.bookmarks == before, "list did not shrink")
        return DONE
    end)

    return steps
end

---------------------------------------------------------------------------
-- Runner
---------------------------------------------------------------------------
local function tickRun()
    if not run then return end
    local step = run.steps[run.at]
    if not step then
        print(string.format("TARDIS-TEST ==== done: %d passed, %d failed ====",
                            run.pass, run.fail))
        run = nil
        return
    end

    run.elapsed = run.elapsed + 1
    local ok, result = pcall(step.fn, run.elapsed)
    if not ok then
        run.fail = run.fail + 1
        print("TARDIS-TEST FAIL  " .. step.name .. " crashed: " .. tostring(result))
        result = DONE          -- move on rather than crash here every tick
    end

    if result == WAIT then
        if run.elapsed > STEP_TIMEOUT then
            run.fail = run.fail + 1
            print("TARDIS-TEST FAIL  " .. step.name .. "  timed out after " ..
                  run.elapsed .. " ticks")
            run.at = run.at + 1
            run.elapsed = 0
        end
        return
    end

    if result == FAIL then
        print("TARDIS-TEST INFO  aborting after " .. step.name)
        print(string.format("TARDIS-TEST ==== done: %d passed, %d failed ====",
                            run.pass, run.fail))
        run = nil
        return
    end

    run.at = run.at + 1
    run.elapsed = 0
end

function TARDIS_SelfTest()
    local player = U.player(0)
    if not player then
        print("TARDIS-TEST FAIL  no player")
        return
    end
    print("TARDIS-TEST ==== begin, mod version " .. C.Version .. " ====")
    U.state().selfTestDone = true
    run = { steps = buildSteps(player), at = 1, elapsed = 0, pass = 0, fail = 0 }
end

-- Auto-run in debug sessions, a few seconds after the world settles.
local countdown = nil
local function onGameStart()
    local debugOn = false
    if getDebug then debugOn = getDebug() == true end
    if not debugOn and isDebugEnabled then debugOn = isDebugEnabled() == true end
    if not debugOn then return end

    -- Never hijack a world somebody is actually playing. The test flies the
    -- character off to the interior and walks them through every deck, which
    -- is fine on a fresh world and thoroughly unwelcome on a save where the
    -- ship is already in use.
    local s = U.state()
    if s.placed or s.selfTestDone then
        print("TARDIS-TEST skipped (ship already in use here) -- " ..
              "run TARDIS_SelfTest() from the debug console to force it")
        return
    end

    countdown = 240
    print("TARDIS-TEST scheduled (debug mode, fresh world)")
end

-- The self test drives the whole mod, so a mistake in it can throw on every
-- single tick. Unhandled, that floods the log and locks the game up hard
-- enough to look like a crash -- which is exactly what happened. Nothing in
-- here is allowed to escape into the event handler.
local function onTick()
    if countdown then
        countdown = countdown - 1
        if countdown <= 0 then
            countdown = nil
            local ok, err = pcall(TARDIS_SelfTest)
            if not ok then
                print("TARDIS-TEST FAIL  could not start: " .. tostring(err))
                run = nil
            end
        end
        return
    end
    local ok, err = pcall(tickRun)
    if not ok then
        print("TARDIS-TEST FAIL  runner crashed, abandoning run: " .. tostring(err))
        run = nil
    end
end

Events.OnGameStart.Add(onGameStart)
Events.OnTick.Add(onTick)
