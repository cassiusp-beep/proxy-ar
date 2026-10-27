import ARKit
import RealityKit
import simd

// BEGIN PURE (copied verbatim into the numeric check; imports nothing but simd)
/// The Diorama's two-marker geometry, free of ARKit so it can be checked on its own.
enum MarkerLock {
    /// Above these the pair is rejected (gross error: swapped or misplaced markers) and the lock
    /// falls back to the left marker alone.
    static let rejectAngleDegrees: Float = 20
    static let rejectSpacingError: Float = 0.015
    /// Above these the pair still locks, with a warning.
    static let warnAngleDegrees: Float = 5
    static let warnSpacingError: Float = 0.003
    /// Fewer samples per marker than this and the pair lock waits.
    static let minPairSamples = 15
    /// Sample-consistency guard: when a marker's samples fail it they are not one marker, and no
    /// lock (single or pair) is made from them: the setup's samplers restart instead. Device,
    /// 2026-10-26: the marker PDF open on the laptop screen plus the printed marker on the table
    /// put two copies of each image in view; ARKit's anchor jumped between them and a pair locked
    /// from samples with ±90.8 mm / ±0.64° spread (spacing off by −10.9 mm, under the gross-error
    /// limit). Clean averaged locks read ±0.6–0.8 mm and ±0.05–0.07°, so these limits leave ~6×
    /// margin. `maxPositionSpread` is the inlier radius about the median position (see
    /// `minInlierFraction`), not a limit on the RMS spread, which one stray sample can blow up.
    static let maxPositionSpread: Float = 0.005
    static let maxHeadingSpreadDegrees: Float = 0.5
    /// Below this fraction of samples within `maxPositionSpread` of the median, the lock is
    /// refused. Tolerates a few stray samples (the untracked first detection, a re-acquisition
    /// jump: one 28 mm off in 30 is 97%), while two copies of a marker in view split the samples
    /// roughly in half (~50%), and a scattered set (22 clean of 30) reads 73%.
    static let minInlierFraction: Float = 0.8
    /// Height comes from the markers; the LiDAR table plane is only logged. Above this marker-vs-
    /// plane disagreement a warning is logged. Planes farther than `maxTablePlaneOffset` are not
    /// this table (the floor, a shelf) and the next raycast target is tried.
    static let warnPlaneDisagreement: Float = 0.003
    static let maxTablePlaneOffset: Float = 0.015
    /// Paper thickness: the markers sit on the paper's top surface, the table plane under it.
    static let paperThickness: Float = 0.0001

    /// The table plane compared with the markers' height (both world y, meters). Never applied to
    /// the anchor. `expectedOffset` is where the setup's reference surface should be, relative to
    /// the marker's paper (plane minus marker, meters): 0 for the Diorama, whose markers lie on the
    /// table. nil when no single surface is known (`PhysicalSetup.expectedPlaneOffset`): the diff is
    /// then raw (plane + paper − marker), only logged, never warned about or filtered.
    struct PlaneCheck {
        /// plane + paper − marker − expectedOffset (raw when `compared` is false).
        let diff: Float
        let compared: Bool
        var isThisTable: Bool { abs(diff) < MarkerLock.maxTablePlaneOffset }
        var disagrees: Bool { compared && abs(diff) > MarkerLock.warnPlaneDisagreement }
    }
    static func planeCheck(markerY: Float, planeY: Float, expectedOffset: Float?) -> PlaneCheck {
        PlaneCheck(diff: planeY + paperThickness - markerY - (expectedOffset ?? 0), compared: expectedOffset != nil)
    }

    /// Right-only refusal escape (demo safety). A pair refusal where the left marker's samples
    /// pass the consistency test and only the right's fail extends the streak; any other outcome
    /// (both fail, the left fails, or both pass) ends it. At `rightOnlyRefusalsBeforeLeftLock` in a
    /// row the lock falls back to the left marker alone. Sync, Re-lock and any lock reset it to 0.
    static let rightOnlyRefusalsBeforeLeftLock = 2
    static func rightOnlyRefusalStreak(previous: Int, leftConsistent: Bool, rightConsistent: Bool) -> Int {
        leftConsistent && !rightConsistent ? previous + 1 : 0
    }

