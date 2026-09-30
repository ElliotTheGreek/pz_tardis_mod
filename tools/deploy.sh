#!/bin/sh
# Copies the mod into the Project Zomboid mods folder for testing, as
# "TARDIS [DEV]" (id TARDISDev), so it can sit beside the Workshop release
# (id TARDIS) and be chosen instead of it in the mod list. The repo's mod.info
# stays the release one; only the installed copy is renamed. Enable one or the
# other, never both: they share every Lua path, item id and tile.
MODS="/c/Users/Arcade/Zomboid/mods"
SRC="$(cd "$(dirname "$0")/.." && pwd)/TARDIS"
DEST="$MODS/TARDISDev"

# Before 2.0.1 this installed to mods/TARDIS with the release id, which now
# clashes with the Workshop subscription. It was only ever a copy of this repo.
if [ -f "$MODS/TARDIS/42/mod.info" ] && grep -q "^id=TARDIS$" "$MODS/TARDIS/42/mod.info"; then
    rm -rf "$MODS/TARDIS"
    echo "removed the old local copy at $MODS/TARDIS (release id; clashes with the Workshop one)"
fi

rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/." "$DEST/"
sed -i -e 's/^name=.*/name=TARDIS [DEV]/' -e 's/^id=.*/id=TARDISDev/' "$DEST/42/mod.info"
echo "deployed -> $DEST"
grep -E "^(name|id|modversion)=" "$DEST/42/mod.info"
find "$DEST" -type f | wc -l
