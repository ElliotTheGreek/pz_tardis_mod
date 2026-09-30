"""The TARDIS's furniture: every object in the manifest, rendered into tiles.

    python tools/gen_tardis_furniture.py [name ...]

Reads tools/tardis_objects.py (what exists, how big, which ways it faces)
and the meshes the ledger downloaded (tools/assets/interior/*.glb), and
writes

  design/tiles/2x/tardis_interior_02.png    the furniture sheet, 8 columns
  design/tiles/tardis_interior_02.json      what is where: object, facing,
                                            square -> sheet index, its layer
  design/art/interior/furniture_sheet.png   every object in every facing, the
                                            sheet to judge them on

With names, only those are rendered, into furniture_partial*.png, and the
real sheet is left alone -- for looking at one piece without renumbering any.

How each kind is made (the Shuttlecraft mod's gen_adirondack_furniture.py):

* model   an image-to-3D mesh (glTF, Y up, front toward +Z), fitted UNIFORMLY
          into its w x d x h box -- proportions kept, so a chair stays a chair
          -- pushed back against the wall it faces from, and rendered from
          each facing by tools/isorender.py. A facing is a turn, never a
          mirror, so what is on an object's right stays on its right.
* flat    a picture laid on a wall face in the u/v window the manifest gives.
          `split` cuts a wide picture (the police box doors) into one slice
          per wall section.

Vanilla's own rule is followed for facings: things that back onto a wall come
in W and N (the two walls the camera sees); things that turn come in all four.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import isorender as iso  # noqa: E402
import tardis_objects as A  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "design", "art", "interior")
OBJ = os.path.join(ART, "objects")
MESHES = os.path.join(ROOT, "tools", "assets", "interior")
TILES = os.path.join(ROOT, "design", "tiles", "2x")
SHEET = "tardis_interior_02"
INDEX = os.path.join(ROOT, "design", "tiles", SHEET + ".json")
CW, CH = iso.CW, iso.CH


# --- meshes ---------------------------------------------------------------------

def load_glb(path):
    import trimesh
    scene = trimesh.load(path)
    mesh = scene.to_geometry() if hasattr(scene, "to_geometry") else scene
    v = np.asarray(mesh.vertices, np.float64)
    uv = np.asarray(mesh.visual.uv, np.float64).copy()
    uv[:, 1] = 1.0 - uv[:, 1]                 # trimesh flips glTF's v; undo it
    mat = mesh.visual.material
    img = getattr(mat, "baseColorTexture", None) or getattr(mat, "image", None)
    return drop_floor(v, np.asarray(mesh.faces), uv) + (img,)


def drop_floor(v, faces, uv):
    """Remove a baked-in floor: flat, level faces at the very bottom.

    An image-to-3D model sometimes brings the concept's shadow with it as a
    thin dark slab under the object. The camera never sees the underside of
    anything that stands on the floor, so a level face at floor height is
    either that slab or invisible -- safe to drop. Vertices no face uses are
    dropped too, so the fit sees the object only."""
    y = v[:, 1]
    tri = v[faces]
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    low = (tri[:, :, 1] <= y.min() + 0.015 * np.ptp(y)).all(axis=1)
    keep = ~(low & (np.abs(n[:, 1]) > 0.9))
    # And a shadow skirt: near the floor, anything outside the footprint of
    # the object above it goes.
    c = tri.mean(axis=1)
    base = y.min() + 0.06 * np.ptp(y)
    body = c[c[:, 1] > y.min() + 0.12 * np.ptp(y)]
    if len(body):
        pad = 0.02 * max(np.ptp(v[:, 0]), np.ptp(v[:, 2]))
        lo_x, hi_x = body[:, 0].min() - pad, body[:, 0].max() + pad
        lo_z, hi_z = body[:, 2].min() - pad, body[:, 2].max() + pad
        outside = (c[:, 0] < lo_x) | (c[:, 0] > hi_x) | (c[:, 2] < lo_z) | (c[:, 2] > hi_z)
        keep &= ~((c[:, 1] < base) & outside)
    faces = faces[keep]
    used = np.unique(faces.ravel())
    remap = -np.ones(len(v), int)
    remap[used] = np.arange(len(used))
    return v[used], remap[faces], uv[used]


def place(v, facing, w, d, h, back=True, inset=0.03, stretch=False, yaw=0.0):
    """Fit uniformly into the object's box and lay it for one facing.

    A TRELLIS mesh faces +z with its right along +x. `yaw` (degrees) turns it
    about the vertical first, for a mesh made from a concept drawn at an
    angle. `stretch` fits the two floor axes separately -- a single bed drawn
    as wide as a double still fills its one-by-two -- and keeps the height
    in proportion to the smaller of them. Returns world vertices and the
    footprint in squares."""
    if yaw:
        t = np.radians(yaw)
        x, z = v[:, 0] * np.cos(t) - v[:, 2] * np.sin(t), v[:, 0] * np.sin(t) + v[:, 2] * np.cos(t)
        v = np.stack([x, v[:, 1], z], axis=1)
    across, out, up = v[:, 0], v[:, 2], v[:, 1]
    ext = np.array([np.ptp(across), np.ptp(out), np.ptp(up)])
    room = np.array([w - 2 * inset, d - 2 * inset, h])
    k = room / np.maximum(1e-9, ext)
    if stretch:
        sa, so = k[0], k[1]
        su = min(k[2], min(sa, so))
    else:
        sa = so = su = float(np.min(k))
    a = (across - across.min()) * sa
    o = (out - out.min()) * so
    u = (up - up.min()) * su
    a += (w - a.max()) / 2.0                          # centred along the wall
    o += inset if back else (d - o.max()) / 2.0      # against the wall, or centred
    if facing == "W":
        wx, wy, fp = o, a, (d, w)
    elif facing == "N":
        wx, wy, fp = w - a, o, (w, d)
    elif facing == "E":
        wx, wy, fp = d - o, w - a, (d, w)
    else:
        wx, wy, fp = a, d - o, (w, d)
    return np.stack([wx, wy, u], axis=1), (int(round(fp[0])), int(round(fp[1])))


def facings_of(o):
    return {"WN": "WN", "WNES": "WNES", "1": "W"}[o["facings"]]


# --- flats -------------------------------------------------------------------------

def concept(o):
    for ext in (".jpg", ".png"):
        p = os.path.join(OBJ, A.concept_name(o) + "_concept" + ext)
        if os.path.exists(p):
            return Image.open(p).convert("RGB")
    return None


def render_flat(o, facing):
    import gen_tardis_tiles as T
    src = concept(o)
    if src is None:
        raise SystemExit("no concept image for " + o["name"])
    if o.get("split"):
        k, n = o["split"]
        src = src.crop((src.width * k // n, 0, src.width * (k + 1) // n, src.height))
    u0, u1 = o["u"]
    v0, v1 = o["v"]
    tw = max(8, int(72 * (u1 - u0)))
    th = max(8, int(216 * (v1 - v0)))
    tex = src.resize((tw, th), Image.LANCZOS)
    m = T.mask_of("industry_01", 0 if facing == "W" else 1)
    tile = T.inset_tile(tex, m, facing, urange=(u0, u1), vrange=(v0, v1))
    if o.get("round"):
        # A round picture (the clock) drawn on a square canvas: whatever of
        # the canvas lies outside the circle is not part of it, and would
        # show on the wall as the concept's background.
        disc = Image.new("RGB", (tw, th), (0, 0, 0))
        ImageDraw.Draw(disc).ellipse((0, 0, tw - 1, th - 1), fill=(255, 255, 255))
        cut = T.inset_tile(disc, m, facing, urange=(u0, u1), vrange=(v0, v1))
        alpha = cut.convert("L").point(lambda a: 255 if a > 60 else 0)
        tile.putalpha(Image.composite(alpha, Image.new("L", tile.size, 0), tile.split()[3]))
    return {(0, 0): tile}


# --- the run -------------------------------------------------------------------------

def build(only=None):
    tiles, index, rows = [], {}, []

    def add(name, area, layer, facing, out, use):
        entry = index.setdefault(name, {"area": area, "layer": layer, "use": use, "facings": {}})
        squares = []
        for (i, j), t in sorted(out.items()):
            if t.split()[3].getbbox() is None:
                continue
            squares.append([i, j, len(tiles)])
            tiles.append(t)
        if not squares:
            raise SystemExit("%s %s rendered nothing" % (name, facing))
        entry["facings"][facing] = squares
        rows.append((name, facing, out))

    missing = []
    for o in A.OBJECTS:
        if only and o["name"] not in only:
            continue
        if o["kind"] == "flat":
            if concept(o) is None:
                missing.append(o["name"])
                continue
            for f in "WN":
                add(o["name"], o["area"], "WallFurniture", f, render_flat(o, f), o["use"])
            continue
        path = os.path.join(MESHES, o["name"] + ".glb")
        if not os.path.exists(path):
            missing.append(o["name"])
            continue
        v, faces, uv, img = load_glb(path)
        back = o["facings"] == "WN"
        for f in facings_of(o):
            world, fp = place(v, f, o["w"], o["d"], o["h"], back=back,
                              stretch=o.get("stretch", False), yaw=o.get("yaw", 0.0))
            out = iso.render_mesh(world, faces, uv, img, fp)
            add(o["name"], o["area"], "Furniture", f, out, o["use"])
        print("rendered", o["name"])
    return tiles, index, rows, missing


def contact_sheet(rows, path):
    cells = []
    for name, facing, out in rows:
        nx = max(i for i, _ in out) + 1
        ny = max(j for _, j in out) + 1
        c = Image.new("RGBA", (64 * (nx + ny) + 128, 32 * (nx + ny) + 280), (44, 46, 54, 255))
        ox, oy = 64 * ny + 64, 236
        for (i, j), t in sorted(out.items(), key=lambda k: (k[0][0] + k[0][1], k[0][0])):
            c.alpha_composite(t, (ox + 64 * (i - j) - 64, oy + 32 * (i + j) - 192))
        ImageDraw.Draw(c).text((6, 6), "%s %s" % (name, facing), fill=(235, 235, 235, 255))
        cells.append(c)
    cols = 8
    cw = max(c.width for c in cells)
    ch = max(c.height for c in cells)
    sheet = Image.new("RGBA", (cols * cw, ((len(cells) + cols - 1) // cols) * ch), (24, 24, 28, 255))
    for k, c in enumerate(cells):
        sheet.alpha_composite(c, ((k % cols) * cw, (k // cols) * ch))
    sheet = sheet.resize((sheet.width // 2, sheet.height // 2), Image.LANCZOS)
    sheet.save(path)


def main():
    only = set(a for a in sys.argv[1:] if not a.startswith("-")) or None
    tiles, index, rows, missing = build(only)
    rows_n = (len(tiles) + 7) // 8
    sheet = Image.new("RGBA", (CW * 8, CH * rows_n), (0, 0, 0, 0))
    for k, t in enumerate(tiles):
        sheet.paste(t, ((k % 8) * CW, (k // 8) * CH))
    if only:
        sheet.save(os.path.join(ART, "furniture_partial.png"))
        contact_sheet(rows, os.path.join(ART, "furniture_partial_sheet.png"))
        print("partial run: %d tiles, not written to the sheet" % len(tiles))
        return
    if missing:
        # A sheet with a piece left out numbers every piece after it
        # differently, and a tile's number is its sprite name in every save.
        raise SystemExit("not written -- no art yet for: " + ", ".join(missing))
    sheet.save(os.path.join(TILES, SHEET + ".png"))
    with open(INDEX, "w") as f:
        json.dump(index, f, indent=1, sort_keys=True)
    contact_sheet(rows, os.path.join(ART, "furniture_sheet.png"))
    print("wrote %d tiles for %d objects" % (len(tiles), len(index)))


if __name__ == "__main__":
    main()
