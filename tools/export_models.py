"""Export PROXY's AR content from the Diorama models into the app bundle.

  city.usdz           TERRAIN_GRAY.stl + FIGURES_MARBLE.stl, terrain split into elevation bands
  pins_occluder.usdz  PINS_FULL from Actuator Release.3dm (rendered invisibly as an occluder)
  terrain.json        NPC walking paths + settlement sites, and the heightfield's layout
  terrain_height.bin  terrain top-surface heights (Float32, meters) for NPC footing and the drone

Both share one origin: the pin model's lower-left corner (Rhino layer PINS_ORIGIN), per the brief.
Coordinates convert from Rhino millimeters Z-up to RealityKit meters Y-up:
  AR (x, y, z) = (X - Ox, Z - Oz, -(Y - Oy)) / 1000
so the app needs only one offset, MARKER_TO_ORIGIN, from the marker to the pin origin.

Usage (needs `pip install rhino3dm` and macOS's usdcat/usdzip):
  python3 -I tools/export_models.py <Diorama folder> <output folder>
"""
import json
import os
import struct
import subprocess
import sys
import tempfile

import rhino3dm

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import terrain_paths  # noqa: E402

# Elevation bands for the cartoon restyle (Rhino Z, mm). Names are matched in ContentLoader.
BANDS = [("terrain_low", 40.0), ("terrain_mid", 75.0), ("terrain_high", 105.0), ("terrain_peak", 1e9)]


ORIGIN = (0.0, 0.0, 0.0)  # set from PINS_ORIGIN in main()


def to_ar(x, y, z):
    ox, oy, oz = ORIGIN
    return ((x - ox) / 1000.0, (z - oz) / 1000.0, -(y - oy) / 1000.0)


def read_pins_origin(path):
    model = rhino3dm.File3dm.Read(path)
    layer_index = next(i for i in range(len(model.Layers)) if model.Layers[i].FullPath == "PINS_ORIGIN")
    point = next(o.Geometry.Location for o in model.Objects if o.Attributes.LayerIndex == layer_index)
    return (point.X, point.Y, point.Z)


def read_stl(path):
    """Binary STL -> list of triangles, each three (x, y, z) tuples in mm."""
    tris = []
    with open(path, "rb") as f:
        f.read(80)
        (n,) = struct.unpack("<I", f.read(4))
        for _ in range(n):
            d = struct.unpack("<12fH", f.read(50))
            tris.append((d[3:6], d[6:9], d[9:12]))
    return tris


def read_3dm_mesh(path, layer_name):
    model = rhino3dm.File3dm.Read(path)
    layer_index = next(i for i in range(len(model.Layers)) if model.Layers[i].FullPath == layer_name)
    tris = []
    for obj in model.Objects:
        if obj.Attributes.LayerIndex != layer_index or not isinstance(obj.Geometry, rhino3dm.Mesh):
            continue
        mesh = obj.Geometry
        v = [(p.X, p.Y, p.Z) for p in (mesh.Vertices[i] for i in range(len(mesh.Vertices)))]
        for i in range(len(mesh.Faces)):
            a, b, c, d = mesh.Faces[i]
            tris.append((v[a], v[b], v[c]))
            if d != c:
                tris.append((v[a], v[c], v[d]))
    return tris


