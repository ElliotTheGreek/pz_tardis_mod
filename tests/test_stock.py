"""Runs TARDIS_Util under a real Lua VM with the engine globals stubbed.

Guards the loot-distribution bug: every container used to start at the top of
its list, so a deck of 120 bookshelves held the same twelve books and most of
the list never reached the world.
"""
import os, sys
from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LUA = os.path.join(ROOT, "TARDIS", "42", "media", "lua")

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(f'package.path = "{LUA.replace(os.sep, "/")}/shared/?.lua;" .. package.path')

# Minimal stand-ins for the engine globals the module touches at load time.
lua.execute("""
    -- Project Zomboid runs Kahlua, a Lua 5.1 dialect, where unpack is a
    -- global. Newer Lua moved it to table.unpack, so put it back.
    _G.unpack = _G.unpack or table.unpack
    _G.print = function(...) end
    _G.instanceof = function() return false end
    _G.getCellSizeInSquares = function() return 256 end
    _G.ModData = { getOrCreate = function() return {} end }
    _G.getPlayer = function() return nil end
    _G.getSpecificPlayer = function() return nil end
    _G.getCell = function() return nil end
""")
lua.execute('require "TARDIS/TARDIS_Config"')
lua.execute('require "TARDIS/TARDIS_Util"')

# A container that just records what it was handed.
lua.execute("""
    function makeShelf()
        local held = {}
        local container = { AddItems = function(self, id, n)
            table.insert(held, id); return {} end }
        local obj = { getContainer = function() return container end }
        return obj, held
    end
""")

U = lua.globals().TARDIS.Util
make = lua.globals().makeShelf

LIST_LEN, PER_SHELF, SHELVES = 90, 12, 120
lua.execute("book_list = {}")
book_list = lua.globals().book_list
for i in range(1, LIST_LEN + 1):
    book_list[i] = f"Base.Book{i}"

U.resetStockCursors()
seen, first_of_each = set(), []
for _ in range(SHELVES):
    obj, held = make()
    U.stock(obj, book_list, PER_SHELF)
    ids = [held[i] for i in range(1, len(held) + 1)]
    assert len(ids) == PER_SHELF, f"expected {PER_SHELF} items, got {len(ids)}"
    first_of_each.append(ids[0])
    seen.update(ids)

failures = []
if len(seen) != LIST_LEN:
    failures.append(f"only {len(seen)}/{LIST_LEN} distinct items ever placed")
if len(set(first_of_each[:8])) == 1:
    failures.append("every shelf starts on the same item (the original bug)")

# a rebuild must lay things out identically
U.resetStockCursors()
obj, held = make()
U.stock(obj, book_list, PER_SHELF)
if held[1] != first_of_each[0]:
    failures.append("reset does not reproduce the original layout")

print(f"{SHELVES} shelves x {PER_SHELF} items over a {LIST_LEN}-item list")
print(f"distinct items placed: {len(seen)}/{LIST_LEN}")
print(f"first item on shelves 1-6: {first_of_each[:6]}")
if failures:
    print("\nFAIL:")
    for f in failures:
        print("  " + f)
    sys.exit(1)
print("loot distribution covers the whole list")
