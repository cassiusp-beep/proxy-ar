import Foundation
import Observation
import RealityKit

// BEGIN SAMPLING (copied verbatim into the numeric check; pure Swift)
/// Viewpoint-diverse sampling before the lock (MarkerSampler, ViewpointSet). Device, 2026-10-27:
/// within one lock the 30 consecutive samples agree to ~0.05–0.3°, but keep-world re-locks from
/// different viewpoints differ by ~0.8–1.0° and 3–4 mm. The image-anchor error is per viewpoint,
/// so averaging one viewpoint's frames can't remove it; averaging over viewpoints can.
/// `false` restores the consecutive 30-sample path exactly ("Hold steady…"). This is the default
/// for `PlacementSettings.diverseSampling`, which the debug panel's "Sweep while locking" toggles
/// at runtime (A/B tests).
let DIVERSE_SAMPLING = false  // Off by default per the 2026-10-27 session-7 A/B test (DECISIONS 019); runtime toggle remains.
/// A sample counts as a new viewpoint once the camera has moved this far (meters) OR its
/// direction from the marker has turned this much (degrees) since the last accepted one.
/// At 30 cm, 2 cm of sideways travel is ~3.8°, so the two agree for side-to-side motion; turning
/// the phone in place moves neither and adds nothing.
let DIVERSE_MIN_CAMERA_MOVE: Float = 0.02
let DIVERSE_MIN_BEARING_CHANGE_DEGREES: Float = 3
/// Camera-to-marker distance accepted (meters). 0.18, not 0.20: logged locks read
/// cam_dist 196–267 mm, so 0.20 would reject the closest of today's normal viewpoints.
let DIVERSE_MIN_DISTANCE: Float = 0.18
let DIVERSE_MAX_DISTANCE: Float = 0.45
/// Largest accepted angle between the camera ray and the marker normal. Each sample is weighted
/// by cos²(incidence): 1 head-on, 0.41 at the limit.
let DIVERSE_MAX_INCIDENCE_DEGREES: Float = 50
/// Ready once this many viewpoints are accepted AND the widest angle between any two of their
/// directions (seen from the marker) reaches the span. 12 at ≥ 3° steps needs ≥ 15° of travel
/// or some back and forth; 15° is ~8 cm of side-to-side at 30 cm, about one slow sweep.
let DIVERSE_TARGET_VIEWPOINTS = 12
let DIVERSE_MIN_BEARING_SPAN_DEGREES: Float = 15
/// Accepted viewpoints kept (oldest dropped), so a pair's first-ready marker keeps a bounded set.
let DIVERSE_MAX_VIEWPOINTS = 30
/// Seconds after a marker's first sighting before giving up on diversity and locking from the
/// last 30 consecutive samples exactly as with `DIVERSE_SAMPLING = false`.
let DIVERSE_FALLBACK_TIMEOUT: TimeInterval = 6
// END SAMPLING

/// Field Unit 50: offset from the 50 mm CalibrationMarker's center to the pin origin (the pin
/// model's lower-left corner), in meters.
///
/// Expressed in ARKit's image-anchor frame. The player stands at the Field Unit's front, which is
/// Rhino +X (diorama.py: "every facade faces the viewer (+X)"). The marker is placed upright as
/// read from there, top edge toward the pins:
///   +X → toward the marker's right edge  (Rhino +Y)
///   +Y → up, out of the printed marker   (Rhino +Z)
///   +Z → toward the marker's bottom edge (Rhino +X, toward the player)
/// so the content (Rhino X → +X) is turned −90° about +Y relative to the marker.
///
/// Derived from Actuator Release.3dm: the marker sits on the pocket floor inside the four 1 mm
/// corner guides (50.4 mm opening, X 226.374–276.774, Y 9.4–59.8); its center is Rhino
/// (251.574, 34.6, 13.58), i.e. (246.574, 34.6, 6.0) mm from PINS_ORIGIN, plus 0.2 mm for a
/// matte sticker.
/// Fine-tune with the debug panel (three-finger tap), press "Print values", paste the lines here.
let MARKER_TO_ORIGIN = SIMD3<Float>(-0.0346, -0.0062, -0.2466)

