"""Runs TARDIS_Build.buildDeck for every deck against a stub engine.

Every engine call in the builder is wrapped (U.try, U.batch), which is right
in game -- one bad call must never take a deck down -- and means a typo, a nil
index or a wrong argument is a WARN line in console.txt rather than a crash.
This runs the real builder under a real Lua VM against a small stand-in for
the engine and **fails on any WARN**, so those are caught here, in seconds,
rather than by walking every deck in game.

It also checks what a build leaves behind: every layout object on its square,
doors in the special-object list, containers made and stocked, the hold
packed within capacity, the sonic case holding its screwdrivers, water stores
on the water fittings, the range a stove -- and that a second build places
nothing new and stocks nothing twice, and that a deck built by the old
generator is refitted with its contents handed back.

The stub is deliberately small; it is not the engine. What it proves is that
the Lua is sound and does what it means to. What the game makes of it is only
settled in game.
"""
import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.path.join(ROOT, "TARDIS", "42", "media", "lua").replace(os.sep, "/")

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'package.path = "{LUA}/shared/?.lua;{LUA}/client/?.lua;" .. package.path')
lua.execute(r'''
_G.unpack = _G.unpack or table.unpack
WARNINGS, LOG = {}, {}
_G.print = function(s)
    s = tostring(s)
    table.insert(LOG, s)
    if s:find("WARN") then table.insert(WARNINGS, s) end
end

-- items -----------------------------------------------------------------
local WEIGHT = { ["Base.556Carton"] = 5, ["Base.Bullets9mmCarton"] = 8, ["Base.Bullets44Carton"] = 12,
                 ["Base.Rice"] = 2, ["Base.Pasta"] = 2, ["Base.AssaultRifle"] = 3.5 }
function newItem(id)
    local it = { id = id }
    function it:getFullType() return self.id end
    function it:getWeight() return WEIGHT[self.id] or 0.3 end
    return it
end

local function list(t)
    local l = { t = t or {} }
    function l:size() return #self.t end
    function l:get(i) return self.t[i + 1] end
    function l:contains(x) for _, v in ipairs(self.t) do if v == x then return true end end return false end
    return l
end

function newContainer(cap)
    local c = { items = {}, cap = cap or 40, explored = false }
    function c:getItems() return list(self.items) end
    function c:AddItem(id)
        local it = type(id) == "string" and newItem(id) or id
        table.insert(self.items, it)
        return it
    end
    function c:AddItems(id, n) for _ = 1, n do self:AddItem(id) end return {} end
    function c:DoRemoveItem(it)
        for i, v in ipairs(self.items) do if v == it then table.remove(self.items, i) return end end
    end
    function c:getCapacity() return self.cap end
    function c:getCapacityWeight()
        local w = 0
        for _, it in ipairs(self.items) do w = w + it:getWeight() end
        return w
    end
    function c:setExplored(b) self.explored = b end
    return c
end

-- sprites and tile properties ----------------------------------------------
PROPS = {}
function getSprite(name)
    local s = { name = name }
    function s:getName() return self.name end
    function s:getProperties()
        local p = PROPS[self.name] or {}
        return { isTableTop = function() return false end, isSurfaceOffset = function() return false end,
                 isTable = function() return false end, getSurface = function() return 0 end,
                 Val = function(_, k) return p[k] end }
    end
    return s
end

-- objects -------------------------------------------------------------------
local function baseObject(sq, sprite, class)
    local o = { sq = sq, sprite = getSprite(sprite), md = {}, class = class or "IsoObject" }
    function o:getSprite() return self.sprite end
    function o:getModData() return self.md end
    function o:getContainer() return self.container end
    function o:getItemContainer() return self.container end
    function o:createContainersFromSpriteProperties()
        local p = PROPS[self.sprite.name]
        if p and p.container then self.container = newContainer(tonumber(p.ContainerCapacity) or 40) end
    end
    function o:getFluidCapacity() return self.fluid and self.fluid.cap or 0 end
    function o:getFluidAmount() return self.fluid and self.fluid.amount or 0 end
    function o:addFluid(_, n) if self.fluid then self.fluid.amount = math.min(self.fluid.cap, self.fluid.amount + n) end end
    function o:setRenderYOffset() end
    return o
end
IsoObject = { new = function(sq, sprite, _) return baseObject(sq, sprite) end }
IsoStove = { new = function(_, sq, spr) return baseObject(sq, spr.name, "IsoStove") end }
IsoDoor = { new = function(_, sq, sprite, north)
    local d = baseObject(sq, sprite, "IsoDoor")
    d.north = north
    function d:getNorth() return self.north end
    return d
end }
function instanceof(o, class)
    if type(o) ~= "table" then return false end
    if class == "IsoObject" then return true end
    return o.class == class
end

ComponentType = { FluidContainer = { CreateComponent = function()
    local f = { cap = 0, amount = 0 }
    function f:setCapacity(n) self.cap = n end
    function f:addFluid(_, n) self.amount = self.amount + n end
    return f
end } }
FluidType = { Water = "Water" }
GameEntityFactory = { AddComponent = function(obj, _, f) obj.fluid = f end }

-- squares and the cell --------------------------------------------------------
SQUARES = {}
local function key(x, y, z) return x .. "," .. y .. "," .. z end
function newSquare(x, y, z)
    local sq = { x = x, y = y, z = z, objects = {}, special = {}, floor = nil, world = {} }
    function sq:getObjects() return list(self.objects) end
    function sq:getSpecialObjects() return list(self.special) end
    function sq:getWorldObjects() return list(self.world) end
    function sq:getFloor() return self.floor end
    function sq:getX() return self.x end
    function sq:getY() return self.y end
    function sq:getZ() return self.z end
    function sq:addFloor(sprite)
        local f = baseObject(self, sprite)
        self.floor = f
        table.insert(self.objects, 1, f)
        return f
    end
    function sq:AddTileObject(o) table.insert(self.objects, o) end
    function sq:AddSpecialObject(o) table.insert(self.objects, o); table.insert(self.special, o) end
    function sq:RemoveTileObjectErosionNoRecalc(o)
        for i, v in ipairs(self.objects) do if v == o then table.remove(self.objects, i) break end end
        for i, v in ipairs(self.special) do if v == o then table.remove(self.special, i) break end end
        if self.floor == o then self.floor = nil end
        return 1
    end
    function sq:AddWorldInventoryItem(it, _, _, _)
        if type(it) == "string" then it = newItem(it) end
        local w = { item = it, class = "IsoWorldInventoryObject", md = {} }
        function w:getItem() return self.item end
        function w:getModData() return self.md end
        function w:getSprite() return nil end
        table.insert(self.world, w)
        table.insert(self.objects, w)
        return it
    end
    function sq:removeWorldObject(w)
        for i, v in ipairs(self.world) do if v == w then table.remove(self.world, i) break end end
        for i, v in ipairs(self.objects) do if v == w then table.remove(self.objects, i) break end end
    end
    function sq:setHaveElectricity() end
    function sq:isSolid() return false end
    return sq
end
local cell = {}
function cell:getGridSquare(x, y, z) return SQUARES[key(x, y, z)] end
function cell:getOrCreateGridSquare(x, y, z)
    local k = key(x, y, z)
    SQUARES[k] = SQUARES[k] or newSquare(x, y, z)
    return SQUARES[k]
end
function cell:getChunkForGridSquare() return {} end
LAMPS = {}
function cell:addLamppost(x, y, z) local l = { x, y, z } table.insert(LAMPS, l) return l end
function cell:getLamppostPositions() return list(LAMPS) end
function getCell() return cell end
function getCellSizeInSquares() return 256 end
MODDATA = {}
ModData = { getOrCreate = function(k) MODDATA[k] = MODDATA[k] or {} return MODDATA[k] end }
function getPlayer() return nil end
function getSpecificPlayer() return nil end
function ZombRandFloat(a, b) return a end
AnimalDefinitions = { getDef = function(kind)
    return { getBreeds = function() return { size = function() return 1 end, get = function() return "breed" end } end }
end }
ANIMALS = {}
function addAnimal(_, x, y, z, kind) local a = { kind = kind } function a:addToWorld() end table.insert(ANIMALS, a) return a end

-- farming: a record per plowed square
PLANTS = {}
SFarmingSystem = { instance = {
    getLuaObjectOnSquare = function(_, sq) return PLANTS[sq] end,
    plow = function(_, sq)
        local p = {}
        function p:seed() end
        PLANTS[sq] = p
    end,
} }
''')

