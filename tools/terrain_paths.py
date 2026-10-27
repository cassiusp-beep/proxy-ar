"""Heightfield and walking paths for PROXY's NPCs, rebuilt from the finished terrain.

Exact paths come from diorama.py's read-only "paths" mode (RUN_MODE = "paths"), which writes
paths.json next to the script. Until that exists, route_paths() rebuilds them: the same A* search
as diorama.py, run on the finished TERRAIN_GRAY mesh, with an extra pull toward smooth ground.
The carved beds are the only places without rock grain, so routes snap into them. Verified against
the logged path figures, FRONT-LOW and LOW-MID2 match within 1 mm; LOW-MID and MID-HIGH do not.

All coordinates here are Rhino millimeters (Z-up); export_models.py converts for the app.
"""
import heapq
import math

CELL = 0.5            # heightfield cell (mm)
ASTAR_RES = 1.0       # path search grid (mm), as in diorama.py
PATH_GRADE = 0.30
PATH_STEEP_PENALTY = 25.0
ROUGHNESS_PULL = 3.0  # cost multiplier per unit of (roughness / typical roughness), capped at 4
TYPICAL_ROUGHNESS = 0.24
EDGE_MARGIN = 3.0     # PATH_W / 2 + PATH_SHOULDER + 1.0 in diorama.py, rounded up

# From diorama.py: site centers are (wall_x + u, v) with wall_x = 5. Facades face +X (the viewer),
# and each path ends at a forecourt about 0.55 r + 2.5 mm in front of the site center.
WALL_X = 5.0
SITES = [
    dict(name="LOW", u=112.0, v=62.0, r=17.0),
    dict(name="MID", u=51.0, v=40.0, r=15.0),
    dict(name="MID2", u=60.0, v=120.0, r=13.0),
    dict(name="HIGH", u=29.0, v=72.0, r=12.0),
]
FRONT_TRAILHEAD_V = 80.0
PATH_LINKS = [("FRONT", "LOW"), ("LOW", "MID"), ("LOW", "MID2"), ("MID", "HIGH"), ("MID2", "HIGH")]


class Heightfield:
    """Top surface of a triangle soup, sampled on a regular grid (max Z per grid point)."""

    def __init__(self, tris):
        xs = [p[0] for t in tris for p in t]
        ys = [p[1] for t in tris for p in t]
        self.x0, self.y0 = min(xs), min(ys)
        self.nx = int(math.floor((max(xs) - self.x0) / CELL)) + 1
        self.ny = int(math.floor((max(ys) - self.y0) / CELL)) + 1
        H = [[-1e9] * self.ny for _ in range(self.nx)]
        for (ax, ay, az), (bx, by, bz), (cx, cy, cz) in tris:
            det = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
            if abs(det) < 1e-12:
                continue  # vertical wall: no top-down area
            i0 = max(0, int(math.ceil((min(ax, bx, cx) - self.x0) / CELL)))
            i1 = min(self.nx - 1, int(math.floor((max(ax, bx, cx) - self.x0) / CELL)))
            j0 = max(0, int(math.ceil((min(ay, by, cy) - self.y0) / CELL)))
            j1 = min(self.ny - 1, int(math.floor((max(ay, by, cy) - self.y0) / CELL)))
            for i in range(i0, i1 + 1):
                x = self.x0 + i * CELL
                for j in range(j0, j1 + 1):
                    y = self.y0 + j * CELL
                    l1 = ((by - cy) * (x - cx) + (cx - bx) * (y - cy)) / det
                    l2 = ((cy - ay) * (x - cx) + (ax - cx) * (y - cy)) / det
                    l3 = 1 - l1 - l2
                    if l1 >= -1e-9 and l2 >= -1e-9 and l3 >= -1e-9:
                        z = l1 * az + l2 * bz + l3 * cz
                        if z > H[i][j]:
                            H[i][j] = z
        # Fill any grid point no triangle covered from its highest neighbor.
        for _ in range(3):
            for i in range(self.nx):
                for j in range(self.ny):
                    if H[i][j] < -1e8:
                        nb = [H[a][b] for a in (i - 1, i, i + 1) for b in (j - 1, j, j + 1)
                              if 0 <= a < self.nx and 0 <= b < self.ny and H[a][b] > -1e8]
                        if nb:
                            H[i][j] = max(nb)
        self.H = H
        self.rough = self._roughness()

    def _roughness(self):
        """Blurred curvature: high on rock grain and cracks, near zero on the smoothed path beds."""
        H, nx, ny = self.H, self.nx, self.ny
        R = [[0.0] * ny for _ in range(nx)]
        for i in range(1, nx - 1):
            for j in range(1, ny - 1):
                c = H[i][j]
                R[i][j] = abs(H[i - 1][j] + H[i + 1][j] - 2 * c) + abs(H[i][j - 1] + H[i][j + 1] - 2 * c)
        B = [[0.0] * ny for _ in range(nx)]
        for i in range(1, nx - 1):
            for j in range(1, ny - 1):
                B[i][j] = sum(R[a][b] for a in (i - 1, i, i + 1) for b in (j - 1, j, j + 1)) / 9
        return B

    def rough_at(self, x, y):
        i = min(self.nx - 1, max(0, int(round((x - self.x0) / CELL))))
        j = min(self.ny - 1, max(0, int(round((y - self.y0) / CELL))))
        return self.rough[i][j]

    def at(self, x, y):
        i = min(self.nx - 1, max(0, int(round((x - self.x0) / CELL))))
        j = min(self.ny - 1, max(0, int(round((y - self.y0) / CELL))))
        return self.H[i][j]


def site_center(s):
    return (WALL_X + s["u"], s["v"])