/// Yaw (degrees, around +Y) and uniform scale applied with MARKER_TO_ORIGIN.
let MARKER_TO_ORIGIN_YAW_DEGREES: Float = -90
let MARKER_TO_ORIGIN_SCALE: Float = 1

/// Field Unit 100: the same offset for the 100 mm "DockMarker", a stiff card that fills the
/// sync-dock pocket and rests on top of the 1 mm corner guides. Same frame conventions and yaw
/// as MARKER_TO_ORIGIN (upright from the front, notch top-left: marker +X = Rhino +Y,
/// +Y = Rhino +Z, +Z = Rhino +X).
///
/// Measured from Actuator Release.3dm (BASE_TEXTURED_V2_PARTS, "texture_v2_part_5 front-left
/// (marker)", 2026-10-27):
///   pocket walls  X 180.974–281.574, Y 4.6–105.2 (100.6 mm square; the rim is 2 mm tall, Z 15.58)
///   pocket floor  Z 13.58; corner-guide tops Z 14.58
///   card          100.0 mm square, 0.3 mm clearance per side, so its center is the pocket center
///                 X (180.974 + 281.574)/2 = 231.274, Y (4.6 + 105.2)/2 = 54.9
///   printed face  Z 14.58 + t, t = 1.2 mm (≥1 mm board + paper + glue) → Z 15.78
/// From PINS_ORIGIN (5, 0, 7.58): Δ = (226.274, 54.9, 8.2) mm in Rhino X, Y, Z. The pin origin
/// seen from the marker is −Δ; in marker axes (x, y, z) = (−ΔY, −ΔZ, −ΔX) = (−54.9, −8.2, −226.274) mm.
/// A thicker board lowers y by its extra thickness (y = −(7.0 + t) mm). If the guides are sanded
/// off and the card lies on the floor, y = −(6.0 + t) mm.
let DOCK_MARKER_TO_ORIGIN = SIMD3<Float>(-0.0549, -0.0082, -0.22627)
let DOCK_MARKER_TO_ORIGIN_YAW_DEGREES: Float = -90
let DOCK_MARKER_TO_ORIGIN_SCALE: Float = 1

/// Same offset for the diorama (trophy) print, with the marker on the table in front of it.
/// The paper is trimmed to the marker's black border, so only Rhino dimensions matter: the
/// border's top edge against the marble base's front face (Rhino X 182.8) and its left edge in
/// line with the base's left side (Rhino Y 0), as seen from the front. Marker center: Rhino
/// (207.8, 25.0, 0.1) mm. The diorama's terrain shares the pins' Rhino coordinates.
/// This is the LEFT marker ("CalibrationMarker"); the lock anchors to its center either way.
/// A single 50 mm marker's pose varied by mm and 1–2° between locks, so a saved 3.3 mm correction
/// (2026-10-26) fixed one session and not the next. The two-marker lock replaces it, so this is
/// back to the geometric value.
let DIORAMA_MARKER_TO_ORIGIN = SIMD3<Float>(-0.0250, 0.0075, -0.2028)
let DIORAMA_MARKER_TO_ORIGIN_YAW_DEGREES: Float = -90
let DIORAMA_MARKER_TO_ORIGIN_SCALE: Float = 1

/// Center-to-center distance (meters) from the left marker to the right one ("CalibrationMarkerRight"),
/// along the markers' +X (Rhino +Y). The right marker's right edge is flush with the base's right side
/// (Rhino Y 146.35), so its center is Rhino (207.8, 121.35). The heading comes from this line: a
/// 96.35 mm baseline vs one marker's 50 mm (~1.9×). It beats a single marker's own heading only if
/// each marker's position is good to ≲0.5 mm or their errors are common-mode; the first device
/// session's logs (playbook §7) decide it.
let DIORAMA_MARKER_SPACING: Float = 0.09635

