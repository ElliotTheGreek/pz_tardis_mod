"""Pulls tile sprites out of the game's texture packs and draws them.

A sprite name resolving is not the same as a sprite *looking right*, and the
difference has cost this project more time than any other kind of bug. A sink
that "is not there" turned out to be a counter basin drawn at counter height,
floating over the square behind it. Nothing in the tile properties says that
in so many words; the pixels do.

    python tools/tileview.py fixtures_sinks_01_0                     # one sprite
    python tools/tileview.py fixtures_sinks_01_28 fixtures_sinks_01_0 -o out.png
    python tools/tileview.py --stack carpentry_02_17 fixtures_sinks_01_0
    python tools/tileview.py --offset 34 appliances_cooking_01_25
    python tools/tileview.py --where fixtures_sinks_01_0             # geometry only

Each sprite is composited over a floor tile on its own 128x256 canvas, which
is how the engine lays them out: **the floor diamond occupies canvas rows
192-255**, so art that ends above row 192 is not standing on the ground. That
one number answers most "why does this look wrong" questions on its own, and
`--where` prints it without writing an image.

`--stack` draws every sprite on one tile in the order given, which is what a
counter with a basin on it actually is. `--offset N` applies a render offset
in the engine's units (positive is down, the direction that grounds a
table-top sprite -- see U.addObject).

The pack format, for anyone extending this: "PZPK", int version, int page
count, then per page a name, an entry count, a flag, that many entries of
(name, x, y, w, h, ox, oy, ow, oh), an int byte length and a PNG. Floors live
in a separate .floor.pack.
"""
import argparse, json, os, struct, sys, zlib

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pngwrite import Image, draw_text

GAME = r"C:/Program Files (x86)/Steam/steamapps/common/ProjectZomboid"
PACKS = [os.path.join(GAME, "media", "texturepacks", n)
         for n in ("Tiles2x.pack", "Tiles2x.floor.pack")]
FLOOR = "floors_interior_tilesandwood_01_24"
DIAMOND_TOP = 192          # first canvas row the floor tile covers, of 256


def read_pack(path):
    """Returns {sprite: (path, page_offset, page_len, x, y, w, h, ox, oy, ow, oh)}."""
    data = open(path, "rb").read()
    off = 4
    _ver, npages = struct.unpack_from("<ii", data, off); off += 8
    index = {}

    def rstr(o):
        n = struct.unpack_from("<i", data, o)[0]
        return data[o + 4:o + 4 + n].decode("latin1"), o + 4 + n

    for _ in range(npages):
        _name, off = rstr(off)
        count, _flag = struct.unpack_from("<ii", data, off); off += 8
        entries = []
        for _e in range(count):
            ename, off = rstr(off)
            entries.append((ename, struct.unpack_from("<8i", data, off))); off += 32
        blen = struct.unpack_from("<i", data, off)[0]; off += 4
        for ename, vals in entries:
            index[ename] = (path, off, blen) + vals
        off += blen
    return index


_index = None
def index():
    global _index
    if _index is None:
        _index = {}
        for p in PACKS:
            _index.update(read_pack(p))
    return _index


_pages = {}
def _page(path, off, blen):
    key = (path, off)
    if key not in _pages:
        _pages[key] = decode_png(open(path, "rb").read()[off:off + blen])
    return _pages[key]


def decode_png(blob):
    """RGBA8 PNG -> list of rows of (r,g,b,a) tuples. No third-party deps."""
    o, idat, w, h = 8, b"", 0, 0
    while o < len(blob):
        ln = struct.unpack_from(">I", blob, o)[0]
        typ, body = blob[o + 4:o + 8], blob[o + 8:o + 8 + ln]
        if typ == b"IHDR":
            w, h, depth, ctype = struct.unpack(">IIBB", body[:10])
            if (depth, ctype) != (8, 6):
                raise SystemExit("expected 8-bit RGBA, got depth %d type %d" % (depth, ctype))
        elif typ == b"IDAT":
            idat += body
        elif typ == b"IEND":
            break
        o += 12 + ln
    raw, stride = zlib.decompress(idat), w * 4
    rows, prev, p = [], bytearray(stride), 0
    for _y in range(h):
        f = raw[p]; p += 1
        line = bytearray(raw[p:p + stride]); p += stride
        for x in range(stride):
            a = line[x - 4] if x >= 4 else 0
            b = prev[x]
            c = prev[x - 4] if x >= 4 else 0
            v = line[x]
            if   f == 1: v += a
            elif f == 2: v += b
            elif f == 3: v += (a + b) // 2
            elif f == 4:
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                v += a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
            line[x] = v & 255
        rows.append(line); prev = line
    return w, h, rows