# Tile properties for the stub, from the real tiledef.
sys.path.insert(0, os.path.join(ROOT, "tools"))
import gen_tardis_pack as PACK  # noqa: E402

props = lua.globals().PROPS
for sheet, ts in PACK.read_tiledefs(PACK.TILES).items():
    for i, p in enumerate(ts["tiles"]):
        if p:
            t = lua.table()
            for k, v in p.items():
                t[k] = v
            props["%s_%d" % (sheet, i)] = t

lua.execute('require "TARDIS/TARDIS_Config"')
lua.execute('require "TARDIS/TARDIS_Util"')
lua.execute('require "TARDIS/TARDIS_Layout"')
lua.execute('require "TARDIS/TARDIS_Build"')
G = lua.globals()
C, L, B, U = G.TARDIS.Config, G.TARDIS.Layout, G.TARDIS.Build, G.TARDIS.Util

failures = []


def lst(t):
    return [t[i] for i in range(1, len(t) + 1)] if t is not None else []


def warnings():
    return lst(G.WARNINGS)


def square(x, y, z):
    return G.getCell().getGridSquare(G.getCell(), x, y, z)


def deck_objects(index):
    """What stands on each layout square after a build: (piece-or-sprite, kind) found/missing."""
    deck = C.Decks[index]
    lay = L.decks[deck.id]
    rx, ry = U.deckOrigin(deck)
    missing, containers = [], []
    for o in lst(lay.objects):
        o = lst(o)
        sq = square(rx + int(o[0]), ry + int(o[1]), int(deck.z))
        found = None
        if sq is not None:
            for obj in lst(sq.objects):
                spr = obj.sprite
                if o[3] in ("dW", "dN"):
                    if obj["class"] == "IsoDoor" and bool(obj.north) == (o[3] == "dN"):
                        found = obj
                elif spr is not None and spr.name == o[2]:
                    found = obj
        if found is None:
            missing.append("%s at %s,%s" % (o[4] if len(o) > 4 else o[2], o[0], o[1]))
        elif o[3] == "c":
            containers.append((o[4], found))
    return missing, containers


