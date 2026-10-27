import ARKit
import simd

/// Accumulates LiDAR depth points that land on the physical model, for FidelityFit.
///
/// Reads ARKit's per-frame depth map (256 × 192, mm-accurate at arm's length) rather than the
/// scene mesh, whose room-scale triangles leave only a few dozen points on a 15 cm model.
/// Coverage is tracked on a 16 × 16 grid over the footprint so the scan knows when it's done.
final class DepthScan {
    static let gridSize = 16
    static let maxPoints = 30_000
    /// Coverage at which the scan stops and fits on its own.
    static let autoFitCoverage: Float = 0.75
    static let minPointsToFit = 500

    private(set) var points: [SIMD3<Float>] = []   // content frame
    private var covered = Set<Int>()
    private var frameIndex = 0

    var coverage: Float { Float(covered.count) / Float(Self.gridSize * Self.gridSize) }

    /// Adds the frame's high-confidence depth samples that fall on the model.
    /// `worldToContent` maps world space into the content frame (where the terrain lives).
    func add(_ frame: ARFrame, worldToContent: simd_float4x4, terrain: TerrainData) {
        frameIndex += 1
        guard frameIndex % 3 == 0, let depth = frame.sceneDepth, let confidence = depth.confidenceMap else { return }
        let depthMap = depth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidence, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
        }
        guard let depthBase = CVPixelBufferGetBaseAddress(depthMap),
              let confidenceBase = CVPixelBufferGetBaseAddress(confidence) else { return }
        let width = CVPixelBufferGetWidth(depthMap), height = CVPixelBufferGetHeight(depthMap)
        let depthRow = CVPixelBufferGetBytesPerRow(depthMap), confidenceRow = CVPixelBufferGetBytesPerRow(confidence)

        // Intrinsics are for the full camera image; scale them down to the depth map.
        let k = frame.camera.intrinsics
        let image = frame.camera.imageResolution
        let sx = Float(width) / Float(image.width), sy = Float(height) / Float(image.height)
        let fx = k[0][0] * sx, fy = k[1][1] * sy, cx = k[2][0] * sx, cy = k[2][1] * sy
        let cameraToContent = worldToContent * frame.camera.transform

        let inset = FidelityFit.edgeInset
        let size = PIN_FIELD_SIZE
        for v in stride(from: 0, to: height, by: 2) {
            let depthRowPtr = (depthBase + v * depthRow).assumingMemoryBound(to: Float32.self)
            let confidenceRowPtr = (confidenceBase + v * confidenceRow).assumingMemoryBound(to: UInt8.self)
            for u in stride(from: 0, to: width, by: 2) {
                guard confidenceRowPtr[u] == UInt8(ARConfidenceLevel.high.rawValue) else { continue }
                let d = depthRowPtr[u]
                guard d > 0.05, d < 1.2 else { continue }
                // Camera space: x right, y up, looking down −z; image v grows downward.
                let camera = SIMD4<Float>((Float(u) - cx) * d / fx, -(Float(v) - cy) * d / fy, -d, 1)
                let q = cameraToContent * camera
                guard q.x > inset, q.x < size.x - inset, q.z < -inset, q.z > -size.y + inset,
                      abs(q.y - terrain.height(x: q.x, z: q.z)) < FidelityFit.gate else { continue }
                let p = SIMD3(q.x, q.y, q.z)
                if points.count < Self.maxPoints {
                    points.append(p)
                } else {
                    points[Int.random(in: 0..<points.count)] = p
                }
                let cellX = min(Self.gridSize - 1, Int(q.x / size.x * Float(Self.gridSize)))
                let cellZ = min(Self.gridSize - 1, Int(-q.z / size.y * Float(Self.gridSize)))
                covered.insert(cellZ * Self.gridSize + cellX)
            }
        }
    }
}
