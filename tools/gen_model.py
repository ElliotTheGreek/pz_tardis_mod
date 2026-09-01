"""Generates TARDIS_PoliceBox.x -- a DirectX .x text mesh of a police box.

Units: 1.0 == one iso tile. The model sits on the ground plane and extends
upward along UP_AXIS. Project Zomboid loads .x through assimp; the file
mirrors the template block vanilla models ship with.
"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_texture import REGIONS

TEX_W = TEX_H = 256
UP_AXIS = "y"          # Project Zomboid world models are Y-up

# --- box dimensions, in tiles ------------------------------------------
HALF_BODY  = 0.44
HALF_BASE  = 0.50
HALF_ROOF1 = 0.52
HALF_ROOF2 = 0.46
HALF_LAMP  = 0.07

Z_BASE0, Z_BASE1   = 0.00, 0.10
Z_BODY0, Z_BODY1   = 0.10, 1.72
Z_ROOF1_0, Z_ROOF1_1 = 1.72, 1.86
Z_ROOF2_0, Z_ROOF2_1 = 1.86, 1.96
Z_LAMP0, Z_LAMP1   = 1.96, 2.12

verts, faces, norms, uvs = [], [], [], []

def uv(region, fu, fv):
    """Map a 0..1 face coordinate into an atlas region (v is flipped for .x)."""
    x0, y0, x1, y1 = REGIONS[region]
    u = (x0 + fu * (x1 - x0)) / TEX_W
    v = (y0 + fv * (y1 - y0)) / TEX_H
    return (u, v)

def place(a, b, c):
    """Model-space point from (east, north, height)."""
    if UP_AXIS == "z":
        return (a, b, c)
    return (a, c, b)

def quad(p0, p1, p2, p3, region, normal, flip_u=False):
    """Adds a quad as two triangles with its own verts, normal and UVs."""
    base = len(verts)
    for p in (p0, p1, p2, p3):
        verts.append(p)
        norms.append(normal)
    corners = [(0, 1), (1, 1), (1, 0), (0, 0)]
    for (fu, fv) in corners:
        if flip_u:
            fu = 1.0 - fu
        uvs.append(uv(region, fu, fv))
    faces.append((base, base + 1, base + 2))
    faces.append((base, base + 2, base + 3))

def box(half, z0, z1, side_regions, top_region, bottom=False):
    """Axis-aligned box. side_regions = (south, east, north, west)."""
    s, e, n, w = side_regions
    # south face (-north), outward normal -Y
    quad(place(-half, -half, z0), place(half, -half, z0),
         place(half, -half, z1), place(-half, -half, z1), s, place(0, -1, 0))
    # east face, +X
    quad(place(half, -half, z0), place(half, half, z0),
         place(half, half, z1), place(half, -half, z1), e, place(1, 0, 0))
    # north face, +Y
    quad(place(half, half, z0), place(-half, half, z0),
         place(-half, half, z1), place(half, half, z1), n, place(0, 1, 0))
    # west face, -X
    quad(place(-half, half, z0), place(-half, -half, z0),
         place(-half, -half, z1), place(-half, half, z1), w, place(-1, 0, 0))
    if top_region:
        quad(place(-half, -half, z1), place(half, -half, z1),
             place(half, half, z1), place(-half, half, z1),
             top_region, place(0, 0, 1))
    if bottom:
        quad(place(-half, half, z0), place(half, half, z0),
             place(half, -half, z0), place(-half, -half, z0),
             top_region or "base", place(0, 0, -1))

# plinth, body (door faces south), two roof slabs, lamp
box(HALF_BASE,  Z_BASE0,  Z_BASE1,  ("base",) * 4, "base")
box(HALF_BODY,  Z_BODY0,  Z_BODY1,  ("door", "side", "side", "side"), None)
box(HALF_ROOF1, Z_ROOF1_0, Z_ROOF1_1, ("roof",) * 4, "top")
box(HALF_ROOF2, Z_ROOF2_0, Z_ROOF2_1, ("roof",) * 4, "top")
box(HALF_LAMP,  Z_LAMP0,  Z_LAMP1,  ("lamp",) * 4, "lamp")

TEMPLATES = """template ColorRGBA {
 <35ff44e0-6c7c-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
 FLOAT alpha;
}

template ColorRGB {
 <d3e16e81-7835-11cf-8f52-0040333594a3>
 FLOAT red;
 FLOAT green;
 FLOAT blue;
}

template Material {
 <3d82ab4d-62da-11cf-ab39-0020af71e433>
 ColorRGBA faceColor;
 FLOAT power;
 ColorRGB specularColor;
 ColorRGB emissiveColor;
 [...]
}