def items_in(obj):
    c = obj.container
    return lst(c["items"]) if c is not None else []


# --- a fresh world: every deck ----------------------------------------------------
for index in range(1, len(C.Decks) + 1):
    deck = C.Decks[index]
    before = len(warnings())
    ok = B.buildDeck(index)
    if not ok:
        failures.append(f"{deck.id}: buildDeck returned {ok}")
    new = warnings()[before:]
    for w in new:
        failures.append(f"{deck.id}: {w}")
    missing, containers = deck_objects(index)
    if missing:
        failures.append(f"{deck.id}: {len(missing)} layout objects not placed, e.g. {missing[:3]}")
    empty = [p for p, o in containers if not items_in(o)
             and p not in ("kitchen_range",)]
    stocked = len(containers) - len(empty)
    print(f"{deck.id:8s} built: {len(containers)} containers, {stocked} stocked"
          + (f"; empty: {sorted(set(empty))}" if empty else ""))
    if deck.id != "console" and empty:
        failures.append(f"{deck.id}: {len(empty)} container(s) left empty: {sorted(set(empty))}")
    if not B.deckCurrent(index):
        failures.append(f"{deck.id}: not current after building")

# --- the console room's specifics -----------------------------------------------------
_, cons = deck_objects(1)
hold = {}
for piece, obj in cons:
    if piece in ("console", "hold_locker"):
        hold[id(obj.container)] = obj.container
held = sum(len(lst(c["items"])) for c in hold.values())
over = [c for c in hold.values() if c.getCapacityWeight(c) > c.getCapacity(c) + 1e-6]
print(f"hold: {len(hold)} containers, {held} items packed, {len(over)} over capacity")
# The console is a 2x2 piece and, as vanilla's multi-square wardrobes do,
# every square of it is a container of its own: four, and six lockers.
if len(hold) != 10:
    failures.append(f"hold: expected the console's four squares and six lockers, found {len(hold)}")
if held < 600:
    failures.append(f"hold: only {held} items of the kit landed")
if over:
    failures.append(f"hold: {len(over)} container(s) packed past capacity")
sonics = [it for p, o in cons if p == "sonic_case" for it in items_in(o) if it.id == C.SonicItem]
if len(sonics) != int(C.SonicCount):
    failures.append(f"sonic case holds {len(sonics)} of {int(C.SonicCount)}")

