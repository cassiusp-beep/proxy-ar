import RealityKit
import UIKit

/// A townsperson walking the terrain. NPCSystem drives every entity that has one.
struct NPCComponent: Component {
    enum Activity {
        /// Walking a path; `forward` means from its start node to its end node.
        case walking(path: Int, forward: Bool, distance: Float)
        /// Strolling around a node's forecourt, `legsLeft` strolls before heading home to `node`.
        case wandering(node: String, target: SIMD2<Float>, legsLeft: Int)
        case pausing(node: String, timeLeft: Float)
    }

    var activity: Activity
    var position: SIMD2<Float>          // (x, z) in the content frame
    var height: Float                   // smoothed foot height, so steps read as steps, not teleports
    var speed: Float                    // m/s
    var heading: Float = 0              // radians around +Y
    var stride: Float = 0               // walk-cycle phase
    var panicTimer: Float = 0           // When > 0, rapid scatter flee state
    var panicVector: SIMD2<Float> = .zero
}

enum NPCFactory {
    /// The diorama's figures are 5.5 mm tall and 3 mm wide; NPCs match them.
    static let height: Float = 0.0055

    static let shirtColors: [UIColor] = ContentLoader.palette
    static let skin = UIColor(red: 1.00, green: 0.86, blue: 0.70, alpha: 1)
    static let chitin = UIColor(red: 0.12, green: 0.08, blue: 0.05, alpha: 1)

    @MainActor
    static func make(colorIndex: Int) -> ModelEntity {
        let shirt = ContentLoader.material(for: shirtColors[colorIndex % shirtColors.count])
        let root = ModelEntity()
        root.name = "npc"

        // 1. Humanoid Body (Prestige 0)
        let body = Entity()
        body.name = "body"
        root.addChild(body)

        let torso = ModelEntity(mesh: .generateBox(width: 0.0026, height: 0.0031, depth: 0.0018, cornerRadius: 0.0008),
                                materials: [shirt])
        torso.position.y = 0.00175
        body.addChild(torso)

        let head = ModelEntity(mesh: .generateSphere(radius: 0.0012), materials: [ContentLoader.material(for: skin)])
        head.position.y = height - 0.0012
        body.addChild(head)

        // 2. Ant Body (Prestige 1: Swarm / Pest Theme)
        let ant = makeAnt()
        ant.name = "ant"
        ant.isEnabled = false // Enabled dynamically by PrestigeManager
        root.addChild(ant)

        // Forgiving 14 mm collision sphere centered at torso/ant height for responsive reticle targeting
        let collisionShape = ShapeResource.generateSphere(radius: 0.014).offsetBy(translation: [0, 0.0035, 0])
        root.components.set(CollisionComponent(shapes: [collisionShape]))
        return root
    }

    @MainActor
    private static func makeAnt() -> Entity {
        let antRoot = Entity()
        // Deep obsidian glossy chitin with high specular sheen
        let chitinMat = SimpleMaterial(color: UIColor(red: 0.06, green: 0.06, blue: 0.07, alpha: 1), roughness: 0.08, isMetallic: false)
        let eyeMat = SimpleMaterial(color: UIColor(red: 0.85, green: 0.52, blue: 0.12, alpha: 1), roughness: 0.25, isMetallic: false)

        // 1. Abdomen (gaster) with prominent insectoid tapering
        let gaster = ModelEntity(mesh: .generateSphere(radius: 0.0013), materials: [chitinMat])
        gaster.scale = SIMD3<Float>(0.95, 0.85, 1.5)
        gaster.position = [0, 0.0010, -0.0015]
        antRoot.addChild(gaster)

        // 2. Petiole (narrow waist node connecting gaster and thorax)
        let petiole = ModelEntity(mesh: .generateSphere(radius: 0.00045), materials: [chitinMat])
        petiole.position = [0, 0.00075, -0.00055]
        antRoot.addChild(petiole)

        // 3. Thorax
        let thorax = ModelEntity(mesh: .generateSphere(radius: 0.00085), materials: [chitinMat])
        thorax.scale = SIMD3<Float>(0.8, 0.8, 1.2)
        thorax.position = [0, 0.0008, 0.0002]
        antRoot.addChild(thorax)

        // 4. Head
        let antHead = ModelEntity(mesh: .generateSphere(radius: 0.00075), materials: [chitinMat])
        antHead.scale = SIMD3<Float>(0.9, 0.85, 1.1)
        antHead.position = [0, 0.00075, 0.0014]
        antRoot.addChild(antHead)

        // 5. Amber Compound Eyes
        let leftEye = ModelEntity(mesh: .generateSphere(radius: 0.00022), materials: [eyeMat])
        leftEye.position = [-0.00055, 0.00095, 0.0016]
        antRoot.addChild(leftEye)

        let rightEye = ModelEntity(mesh: .generateSphere(radius: 0.00022), materials: [eyeMat])
        rightEye.position = [0.00055, 0.00095, 0.0016]
        antRoot.addChild(rightEye)

        // 6. Articulated Legs (Coxa + Femur + Tibia)
        // 3 pairs with realistic splay angles along the thorax
        let zOffsets: [Float] = [-0.0005, 0.0002, 0.0009]
        let legMesh = MeshResource.generateCylinder(height: 0.0018, radius: 0.00014)

        for (i, z) in zOffsets.enumerated() {
            let splayAngle: Float = i == 0 ? .pi / 4.2 : (i == 1 ? .pi / 3.6 : .pi / 3.0)

            // Left leg
            let leftLeg = ModelEntity(mesh: legMesh, materials: [chitinMat])
            leftLeg.position = [-0.0012, 0.0006, z]
            leftLeg.orientation = simd_quatf(angle: splayAngle, axis: [0, 0, 1]) * simd_quatf(angle: Float(i - 1) * 0.15, axis: [0, 1, 0])
            antRoot.addChild(leftLeg)

            // Right leg
            let rightLeg = ModelEntity(mesh: legMesh, materials: [chitinMat])
            rightLeg.position = [0.0012, 0.0006, z]
            rightLeg.orientation = simd_quatf(angle: -splayAngle, axis: [0, 0, 1]) * simd_quatf(angle: Float(1 - i) * 0.15, axis: [0, 1, 0])
            antRoot.addChild(rightLeg)
        }

        // 7. Sweeping Antennae
        let antennaMesh = MeshResource.generateCylinder(height: 0.0013, radius: 0.00009)
        let leftAntenna = ModelEntity(mesh: antennaMesh, materials: [chitinMat])
        leftAntenna.position = [-0.00035, 0.00105, 0.0020]
        leftAntenna.orientation = simd_quatf(angle: .pi / 3.8, axis: [1, 0, 0]) * simd_quatf(angle: -.pi / 5, axis: [0, 1, 0])
        antRoot.addChild(leftAntenna)

        let rightAntenna = ModelEntity(mesh: antennaMesh, materials: [chitinMat])
        rightAntenna.position = [0.00035, 0.00105, 0.0020]
        rightAntenna.orientation = simd_quatf(angle: .pi / 3.8, axis: [1, 0, 0]) * simd_quatf(angle: .pi / 5, axis: [0, 1, 0])
        antRoot.addChild(rightAntenna)

        return antRoot
    }
}