    /// True if a marker's samples are one marker: enough of them near the median position, and
    /// the RMS heading spread (degrees) within its limit.
    static func samplesConsistent(inlierFraction: Float, headingSpreadDegrees: Float) -> Bool {
        inlierFraction >= minInlierFraction && headingSpreadDegrees <= maxHeadingSpreadDegrees
    }

    /// A marker's averaged center (world) and level heading (its +X projected on the floor, unit).
    struct Marker {
        var position: SIMD3<Float>
        var right: SIMD3<Float>
    }

    struct PairPose {
        /// The anchor: the left marker's center, on the center line at the known spacing from the
        /// midpoint, at the markers' mean height.
        let position: SIMD3<Float>
        /// Level heading of the line from the left center to the right one.
        let right: SIMD3<Float>
        let spacing: Float            // horizontal (flattened) center distance, meters
        let spacing3D: Float          // unflattened center distance, meters
        let spacingError: Float       // spacing − expected, meters
        let dy: Float                 // right.y − left.y, meters
        let leftAngle: Float          // degrees from the left marker's heading to the line, about +Y
        let rightAngle: Float         // same for the right marker

        var isGrossError: Bool { abs(leftAngle) > MarkerLock.rejectAngleDegrees || abs(spacingError) > MarkerLock.rejectSpacingError }
        var isSuspect: Bool { abs(leftAngle) > MarkerLock.warnAngleDegrees || abs(spacingError) > MarkerLock.warnSpacingError }
    }

    /// Signed angle (degrees) from `a` to `b` about world +Y; both level.
    static func signedAngle(from a: SIMD3<Float>, to b: SIMD3<Float>) -> Float {
        atan2(simd_cross(a, b).y, simd_dot(a, b)) * 180 / .pi
    }

    /// nil if the centers are under 10 mm apart (the same marker seen twice, or nonsense).
    static func pairPose(left: Marker, right: Marker, spacing expected: Float) -> PairPose? {
        var line = right.position - left.position
        let spacing3D = simd_length(line)
        line.y = 0
        let measured = simd_length(line)
        guard measured > 0.01 else { return nil }
        let dir = line / measured
        var position = (left.position + right.position) / 2 - dir * (expected / 2)
        position.y = (left.position.y + right.position.y) / 2
        return PairPose(position: position, right: dir, spacing: measured, spacing3D: spacing3D,
                        spacingError: measured - expected, dy: right.position.y - left.position.y,
                        leftAngle: signedAngle(from: left.right, to: dir),
                        rightAngle: signedAngle(from: right.right, to: dir))
    }
}
// END PURE

extension MarkerLock {
    /// What a lock placed, kept so "Re-lock (keep world)" can report how far the next lock moved.
    struct Record {
        let anchor: SIMD3<Float>      // the placed anchor (height from the markers)
        let marker: SIMD3<Float>      // the marker-derived position it came from
        let right: SIMD3<Float>
        /// World y of the table plane this lock compared against; nil if none was used.
        let planeY: Float?
    }
}

extension ARViewContainer.Coordinator {
    /// Field Unit: its one marker alone (`PhysicalSetup.primaryMarker`: CalibrationMarker in the
    /// 50 mm guides, or the 100 mm DockMarker filling the pocket). Diorama and pin block: both markers once
    /// each has ≥ 15 samples (all 30, or 15 after the 2 s timeout), or the left alone with its full
    /// 30 if the right hasn't shown up within 3 s (5 s if it appeared but isn't averaged yet).
    func tryLock() {
        // The runtime switch applies at lock time, also to samplers already filling.
        let diverse = settings.diverseSampling
        for name in samplers.keys where samplers[name]?.diverse != diverse { samplers[name]?.diverse = diverse }
        guard !settings.isLocked, let left = samplers[leftMarker] else {
            updateBothMarkersHint()
            return
        }
        guard settings.setup.isPair else {
            updateBothMarkersHint()
            if left.isReady { lockSingle(left) }
            return
        }
        let right = samplers[rightMarker]
        let leftFull = left.isFull
        if let right, pairReady(left, right) {
            lockPair(left: left, right: right)
        } else if leftFull, left.elapsed > (right == nil ? 3 : 5) {
            // A right marker still being averaged gets 2 s more before giving up on it.
            print(right == nil ? "[PROXY] Only the left marker seen; single-marker lock (less accurate)."
                               : "[PROXY] Right marker seen only briefly; single-marker lock (less accurate).")
            lockSingle(left)
        } else {
            updateBothMarkersHint()
        }
    }

