"""Build and optionally stage the TARDIS Steam Workshop upload.

Creates the Build 42 layout expected by Project Zomboid's in-game uploader:

    TARDIS/
      workshop.txt
      preview.png
      Contents/mods/TARDIS/42/...        the mod
      Contents/mods/TARDIS/common/...    seating.txt

Run from the project root:

    python tools/package_workshop.py            # build workshop/TARDIS and check it
    python tools/package_workshop.py --install  # and stage it in ~/Zomboid/Workshop/TARDIS

Then, in Project Zomboid: main menu -> Workshop -> Create and update items ->
TARDIS -> upload. (The Shuttlecraft mod's packager, retargeted.)
"""
import argparse
import os
import shutil
import struct
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

MOD = ROOT / "TARDIS"
BUILD = ROOT / "workshop" / "TARDIS"
INSTALLED = Path.home() / "Zomboid" / "Workshop" / "TARDIS"

# The published Steam Workshop item, once there is one.
#
# This one line is the whole difference between updating the mod and
# publishing a second copy of it: the in-game uploader knows which item it is
# looking at only from the id= in workshop.txt. After the first upload the
# game writes that id into ~/Zomboid/Workshop/TARDIS/workshop.txt; copy it
# here so the repo owns it. Until then an --install keeps whatever id the
# staged copy already has rather than wiping it.
WORKSHOP_ID = "3810732908"

VISIBILITY = "public"

TITLE = "Doctor Who: TARDIS -- Bigger on the Inside (Build 42)"
DESCRIPTION = (ROOT / "workshop" / "description.txt").read_text(encoding="utf-8").splitlines()
DESCRIPTION_LIMIT = 8000

# The 256x256 thumbnail: the console room, cut from a clean render of the
# deck (no landing marker, no caption). The square is given as fractions of
# the render, so it survives a change of deck size.
PREVIEW_DECK = "console"
PREVIEW_BOX = (0.36, 0.09, 0.66, 0.66)      # left, top, right, bottom


def png_dimensions(path):
    with open(path, "rb") as stream:
        if stream.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("not a PNG: " + str(path))
        stream.read(8)
        return struct.unpack(">II", stream.read(8))


def make_preview(out):
    import gen_tardis_decks as D
    tmp = ROOT / "workshop" / "_render.png"
    sec = D.DECKS[PREVIEW_DECK]
    cat = D.catalogue()
    g = D.check(PREVIEW_DECK, sec, cat)
    D.preview(PREVIEW_DECK, sec, cat, g, str(tmp), marks=False)
    im = Image.open(tmp).convert("RGB")
    w, h = im.size
    l, t, r, b = PREVIEW_BOX
    side = int(min((r - l) * w, (b - t) * h))
    x0, y0 = int(l * w), int(t * h)
    im.crop((x0, y0, x0 + side, y0 + side)).resize((256, 256), Image.LANCZOS).save(out)
    tmp.unlink()


def published_id(text):
    for line in text.splitlines():
        if line.startswith("id="):
            return line[3:].strip()
    return None


def workshop_text(item_id):
    lines = ["version=1"]
    if item_id:
        lines.append("id=" + item_id)
    lines.append("title=" + TITLE)
    lines.extend("description=" + line for line in DESCRIPTION)
    lines.extend(["tags=Build 42", "visibility=" + VISIBILITY])
    return "\n".join(lines) + "\n"


def validate(package):
    mod = package / "Contents" / "mods" / "TARDIS"
    required = [
        package / "workshop.txt", package / "preview.png",
        mod / "42" / "mod.info", mod / "42" / "poster.png",
        mod / "42" / "media" / "texturepacks" / "tardis_interior.pack",
        mod / "42" / "media" / "tardis_interior.tiles",
        mod / "42" / "media" / "lua" / "shared" / "TARDIS" / "TARDIS_Layout.lua",
        mod / "42" / "media" / "models_X" / "TARDIS_PoliceBox.x",
        mod / "common" / "media" / "seating.txt",
    ]
    missing = [str(p) for p in required if not p.is_file()]
    if missing:
        raise SystemExit("Workshop package is missing:\n  " + "\n  ".join(missing))
    if png_dimensions(package / "preview.png") != (256, 256):
        raise SystemExit("preview.png must be exactly 256x256")
    info = (mod / "42" / "mod.info").read_text(encoding="utf-8")
    for line in ("id=TARDIS", "pack=tardis_interior", "tiledef=tardis_interior 1963"):
        if line not in info:
            raise SystemExit("mod.info is missing " + line)
    text = (package / "workshop.txt").read_text(encoding="utf-8")
    for field in ("version=", "title=", "description=", "tags=", "visibility="):
        if field not in text:
            raise SystemExit("workshop.txt is missing " + field)
    length = len("\n".join(DESCRIPTION))
    if length > DESCRIPTION_LIMIT:
        raise SystemExit("description is %d characters; Steam allows %d" % (length, DESCRIPTION_LIMIT))
    size = sum(p.stat().st_size for p in package.rglob("*") if p.is_file())
    count = sum(1 for p in package.rglob("*") if p.is_file())
    print("validated %d files, %.1f MB" % (count, size / 1e6))
    print("description %d of %d characters" % (length, DESCRIPTION_LIMIT))
    print("workshop item", published_id(text) or "UNPUBLISHED (the first upload creates it)")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--install", action="store_true",
                        help="also stage it in ~/Zomboid/Workshop/TARDIS for the in-game uploader")
    args = parser.parse_args()

    item_id = WORKSHOP_ID
    staged = INSTALLED / "workshop.txt"
    if staged.is_file():
        existing = published_id(staged.read_text(encoding="utf-8"))
        if existing and item_id and existing != item_id:
            raise SystemExit("%s is staged as Workshop item %s but WORKSHOP_ID is %s; "
                             "uploading the wrong one cannot be undone" % (INSTALLED, existing, item_id))
        if existing and not item_id:
            print("keeping the staged Workshop id %s -- copy it into WORKSHOP_ID" % existing)
            item_id = existing

    if BUILD.exists():
        shutil.rmtree(BUILD)
    mod = BUILD / "Contents" / "mods" / "TARDIS"
    mod.parent.mkdir(parents=True, exist_ok=True)
    shutil.copytree(MOD, mod)
    (BUILD / "workshop.txt").write_text(workshop_text(item_id), encoding="utf-8")
    make_preview(BUILD / "preview.png")
    validate(BUILD)
    print("package ->", BUILD)

    if args.install:
        if INSTALLED.exists():
            shutil.rmtree(INSTALLED)
        INSTALLED.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(BUILD, INSTALLED)
        validate(INSTALLED)
        print("uploader staging ->", INSTALLED)


if __name__ == "__main__":
    main()
