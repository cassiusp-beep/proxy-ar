import RealityKit
import simd

/// System that simulates the drone's flight physics, terrain collision avoidance, banking, and blob shadow.
struct DroneSystem: System {
    static let query = EntityQuery(where: .has(DroneComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        guard let terrain = TerrainData.shared else { return }
        let dt = Float(min(context.deltaTime, 0.1)) // Clamp to avoid large jumps
        let input = GameInput.shared
        let gameState = GameState.shared

        // Tool cycle check from hardware shoulders
        if input.toolCycleDelta != 0 {
            gameState.cycleTool(delta: input.toolCycleDelta)
            input.toolCycleDelta = 0
        }

        // Drain fuel slightly while flying (unless empty)
        if !gameState.isFuelEmpty {
            // ~90 seconds for a full tank = ~1.1% per second
            gameState.fuel = max(0, gameState.fuel - dt * 1.1)
        }

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var drone = entity.components[DroneComponent.self] else { continue }
            guard drone.isOperational else { continue }

            // 1. Update Heading from Yaw Input
            drone.heading -= input.yawInput * DRONE_YAW_RATE * dt
            if drone.heading > .pi { drone.heading -= 2 * .pi }
            if drone.heading < -.pi { drone.heading += 2 * .pi }

            // Direction vectors in content frame (heading 0 = -Z, into the diorama)
            let forward = SIMD3<Float>(-sin(drone.heading), 0, -cos(drone.heading))
            let right = SIMD3<Float>(cos(drone.heading), 0, -sin(drone.heading))

            // 2. Compute Target Horizontal Velocity
            var effectiveMaxSpeed = DRONE_MAX_HORIZONTAL_SPEED
            if gameState.selectedTool == .boost && !gameState.isFuelEmpty {
                effectiveMaxSpeed *= 1.6
            }
            if gameState.isFuelEmpty {
                effectiveMaxSpeed = 0 // Fuel depleted: drone stops horizontal drive
            }

            let targetVelocity = (right * input.moveVector.x + forward * input.moveVector.y) * effectiveMaxSpeed

            // Smooth acceleration and damping
            drone.velocity += (targetVelocity - drone.velocity) * min(1.0, dt * DRONE_HORIZONTAL_DAMPING)

            // 3. Update Position & Clamp to Pin Field Footprint
            var pos = entity.position
            pos.x += drone.velocity.x * dt
            pos.z += drone.velocity.z * dt

            let minX = DRONE_BOUNDS_MARGIN
            let maxX = PIN_FIELD_SIZE.x - DRONE_BOUNDS_MARGIN
            let minZ = -PIN_FIELD_SIZE.y + DRONE_BOUNDS_MARGIN
            let maxZ = -DRONE_BOUNDS_MARGIN

            if pos.x < minX { pos.x = minX; drone.velocity.x = 0 }
            if pos.x > maxX { pos.x = maxX; drone.velocity.x = 0 }
            if pos.z < minZ { pos.z = minZ; drone.velocity.z = 0 }
            if pos.z > maxZ { pos.z = maxZ; drone.velocity.z = 0 }

            // 4. Sample Multi-Point Terrain Clearance
            let r = DRONE_TERRAIN_SAMPLE_RADIUS
            let hCenter = terrain.height(x: pos.x, z: pos.z)
            let hNorth = terrain.height(x: pos.x, z: pos.z - r)
            let hSouth = terrain.height(x: pos.x, z: pos.z + r)
            let hEast = terrain.height(x: pos.x + r, z: pos.z)
            let hWest = terrain.height(x: pos.x - r, z: pos.z)
            let maxLocalTerrain = max(hCenter, max(hNorth, max(hSouth, max(hEast, hWest))))
            let minAllowedAltitude = maxLocalTerrain + DRONE_MIN_TERRAIN_CLEARANCE

            // 5. Altitude & Vertical Flight
            if gameState.isFuelEmpty {
                // Gentle landing on fuel empty
                drone.targetAltitude = minAllowedAltitude
            } else {
                drone.targetAltitude += input.altitudeInput * DRONE_VERTICAL_SPEED * dt
            }
            drone.targetAltitude = max(minAllowedAltitude, min(DRONE_MAX_ALTITUDE, drone.targetAltitude))

            // Smooth altitude change
            drone.altitude += (drone.targetAltitude - drone.altitude) * min(1.0, dt * 10.0)
            drone.altitude = max(minAllowedAltitude, drone.altitude)

            // 6. Dynamic Banking & Pitch into Movement
            let strafeSpeed = simd_dot(drone.velocity, right)
            let forwardSpeed = simd_dot(drone.velocity, forward)
            let targetRoll = -(strafeSpeed / DRONE_MAX_HORIZONTAL_SPEED) * DRONE_MAX_BANK_ANGLE
            let targetPitch = (forwardSpeed / DRONE_MAX_HORIZONTAL_SPEED) * DRONE_MAX_BANK_ANGLE

            drone.bankAngle += (targetRoll - drone.bankAngle) * min(1.0, dt * DRONE_ROTATION_DAMPING)
            drone.pitchAngle += (targetPitch - drone.pitchAngle) * min(1.0, dt * DRONE_ROTATION_DAMPING)

            // 7. Spinning Rotors
            let rotorSpinRate: Float = gameState.isFuelEmpty ? 5.0 : 45.0
            drone.rotorPhase += dt * rotorSpinRate

            // 8. Apply Hierarchy Transforms
            entity.position = SIMD3<Float>(pos.x, 0, pos.z)

            if let body = entity.findEntity(named: "body") {
                body.position = SIMD3<Float>(0, drone.altitude, 0)
                let qYaw = simd_quatf(angle: drone.heading, axis: [0, 1, 0])
                let qPitch = simd_quatf(angle: drone.pitchAngle, axis: [1, 0, 0])
                let qRoll = simd_quatf(angle: drone.bankAngle, axis: [0, 0, 1])
                body.orientation = qYaw * qPitch * qRoll

                // Spin individual rotors
                for i in 0..<4 {
                    if let rotor = body.findEntity(named: "rotor_\(i)") {
                        let spin = (i % 2 == 0) ? drone.rotorPhase : -drone.rotorPhase
                        rotor.orientation = simd_quatf(angle: spin, axis: [0, 1, 0])
                    }
                }
            }

            // 9. Position Ground Blob Shadow
            if let shadow = entity.findEntity(named: "blob_shadow") {
                shadow.position = SIMD3<Float>(0, hCenter + 0.0005, 0)
                let heightAboveGround = max(0.01, drone.altitude - hCenter)
                let shadowScale = max(0.65, min(1.35, 1.0 + (heightAboveGround - 0.03) * 3.5))
                shadow.scale = SIMD3<Float>(shadowScale, 1.0, shadowScale)
            }

            // 10. Update Telemetry for HUD
            gameState.droneAltitudeMM = (drone.altitude - hCenter) * 1000
            var headingDegrees = (-drone.heading * 180.0 / .pi).truncatingRemainder(dividingBy: 360.0)
            if headingDegrees < 0 { headingDegrees += 360.0 }
            gameState.droneHeadingDeg = headingDegrees

            entity.components.set(drone)
        }
    }
}
