import Foundation
import simd

/// One marker's samples taken from distinct camera viewpoints (`DIVERSE_SAMPLING`).
///
/// The image anchor's pose error is systematic per viewpoint (frames from one spot agree to
/// ~0.05–0.3°, spots differ by ~1°), so a sample is kept only when the camera has moved to a new
/// spot, within the distance and incidence limits. Each kept sample is weighted by
/// cos²(incidence), head-on counting most, and `estimate()` averages them like
/// `MarkerSampler`'s consecutive path: weighted circular mean of the headings with outliers
/// dropped, weighted per-axis median of the positions over the inliers.
struct ViewpointSet {
    struct Sample {
        let transform: simd_float4x4
        let camera: SIMD3<Float>
        let direction: SIMD3<Float>   // unit, marker → camera
        let weight: Float
    }

    private(set) var samples: [Sample] = []
    /// Widest angle (degrees) between any two kept viewing directions.
    private(set) var bearingSpanDegrees: Float = 0
    /// Rejections by reason, for the lock line (tuning the limits on device).
    private(set) var rejectedDistance = 0
    private(set) var rejectedIncidence = 0
    private(set) var rejectedSameViewpoint = 0

    var count: Int { samples.count }
    var isReady: Bool {
        samples.count >= DIVERSE_TARGET_VIEWPOINTS && bearingSpanDegrees >= DIVERSE_MIN_BEARING_SPAN_DEGREES
    }
    /// Toward the target for the pill; held one short while the span is too narrow.
    var progress: Int {
        let n = min(samples.count, DIVERSE_TARGET_VIEWPOINTS)
        return isReady ? n : min(n, DIVERSE_TARGET_VIEWPOINTS - 1)
    }
    var rejections: String {
        "rej_dist=\(rejectedDistance) rej_incidence=\(rejectedIncidence) rej_same=\(rejectedSameViewpoint)"
    }

    /// `marker` must already be finite (MarkerSampler checks); a non-finite camera is ignored.
    mutating func add(_ marker: simd_float4x4, camera cameraTransform: simd_float4x4) {
        let c4 = cameraTransform.columns.3
        let camera = SIMD3(c4.x, c4.y, c4.z)
        let position = SIMD3(marker.columns.3.x, marker.columns.3.y, marker.columns.3.z)
        let toCamera = camera - position
        let distance = simd_length(toCamera)
        guard distance.isFinite, distance > 0 else { return }
        guard distance >= DIVERSE_MIN_DISTANCE, distance <= DIVERSE_MAX_DISTANCE else {
            rejectedDistance += 1
            return
        }
        let direction = toCamera / distance
        let normal = simd_normalize(SIMD3(marker.columns.1.x, marker.columns.1.y, marker.columns.1.z))
        let cosIncidence = simd_dot(direction, normal)
        guard cosIncidence >= cos(DIVERSE_MAX_INCIDENCE_DEGREES * .pi / 180) else {
            rejectedIncidence += 1
            return
        }
        if let last = samples.last {
            let moved = simd_distance(camera, last.camera)
            let turned = Self.angleDegrees(direction, last.direction)
            guard moved >= DIVERSE_MIN_CAMERA_MOVE || turned >= DIVERSE_MIN_BEARING_CHANGE_DEGREES else {
                rejectedSameViewpoint += 1
                return
            }
        }
        samples.append(Sample(transform: marker, camera: camera, direction: direction,
                              weight: cosIncidence * cosIncidence))
        if samples.count > DIVERSE_MAX_VIEWPOINTS {
            samples.removeFirst(samples.count - DIVERSE_MAX_VIEWPOINTS)
        }
        bearingSpanDegrees = Self.span(of: samples.map(\.direction))
    }

    static func angleDegrees(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        acos(min(1, max(-1, simd_dot(a, b)))) * 180 / .pi
    }

    /// Widest pairwise angle; at most 30 directions, recomputed only when a viewpoint is added.
    static func span(of directions: [SIMD3<Float>]) -> Float {
        var minDot: Float = 1
        for i in directions.indices {
            for j in directions.indices where j > i {
                minDot = min(minDot, simd_dot(directions[i], directions[j]))
            }
        }
        return acos(min(1, max(-1, minDot))) * 180 / .pi
    }

