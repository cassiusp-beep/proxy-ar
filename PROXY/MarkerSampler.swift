import Foundation
import simd

/// Averages the marker's pose over many frames before locking.
///
/// A single detection of a 50 mm marker misjudges its heading by up to a degree or two, and the
/// model's far side is 20 cm away: 3.5 mm per degree (docs/AR_ALIGNMENT_PLAYBOOK.md §5.1).
/// While unlocked, ARKit tracks the marker and every update is sampled; headings are averaged on
/// the circle with outliers dropped, positions by per-axis median of the samples near the median. One sampler per reference image,
/// so the Diorama's two-marker lock averages each marker on its own.
///
/// With diverse sampling on (`diverse`, the runtime switch), each tracked sample also goes to a `ViewpointSet` (kept only from
/// new camera viewpoints, weighted by incidence), and the lock waits for enough viewpoints over a
/// wide enough bearing span. If that hasn't happened `DIVERSE_FALLBACK_TIMEOUT` s after the first
/// sighting, the consecutive path below decides exactly as with the switch off.
struct MarkerSampler {
    static let targetSamples = 30
    static let minSamples = 6
    /// Lock with what we have if the marker keeps slipping out of view.
    static let timeout: TimeInterval = 2.0

    struct Estimate {
        let position: SIMD3<Float>
        let right: SIMD3<Float>        // level heading: the marker's +X projected onto the floor
        let tiltDegrees: Float         // mean tilt that leveling removes
        let headingSpread: Float       // degrees, RMS of the kept samples about the mean
        let positionSpread: Float      // meters, RMS distance of the kept samples from the median
        /// Fraction of the kept samples within `MarkerLock.maxPositionSpread` of the median position.
        /// Unlike the RMS spread, one stray sample (the untracked first detection, a re-acquisition
        /// jump) barely moves it; two copies of the marker in view halve it.
        let inlierFraction: Float
        let used: Int
        let total: Int
        /// How this estimate was made: `consecutive` (switch off), `diverse` (the viewpoint set),
        /// or `fallback` (switch on, but the consecutive window was used).
        let mode: Mode
        /// Viewpoints accepted and their bearing span (degrees) when the estimate was made; 0 with
        /// the switch off.
        let viewpoints: Int
        let bearingSpanDegrees: Float
        /// Viewpoint-set rejections by reason (`ViewpointSet.rejections`), for tuning the limits.
        let rejections: String
    }

    enum Mode: String { case consecutive, diverse, fallback }

    /// The latest `targetSamples` anchor transforms, oldest first.
    private(set) var samples: [simd_float4x4] = []
    /// When this marker was first seen; not reset as old samples roll off.
    private var started: Date?
    /// Non-finite transforms dropped by `add`.
    private(set) var ignored = 0
    /// Diverse sampling only; stays empty while `diverse` is off.
    private(set) var viewpoints = ViewpointSet()
    /// The runtime switch (`PlacementSettings.diverseSampling`, default `DIVERSE_SAMPLING`). The
    /// coordinator refreshes it on every sample and before every lock attempt, so the debug
    /// toggle applies at lock time. Off: the consecutive path exactly.
    var diverse: Bool

    init(diverse: Bool) {
        self.diverse = diverse
    }

    var count: Int { samples.count }

    /// Seconds since this marker was first seen; 0 if it hasn't been.
    var elapsed: TimeInterval { started.map { Date().timeIntervalSince($0) } ?? 0 }

    var isReady: Bool {
        guard diverse else { return consecutiveReady }
        return viewpoints.isReady || (elapsed > DIVERSE_FALLBACK_TIMEOUT && consecutiveReady)
    }

    /// A complete sample set: the lock code's "full" (switch off: `targetSamples` consecutive).
    var isFull: Bool {
        guard diverse else { return samples.count >= Self.targetSamples }
        return viewpoints.isReady || (elapsed > DIVERSE_FALLBACK_TIMEOUT && samples.count >= Self.targetSamples)
    }

    /// Today's rule, unchanged: all 30, or at least 6 after the 2 s timeout.
    private var consecutiveReady: Bool {
        guard let started else { return false }
        return samples.count >= Self.targetSamples
            || (samples.count >= Self.minSamples && Date().timeIntervalSince(started) > Self.timeout)
    }

