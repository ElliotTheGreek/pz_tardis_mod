--[[ TARDIS -- flight, bookmarks and the landing site search.

    Travel is chosen from inside the ship on the world map, or from the list
    of saved bookmarks. Choosing somewhere does not move anything straight
    away: a destination is stored, and the ship arrives when the player next
    steps out of the doors. That matters because a far-off destination is
    almost certainly in a chunk the game has not streamed in yet, so there is
    nothing to inspect until the player is standing there.
]]

require "TARDIS/TARDIS_Config"
require "TARDIS/TARDIS_Util"

TARDIS = TARDIS or {}
local C = TARDIS.Config
local U = TARDIS.Util

local T = {}
TARDIS.Travel = T

T.picking = false

---------------------------------------------------------------------------
-- Bookmarks
---------------------------------------------------------------------------
function T.bookmarks()
    return U.state().bookmarks
end

function T.addBookmark(name, x, y, z)
    local s = U.state()
    if #s.bookmarks >= C.MaxBookmarks then
        return false, "bookmark list is full"
    end
    if not x then
        if not s.placed then return false, "the ship has never materialised" end
        x, y, z = s.x, s.y, s.z
    end
    table.insert(s.bookmarks, {
        name = name and name ~= "" and name or string.format("%d, %d", x, y),
        x = x, y = y, z = z or 0,
    })
    U.log("bookmarked %s at %d,%d", tostring(name), x, y)
    return true
end

function T.removeBookmark(index)
    local s = U.state()
    if s.bookmarks[index] then
        table.remove(s.bookmarks, index)
        return true
    end
    return false
end

---------------------------------------------------------------------------
-- Choosing a destination
---------------------------------------------------------------------------
--- Records where the ship should arrive. Nothing moves until the doors open.
function T.setDestination(x, y, z)
    local s = U.state()
    s.destination = { x = math.floor(x), y = math.floor(y), z = math.floor(z or 0) }
    U.log("destination set to %d,%d", s.destination.x, s.destination.y)
    return true
end

function T.clearDestination()
    U.state().destination = nil
end

---------------------------------------------------------------------------
-- Landing
---------------------------------------------------------------------------
--- Squares in rings outward from a centre, nearest first.
local function spiral(cx, cy, radius)
    local out = {}
    for r = 0, radius do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    table.insert(out, { x = cx + dx, y = cy + dy })
                end
            end
        end
    end
    return out
end

--- First square near the target the ship can occupy, or nil if the area has
--- not streamed in yet or is genuinely full.
function T.findLandingSite(cx, cy, z)
    for _, p in ipairs(spiral(cx, cy, C.LandingSearchRadius)) do
        local sq = U.square(p.x, p.y, z, false)
        if sq and TARDIS.Core.canMaterialise(sq) then
            return sq
        end
    end
    return nil
end

--- Delivers the player to a destination and brings the ship in after them.
--- The chunk will not be loaded at the moment of the call, so the actual
--- placement is retried on a tick job until the world catches up.
function T.land(player, dest)
    if not player or not dest then return false end
    local s = U.state()

    if not U.teleport(player, dest.x, dest.y, dest.z or 0) then return false end
    s.inside = false
    s.destination = nil

    T.pendingLanding = {
        x = dest.x, y = dest.y, z = dest.z or 0,
        tries = 0, player = player,
    }
    U.log("arriving at %d,%d", dest.x, dest.y)
    return true
end

--- Runs once a tick while a landing is outstanding.
local function serviceLanding()
    local job = T.pendingLanding
    if not job then return end
    job.tries = job.tries + 1

    local sq = T.findLandingSite(job.x, job.y, job.z)
    if not sq then
        -- Give the world a few seconds to stream the area in before
        -- widening the net; only then admit defeat.
        if job.tries > 300 then
            T.pendingLanding = nil
            U.log("could not find open ground near %d,%d", job.x, job.y)
            local p = job.player
            if p then
                U.try("landFailMsg", function()
                    p:setHaloNote(getText("IGUI_TARDIS_NoLandingSite"), 255, 60, 60, 300)
                end)
            end
        end
        return
    end

    T.pendingLanding = nil
    local player = job.player
    TARDIS.Core.materialise(sq, player)

    -- Put the player beside the doors rather than under the shell.
    local beside = TARDIS.Core.landingBeside(sq:getX(), sq:getY(), sq:getZ())
    if beside and player then
        U.teleport(player, beside.x, beside.y, beside.z)
    end
end

Events.OnTick.Add(serviceLanding)

---------------------------------------------------------------------------
-- Map picking
---------------------------------------------------------------------------
--- Called when the player clicks the map while the flight window is open.
function T.onMapPick(worldX, worldY)
    if not T.picking then return end
    T.setDestination(worldX, worldY, 0)
    if T.window then T.window:refresh() end
