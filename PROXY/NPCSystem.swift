import RealityKit
import simd

/// Moves NPCs along the declared paths, and lets them stroll around each settlement's forecourt
/// before choosing the next path. Heights come from the terrain heightfield.
struct NPCSystem: System {
    static let query = EntityQuery(where: .has(NPCComponent.self))

    /// Steepest rise (height per horizontal distance) a stroll may cross; walls and roof edges are steeper.
    static let maxStrollGrade: Float = 0.8
    static let strollRadius: Float = 0.008

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        guard let terrain = TerrainData.shared else { return }
        let dt = Float(min(context.deltaTime, 0.1))  // don't leap after a stall
        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var npc = entity.components[NPCComponent.self] else { continue }
            // Neutralized/tagged figures/ants freeze permanently where they were struck
            if let target = entity.components[TargetComponent.self], target.isTagged {
                continue
            }
            let before = npc.position
            Self.advance(&npc, dt: dt, terrain: terrain)

            let moved = npc.position - before
            if simd_length(moved) > 1e-7 {
                npc.heading = atan2(moved.x, moved.y)  // model faces +Z
                npc.stride += simd_length(moved) / 0.0012 * .pi
            }
            npc.height += (terrain.height(at: npc.position) - npc.height) * min(1, dt * 12)