def canvas(sprite):
    """The sprite drawn into its full tile canvas: (ow, oh, rows of RGBA)."""
    e = index().get(sprite)
    if not e:
        raise SystemExit("no sprite named %s in the texture packs" % sprite)
    path, poff, plen, x, y, w, h, ox, oy, ow, oh = e
    pw, _ph, prows = _page(path, poff, plen)
    out = [bytearray(ow * 4) for _ in range(oh)]
    for row in range(h):
        src = prows[y + row]
        out[oy + row][ox * 4:(ox + w) * 4] = src[(x) * 4:(x + w) * 4]
    return ow, oh, out


def art_rows(sprite):
    """First and last canvas row with any opaque pixel, and the canvas height."""
    ow, oh, rows = canvas(sprite)
    top, bottom = None, None
    for i, row in enumerate(rows):
        if any(row[3::4]):
            top = i if top is None else top
            bottom = i
    return top, bottom, oh


def compose(sprites, stack, offset, out):
    cells = []
    fw, fh, floor = canvas(FLOOR)
    groups = [sprites] if stack else [[s] for s in sprites]
    for group in groups:
        rows = [bytearray(r) for r in floor]
        for sprite in group:
            ow, oh, art = canvas(sprite)
            for y in range(oh):
                ty = y + offset * 2          # the 2x pack: one unit is two rows
                if not (0 <= ty < fh):
                    continue
                src, dst = art[y], rows[ty]
                for x in range(ow):
                    a = src[x * 4 + 3]
                    if not a:
                        continue
                    f = a / 255.0
                    for c in range(3):
                        i = x * 4 + c
                        dst[i] = int(src[i] * f + dst[i] * (1 - f))
                    dst[x * 4 + 3] = 255
        cells.append(("+".join(group), fw, fh, rows))

    label = 12
    img = Image(sum(c[1] for c in cells), cells[0][2] + label, bg=(24, 24, 28, 255))
    x0 = 0
    for name, w, h, rows in cells:
        for y in range(h):
            row = rows[y]
            for x in range(w):
                if row[x * 4 + 3]:
                    img.set(x0 + x, y + label,
                            (row[x * 4], row[x * 4 + 1], row[x * 4 + 2], 255))
        draw_text(img, name[:28], x0 + 3, 2, (255, 220, 120, 255))
        x0 += w
    img.save(out)
    print("wrote", out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("sprites", nargs="+")
    ap.add_argument("-o", "--out", default="tileview.png")
    ap.add_argument("--stack", action="store_true",
                    help="draw every sprite on one tile, in the order given")
    ap.add_argument("--offset", type=int, default=0,
                    help="render offset in engine units; positive is down")
    ap.add_argument("--where", action="store_true",
                    help="print where the art sits on the canvas and stop")
    a = ap.parse_args()

    if a.where:
        print("floor diamond covers canvas rows %d-255" % DIAMOND_TOP)
        for s in a.sprites:
            top, bottom, oh = art_rows(s)
            note = "stands on the floor" if bottom and bottom >= DIAMOND_TOP + 24 \
                   else "drawn above the floor -- needs a surface under it"
            print("%-36s art rows %3s-%3s of %d   %s" % (s, top, bottom, oh, note))
        return
    compose(a.sprites, a.stack, a.offset, a.out)


if __name__ == "__main__":
    main()