end

-- ISWorldMap has no hook for "the player clicked here", so its mouse-up is
-- wrapped once at load. A click that was not a drag is a pick.
local baseOnMouseUp = ISWorldMap.onMouseUp
function ISWorldMap:onMouseUp(x, y)
    local wasDragging = self.dragging
    local wasMoved = self.dragMoved
    local result = baseOnMouseUp(self, x, y)
    if T.picking and wasDragging and not wasMoved and self.mapAPI then
        local wx = self.mapAPI:uiToWorldX(x, y)
        local wy = self.mapAPI:uiToWorldY(x, y)
        if wx and wy then T.onMapPick(math.floor(wx), math.floor(wy)) end
    end
    return result
end

---------------------------------------------------------------------------
-- Markers drawn over the map while the flight console is open
---------------------------------------------------------------------------
--- A diamond centred on a world position, with a label above it.
local function marker(map, wx, wy, r, g, b, label)
    if not map.mapAPI then return end
    local sx = map.mapAPI:worldToUIX(wx, wy)
    local sy = map.mapAPI:worldToUIY(wx, wy)
    if not sx or not sy then return end
    if sx < 0 or sy < 0 or sx > map:getWidth() or sy > map:getHeight() then return end

    for i = 0, 6 do
        local w = 6 - i
        map:drawRect(sx - w, sy - 7 + i, w * 2, 1, 0.95, r, g, b)
        map:drawRect(sx - w, sy + 7 - i, w * 2, 1, 0.95, r, g, b)
    end
    map:drawRectBorder(sx - 7, sy - 7, 15, 15, 0.6, 0, 0, 0)
    if label then
        map:drawTextCentre(label, sx, sy - 26, r, g, b, 1, UIFont.Small)
    end
end

-- The player marker is useless here: the character is standing in the
-- interior cell, nowhere near anywhere the map depicts. These markers show
-- what the flight console actually needs -- where the ship is, where it has
-- been told to go, and every place it has been bookmarked.
local baseRender = ISWorldMap.render
function ISWorldMap:render()
    baseRender(self)
    if not T.picking then return end

    local s = U.state()
    for i, b in ipairs(s.bookmarks) do
        marker(self, b.x, b.y, 0.65, 0.65, 0.7, b.name)
    end
    if s.placed then
        marker(self, s.x, s.y, 0.30, 0.65, 0.95,
               getText("IGUI_TARDIS_MapHere"))
    end
    if s.destination then
        marker(self, s.destination.x, s.destination.y, 0.95, 0.45, 0.35,
               getText("IGUI_TARDIS_MapDestination"))
    end
end

---------------------------------------------------------------------------
-- The flight console window
---------------------------------------------------------------------------
TARDISTravelWindow = ISCollapsableWindow:derive("TARDISTravelWindow")

function TARDISTravelWindow:createChildren()
    ISCollapsableWindow.createChildren(self)
    local pad = 10
    local top = self:titleBarHeight() + pad
    local btnH = 25
    local w = self.width - pad * 2

    self.info = ISRichTextPanel:new(pad, top, w, 46)
    self.info:initialise()
    self:addChild(self.info)

    local listY = top + 52
    local listH = self.height - listY - btnH * 3 - pad * 4
    self.list = ISScrollingListBox:new(pad, listY, w, listH)
    self.list:initialise()
    self.list:instantiate()
    self.list.itemheight = 22
    self.list.selected = 0
    self.list.joypadParent = self
    self.list.drawBorder = true
    self.list.doDrawItem = self.drawBookmark
    self.list.target = self
    self:addChild(self.list)

    local y = listY + listH + pad
    self.travelBtn = ISButton:new(pad, y, w / 2 - 4, btnH,
        getText("IGUI_TARDIS_Travel"), self, TARDISTravelWindow.onTravel)
    self.travelBtn:initialise()
    self:addChild(self.travelBtn)

    self.bookmarkBtn = ISButton:new(pad + w / 2 + 4, y, w / 2 - 4, btnH,
        getText("IGUI_TARDIS_SaveBookmark"), self, TARDISTravelWindow.onBookmark)
    self.bookmarkBtn:initialise()
    self:addChild(self.bookmarkBtn)

    y = y + btnH + 4
    self.gotoBtn = ISButton:new(pad, y, w / 2 - 4, btnH,
        getText("IGUI_TARDIS_UseBookmark"), self, TARDISTravelWindow.onUseBookmark)
    self.gotoBtn:initialise()
    self:addChild(self.gotoBtn)

    self.deleteBtn = ISButton:new(pad + w / 2 + 4, y, w / 2 - 4, btnH,
        getText("IGUI_TARDIS_DeleteBookmark"), self, TARDISTravelWindow.onDeleteBookmark)
    self.deleteBtn:initialise()
    self:addChild(self.deleteBtn)

    self:refresh()
