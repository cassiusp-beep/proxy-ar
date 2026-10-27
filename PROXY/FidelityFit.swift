import RealityKit
import simd

/// Fits the LiDAR scan of the physical model to the Rhino terrain, as a fidelity check and a
/// small correction on top of the marker lock.
///
/// DepthScan collects LiDAR depth points on the model in the content frame (where the terrain
/// heightfield lives), and the solver finds a shift (x, y, z) and yaw that puts them on the
/// terrain surface. The models sit flat on a table and the lock is leveled, so tilt isn't solved.
enum FidelityFit {
    struct Result {
        let points: Int
        let rmsBefore: Float          // meters, scan-to-terrain distance with the current lock
        let rmsAfter: Float           // meters, after the correction
        let shift: SIMD3<Float>       // meters, in the content frame
        let yawDegrees: Float
        let center: SIMD3<Float>      // the yaw pivots here (content frame)
        let depthBias: Float          // meters; the scan's vertical offset, measured but never applied

        var summary: String {
            String(format: "%d pts · %.1f → %.1f mm RMS\nshift x %+.1f, z %+.1f mm · yaw %+.2f° · LiDAR bias %+.1f mm (ignored)",
                   points, rmsBefore * 1000, rmsAfter * 1000,
                   shift.x * 1000, shift.z * 1000, yawDegrees, depthBias * 1000)
        }

        /// The fit correction expressed as a transform of content coordinates.
        var correction: float4x4 {
            let rotation = float4x4(simd_quatf(angle: yawDegrees * .pi / 180, axis: [0, 1, 0]))
            return translation(center + shift) * rotation * translation(-center)
        }
    }

    /// Ignore the model's outer 4 mm: edges, the back wall and the base read badly in the scan.
    static let edgeInset: Float = 0.004
    /// Only points within this distance of the terrain count as the model at the start.
    static let gate: Float = 0.02
    /// Huber threshold: residuals beyond this count linearly, so stray points can't dominate.
    static let huber: Float = 0.003

    /// `points` are in the content frame. Returns nil if too little of the model was scanned.
    ///
    /// Height is not solved: the leveled lock already puts the model's base on the LiDAR table plane.
    /// LiDAR depth on a small matte model reads a few mm deep, so a vertical term is estimated as a
    /// nuisance (params.y) to soak that bias up, and only x, z and yaw are applied.
    static func solve(points: [SIMD3<Float>], terrain: TerrainData) -> Result? {
        let lo = SIMD2<Float>(edgeInset, -PIN_FIELD_SIZE.y + edgeInset)
        let hi = SIMD2<Float>(PIN_FIELD_SIZE.x - edgeInset, -edgeInset)
        let center = SIMD3<Float>(PIN_FIELD_SIZE.x / 2, 0, -PIN_FIELD_SIZE.y / 2)

        func moved(_ p: SIMD3<Float>, _ params: SIMD4<Float>) -> SIMD3<Float> {
            let c = cos(params.w), s = sin(params.w)
            let d = p - center
            return SIMD3(c * d.x + s * d.z, d.y, -s * d.x + c * d.z) + center + SIMD3(params.x, 0, params.z)
        }
        func residual(_ p: SIMD3<Float>, _ params: SIMD4<Float>) -> Float {
            let q = moved(p, params)
            return q.y - terrain.height(x: q.x, z: q.z) + params.y
        }

        var candidates = points.filter { p in
            p.x > lo.x && p.x < hi.x && p.z > lo.y && p.z < hi.y && abs(residual(p, .zero)) < gate
        }
        guard candidates.count >= 150 else { return nil }
        if candidates.count > 6000 {  // plenty for four unknowns; keeps the solve quick
            let step = candidates.count / 6000 + 1
            candidates = stride(from: 0, to: candidates.count, by: step).map { candidates[$0] }
        }

        func rms(_ params: SIMD4<Float>, _ pts: [SIMD3<Float>]) -> Float {
            let sum = pts.reduce(Float(0)) { $0 + pow(residual($1, params), 2) }
            return sqrt(sum / Float(max(pts.count, 1)))
        }
        // Fair "before": the current lock with only the depth bias removed.
        let meanBefore = candidates.reduce(Float(0)) { $0 + residual($1, .zero) } / Float(candidates.count)
        let rmsBefore = rms(SIMD4(0, -meanBefore, 0, 0), candidates)

        // Gauss-Newton with Huber weights; inliers are re-gated as the fit tightens.
        var params = SIMD4<Float>.zero
        var inliers = candidates
        let eps: Float = 0.0002
        for _ in 0..<25 {
            var jtj = simd_double4x4(0), jtr = SIMD4<Double>.zero
            for p in inliers {
                let r = residual(p, params)
                var j = SIMD4<Double>.zero
                for k in 0..<4 {
                    var bumped = params
                    bumped[k] += eps
                    j[k] = Double((residual(p, bumped) - r) / eps)
                }
                let w = Double(abs(r) <= huber ? 1 : huber / abs(r))
                jtj += w * simd_double4x4(columns: (j * j.x, j * j.y, j * j.z, j * j.w))
                jtr += w * j * Double(r)
            }
            let damped = jtj + simd_double4x4(diagonal: SIMD4(repeating: 1e-6))
            let step = -(damped.inverse * jtr)
            params += SIMD4<Float>(Float(step.x), Float(step.y), Float(step.z), Float(step.w))
            let current = rms(params, inliers)
            inliers = candidates.filter { abs(residual($0, params)) < max(0.006, 3 * current) }
            if simd_length(SIMD3(Float(step.x), Float(step.y), Float(step.z))) < 1e-5 && abs(step.w) < 1e-5 { break }
        }
        return Result(points: inliers.count, rmsBefore: rmsBefore, rmsAfter: rms(params, inliers),
                      shift: SIMD3(params.x, 0, params.z), yawDegrees: params.w * 180 / .pi, center: center,
                      depthBias: -params.y)
    }
}

private func translation(_ t: SIMD3<Float>) -> float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(t, 1)
    return m
}
