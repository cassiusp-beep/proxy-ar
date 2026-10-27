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
}

enum NPCFactory {
    /// The diorama's figures are 5.5 mm tall and 3 mm wide; NPCs match them.
    static let height: Float = 0.0055

    static let shirtColors: [UIColor] = ContentLoader.palette
    static let skin = UIColor(red: 1.00, green: 0.86, blue: 0.70, alpha: 1)

    @MainActor
    static func make(colorIndex: Int) -> ModelEntity {
        let shirt = ContentLoader.material(for: shirtColors[colorIndex % shirtColors.count])
        let root = ModelEntity()
        root.name = "npc"

        // Child "body" carries the walk bob so the root stays on the ground.
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
        return root
    }
}
