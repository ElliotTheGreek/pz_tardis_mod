--[[ TARDIS -- right-click menus.

    Everything hangs off OnPreFillWorldObjectContextMenu rather than
    OnFillWorldObjectContextMenu. Build 42 returns early from the menu
    builder when the clicked square holds nothing the base game considers
    interactable, so the later event never fires on bare grass, road or an
    empty floor -- exactly the tiles the ship most needs to be summoned to.
]]

require "TARDIS/TARDIS_Config"
require "TARDIS/TARDIS_Util"

TARDIS = TARDIS or {}
local C = TARDIS.Config
local U = TARDIS.Util

local M = {}
TARDIS.Menu = M

--- The square under the cursor, taken from the menu position so that it
--- resolves even when the tile holds no objects at all.
local function clickedSquare(playerIndex, context, player)
    local z = math.floor(player:getZ())
    local x = U.try("screenToIsoX", function()
        return screenToIsoX(playerIndex, context.x, context.y, z)
    end)
    local y = U.try("screenToIsoY", function()
        return screenToIsoY(playerIndex, context.x, context.y, z)
    end)
    if not x or not y then return nil end
    return U.square(x, y, z, false)
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function M.onSummon(_, player, x, y, z)
    local sq = U.square(x, y, z, false)
    if not sq then return end
    if not TARDIS.Core.materialise(sq, player) then
        U.try("summonFailMsg", function()
            player:setHaloNote(getText("IGUI_TARDIS_CannotMaterialise"), 255, 60, 60, 200)
        end)
    end
end

function M.onEnter(_, player)
    TARDIS.Core.enter(player)
end

function M.onExit(_, player)
    TARDIS.Core.exit(player)
end

function M.onFlightConsole(_, player)
    TARDIS.Travel.openConsole(player)
end

function M.onBookmarkHere(_, player)
    local ok, err = TARDIS.Travel.addBookmark(nil)
    if not ok then
        U.try("bookmarkFailMsg", function()
            player:setHaloNote(tostring(err), 255, 60, 60, 200)
        end)
    else
        U.try("bookmarkOkMsg", function()
            player:setHaloNote(getText("IGUI_TARDIS_Bookmarked"), 60, 255, 60, 200)
        end)
    end
end

function M.onChangeDeck(_, player, delta)
    TARDIS.Core.changeDeck(player, delta)
end

---------------------------------------------------------------------------
-- Menu assembly
---------------------------------------------------------------------------
local function insideMenu(context, player, worldobjects, test)
    if test then return ISWorldObjectContextMenu.setTest() end

    local sub = context:addOption(getText("IGUI_TARDIS_Name"), worldobjects, nil)
    local menu = ISContextMenu:getNew(context)
    context:addSubMenu(sub, menu)

    menu:addOption(getText("IGUI_TARDIS_StepOutside"), worldobjects, M.onExit, player)
    menu:addOption(getText("IGUI_TARDIS_FlightConsole"), worldobjects,
                   M.onFlightConsole, player)
    menu:addOption(getText("IGUI_TARDIS_BookmarkHere"), worldobjects,
                   M.onBookmarkHere, player)

    local index = TARDIS.Core.deckIndexOf(player)
    if index then
        if C.Decks[index + 1] then
            menu:addOption(getText("IGUI_TARDIS_GoDown", C.Decks[index + 1].name),
                           worldobjects, M.onChangeDeck, player, 1)
        end
        if C.Decks[index - 1] then
            menu:addOption(getText("IGUI_TARDIS_GoUp", C.Decks[index - 1].name),
                           worldobjects, M.onChangeDeck, player, -1)
        end
    end
    return true
end

local function outsideMenu(context, player, worldobjects, sq, test)
    -- Standing next to the shell: offer the door.
    local onShell = TARDIS.Core.exteriorOn(sq) ~= nil
    local canPlace = (not onShell) and TARDIS.Core.canMaterialise(sq)

    if not onShell and not canPlace then return false end
    if test then return ISWorldObjectContextMenu.setTest() end

    if onShell then
        context:addOption(getText("IGUI_TARDIS_Enter"), worldobjects, M.onEnter, player)
        return true
    end

    context:addOption(getText("IGUI_TARDIS_Materialise"), worldobjects, M.onSummon,
                      player, sq:getX(), sq:getY(), sq:getZ())
    return true
end

local function onPreFill(playerIndex, context, worldobjects, test)
    local player = U.player(playerIndex)
    if not player then return end

    if U.isInteriorPlayer(player) then
        return insideMenu(context, player, worldobjects, test)
    end

    local sq = clickedSquare(playerIndex, context, player)
    if not sq then return end
    return outsideMenu(context, player, worldobjects, sq, test)
end

Events.OnPreFillWorldObjectContextMenu.Add(onPreFill)

U.log("loaded v%s -- menus registered on OnPreFillWorldObjectContextMenu", C.Version)

return M