/// Pin block: the standalone printed pin block (pins_block.stl, no Field Unit base) on the table,
/// with the Diorama's two 50 mm markers (same pair lock) trimmed to the border, top edges against
/// the block's front face, LEFT flush with its left side, RIGHT flush with its right side, upright
/// as read from the front (notch top-left). Same frame conventions and yaw as MARKER_TO_ORIGIN.
///
/// From Actuator Release.3dm and pins_log.txt: PINS_FULL spans X 5–163.574, Y 0–146.354,
/// Z 9.08–137.358 (pins_block.stl is the same solid, Z 0–128.278, so its floor is Rhino Z 9.08).
/// PINS_ORIGIN Z 7.58 is the Field Unit base's bottom; the block's 1.5 mm floor drops into a
/// 1.5 mm recess in that base, so standing alone on the table the origin is 1.5 mm BELOW the table.
///   front face  X 163.574  →  LEFT center X 163.574 + 25 = 188.574
///   left side   Y 0        →  LEFT center Y 25.0
///   table       Z 9.08     →  marker face Z 9.08 + 0.1 (paper) = 9.18
/// Marker → pin origin, Rhino: (5 − 188.574, 0 − 25.0, 7.58 − 9.18) = (−183.574, −25.0, −1.6) mm;
/// in marker axes (x, y, z) = (Rhino Y, Z, X) = (−25.0, −1.6, −183.574) mm.
let PINBLOCK_MARKER_TO_ORIGIN = SIMD3<Float>(-0.0250, -0.0016, -0.18357)
let PINBLOCK_MARKER_TO_ORIGIN_YAW_DEGREES: Float = -90
let PINBLOCK_MARKER_TO_ORIGIN_SCALE: Float = 1
/// RIGHT center Y 146.354 − 25 = 121.354, so the spacing is 96.354 mm (Diorama: 96.35).
let PINBLOCK_MARKER_SPACING: Float = 0.096354

/// Reference image names in "AR Resources".
enum MarkerName {
    static let left = "CalibrationMarker"        // 50 mm: Diorama LEFT, and the Field Unit 50 guides
    static let right = "CalibrationMarkerRight"  // 50 mm: Diorama RIGHT
    static let dock = "DockMarker"               // 100 mm: fills the Field Unit's sync-dock pocket
}

/// Which physical model the marker is placed against. Each setup samples and locks only on its
/// own reference image(s); any other marker in view is ignored.
enum PhysicalSetup: String, CaseIterable {
    case diorama = "Diorama"
    case fieldUnit50 = "Field Unit 50"
    case fieldUnit100 = "Field Unit 100"
    case pinBlock = "Pin block"

    var isFieldUnit: Bool { self == .fieldUnit50 || self == .fieldUnit100 }
    /// Physical pins in front of the camera (the pin occluder can act); the diorama has none.
    var hasPins: Bool { self != .diorama }
    /// Two-marker lock (LEFT + RIGHT): the Diorama and the pin block.
    var isPair: Bool { self == .diorama || self == .pinBlock }
    /// LEFT-to-RIGHT center spacing for the pair lock (meters); unused by single-marker setups.
    var pairSpacing: Float { self == .pinBlock ? PINBLOCK_MARKER_SPACING : DIORAMA_MARKER_SPACING }

    /// The marker the lock anchors to (the Diorama's left one).
    var primaryMarker: String { self == .fieldUnit100 ? MarkerName.dock : MarkerName.left }
    /// The pair's right marker; nil for the single-marker Field Unit setups.
    var secondaryMarker: String? { isPair ? MarkerName.right : nil }
    func uses(_ name: String) -> Bool { name == primaryMarker || name == secondaryMarker }

