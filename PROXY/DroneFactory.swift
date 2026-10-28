import RealityKit
import UIKit
import simd

/// Assembles the friendly cartoon quadcopter and its ground blob shadow.
enum DroneFactory {
    /// Overall dimensions: ~18 mm wide × 18 mm long × 6 mm high, tuned to the 15 cm terrain.
    static let bodyWidth: Float = 0.009
    static let bodyHeight: Float = 0.0042
    static let bodyLength: Float = 0.012
    static let armSpan: Float = 0.0075
    static let rotorRadius: Float = 0.0036
    static let shadowRadius: Float = 0.0085

    @MainActor
    static func makeDrone() -> ModelEntity {
        let root = ModelEntity()
        root.name = "drone"

        // 1. Flight Body Entity (carries altitude, pitch, roll, yaw)
        let body = Entity()
        body.name = "body"
        root.addChild(body)

        // Primary fuselage (rounded candy-colored hull)
        let hullMat = ContentLoader.material(for: ContentLoader.palette[2]) // Sky blue
        let accentMat = ContentLoader.material(for: ContentLoader.palette[0]) // Hot pink
        let trimMat = ContentLoader.material(for: ContentLoader.palette[1]) // Sunshine yellow
        let darkMat = ContentLoader.material(for: UIColor(white: 0.15, alpha: 1.0))
        let rotorMat = ContentLoader.material(for: ContentLoader.palette[3]) // Lime

        let fuselage = ModelEntity(
            mesh: .generateBox(width: bodyWidth, height: bodyHeight, depth: bodyLength, cornerRadius: 0.0018),
            materials: [hullMat]
        )
        fuselage.name = "fuselage"
        body.addChild(fuselage)

        // Upper cockpit visor
        let visor = ModelEntity(
            mesh: .generateBox(width: bodyWidth * 0.72, height: bodyHeight * 0.55, depth: bodyLength * 0.5, cornerRadius: 0.0012),
            materials: [darkMat]
        )
        visor.position = [0, bodyHeight * 0.35, -bodyLength * 0.15]
        body.addChild(visor)

        // Dual sensor "eyes" echoing the [ + + ] motif
        let leftEye = ModelEntity(mesh: .generateSphere(radius: 0.0009), materials: [accentMat])
        leftEye.position = [-0.0022, 0.0003, -bodyLength * 0.51]
        body.addChild(leftEye)

        let rightEye = ModelEntity(mesh: .generateSphere(radius: 0.0009), materials: [accentMat])
        rightEye.position = [0.0022, 0.0003, -bodyLength * 0.51]
        body.addChild(rightEye)

        // Navigation beacon (top rear)
        let beacon = ModelEntity(mesh: .generateSphere(radius: 0.0008), materials: [trimMat])
        beacon.position = [0, bodyHeight * 0.52, bodyLength * 0.25]
        body.addChild(beacon)

        // 4 diagonal rotor arms and spinning propeller discs
        let armCorners: [(x: Float, z: Float, index: Int)] = [
            (-armSpan, -armSpan, 0), // Front-left
            ( armSpan, -armSpan, 1), // Front-right
            (-armSpan,  armSpan, 2), // Rear-left
            ( armSpan,  armSpan, 3)  // Rear-right
        ]

        for corner in armCorners {
            // Strut from body to nacelle
            let strut = ModelEntity(
                mesh: .generateBox(width: 0.0010, height: 0.0008, depth: armSpan * 1.3),
                materials: [darkMat]
            )
            strut.position = [corner.x * 0.5, 0, corner.z * 0.5]
            strut.orientation = simd_quatf(angle: corner.x * corner.z > 0 ? .pi / 4 : -.pi / 4, axis: [0, 1, 0])
            body.addChild(strut)

            // Motor nacelle
            let nacelle = ModelEntity(
                mesh: .generateCylinder(height: 0.0022, radius: 0.0012),
                materials: [hullMat]
            )
            nacelle.position = [corner.x, 0.0005, corner.z]
            body.addChild(nacelle)

            // Spinning rotor disc
            let rotor = ModelEntity(
                mesh: .generateBox(width: rotorRadius * 2, height: 0.0002, depth: 0.0011, cornerRadius: 0.0001),
                materials: [rotorMat]
            )
            rotor.name = "rotor_\(corner.index)"
            rotor.position = [corner.x, 0.0018, corner.z]
            body.addChild(rotor)
        }

        // 2. Ground Blob Shadow (placed directly on the terrain surface)
        var shadowMat = UnlitMaterial(color: UIColor(white: 0.0, alpha: 0.40))
        shadowMat.blending = .transparent(opacity: 0.40)
        let shadow = ModelEntity(
            mesh: .generateCylinder(height: 0.0001, radius: shadowRadius),
            materials: [shadowMat]
        )
        shadow.name = "blob_shadow"
        root.addChild(shadow)

        return root
    }
}