end

function TARDISTravelWindow:drawBookmark(y, item, alt)
    local a = 0.9
    if self.selected == item.itemindex then
        self:drawRect(0, y, self:getWidth(), item.height - 1, 0.3, 0.7, 0.8, 1.0)
    end
    self:drawRectBorder(0, y, self:getWidth(), item.height - 1, 0.5, 0.4, 0.4, 0.4)
    local b = item.item
    self:drawText(b.name, 8, y + 3, 1, 1, 1, a, UIFont.Small)
    self:drawText(string.format("%d, %d", b.x, b.y),
                  self:getWidth() - 100, y + 3, 0.7, 0.7, 0.7, a, UIFont.Small)
    return y + item.height
end

function TARDISTravelWindow:refresh()
    local s = U.state()
    self.list:clear()
    for i, b in ipairs(s.bookmarks) do
        self.list:addItem(b.name, b)
    end

    local text = getText("IGUI_TARDIS_PickPrompt")
    if s.destination then
        text = text .. " <LINE> " .. getText("IGUI_TARDIS_DestinationSet",
                                             s.destination.x, s.destination.y)
    end
    self.info:setText(text)
    self.info.textDirty = true
    self.info:paginate()
end

function TARDISTravelWindow:onTravel()
    local s = U.state()
    if not s.destination then
        self.info:setText(getText("IGUI_TARDIS_NoDestination"))
        self.info.textDirty = true
        self.info:paginate()
        return
    end
    self:close()
end

function TARDISTravelWindow:onBookmark()
    local s = U.state()
    local x, y, z = s.x, s.y, s.z
    if s.destination then
        x, y, z = s.destination.x, s.destination.y, s.destination.z
    end
    if not x then return end

    local modal = ISTextBox:new(0, 0, 280, 120,
        getText("IGUI_TARDIS_NameBookmark"), "", nil,
        function(_, button, bx, by, bz)
            if button.internal == "OK" then
                T.addBookmark(button.parent.entry:getText(), bx, by, bz)
                if T.window then T.window:refresh() end
            end
        end, nil, x, y, z)
    modal:initialise()
    modal:addToUIManager()
end

function TARDISTravelWindow:onUseBookmark()
    local item = self.list.items[self.list.selected]
    if not item then return end
    local b = item.item
    T.setDestination(b.x, b.y, b.z)
    self:refresh()
end

function TARDISTravelWindow:onDeleteBookmark()
    local index = self.list.selected
    if T.removeBookmark(index) then self:refresh() end
end

function TARDISTravelWindow:close()
    T.picking = false
    T.window = nil
    U.try("restoreMapSettings", function()
        local map = ISWorldMap_instance
        if not map then return end
        if T.restoreShowPlayers ~= nil then
            map:setShowPlayers(T.restoreShowPlayers)
        end
        if T.restoreHideUnvisited ~= nil then
            map:setHideUnvisitedAreas(T.restoreHideUnvisited)
        end
    end)
    ISCollapsableWindow.close(self)
end

function TARDISTravelWindow:new(x, y, w, h, player)
    local o = ISCollapsableWindow:new(x, y, w, h)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o.title = getText("IGUI_TARDIS_FlightConsole")
    o:setResizable(false)
    return o
end

--- Opens the world map plus the flight window beside it.
function T.openConsole(player)
    if T.window then
        T.window:close()
    end

    local s = U.state()
    U.try("showWorldMap", function()
        ISWorldMap.ShowWorldMap(player:getPlayerNum(), s.x, s.y, 60)
    end)

    -- ShowWorldMap only honours a centre when it builds the window for the
    -- first time, and it always centres on the character. From inside the
    -- ship the character is in the interior cell, which is nowhere the map
    -- can show, so re-centre on the ship itself every time.
    U.try("centreOnShip", function()
        local map = ISWorldMap_instance
        if not map then return end
        if s.placed then
            map.mapAPI:centerOn(s.x, s.y)
            map.mapAPI:setZoom(60)
        end
        -- the character marker would sit in the void; the ship marker
        -- replaces it while the console is open
        T.restoreShowPlayers = map.showPlayers
        map:setShowPlayers(false)

        -- Lift the fog for the duration. A ship that can go anywhere is not
        -- much use if you can only aim it at places you have already walked
        -- to, and the whole point of the console is picking somewhere new.
        -- The setting is restored on close, so the ordinary map keeps its
        -- fog and nothing about exploration is given away permanently.
        T.restoreHideUnvisited = map.hideUnvisitedAreas
        map:setHideUnvisitedAreas(false)
    end)

    T.picking = true
    local w, h = 320, 420
    local win = TARDISTravelWindow:new(60, 120, w, h, player)
    win:initialise()
    win:addToUIManager()
    win:setVisible(true)
    T.window = win
    return win
end

return T