    /// Ring buffer: while one marker waits for the other, its window keeps sliding, so the lock
    /// uses the freshest 30 samples (the phone has usually settled by then). `count` saturates
    /// at `targetSamples`, so readiness is unchanged.
    /// Transforms with any non-finite element (a NaN or infinite translation or axis) are
    /// ignored: one NaN heading would otherwise poison the circular mean for the whole window.
    /// `camera` is the camera's world transform for this sample; nil (untracked first detection,
    /// no current frame) or the switch off keeps the sample out of the viewpoint set.
    mutating func add(_ transform: simd_float4x4, camera: simd_float4x4?) {
        let c = transform.columns
        guard [c.0, c.1, c.2, c.3].allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && $0.w.isFinite }) else {
            ignored += 1
            if ignored == 1 { print("[PROXY] WARNING: ignored a marker sample with a non-finite transform (logged once per sampler).") }
            return
        }
        if started == nil { started = Date() }
        samples.append(transform)
        if samples.count > Self.targetSamples {
            samples.removeFirst(samples.count - Self.targetSamples)
        }
        if diverse, let camera { viewpoints.add(transform, camera: camera) }
    }

    /// Switch off: the consecutive estimate. On: the viewpoint estimate once the set is ready,
    /// else (timeout) the consecutive one. A ready set whose samples fail the consistency test
    /// (per-viewpoint heading bias beyond `MarkerLock.maxHeadingSpreadDegrees`) also falls back to
    /// the consecutive window, so diversity never refuses a lock the old path would make; a
    /// marker seen twice fails the consecutive window too and is refused as before.
    func estimate() -> Estimate? {
        guard diverse else { return consecutiveEstimate(mode: .consecutive) }
        if viewpoints.isReady, let d = viewpoints.estimate() {
            if MarkerLock.samplesConsistent(inlierFraction: d.inlierFraction, headingSpreadDegrees: d.headingSpread) {
                return d
            }
            print(String(format: "[PROXY] Diverse samples inconsistent (inliers=%.2f, heading spread ±%.2f° over %d viewpoints); using the last %d consecutive samples.",
                         d.inlierFraction, d.headingSpread, d.viewpoints, samples.count))
        }
        return consecutiveEstimate(mode: .fallback)
    }

    /// Today's estimate, unchanged apart from the labels it carries.
    private func consecutiveEstimate(mode: Mode) -> Estimate? {
        guard !samples.isEmpty else { return nil }
        let up = SIMD3<Float>(0, 1, 0)
        let headings = samples.map { m in atan2(m.columns.0.z, m.columns.0.x) }
        let tilts = samples.map { m -> Float in
            let n = simd_normalize(SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z))
            return acos(min(1, max(-1, simd_dot(n, up)))) * 180 / .pi
        }

        func circularMean(_ angles: [Float]) -> Float {
            atan2(angles.reduce(0) { $0 + sin($1) }, angles.reduce(0) { $0 + cos($1) })
        }
        func wrapped(_ a: Float) -> Float { atan2(sin(a), cos(a)) }

        // Drop headings far from the mean (2.5 σ, never tighter than 0.3°), then re-average.
        let first = circularMean(headings)
        let deviations = headings.map { wrapped($0 - first) }
        let sigma = sqrt(deviations.reduce(0) { $0 + $1 * $1 } / Float(deviations.count))
        let limit = max(2.5 * sigma, 0.3 * .pi / 180)
        let keep = deviations.indices.filter { abs(deviations[$0]) <= limit }
        // Guard: a non-finite heading (NaN mean or sigma) fails every comparison and empties
        // `keep`; the medians below would then index an empty array. Callers treat nil as "wait".
        guard !keep.isEmpty else { return nil }
        let heading = circularMean(keep.map { headings[$0] })
        let headingSpread = sqrt(keep.reduce(Float(0)) { $0 + pow(wrapped(headings[$1] - heading), 2) } / Float(keep.count))

        func median(_ values: [Float]) -> Float {
            let sorted = values.sorted()
            let mid = sorted.count / 2
            return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
        }
        func median3(_ points: [SIMD3<Float>]) -> SIMD3<Float> {
            SIMD3(median(points.map(\.x)), median(points.map(\.y)), median(points.map(\.z)))
        }
        let positions = keep.map { SIMD3(samples[$0].columns.3.x, samples[$0].columns.3.y, samples[$0].columns.3.z) }
        // Inliers: within the consistency radius of the median of all kept samples. The lock
        // position is then the median of the inliers alone: the plain median already ignores a
        // stray sample's distance, but outliers all on one side still pull it a few ranks across
        // the clean cluster (~0.3 mm at 20% outliers); re-taking it over the inliers removes that.
        let radius = MarkerLock.maxPositionSpread
        let rough = median3(positions)
        let inliers = positions.filter { simd_distance($0, rough) <= radius }
        let position = inliers.isEmpty ? rough : median3(inliers)
        let inlierFraction = Float(inliers.count) / Float(positions.count)
        let positionSpread = sqrt(positions.reduce(Float(0)) { $0 + simd_length_squared($1 - position) } / Float(positions.count))

        return Estimate(position: position, right: SIMD3(cos(heading), 0, sin(heading)),
                        tiltDegrees: tilts.reduce(0, +) / Float(tilts.count),
                        headingSpread: headingSpread * 180 / .pi, positionSpread: positionSpread,
                        inlierFraction: inlierFraction,
                        used: keep.count, total: samples.count,
                        mode: mode, viewpoints: viewpoints.count, bearingSpanDegrees: viewpoints.bearingSpanDegrees,
                        rejections: viewpoints.rejections)
    }
}