    var offset: SIMD3<Float> {
        switch self {
        case .diorama: DIORAMA_MARKER_TO_ORIGIN
        case .fieldUnit50: MARKER_TO_ORIGIN
        case .fieldUnit100: DOCK_MARKER_TO_ORIGIN
        case .pinBlock: PINBLOCK_MARKER_TO_ORIGIN
        }
    }
    var yawDegrees: Float {
        switch self {
        case .diorama: DIORAMA_MARKER_TO_ORIGIN_YAW_DEGREES
        case .fieldUnit50: MARKER_TO_ORIGIN_YAW_DEGREES
        case .fieldUnit100: DOCK_MARKER_TO_ORIGIN_YAW_DEGREES
        case .pinBlock: PINBLOCK_MARKER_TO_ORIGIN_YAW_DEGREES
        }
    }
    var scale: Float {
        switch self {
        case .diorama: DIORAMA_MARKER_TO_ORIGIN_SCALE
        case .fieldUnit50: MARKER_TO_ORIGIN_SCALE
        case .fieldUnit100: DOCK_MARKER_TO_ORIGIN_SCALE
        case .pinBlock: PINBLOCK_MARKER_TO_ORIGIN_SCALE
        }
    }
    var constantPrefix: String {
        switch self {
        case .diorama: "DIORAMA_MARKER_TO_ORIGIN"
        case .fieldUnit50: "MARKER_TO_ORIGIN"
        case .fieldUnit100: "DOCK_MARKER_TO_ORIGIN"
        case .pinBlock: "PINBLOCK_MARKER_TO_ORIGIN"
        }
    }

    /// Where the table plane should sit relative to the marker's paper (plane minus marker, meters),
    /// for the lock's height check (`MarkerLock.planeCheck`). Diorama and pin block: 0, the markers
    /// lie on the same table as the model.
    /// Field Unit (both): nil, no single surface is known, so the plane is logged raw and never
    /// warned about. The marker is in the dock's pocket (floor Rhino Z 13.58; the 100 mm card's
    /// face ≈ 2.2 mm above it). A raycast down from above it may hit a plane on the marker itself
    /// (≈ 0), the unit's top (Actuator Release.3dm doesn't say which base variant was printed:
    /// their tops reach Z 22.18–26.38, i.e. 8.6–12.8 mm above the floor, not the 6 mm once
    /// assumed), or the table under the unit (its bottom is Z ≈ 1.4, so ≈ 12 mm below: inside the
    /// 15 mm "this table" window, so any fixed offset would mislabel it).
    var expectedPlaneOffset: Float? { isPair ? 0 : nil }

    /// Reads a stored setup; the pre-2026-10-27 "Field Unit" meant the 50 mm guide marker.
    init?(stored: String) {
        self.init(rawValue: stored == "Field Unit" ? PhysicalSetup.fieldUnit50.rawValue : stored)
    }
}

/// Pin field footprint from PINS_FULL (meters): extends +X and −Z from the pin origin.
let PIN_FIELD_SIZE = SIMD2<Float>(0.158574, 0.146354)

@Observable
final class PlacementSettings {
    /// Remembered between launches; switching applies that setup's measured offset.
    var setup: PhysicalSetup {
        didSet {
            UserDefaults.standard.set(setup.rawValue, forKey: "physicalSetup")
            reset()
        }
    }
    var x: Float = 0
    var y: Float = 0
    var z: Float = 0
    var yawDegrees: Float = 0
    var scale: Float = 1

    var showDebug = false
    var showCity = true
    /// Lower it to see the physical model through the city while aligning.
    var cityOpacity: Float = 1
    var showNPCs = true
    var showPlaceholder = false
    /// The pin occluder only acts while the city is hidden: the opaque city already replaces
    /// the physical model and hides whatever is behind its ridges (DECISIONS 010).
    var pinOcclusion = true
    var lidarOcclusion = false
    var handOcclusion = true
    var showMesh = false
#if targetEnvironment(simulator)
    var isLocked = true
#else
    var isLocked = false
#endif
    /// The marker is in view and its pose is being averaged before locking.
    var isSampling = false
    /// Viewpoint-diverse sampling before the lock; read by the samplers at lock time.
    var diverseSampling = DIVERSE_SAMPLING
    /// Diverse sampling: viewpoints toward `DIVERSE_TARGET_VIEWPOINTS` (the least-advanced marker
    /// for the pair setups); held one short until the bearing span is met. Shown in the pill.
    var samplingViewpoints = 0
    /// Diorama only: one marker has been in view for a while but the other hasn't appeared.
    var needsBothMarkers = false
    /// A lock was refused because a marker's samples spread too far (two copies of it in view?).
    /// Cleared by the next lock, by Sync, and once no marker has been sampled for ~1 s.
    var markerSeenTwice = false