    /// `isFull`: switch off, 30 consecutive samples each (as before); on, the viewpoint target
    /// met, or the fallback timeout passed with 30 consecutive samples.
    private func pairReady(_ left: MarkerSampler, _ right: MarkerSampler) -> Bool {
        let least = MarkerLock.minPairSamples
        if left.isFull && right.isFull { return true }
        return left.count >= least && right.count >= least && left.isReady && right.isReady
    }

    /// The pill's "N/12": the least-advanced of the setup's markers (a pair marker not yet seen
    /// counts 0). Written only on change.
    func updateViewpointProgress() {
        let names = [leftMarker] + (settings.setup.isPair ? [rightMarker] : [])
        let n = names.map { samplers[$0]?.viewpoints.progress ?? 0 }.min() ?? 0
        if settings.samplingViewpoints != n { settings.samplingViewpoints = n }
    }

    /// "Show both markers" once one marker has been in view for 1 s without the other.
    func updateBothMarkersHint() {
        let left = samplers[leftMarker], right = samplers[rightMarker]
        let lone = left == nil ? right : (right == nil ? left : nil)
        let hint = settings.setup.isPair && (lone?.elapsed ?? 0) > 1
        if settings.needsBothMarkers != hint { settings.needsBothMarkers = hint }
    }

    private func lockSingle(_ sampler: MarkerSampler, reason: String? = nil) {
        guard let e = sampler.estimate(), samplesConsistent([(leftMarker, e)]) else { return }
        if let reason { print("[PROXY] WARNING: pair rejected (\(reason)); single-marker lock. Check placement: swapped or misplaced markers.") }
        lockSingle(e)
    }

    /// Locks on an estimate that already passed the consistency test.
    private func lockSingle(_ e: MarkerSampler.Estimate) {
        lock(position: e.position, right: e.right, mode: e.mode.rawValue, summary: String(
            format: "Locked to %@ from %d/%d samples: heading spread ±%.2f°, position spread ±%.1f mm, inliers=%.2f viewpoints=%d bearing_span_deg=%.1f mode=%@ %@. Removed %.2f° of marker tilt; ",
            leftMarker, e.used, e.total, e.headingSpread, e.positionSpread * 1000, e.inlierFraction,
            e.viewpoints, e.bearingSpanDegrees, e.mode.rawValue, e.rejections, e.tiltDegrees))
    }