    /// Weighted median: the value where the cumulative weight reaches half; with equal weights
    /// and an even count, the mean of the two middle values (the plain median).
    static func weightedMedian(_ values: [Float], _ weights: [Float]) -> Float {
        let order = values.indices.sorted { values[$0] < values[$1] }
        let half = weights.reduce(0, +) / 2
        var cumulative: Float = 0
        for (rank, i) in order.enumerated() {
            cumulative += weights[i]
            if abs(cumulative - half) <= half * 1e-5, rank + 1 < order.count {
                return (values[i] + values[order[rank + 1]]) / 2
            }
            if cumulative >= half { return values[i] }
        }
        return values[order.last!]
    }

    func estimate() -> MarkerSampler.Estimate? {
        guard !samples.isEmpty else { return nil }
        let up = SIMD3<Float>(0, 1, 0)
        let weights = samples.map(\.weight)
        let headings = samples.map { s in atan2(s.transform.columns.0.z, s.transform.columns.0.x) }
        let tilts = samples.map { s -> Float in
            let n = simd_normalize(SIMD3(s.transform.columns.1.x, s.transform.columns.1.y, s.transform.columns.1.z))
            return acos(min(1, max(-1, simd_dot(n, up)))) * 180 / .pi
        }

        func circularMean(_ idx: [Int]) -> Float {
            atan2(idx.reduce(0) { $0 + weights[$1] * sin(headings[$1]) },
                  idx.reduce(0) { $0 + weights[$1] * cos(headings[$1]) })
        }
        func wrapped(_ a: Float) -> Float { atan2(sin(a), cos(a)) }
        func weightedRMS(_ idx: [Int], _ dev: (Int) -> Float) -> Float {
            sqrt(idx.reduce(Float(0)) { $0 + weights[$1] * dev($1) * dev($1) } / idx.reduce(Float(0)) { $0 + weights[$1] })
        }

        // Same rule as the consecutive path: drop headings beyond 2.5 σ (never tighter than 0.3°).
        let all = Array(samples.indices)
        let first = circularMean(all)
        let sigma = weightedRMS(all) { wrapped(headings[$0] - first) }
        let limit = max(2.5 * sigma, 0.3 * .pi / 180)
        let keep = all.filter { abs(wrapped(headings[$0] - first)) <= limit }
        guard !keep.isEmpty else { return nil }  // NaN guard, as in MarkerSampler
        let heading = circularMean(keep)
        let headingSpread = weightedRMS(keep) { wrapped(headings[$0] - heading) }

        func median3(_ idx: [Int]) -> SIMD3<Float> {
            let p = idx.map { SIMD3(samples[$0].transform.columns.3.x, samples[$0].transform.columns.3.y, samples[$0].transform.columns.3.z) }
            let w = idx.map { weights[$0] }
            return SIMD3(Self.weightedMedian(p.map(\.x), w), Self.weightedMedian(p.map(\.y), w), Self.weightedMedian(p.map(\.z), w))
        }
        func position(_ i: Int) -> SIMD3<Float> {
            SIMD3(samples[i].transform.columns.3.x, samples[i].transform.columns.3.y, samples[i].transform.columns.3.z)
        }
        // Inliers within the consistency radius of the rough median; the fraction stays a count,
        // so the duplicate guard (MarkerLock.minInlierFraction) means what it did.
        let rough = median3(keep)
        let inliers = keep.filter { simd_distance(position($0), rough) <= MarkerLock.maxPositionSpread }
        let center = inliers.isEmpty ? rough : median3(inliers)
        let inlierFraction = Float(inliers.count) / Float(keep.count)
        let positionSpread = weightedRMS(keep) { simd_distance(position($0), center) }
        let totalWeight = weights.reduce(0, +)

        return MarkerSampler.Estimate(
            position: center, right: SIMD3(cos(heading), 0, sin(heading)),
            tiltDegrees: zip(tilts, weights).reduce(0) { $0 + $1.0 * $1.1 } / totalWeight,
            headingSpread: headingSpread * 180 / .pi, positionSpread: positionSpread,
            inlierFraction: inlierFraction, used: keep.count, total: samples.count,
            mode: .diverse, viewpoints: samples.count, bearingSpanDegrees: bearingSpanDegrees,
            rejections: rejections)
    }
}