def endpoints(hf):
    ends = {}
    for s in SITES:
        cx, cy = site_center(s)
        ends[s["name"]] = (cx + 0.55 * s["r"] + 2.5, cy)
    ends["FRONT"] = (hf.x0 + (hf.nx - 1) * CELL - 1.5, FRONT_TRAILHEAD_V)
    return ends


def astar(hf, start, goal):
    nxa = int((hf.nx - 1) * CELL / ASTAR_RES) + 1
    nya = int((hf.ny - 1) * CELL / ASTAR_RES) + 1
    hz = [[hf.at(hf.x0 + i * ASTAR_RES, hf.y0 + j * ASTAR_RES) for j in range(nya)] for i in range(nxa)]
    rz = [[min(4.0, hf.rough_at(hf.x0 + i * ASTAR_RES, hf.y0 + j * ASTAR_RES) / TYPICAL_ROUGHNESS)
           for j in range(nya)] for i in range(nxa)]
    edge = int(math.ceil(EDGE_MARGIN / ASTAR_RES))

    def node(p):
        return (min(nxa - 1, max(0, int(round((p[0] - hf.x0) / ASTAR_RES)))),
                min(nya - 1, max(0, int(round((p[1] - hf.y0) / ASTAR_RES)))))

    sn, gn = node(start), node(goal)

    def free(n):
        if min(math.hypot(n[0] - e[0], n[1] - e[1]) for e in (sn, gn)) * ASTAR_RES <= 5.0:
            return True  # endpoints stay reachable, as in diorama.py
        return edge <= n[0] < nxa - edge and edge <= n[1] < nya - edge

    moves = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1),
             (2, 1), (2, -1), (-2, 1), (-2, -1), (1, 2), (1, -2), (-1, 2), (-1, -2)]

    def cost(a, b):
        d = math.hypot(b[0] - a[0], b[1] - a[1]) * ASTAR_RES
        g = abs(hz[b[0]][b[1]] - hz[a[0]][a[1]]) / d
        if g <= PATH_GRADE:
            base = d * (1.0 + g)
        elif g <= 1.0:
            base = d * (1.0 + g) * (1.0 + PATH_STEEP_PENALTY * (g - PATH_GRADE))
        else:
            base = d * 60.0
        return base * (1.0 + ROUGHNESS_PULL * rz[b[0]][b[1]])

    openq = [(0.0, 0.0, sn)]
    best, prev = {sn: 0.0}, {}
    while openq:
        _, gc, n = heapq.heappop(openq)
        if n == gn:
            break
        if gc > best.get(n, 1e18):
            continue
        for mx, my in moves:
            m = (n[0] + mx, n[1] + my)
            if not (0 <= m[0] < nxa and 0 <= m[1] < nya) or not free(m):
                continue
            nc = gc + cost(n, m)
            if nc < best.get(m, 1e18):
                best[m], prev[m] = nc, n
                heapq.heappush(openq, (nc + math.hypot(gn[0] - m[0], gn[1] - m[1]) * ASTAR_RES, nc, m))
    if gn not in prev:
        return None
    path = [gn]
    while path[-1] != sn:
        path.append(prev[path[-1]])
    path.reverse()
    return [(hf.x0 + i * ASTAR_RES, hf.y0 + j * ASTAR_RES) for i, j in path]


def simplify(pts, eps=0.5):
    """Douglas-Peucker, as in diorama.py."""
    if len(pts) < 3:
        return pts
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    L = math.hypot(x1 - x0, y1 - y0) or 1e-9
    dmax, imax = 0.0, 0
    for i in range(1, len(pts) - 1):
        d = abs((x1 - x0) * (y0 - pts[i][1]) - (x0 - pts[i][0]) * (y1 - y0)) / L
        if d > dmax:
            dmax, imax = d, i
    if dmax <= eps:
        return [pts[0], pts[-1]]
    return simplify(pts[:imax + 1], eps)[:-1] + simplify(pts[imax:], eps)


def smooth_resample(pts, step=1.0, iters=3):
    """Chaikin corner cutting, then even spacing along the curve."""
    for _ in range(iters):
        q = [pts[0]]
        for a, b in zip(pts[:-1], pts[1:]):
            q.append((0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]))
            q.append((0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]))
        q.append(pts[-1])
        pts = q
    out, carry = [pts[0]], 0.0
    for a, b in zip(pts[:-1], pts[1:]):
        L = math.hypot(b[0] - a[0], b[1] - a[1])
        t = step - carry
        while t <= L:
            out.append((a[0] + (b[0] - a[0]) * t / L, a[1] + (b[1] - a[1]) * t / L))
            t += step
        carry = L - (t - step)
    out.append(pts[-1])
    return out


def load_exact_paths(path):
    """paths.json from diorama.py's paths mode -> the same shape route_paths() returns."""
    import json
    data = json.load(open(path))
    paths = []
    for p in data["paths"]:
        a, b = p["name"].split("-")
        pts = smooth_resample([(q[0], q[1]) for q in p["pts"]], iters=0)
        paths.append(dict(name=p["name"], start=a, end=b, pts=pts))
    ends = {s["name"]: tuple(s["forecourt"]) for s in data["sites"]}
    return paths, ends


def route_paths(hf):
    ends = endpoints(hf)
    paths = []
    for a, b in PATH_LINKS:
        raw = astar(hf, ends[a], ends[b])
        if raw is None:
            print(f"  WARNING: no path {a} -> {b}")
            continue
        pts = smooth_resample(simplify(raw))
        length = sum(math.hypot(q[0] - p[0], q[1] - p[1]) for p, q in zip(pts[:-1], pts[1:]))
        print(f"  path {a:5s} -> {b:5s} {length:6.0f} mm, {len(pts)} points")
        paths.append(dict(name=f"{a}-{b}", start=a, end=b, pts=pts))
    return paths, ends