    /// Heading comes from the line between the two marker centers, 96 mm apart, not from either
    /// marker's own heading. The anchor is the left marker's center, placed on that line at the
    /// known spacing from the midpoint (`MarkerLock.pairPose`).
    private func lockPair(left: MarkerSampler, right: MarkerSampler) {
        guard let l = left.estimate(), let r = right.estimate() else { return }
        func passes(_ e: MarkerSampler.Estimate) -> Bool {
            MarkerLock.samplesConsistent(inlierFraction: e.inlierFraction, headingSpreadDegrees: e.headingSpread)
        }
        rightOnlyRefusals = MarkerLock.rightOnlyRefusalStreak(previous: rightOnlyRefusals,
                                                              leftConsistent: passes(l), rightConsistent: passes(r))
        guard samplesConsistent([(leftMarker, l), (rightMarker, r)]) else {
            // Demo safety: a right marker that keeps failing (glare, a stray copy near it) must
            // not block the lock forever when the left is clean. `l` passed the test above.
            if rightOnlyRefusals >= MarkerLock.rightOnlyRefusalsBeforeLeftLock {
                print("[PROXY] WARNING: right marker inconsistent twice; single-marker lock on the left (less accurate).")
                lockSingle(l)
            }
            return
        }
        guard let pair = MarkerLock.pairPose(left: .init(position: l.position, right: l.right),
                                             right: .init(position: r.position, right: r.right),
                                             spacing: settings.setup.pairSpacing) else {
            if left.isFull { lockSingle(left, reason: "markers under 10 mm apart") }
            return
        }
        let errMM = pair.spacingError * 1000
        if pair.isGrossError {
            // Decide with full sample sets; the samplers keep filling while we wait. A right
            // marker that stops filling gets until the left has been seen for 5 s.
            guard left.isFull, right.isFull || left.elapsed > 5 else { return }
            lockSingle(left, reason: String(format: "line vs left heading %+.1f°, spacing off by %+.1f mm", pair.leftAngle, errMM))
            return
        }
        if pair.isSuspect {
            print(String(format: "[PROXY] WARNING: marker spacing off by %+.1f mm, line vs left heading %+.1f°. Markers misplaced, swapped, or misprinted?",
                         errMM, pair.leftAngle))
        }

        // Diagnostics for the playbook §7 protocol, one machine-readable line.
        let mid = (l.position + r.position) / 2
        let camDist = (arView?.session.currentFrame?.camera.transform.columns.3).map {
            String(format: "%.0f", simd_distance(SIMD3($0.x, $0.y, $0.z), mid) * 1000)
        } ?? "nan"
        // Print-scale check (H4): spacing error as a percentage of the known spacing. A uniformly
        // misprinted pair reads as the same percentage off.
        let printScalePct = errMM / (settings.setup.pairSpacing * 1000) * 100
        let full = MarkerSampler.targetSamples
        let low = !left.isFull || !right.isFull
        print(String(format: "[PROXY] PAIR spacing_mm=%.2f spacing3d_mm=%.2f err_mm=%+.2f print_scale_pct=%+.2f dy_mm=%+.2f left_vs_line_deg=%+.2f right_vs_line_deg=%+.2f L_n=%d/%d R_n=%d/%d L_pos_spread_mm=%.2f R_pos_spread_mm=%.2f L_head_spread_deg=%.3f R_head_spread_deg=%.3f L_inliers=%.2f R_inliers=%.2f cam_dist_mm=%@ L_viewpoints=%d R_viewpoints=%d L_bearing_span_deg=%.1f R_bearing_span_deg=%.1f L_mode=%@ R_mode=%@ L_%@ R_%@",
                     pair.spacing * 1000, pair.spacing3D * 1000, errMM, printScalePct, pair.dy * 1000, pair.leftAngle, pair.rightAngle,
                     l.used, l.total, r.used, r.total, l.positionSpread * 1000, r.positionSpread * 1000,
                     l.headingSpread, r.headingSpread, l.inlierFraction, r.inlierFraction, camDist,
                     l.viewpoints, r.viewpoints, l.bearingSpanDegrees, r.bearingSpanDegrees, l.mode.rawValue, r.mode.rawValue,
                     l.rejections.replacingOccurrences(of: " ", with: " L_"), r.rejections.replacingOccurrences(of: " ", with: " R_"))
              + (low ? String(format: " LOW_SAMPLES L=%d R=%d target=%d", left.count, right.count, full) : ""))

        lock(position: pair.position, right: pair.right,
             mode: l.mode == r.mode ? l.mode.rawValue : "\(l.mode.rawValue)+\(r.mode.rawValue)", summary: String(
            format: "Locked to both markers: spacing %.1f mm (expected %.2f), line vs left heading %+.2f°. Left %d/%d samples ±%.2f°, right %d/%d ±%.2f°. Removed %.2f°/%.2f° of marker tilt; ",
            pair.spacing * 1000, settings.setup.pairSpacing * 1000, pair.leftAngle,
            l.used, l.total, l.headingSpread, r.used, r.total, r.headingSpread, l.tiltDegrees, r.tiltDegrees))
    }

