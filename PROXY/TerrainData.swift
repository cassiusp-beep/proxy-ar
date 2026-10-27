import Foundation
import simd

/// Walking paths, settlement sites and the terrain heightfield, from terrain.json and
/// terrain_height.bin (written by tools/export_models.py). All coordinates are in the content
/// frame: meters from the pin origin, x right, z away (negative), y up.
struct TerrainData {
    struct Path {
        let name: String
        let start: String
        let end: String
        let points: [SIMD2<Float>]   // (x, z)
        let cumulative: [Float]      // distance along the path at each point
        var length: Float { cumulative.last ?? 0 }

        /// Point at `distance` along the path, clamped to its ends.
        func point(at distance: Float) -> SIMD2<Float> {
            guard points.count > 1 else { return points.first ?? .zero }
            let d = min(max(distance, 0), length)
            var lo = 0, hi = cumulative.count - 1
            while hi - lo > 1 {
                let mid = (lo + hi) / 2
                if cumulative[mid] <= d { lo = mid } else { hi = mid }
            }
            let span = cumulative[hi] - cumulative[lo]
            let t = span > 0 ? (d - cumulative[lo]) / span : 0
            return points[lo] + (points[hi] - points[lo]) * t
        }
    }

    struct Site {
        let name: String
        let center: SIMD2<Float>
        let radius: Float
    }

    let paths: [Path]
    let sites: [Site]
    private let nx: Int, ny: Int, cell: Float, origin: SIMD2<Float>
    private let heights: [Float]

    static let shared: TerrainData? = load()

    /// Terrain top-surface height at (x, z), bilinear between heightfield samples.
    func height(x: Float, z: Float) -> Float {
        let fx = min(max((x - origin.x) / cell, 0), Float(nx - 1))
        let fz = min(max((origin.y - z) / cell, 0), Float(ny - 1))
        let i0 = min(Int(fx), nx - 2), j0 = min(Int(fz), ny - 2)
        let tx = fx - Float(i0), tz = fz - Float(j0)
        func h(_ i: Int, _ j: Int) -> Float { heights[i * ny + j] }
        let a = h(i0, j0) + (h(i0 + 1, j0) - h(i0, j0)) * tx
        let b = h(i0, j0 + 1) + (h(i0 + 1, j0 + 1) - h(i0, j0 + 1)) * tx
        return a + (b - a) * tz
    }

    func height(at p: SIMD2<Float>) -> Float { height(x: p.x, z: p.y) }

    /// Where paths meet a named node (a settlement forecourt or the FRONT trailhead).
    func nodePoint(_ name: String) -> SIMD2<Float>? {
        for path in paths {
            if path.start == name { return path.points.first }
            if path.end == name { return path.points.last }
        }
        return nil
    }

    // MARK: Loading

    private struct File: Decodable {
        struct Heightfield: Decodable { let file: String; let nx: Int; let ny: Int; let cell: Float; let origin: [Float] }
        struct PathEntry: Decodable { let name: String; let start: String; let end: String; let points: [[Float]] }
        struct SiteEntry: Decodable { let name: String; let center: [Float]; let radius: Float }
        let heightfield: Heightfield
        let pathSource: String
        let paths: [PathEntry]
        let sites: [SiteEntry]
    }

    private static func load() -> TerrainData? {
        do {
            guard let jsonURL = Bundle.main.url(forResource: "terrain", withExtension: "json") else {
                print("[PROXY] terrain.json missing; NPCs disabled.")
                return nil
            }
            let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: jsonURL))
            let hf = file.heightfield
            guard let binURL = Bundle.main.url(forResource: hf.file, withExtension: nil) else {
                print("[PROXY] \(hf.file) missing; NPCs disabled.")
                return nil
            }
            let raw = try Data(contentsOf: binURL)
            let heights = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            guard heights.count == hf.nx * hf.ny else {
                print("[PROXY] terrain_height.bin has \(heights.count) samples, expected \(hf.nx * hf.ny).")
                return nil
            }
            let paths = file.paths.map { entry -> Path in
                let points = entry.points.map { SIMD2<Float>($0[0], $0[1]) }
                var cumulative: [Float] = [0]
                for k in 1..<max(points.count, 1) {
                    cumulative.append(cumulative[k - 1] + simd_distance(points[k - 1], points[k]))
                }
                return Path(name: entry.name, start: entry.start, end: entry.end, points: points, cumulative: cumulative)
            }
            let sites = file.sites.map { Site(name: $0.name, center: SIMD2($0.center[0], $0.center[1]), radius: $0.radius) }
            print("[PROXY] Terrain: \(paths.count) paths (\(file.pathSource)), \(sites.count) sites, heightfield \(hf.nx)×\(hf.ny).")
            return TerrainData(paths: paths, sites: sites, nx: hf.nx, ny: hf.ny, cell: hf.cell,
                               origin: SIMD2(hf.origin[0], hf.origin[1]), heights: heights)
        } catch {
            print("[PROXY] Couldn't load terrain data: \(error)")
            return nil
        }
    }
}
