import RealityKit
import simd

/// Component marking an NPC as a designated reconnaissance target in the current mission.
struct TargetComponent: Component {
    /// Identifier 1...N
    var targetId: Int

    /// Settlement sector name (e.g. "LOW", "MID", "HIGH")
    var sector: String = "LOW"

    /// Whether this target has already been tagged
    var isTagged: Bool = false

    /// Animation phase for pulsing ring effect
    var pulsePhase: Float = 0

    /// Timer for tag celebration pop animation
    var popTimer: Float = 0
}