    /// Sample-consistency guard (`MarkerLock.minInlierFraction`, `maxHeadingSpreadDegrees`). On
    /// failure: no lock, one warning, the pill asks to hide extra copies, and the samplers restart,
    /// so the next refusal (if any) needs a full new sample set: at most one log line per cycle.
    /// The pill clears itself once no marker has been sampled for `seenTwiceTimeout`.
    private func samplesConsistent(_ estimates: [(name: String, estimate: MarkerSampler.Estimate)]) -> Bool {
        let bad = estimates.filter {
            !MarkerLock.samplesConsistent(inlierFraction: $0.estimate.inlierFraction, headingSpreadDegrees: $0.estimate.headingSpread)
        }
        guard !bad.isEmpty else { return true }
        let detail = bad.map {
            String(format: "%@ inliers=%.2f position spread %.1f mm / heading spread %.2f°", $0.name, $0.estimate.inlierFraction,
                   $0.estimate.positionSpread * 1000, $0.estimate.headingSpread)
        }.joined(separator: "; ")
        print(String(format: "[PROXY] WARNING: lock refused: %@ (limits %.0f%% within %.0f mm / %.1f°). Is a marker visible twice (screen, second print)?",
                     detail, MarkerLock.minInlierFraction * 100, MarkerLock.maxPositionSpread * 1000, MarkerLock.maxHeadingSpreadDegrees))
        samplers = [:]
        settings.isSampling = false
        settings.needsBothMarkers = false
        settings.markerSeenTwice = true
        return false
    }

    /// `summary` opens the lock's log line; the height source and table-plane diff are appended.
    /// `mode` (the sampling mode) only labels the lock's snapshot.
    private func lock(position: SIMD3<Float>, right: SIMD3<Float>, mode: String, summary: String) {
        guard !settings.isLocked, let arView else { return }
        let session = arView.session

        // Pin a plain world anchor at the averaged pose so content stays put
        // after the marker leaves the camera's view.
        let (pose, plane) = leveledPose(position: position, right: right, in: arView)
        let anchor = ARAnchor(name: "markerWorld", transform: pose)
        session.add(anchor: anchor)
        for case let marker as ARImageAnchor in session.currentFrame?.anchors ?? [] {
            session.remove(anchor: marker)
        }

        let anchorEntity = AnchorEntity(anchor: anchor)
        anchorEntity.addChild(offsetEntity)
        arView.scene.addAnchor(anchorEntity)

        self.worldAnchor = anchor
        self.anchorEntity = anchorEntity
        samplers = [:]
        settings.isSampling = false
        settings.needsBothMarkers = false
        settings.markerSeenTwice = false
        settings.isLocked = true
        rightOnlyRefusals = 0
        runSession(reset: false)  // marker detection off; world map and anchor kept
        let height: String
        switch plane {
        case .compared(let diff, _):
            height = String(format: "height from markers; plane diff %+.1f mm", diff * 1000)
        case .uncompared(let diff, _):
            height = String(format: "height from markers; plane raw diff %+.1f mm (Field Unit: not compared)", diff * 1000)
        case .ignored:
            height = String(format: "height from markers; table plane ignored (> %.0f mm)", MarkerLock.maxTablePlaneOffset * 1000)
        case .none:
            height = "height from markers; no table plane found"
        }
        print("[PROXY] " + summary + height + ".")

        let record = MarkerLock.Record(anchor: SIMD3(pose.columns.3.x, pose.columns.3.y, pose.columns.3.z),
                                       marker: position, right: right, planeY: plane.planeY)
        if let previous = lastLock {
            // Only set by "Re-lock (keep world)", so both locks share one world frame.
            // anchor_* is kept for log-format compatibility; since height comes from the markers
            // it equals marker_*. plane_dy_mm tracks the LiDAR plane's own drift between locks.
            let d = record.anchor - previous.anchor, dm = record.marker - previous.marker
            let planeDy = record.planeY.flatMap { y in previous.planeY.map { String(format: "%+.2f", (y - $0) * 1000) } } ?? "na"
            print(String(format: "[PROXY] RELOCK anchor_dpos_mm=%.2f anchor_dx_mm=%+.2f anchor_dy_mm=%+.2f anchor_dz_mm=%+.2f marker_dpos_mm=%.2f marker_dy_mm=%+.2f dheading_deg=%+.3f plane_dy_mm=%@",
                         simd_length(d) * 1000, d.x * 1000, d.y * 1000, d.z * 1000,
                         simd_length(dm) * 1000, dm.y * 1000, MarkerLock.signedAngle(from: previous.right, to: record.right), planeDy))
        }
        // Snapshot ~2 s after the lock: "relock<k>" after Re-lock (keep world), else "lock<k>".
        lockCount += 1
        lastLockMode = mode
        scheduleLockSnapshot(tag: (lastLock == nil ? "lock" : "relock") + "\(lockCount)")
        lastLock = record
    }