            entity.position = [npc.position.x, npc.height, npc.position.y]
            entity.orientation = simd_quatf(angle: npc.heading, axis: [0, 1, 0])
            // 60FPS Optimization: direct child access instead of recursive tree search
            if let body = entity.children.first, body.name == "body" {
                body.position.y = abs(sin(npc.stride)) * 0.0005
            }
            entity.components.set(npc)
        }
    }

    /// Triggers biological panic scatter in live ants within the blast radius of a strike
    @MainActor
    static func triggerScatter(around blastPos: SIMD3<Float>, radius: Float = 0.050, in npcsRoot: Entity) {
        let blast2D = SIMD2<Float>(blastPos.x, blastPos.z)
        for child in npcsRoot.children {
            guard var npc = child.components[NPCComponent.self] else { continue }
            if let target = child.components[TargetComponent.self], target.isTagged { continue }
            let diff = npc.position - blast2D
            let dist = simd_length(diff)
            if dist < radius && dist > 1e-4 {
                npc.panicTimer = Float.random(in: 1.1...1.7)
                let fleeDir = simd_normalize(diff)
                // Add jitter so the swarm fans out organically
                let jitterAngle = Float.random(in: -0.5...0.5)
                let rot = simd_quatf(angle: jitterAngle, axis: [0, 1, 0])
                let rotatedFlee = rot.act(SIMD3<Float>(fleeDir.x, 0, fleeDir.y))
                npc.panicVector = SIMD2<Float>(rotatedFlee.x, rotatedFlee.z)
                child.components.set(npc)
            }
        }
    }

    private static func advance(_ npc: inout NPCComponent, dt: Float, terrain: TerrainData) {
        // Ant Panic Scatter Mode (scurry rapidly away from orbital blast impact)
        if npc.panicTimer > 0 {
            npc.panicTimer -= dt
            let speedMultiplier: Float = 2.6
            let step = npc.panicVector * (npc.speed * speedMultiplier) * dt
            let nextPos = npc.position + step

            // Keep within pin-block terrain footprint
            let minX: Float = 0.008
            let maxX: Float = PIN_FIELD_SIZE.x - 0.008
            let minZ: Float = -PIN_FIELD_SIZE.y + 0.008
            let maxZ: Float = -0.008

            if nextPos.x >= minX && nextPos.x <= maxX && nextPos.y >= minZ && nextPos.y <= maxZ {
                npc.position = nextPos
            } else {
                // Reverse panic direction upon wall contact
                npc.panicVector = -npc.panicVector
            }
            return
        }

        switch npc.activity {
        case let .walking(index, forward, distance):
            let path = terrain.paths[index]
            let next = distance + npc.speed * dt
            if next >= path.length {
                let node = forward ? path.end : path.start
                npc.position = path.point(at: forward ? path.length : 0)
                npc.activity = arrive(at: node, terrain: terrain)
            } else {
                npc.position = path.point(at: forward ? next : path.length - next)
                npc.activity = .walking(path: index, forward: forward, distance: next)
            }

        case let .wandering(node, target, legsLeft):
            let toTarget = target - npc.position
            let step = npc.speed * 0.7 * dt  // strolling pace
            if simd_length(toTarget) <= step {
                npc.position = target
                if legsLeft > 0 {
                    npc.activity = .pausing(node: node, timeLeft: Float.random(in: 0.8...3.0))
                } else {
                    npc.activity = depart(from: node, terrain: terrain)
                }
            } else {
                npc.position += simd_normalize(toTarget) * step
            }

        case let .pausing(node, timeLeft):
            if timeLeft - dt > 0 {
                npc.activity = .pausing(node: node, timeLeft: timeLeft - dt)
            } else {
                npc.activity = nextStroll(around: node, from: npc.position, terrain: terrain)
            }
        }
    }

    /// At a settlement, usually stroll a while; at the trailhead (the model's edge), turn around.
    private static func arrive(at node: String, terrain: TerrainData) -> NPCComponent.Activity {
        if node != "FRONT", Int.random(in: 0..<3) > 0 {
            return .pausing(node: node, timeLeft: Float.random(in: 0.5...2.0))
        }
        return depart(from: node, terrain: terrain)
    }

    private static func nextStroll(around node: String, from position: SIMD2<Float>, terrain: TerrainData) -> NPCComponent.Activity {
        guard let home = terrain.nodePoint(node) else { return depart(from: node, terrain: terrain) }
        if Int.random(in: 0..<4) == 0 {
            return .wandering(node: node, target: home, legsLeft: 0)  // head home and leave
        }
        for _ in 0..<8 {
            let angle = Float.random(in: 0..<(2 * .pi))
            let target = home + SIMD2(cos(angle), sin(angle)) * Float.random(in: 0.002...strollRadius)
            if walkable(from: position, to: target, terrain: terrain) {
                return .wandering(node: node, target: target, legsLeft: 1)
            }
        }
        return .wandering(node: node, target: home, legsLeft: 0)
    }

    /// Leave a node along a random path that touches it.
    private static func depart(from node: String, terrain: TerrainData) -> NPCComponent.Activity {
        let options = terrain.paths.indices.filter { terrain.paths[$0].start == node || terrain.paths[$0].end == node }
        guard let index = options.randomElement() else { return .pausing(node: node, timeLeft: 1) }
        return .walking(path: index, forward: terrain.paths[index].start == node, distance: 0)
    }

    /// A stroll is allowed if no 1 mm step along it climbs a wall or drops off a roof edge.
    private static func walkable(from a: SIMD2<Float>, to b: SIMD2<Float>, terrain: TerrainData) -> Bool {
        let steps = max(1, Int(simd_distance(a, b) / 0.001))
        var previous = terrain.height(at: a)
        for k in 1...steps {
            let h = terrain.height(at: a + (b - a) * (Float(k) / Float(steps)))
            if abs(h - previous) / 0.001 > maxStrollGrade { return false }
            previous = h
        }
        return true
    }

    /// Scatter NPCs along the paths at random points, heading random ways.
    @MainActor
    static func spawn(count: Int, terrain: TerrainData) -> Entity {
        let root = Entity()
        root.name = "npcs"
        guard !terrain.paths.isEmpty else { return root }
        for n in 0..<count {
            let index = Int.random(in: 0..<terrain.paths.count)
            let path = terrain.paths[index]
            let distance = Float.random(in: 0..<path.length)
            let forward = Bool.random()
            let position = path.point(at: forward ? distance : path.length - distance)
            let entity = NPCFactory.make(colorIndex: n)
            entity.components.set(NPCComponent(
                activity: .walking(path: index, forward: forward, distance: distance),
                position: position,
                height: terrain.height(at: position),
                speed: Float.random(in: 0.004...0.007)
            ))
            root.addChild(entity)
        }
        return root
    }
}
