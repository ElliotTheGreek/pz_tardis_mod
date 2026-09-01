#!/bin/sh
# Pulls the mod's own lines out of the game log after a test run.
LOG="/c/Users/Arcade/Zomboid/console.txt"
echo "=== log: $(wc -l < "$LOG") lines, modified $(date -r "$LOG" '+%Y-%m-%d %H:%M:%S') ==="
echo
echo "--- self test ---"
grep -E "TARDIS-TEST" "$LOG" || echo "(no self-test output)"
echo
echo "--- mod runtime log ---"
grep -E "\[TARDIS\]" "$LOG" || echo "(no runtime log)"
echo
echo "--- errors mentioning the mod ---"
grep -inE "(ERROR|WARN).*(TARDIS|tardis)" "$LOG" | head -40 || true
