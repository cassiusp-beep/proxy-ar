import RealityKit
import simd

// MARK: - Drone Tuning Constants (Meters & Seconds)
let DRONE_MAX_HORIZONTAL_SPEED: Float = 0.05   // 5 cm/s max tuned to 15 cm field
let DRONE_VERTICAL_SPEED: Float = 0.03         // 3 cm/s ascend/descend
let DRONE_YAW_RATE: Float = 1.8                // rad/s (~103 deg/s)
let DRONE_MIN_TERRAIN_CLEARANCE: Float = 0.02  // 2 cm minimum altitude above terrain
let DRONE_MAX_ALTITUDE: Float = 0.20           // 20 cm ceiling above pin origin
let DRONE_MAX_BANK_ANGLE: Float = 0.2618       // 15 degrees in radians
let DRONE_HORIZONTAL_DAMPING: Float = 8.0      // Velocity smoothing
let DRONE_ROTATION_DAMPING: Float = 10.0       // Bank angle smoothing
let DRONE_BOUNDS_MARGIN: Float = 0.006         // 6 mm margin inside pin field perimeter
let DRONE_TERRAIN_SAMPLE_RADIUS: Float = 0.008 // 8 mm multi-point sample radius

/// RealityKit component driving the friendly cartoon reconnaissance drone.
struct DroneComponent: Component {
    /// 3D velocity in the content frame (m/s)
    var velocity: SIMD3<Float> = .zero

    /// Heading angle in radians around +Y (0 points -Z, directly away from player into diorama)
    var heading: Float = 0

    /// Current altitude (meters Y in content frame)
    var altitude: Float = 0.05

    /// Desired altitude target driven by pilot input
    var targetAltitude: Float = 0.05

    /// Banking angle (roll around forward axis) in radians
    var bankAngle: Float = 0

    /// Pitch angle (pitch around transverse axis) in radians
    var pitchAngle: Float = 0

    /// Rotor rotation phase angle (radians)
    var rotorPhase: Float = 0

    /// Active state (true when locked and operational)
    var isOperational: Bool = true
}