def mesh_usda(name, tris, with_normals=True):
    """Weld vertices, convert to AR space, and emit a USD Mesh prim."""
    index, points, faces = {}, [], []
    for tri in tris:
        for p in tri:
            key = (round(p[0], 4), round(p[1], 4), round(p[2], 4))
            if key not in index:
                index[key] = len(points)
                points.append(to_ar(*key))
            faces.append(index[key])

    lines = [f'        def Mesh "{name}"', "        {"]
    if with_normals:
        normals = [[0.0, 0.0, 0.0] for _ in points]
        for t in range(0, len(faces), 3):
            a, b, c = (points[i] for i in faces[t:t + 3])
            u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
            w = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
            n = (u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0])
            for i in faces[t:t + 3]:
                for k in range(3):
                    normals[i][k] += n[k]
        for n in normals:
            length = (n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5 or 1.0
            n[0], n[1], n[2] = n[0] / length, n[1] / length, n[2] / length
        lines.append("            normal3f[] normals = [" + ",".join("(%.5f,%.5f,%.5f)" % tuple(n) for n in normals) + "] (")
        lines.append('                interpolation = "vertex"')
        lines.append("            )")
    lines.append("            int[] faceVertexCounts = [" + ",".join(["3"] * (len(faces) // 3)) + "]")
    lines.append("            int[] faceVertexIndices = [" + ",".join(map(str, faces)) + "]")
    lines.append("            point3f[] points = [" + ",".join("(%.6f,%.6f,%.6f)" % p for p in points) + "]")
    lines.append('            uniform token subdivisionScheme = "none"')
    lines.append("        }")
    print(f"  {name}: {len(faces) // 3} triangles, {len(points)} vertices")
    return "\n".join(lines)


def write_usdz(out_path, root_name, prims):
    usda = "\n".join([
        "#usda 1.0",
        f'(\n    defaultPrim = "{root_name}"\n    metersPerUnit = 1\n    upAxis = "Y"\n)',
        f'def Xform "{root_name}"',
        "{",
        *prims,
        "}",
        "",
    ])
    with tempfile.TemporaryDirectory() as tmp:
        usda_path = os.path.join(tmp, root_name + ".usda")
        usdc_path = os.path.join(tmp, root_name + ".usdc")
        with open(usda_path, "w") as f:
            f.write(usda)
        subprocess.run(["usdcat", usda_path, "-o", usdc_path], check=True)
        if os.path.exists(out_path):
            os.remove(out_path)
        subprocess.run(["usdzip", out_path, usdc_path], check=True, cwd=tmp)
    print(f"wrote {out_path} ({os.path.getsize(out_path) / 1e6:.1f} MB)")


def main(diorama, out_dir):
    global ORIGIN
    export = os.path.join(diorama, "export")
    rhino_file = os.path.join(export, "Actuator Release.3dm")
    ORIGIN = read_pins_origin(rhino_file)
    print("pin origin (Rhino mm):", ORIGIN)

    print("city.usdz")
    terrain = read_stl(os.path.join(export, "TERRAIN_GRAY.stl"))
    bands = {name: [] for name, _ in BANDS}
    for tri in terrain:
        z = (tri[0][2] + tri[1][2] + tri[2][2]) / 3
        bands[next(name for name, top in BANDS if z < top)].append(tri)
    prims = [mesh_usda(name, tris) for name, tris in bands.items() if tris]
    prims.append(mesh_usda("figures", read_stl(os.path.join(export, "FIGURES_MARBLE.stl"))))
    write_usdz(os.path.join(out_dir, "city.usdz"), "city", prims)

    print("pins_occluder.usdz")
    pins = read_3dm_mesh(rhino_file, "PINS_FULL")
    write_usdz(os.path.join(out_dir, "pins_occluder.usdz"), "pins", [mesh_usda("pins", pins, with_normals=False)])

    print("terrain.json + terrain_height.bin")
    write_terrain_data(terrain, os.path.join(diorama, "paths.json"), out_dir)


def write_terrain_data(terrain, exact_paths_file, out_dir):
    hf = terrain_paths.Heightfield(terrain)
    if os.path.exists(exact_paths_file):
        print(f"  exact paths from {exact_paths_file}")
        paths, _ = terrain_paths.load_exact_paths(exact_paths_file)
        source = "diorama.py"
    else:
        print("  paths.json not found; rebuilding routes from the terrain (approximate)")
        paths, _ = terrain_paths.route_paths(hf)
        source = "rebuilt"

    def xz(x, y):
        ax, _, az = to_ar(x, y, 0.0)
        return [round(ax, 5), round(az, 5)]

    with open(os.path.join(out_dir, "terrain_height.bin"), "wb") as f:
        for i in range(hf.nx):  # x-major: index = i * ny + j
            f.write(struct.pack(f"<{hf.ny}f", *[to_ar(0, 0, z)[1] for z in hf.H[i]]))
    data = dict(
        heightfield=dict(file="terrain_height.bin", nx=hf.nx, ny=hf.ny, cell=terrain_paths.CELL / 1000.0,
                         origin=xz(hf.x0, hf.y0), note="x = origin.x + i*cell, z = origin.z - j*cell"),
        pathSource=source,
        paths=[dict(name=p["name"], start=p["start"], end=p["end"], points=[xz(*q) for q in p["pts"]])
               for p in paths],
        sites=[dict(name=s["name"], center=xz(*terrain_paths.site_center(s)), radius=s["r"] / 1000.0)
               for s in terrain_paths.SITES],
    )
    with open(os.path.join(out_dir, "terrain.json"), "w") as f:
        json.dump(data, f)
    print(f"  {len(paths)} paths ({source}), heightfield {hf.nx} x {hf.ny}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