# water on every water fitting, a stove for the range
for index in range(1, len(C.Decks) + 1):
    deck = C.Decks[index]
    rx, ry = U.deckOrigin(deck)
    for o in lst(L.decks[deck.id].objects):
        o = lst(o)
        piece = o[4] if len(o) > 4 else None
        use = L.uses[piece] if piece else None
        if not use:
            continue
        sq = square(rx + int(o[0]), ry + int(o[1]), int(deck.z))
        objs = [sq.objects[i] for i in range(1, len(sq.objects) + 1)]
        mine = [ob for ob in objs if ob.md is not None and ob.md.TARDIS == piece]
        if use.water and not any(ob.fluid is not None and ob.fluid.amount > 0 for ob in mine):
            failures.append(f"{deck.id}: {piece} at {o[0]},{o[1]} has no water")
        if use.stove and not any(ob["class"] == "IsoStove" for ob in mine):
            failures.append(f"{deck.id}: {piece} at {o[0]},{o[1]} is not an IsoStove")

plants = len(list(G.PLANTS.items()))
print(f"gardens: {plants} plots sown, {len(list(G.ANIMALS.items()))} animals in the stable")
if plants == 0:
    failures.append("no crops sown in the gardens")

# --- a second build places nothing new and stocks nothing twice ----------------------
counts = {}
for index in range(1, len(C.Decks) + 1):
    _, cs = deck_objects(index)
    counts[index] = sum(len(items_in(o)) for _, o in cs)
    G.MODDATA[C.StateKey].layoutRev[str(index)] = -1        # as a new layout would
before = len(warnings())
for index in range(1, len(C.Decks) + 1):
    B.buildDeck(index)
    _, cs = deck_objects(index)
    after = sum(len(items_in(o)) for _, o in cs)
    if after != counts[index]:
        failures.append(f"{C.Decks[index].id}: a rebuild changed the stock from {counts[index]} to {after}")
for w in warnings()[before:]:
    failures.append(f"rebuild: {w}")
placed = [l for l in lst(G.LOG) if "placed" in l][-6:]
if any(" 0 placed" not in l for l in placed):
    failures.append("a rebuild placed objects again: " + "; ".join(placed))

# --- a world built by the old generator: refitted, contents handed back ------------------
state = G.MODDATA[C.StateKey]
deck = C.Decks[2]
rx, ry = U.deckOrigin(deck)
for k in list(G.SQUARES.keys()):
    sq = G.SQUARES[k]
    if int(sq.z) == int(deck.z):
        del G.SQUARES[k]
old = G.getCell().getOrCreateGridSquare(G.getCell(), rx + 12, ry + 12, int(deck.z))
old.addFloor(old, "floors_interior_carpet_01_0")
shelf = lua.eval("function(sq) local o = IsoObject.new(sq, 'furniture_shelving_01_1', '') "
                 "o.md.TARDIS = 'books' o.container = newContainer(15) sq:AddTileObject(o) return o end")(old)
for i in range(5):
    shelf.container.AddItem(shelf.container, "Base.TestMarker")
state.deckRev["2"] = 15
state.layoutRev["2"] = None
before = len(warnings())
B.buildDeck(2)
for w in warnings()[before:]:
    failures.append(f"refit: {w}")
books = 0
for k in list(G.SQUARES.keys()):
    sq = G.SQUARES[k]
    if int(sq.z) != int(deck.z):
        continue
    for i in range(1, len(sq.objects) + 1):
        ob = sq.objects[i]
        if ob.container is not None:
            books += sum(1 for it in lst(ob.container["items"]) if it.id == "Base.TestMarker")
        if ob["class"] == "IsoWorldInventoryObject" and ob.item.id == "Base.TestMarker":
            books += 1
    for i in range(1, len(sq.objects) + 1):
        ob = sq.objects[i]
        if ob.sprite is not None and ob.sprite.name == "furniture_shelving_01_1":
            failures.append("refit: the old shelf is still standing")
print(f"refit: {books} of 5 old books handed back")
if books != 5:
    failures.append(f"refit: {books} of the 5 books in the old shelf were handed back")

if failures:
    print(f"\n{len(failures)} PROBLEM(S):")
    for f in failures:
        print("  " + f)
    sys.exit(1)
print("\nevery deck builds clean, rebuilds idempotently, and refits an old one without losing anything")