template TextureFilename {
 <a42790e1-7810-11cf-8f52-0040333594a3>
 STRING filename;
}

template Frame {
 <3d82ab46-62da-11cf-ab39-0020af71e433>
 [...]
}

template Matrix4x4 {
 <f6f23f45-7686-11cf-8f52-0040333594a3>
 array FLOAT matrix[16];
}

template FrameTransformMatrix {
 <f6f23f41-7686-11cf-8f52-0040333594a3>
 Matrix4x4 frameMatrix;
}

template Vector {
 <3d82ab5e-62da-11cf-ab39-0020af71e433>
 FLOAT x;
 FLOAT y;
 FLOAT z;
}

template MeshFace {
 <3d82ab5f-62da-11cf-ab39-0020af71e433>
 DWORD nFaceVertexIndices;
 array DWORD faceVertexIndices[nFaceVertexIndices];
}

template Mesh {
 <3d82ab44-62da-11cf-ab39-0020af71e433>
 DWORD nVertices;
 array Vector vertices[nVertices];
 DWORD nFaces;
 array MeshFace faces[nFaces];
 [...]
}

template MeshNormals {
 <f6f23f43-7686-11cf-8f52-0040333594a3>
 DWORD nNormals;
 array Vector normals[nNormals];
 DWORD nFaceNormals;
 array MeshFace faceNormals[nFaceNormals];
}

template Coords2d {
 <f6f23f44-7686-11cf-8f52-0040333594a3>
 FLOAT u;
 FLOAT v;
}

template MeshTextureCoords {
 <f6f23f40-7686-11cf-8f52-0040333594a3>
 DWORD nTextureCoords;
 array Coords2d textureCoords[nTextureCoords];
}

template MeshMaterialList {
 <f6f23f42-7686-11cf-8f52-0040333594a3>
 DWORD nMaterials;
 DWORD nFaceIndexes;
 array DWORD faceIndexes[nFaceIndexes];
 [Material]
}
"""

def joinlist(items, fmt):
    """.x lists separate entries with ',' and terminate with ';'."""
    return "".join(fmt(v) + ("," if i < len(items) - 1 else ";") + "\n"
                   for i, v in enumerate(items))

def emit(path):
    n_v, n_f = len(verts), len(faces)
    out = ["xof 0303txt 0032", "", TEMPLATES, "Frame Root {",
           " FrameTransformMatrix {",
           "  1.000000,0.000000,0.000000,0.000000,",
           "  0.000000,1.000000,0.000000,0.000000,",
           "  0.000000,0.000000,1.000000,0.000000,",
           "  0.000000,0.000000,0.000000,1.000000;;",
           " }",
           " Mesh TARDISPoliceBox {",
           f"  {n_v};"]
    out.append(joinlist(verts, lambda v: "  %.6f;%.6f;%.6f;" % v).rstrip("\n"))
    out.append(f"  {n_f};")
    out.append(joinlist(faces, lambda f: "  3;%d,%d,%d;" % f).rstrip("\n"))
    out.append("  MeshNormals {")
    out.append(f"   {n_v};")
    out.append(joinlist(norms, lambda v: "   %.6f;%.6f;%.6f;" % v).rstrip("\n"))
    out.append(f"   {n_f};")
    out.append(joinlist(faces, lambda f: "   3;%d,%d,%d;" % f).rstrip("\n"))
    out.append("  }")
    out.append("  MeshTextureCoords {")
    out.append(f"   {n_v};")
    out.append(joinlist(uvs, lambda v: "   %.6f;%.6f;" % v).rstrip("\n"))
    out.append("  }")
    out.append("  MeshMaterialList {")
    out.append("   1;")
    out.append(f"   {n_f};")
    out.append(joinlist([0] * n_f, lambda v: "   %d" % v).rstrip("\n"))
    out.append("   Material {")
    out.append("    1.000000;1.000000;1.000000;1.000000;;")
    out.append("    0.000000;")
    out.append("    0.000000;0.000000;0.000000;;")
    out.append("    0.000000;0.000000;0.000000;;")
    out.append("    TextureFilename {")
    out.append('     "TARDIS_PoliceBox.png";')
    out.append("    }")
    out.append("   }")
    out.append("  }")
    out.append(" }")
    out.append("}")
    open(path, "w").write("\n".join(out) + "\n")
    return n_v, n_f

if __name__ == "__main__":
    root = sys.argv[1]
    nv, nf = emit(os.path.join(root, "media", "models_X", "TARDIS_PoliceBox.x"))
    print(f"model written: {nv} verts, {nf} tris, up-axis={UP_AXIS}")