    /// Bumped by the Sync button; ARViewContainer drops its anchor when this changes.
    var syncRequest = 0
    /// Bumped by "Re-lock (keep world)": drop the anchor and lock again without resetting tracking.
    var relockRequest = 0
    /// Bumped by "Snapshot": save the AR view to Documents/Snapshots (SnapshotStore).
    var snapshotRequest = 0

    /// LiDAR fidelity scan: "Start scan" sets isScanning; ARViewContainer fills in progress, fits
    /// at full coverage or when "Fit now" bumps fitRequest, and reports in fitStatus.
    var isScanning = false
    var scanCoverage: Float = 0
    var scanPoints = 0
    var fitRequest = 0
    var fitStatus: String?
    var fitResult: FidelityFit.Result?

    var transform: Transform {
        Transform(
            scale: SIMD3(repeating: scale),
            rotation: simd_quatf(angle: yawDegrees * .pi / 180, axis: [0, 1, 0]),
            translation: [x, y, z]
        )
    }

    init() {
        setup = PhysicalSetup(stored: UserDefaults.standard.string(forKey: "physicalSetup") ?? "") ?? .pinBlock
        reset()
    }

    func reset() {
        x = setup.offset.x
        y = setup.offset.y
        z = setup.offset.z
        yawDegrees = setup.yawDegrees
        scale = setup.scale
    }

    /// Fold the fit's correction into the offset: new = old · correction⁻¹, so scanned points land
    /// on the terrain. Scale is unchanged; the correction is a shift plus yaw.
    /// DISABLED in the UI (2026-10-27): the fit is biased (along-ray LiDAR depth bias reads as a
    /// false +x; yaw scatter sd 1.8°) and applying it made the alignment worse on device. The
    /// "Apply fit" button is gone until an along-ray fit replaces this (playbook §5, §1); the scan
    /// and its read-only result stay.
    func applyFit() {
        guard let fit = fitResult else { return }
        setOffset(transform.matrix * fit.correction.inverse)
        fitResult = nil
        fitStatus = "Fit applied. Tap Print values to keep it."
    }

    /// Move the city in its own frame (meters): +x toward the front (the viewer), +y up,
    /// +z toward the left as seen from the front. Yaw turns it about the model's center.
    func nudge(_ delta: SIMD3<Float>, yawDegrees turn: Float = 0) {
        let center = SIMD3<Float>(PIN_FIELD_SIZE.x / 2, 0, -PIN_FIELD_SIZE.y / 2)
        let rotation = float4x4(simd_quatf(angle: turn * .pi / 180, axis: [0, 1, 0]))
        setOffset(transform.matrix * translationMatrix(delta + center) * rotation * translationMatrix(-center))
    }

    private func setOffset(_ m: float4x4) {
        x = m.columns.3.x
        y = m.columns.3.y
        z = m.columns.3.z
        yawDegrees = atan2(-m.columns.0.z, m.columns.0.x) * 180 / .pi
    }

    private func translationMatrix(_ t: SIMD3<Float>) -> float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t, 1)
        return m
    }

    func printValues() {
        func f(_ v: Float) -> String { String(format: "%.4f", v) }
        print("""
        // ---- PROXY calibration (\(setup.rawValue)) ----
        let \(setup.constantPrefix) = SIMD3<Float>(\(f(x)), \(f(y)), \(f(z)))
        let \(setup.constantPrefix)_YAW_DEGREES: Float = \(String(format: "%.2f", yawDegrees))
        let \(setup.constantPrefix)_SCALE: Float = \(f(scale))
        // ----------------------------
        """)
    }
}