    /// What the table-plane raycast found, for the lock's log line and the RELOCK comparison.
    enum PlaneResult {
        /// A plane within `maxTablePlaneOffset` of the expected surface; diff per `PlaneCheck`.
        case compared(diff: Float, planeY: Float)
        /// Field Unit: the first plane hit, logged raw (no single expected surface is known).
        case uncompared(diff: Float, planeY: Float)
        /// Every plane hit was farther than `maxTablePlaneOffset`: not this table.
        case ignored
        case none

        var planeY: Float? {
            switch self {
            case .compared(_, let y), .uncompared(_, let y): return y
            case .ignored, .none: return nil
            }
        }
    }

    /// The marker and the models lie flat on a level table, so only the marker's position and
    /// heading are trusted. A small marker's estimated tilt is often off by a degree or more,
    /// which swings content 20 cm away by millimeters and makes it slide as the phone moves.
    /// Up comes from gravity (ARKit's world Y), and the height from the markers themselves (pair:
    /// mean of L.y and R.y; single: that marker's y; the paper's top surface, so no offset).
    /// The LiDAR table plane used to be snapped to, but over three keep-world re-locks it drifted
    /// 3.7 mm while the markers' height held to 0.3 mm, so (user-approved) it is now only logged,
    /// with a warning above `MarkerLock.warnPlaneDisagreement`. In the Field Unit no single
    /// surface is expected (`PhysicalSetup.expectedPlaneOffset`), so the first hit is logged raw.
    private func leveledPose(position marker: SIMD3<Float>, right: SIMD3<Float>, in arView: ARView) -> (simd_float4x4, PlaneResult) {
        let up = SIMD3<Float>(0, 1, 0)
        let back = simd_cross(right, up)  // marker +Z (toward its bottom edge), level
        let expected = settings.setup.expectedPlaneOffset

        var result = PlaneResult.none
        // Prefer the detected (LiDAR-refined) table plane; fall back to ARKit's rough estimate.
        for target in [ARRaycastQuery.Target.existingPlaneGeometry, .estimatedPlane] {
            let query = ARRaycastQuery(origin: marker + up * 0.05, direction: -up,
                                       allowing: target, alignment: .horizontal)
            guard let hit = arView.session.raycast(query).first else { continue }
            let planeY = hit.worldTransform.columns.3.y
            let check = MarkerLock.planeCheck(markerY: marker.y, planeY: planeY, expectedOffset: expected)
            let kind = target == .existingPlaneGeometry ? "detected" : "estimated"
            guard check.compared else {
                print(String(format: "[PROXY] Height: marker %.1f mm, %@ plane %.1f mm, raw diff %+.1f mm (Field Unit: not compared; the plane may be the pocket floor, the unit's top or the table below).",
                             marker.y * 1000, kind, planeY * 1000, check.diff * 1000))
                result = .uncompared(diff: check.diff, planeY: planeY)
                break
            }
            guard check.isThisTable else {
                print(String(format: "[PROXY] Height: marker %.1f mm, %@ plane %.1f mm, diff %+.1f mm (not this table; ignored).",
                             marker.y * 1000, kind, planeY * 1000, check.diff * 1000))
                result = .ignored
                continue
            }
            print(String(format: "[PROXY] Height: marker %.1f mm, %@ plane %.1f mm, diff %+.1f mm (not applied).",
                         marker.y * 1000, kind, planeY * 1000, check.diff * 1000))
            if check.disagrees {
                print(String(format: "[PROXY] WARNING: table plane disagrees with markers by %+.1f mm.", check.diff * 1000))
            }
            result = .compared(diff: check.diff, planeY: planeY)
            break
        }

        let pose = simd_float4x4(columns: (SIMD4(right, 0), SIMD4(up, 0), SIMD4(back, 0), SIMD4(marker, 1)))
        return (pose, result)
    }
}
