import RealityKit
import UIKit
import simd
import AudioToolbox

/// Manages mission objectives, target assignment on NPCs, pulsing marker rings, and tag animations.
struct MissionSystem: System {
    static let query = EntityQuery(where: .has(TargetComponent.self))

    init(scene: RealityKit.Scene) {}

    func update(context: SceneUpdateContext) {
        let dt = Float(min(context.deltaTime, 0.1))
        let prestige = GameState.shared.prestigeLevel

        for entity in context.entities(matching: Self.query, updatingSystemWhen: .rendering) {
            guard var target = entity.components[TargetComponent.self] else { continue }

            let ring = entity.findEntity(named: "target_ring")
            let badge = entity.findEntity(named: "target_badge")

            // Critical critique design: In Prestige thermal view (level >= 2), all NPCs look identical.
            // Target markers disappear so player sees thermal reality without game cues.
            let shouldShowMarkers = prestige < 2
            ring?.isEnabled = shouldShowMarkers
            badge?.isEnabled = shouldShowMarkers

            if target.isTagged {
                // Celebration pop decay
                if target.popTimer > 0 {
                    target.popTimer -= dt
                    let progress = 1.0 - max(0, target.popTimer / 0.4)
                    let bounce = 1.0 + sin(progress * .pi) * 0.35
                    if let body = entity.findEntity(named: "body") {
                        body.scale = SIMD3<Float>(repeating: bounce)
                    }
                } else {
                    if let body = entity.findEntity(named: "body") {
                        body.scale = SIMD3<Float>(repeating: 1.0)
                    }
                }
            } else {
                // Pulse un-tagged target ring
                target.pulsePhase += dt * 4.0
                let pulseScale = 1.0 + sin(target.pulsePhase) * 0.18
                ring?.scale = SIMD3<Float>(pulseScale, 1.0, pulseScale)
            }

            entity.components.set(target)
        }
    }

    // MARK: - Target Setup & Tagging

    @MainActor
    static func setupTargets(in npcsRoot: Entity, count: Int = 3) {
        // Only select live, un-tagged NPCs as new mission targets
        let npcs = npcsRoot.children.filter {
            guard $0.components.has(NPCComponent.self) else { return false }
            let isTagged = $0.components[TargetComponent.self]?.isTagged ?? false
            return !isTagged
        }
        guard !npcs.isEmpty else { return }

        let currentSector = GameState.shared.currentSector

        // Clean up any stale target markers from previous sectors
        for child in npcsRoot.children {
            child.findEntity(named: "target_ring")?.removeFromParent()
            child.findEntity(named: "target_badge")?.removeFromParent()
        }

        // Shuffle and select targets
        let selected = Array(npcs.shuffled().prefix(count))
        for (index, npc) in selected.enumerated() {
            let targetId = index + 1
            npc.components.set(TargetComponent(targetId: targetId, sector: currentSector))

            // Pulsing ground target ring
            var ringMat = UnlitMaterial(color: UIColor(red: 1.00, green: 0.25, blue: 0.55, alpha: 0.75)) // Hot pink
            ringMat.blending = .transparent(opacity: 0.75)
            let ring = ModelEntity(
                mesh: .generateCylinder(height: 0.0001, radius: 0.005),
                materials: [ringMat]
            )
            ring.name = "target_ring"
            ring.position = [0, 0.0003, 0]
            npc.addChild(ring)

            // Floating indicator beacon
            let badgeMat = ContentLoader.material(for: ContentLoader.palette[1])
            let badge = ModelEntity(
                mesh: .generateSphere(radius: 0.0012),
                materials: [badgeMat]
            )
            badge.name = "target_badge"
            badge.position = [0, NPCFactory.height + 0.003, 0]
            npc.addChild(badge)
        }

        GameState.shared.targetsTotal = count
        GameState.shared.targetsRemaining = count
        print("[PROXY] MissionSystem: \(count) targets assigned in sector \(currentSector).")
    }

    @MainActor
    static func tag(npcEntity: Entity) {
        var target = npcEntity.components[TargetComponent.self] ?? TargetComponent(targetId: 0, sector: GameState.shared.currentSector)
        guard !target.isTagged else { return }

        let prestige = GameState.shared.prestigeLevel
        target.isTagged = true
        target.popTimer = 0.4
        npcEntity.components.set(target)

        // Set banner text and score based on theme
        switch prestige {
        case 0:
            GameState.shared.tagBannerTitle = target.targetId > 0 ? "TARGET CONFIRMED" : "VIP IDENTIFIED"
            GameState.shared.tagBannerSubtitle = target.targetId > 0 ? "+500 RECON POINTS" : "+200 DISCOVERY PTS"
            GameState.shared.score += target.targetId > 0 ? 500 : 200
        case 1:
            GameState.shared.tagBannerTitle = "PEST ELIMINATED"
            GameState.shared.tagBannerSubtitle = "+250 PEST CREDITS"
            GameState.shared.score += 250
            // Visually squash the ant
            if let ant = npcEntity.findEntity(named: "ant") {
                ant.scale = SIMD3<Float>(1.3, 0.25, 1.3)
            }
        case 2:
            GameState.shared.tagBannerTitle = "HOSTILE NEUTRALIZED"
            GameState.shared.tagBannerSubtitle = "COMBAT LOG UPDATED"
            GameState.shared.score += 300
        case 3:
            GameState.shared.tagBannerTitle = "BUGSPLAT RECORDED"
            GameState.shared.tagBannerSubtitle = "CONFIRMED IMPACT · 0 COLLATERAL"
            GameState.shared.score += 500
        default:
            break
        }

        // Bug Fix: Every eliminated target or ant decrements remaining count so the mission progresses!
        GameState.shared.targetsRemaining = max(0, GameState.shared.targetsRemaining - 1)

        // Tactile Haptic Strike
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        AudioServicesPlaySystemSound(1519) // Crisp pop click

        // Ring feedback or add new glowing splat mark under struck target
        if let ring = npcEntity.findEntity(named: "target_ring") as? ModelEntity {
            let ringColor = (prestige == 1) ? UIColor(red: 0.8, green: 0.9, blue: 0.1, alpha: 0.8) : UIColor(red: 0.10, green: 0.85, blue: 0.80, alpha: 0.8)
            var taggedMat = UnlitMaterial(color: ringColor)
            taggedMat.blending = .transparent(opacity: 0.8)
            ring.model?.materials = [taggedMat]
        } else {
            // Give struck ant / NPC a bio-splat ring on the terrain
            let splatColor = (prestige == 1) ? UIColor(red: 0.85, green: 0.95, blue: 0.1, alpha: 0.85) : UIColor(red: 1.0, green: 0.25, blue: 0.55, alpha: 0.85)
            var splatMat = UnlitMaterial(color: splatColor)
            splatMat.blending = .transparent(opacity: 0.85)
            let splat = ModelEntity(
                mesh: .generateCylinder(height: 0.0001, radius: 0.005),
                materials: [splatMat]
            )
            splat.name = "target_ring"
            splat.position = [0, 0.0002, 0]
            npcEntity.addChild(splat)
        }

        // Squash figure/ant permanently to indicate confirmed strike
        if let ant = npcEntity.findEntity(named: "ant") {
            ant.scale = SIMD3<Float>(1.4, 0.2, 1.4)
        }
        if let body = npcEntity.findEntity(named: "body") {
            body.scale = SIMD3<Float>(1.3, 0.25, 1.3)
        }

        // Change badge
        if let badge = npcEntity.findEntity(named: "target_badge") as? ModelEntity {
            badge.model?.materials = [ContentLoader.material(for: ContentLoader.palette[6])]
        }

        // Trigger Juice: Pop text at reticle and screen flash
        switch prestige {
        case 0:
            GameState.shared.strikePopupText = target.targetId > 0 ? "+500 RECON POINTS 🎯" : "+200 VIP TAGGED ✨"
        case 1:
            GameState.shared.strikePopupText = "+250 PEST ELIMINATED 💥"
        case 2:
            GameState.shared.strikePopupText = "TARGET ACQUIRED ⚔️"
        default:
            GameState.shared.strikePopupText = "BUGSPLAT RECORDED ⚡"
        }
        GameState.shared.strikePopupTimer = 1.3
        GameState.shared.screenFlashTimer = 0.22

        // Spawn dynamic expanding 3D shockwave on the terrain
        spawnShockwave(on: npcEntity, prestige: prestige)

        SessionLogger.shared.log("STRIKE REGISTERED on entity (targetId: \(target.targetId), sector: \(target.sector), remaining: \(GameState.shared.targetsRemaining))", category: "MISSION")

        // Trigger hostile NPC counter-retaliation (Ants fight back!)
        if let parent = npcEntity.parent {
            NPCCombatSystem.shared.triggerRetaliation(from: npcEntity, in: parent)
        }

        // Auto-advance sector with dramatic operational fanfare
        if GameState.shared.targetsRemaining == 0 && GameState.shared.targetsTotal > 0 && !GameState.shared.isAdvancingSector {
            GameState.shared.isAdvancingSector = true
            let sector = GameState.shared.currentSector

            // Dramatic Sector Clear Operational Fanfare
            GameState.shared.tagBannerTitle = "★ SECTOR [\(sector)] STERILIZED ★"
            GameState.shared.tagBannerSubtitle = "ALL HOSTILE SIGNATURES ELIMINATED · AREA SECURED"
            GameState.shared.tagBannerTimer = 4.0
            GameState.shared.screenFlashTimer = 0.40

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioServicesPlaySystemSound(1025)

            GameState.shared.radioMessage = "TACTICAL: Sector \(sector) neutralized. Threat level zero. Stand by for next sector vector."

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) {
                advanceSector(from: npcEntity)
            }
        }
    }

    // MARK: - Reusable Unit Meshes (Zero Runtime Mesh Allocations)
    static let unitCylinderMesh: MeshResource = .generateCylinder(height: 1.0, radius: 1.0)
    static let unitSphereMesh: MeshResource = .generateSphere(radius: 1.0)
    static let unitDiscMesh: MeshResource = .generateCylinder(height: 0.001, radius: 1.0)

    @MainActor
    private static func spawnShockwave(on entity: Entity, prestige: Int) {
        let color: UIColor
        switch prestige {
        case 0: color = UIColor(red: 1.0, green: 0.25, blue: 0.55, alpha: 0.9) // Hot pink
        case 1: color = UIColor(red: 0.85, green: 0.98, blue: 0.10, alpha: 0.9) // Toxic lime
        case 2: color = UIColor(red: 0.20, green: 0.85, blue: 1.00, alpha: 0.9) // Cyan
        default: color = UIColor(white: 1.0, alpha: 0.9) // FLIR white
        }

        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: 0.9)
        let ring = ModelEntity(mesh: unitDiscMesh, materials: [mat])
        ring.name = "shockwave"
        ring.position = [0, 0.0003, 0]
        ring.scale = SIMD3<Float>(0.006, 1.0, 0.006)
        entity.addChild(ring)

        // Animate expanding shockwave over 0.5s using native OpacityComponent
        var currentScale: Float = 0.006
        var opacity: Float = 0.9
        let timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            currentScale += 0.0018
            opacity = max(0, opacity - 0.065)
            ring.scale = SIMD3<Float>(currentScale, 1.0, currentScale)
            ring.components.set(OpacityComponent(opacity: opacity))

            if opacity <= 0.05 {
                t.invalidate()
                ring.removeFromParent()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    @MainActor
    private static func advanceSector(from entity: Entity) {
        guard let parent = entity.parent else {
            GameState.shared.isAdvancingSector = false
            return
        }
        let sectors = ["MID", "HIGH", "PEAK", "LOW"]
        let currentIdx = sectors.firstIndex(of: GameState.shared.currentSector) ?? 0
        let nextSector = sectors[(currentIdx + 1) % sectors.count]
        GameState.shared.currentSector = nextSector
        GameState.shared.isAdvancingSector = false

        // Reassign new targets in next sector
        setupTargets(in: parent, count: 3)
        GameState.shared.tagBannerTitle = "NEW OBJECTIVE: SECTOR [\(nextSector)]"
        GameState.shared.tagBannerSubtitle = "3 HOSTILE SIGNATURES MARKED"
        GameState.shared.tagBannerTimer = 3.0
        SessionLogger.shared.log("Sector advanced cleanly to [\(nextSector)] (Prestige remains \(GameState.shared.prestigeLevel))", category: "MISSION")
    }

    // MARK: - 3D Ballistic Visuals (Orbital Strike Ray, Tracers & Impacts)

    /// Spawns a brilliant vertical ray of light descending from the sky straight onto the target!
    @MainActor
    static func spawnStrikeRay(targetPos: SIMD3<Float>, in parent: Entity) {
        let prestige = GameState.shared.prestigeLevel
        let beamColor: UIColor
        switch prestige {
        case 0: beamColor = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.95) // Neon Cyan
        case 1: beamColor = UIColor(red: 1.00, green: 0.42, blue: 0.12, alpha: 0.95) // High-Threat Laser Amber
        case 2: beamColor = UIColor(red: 0.20, green: 0.95, blue: 0.40, alpha: 0.95) // Phosphor Green
        default: beamColor = UIColor(white: 1.0, alpha: 0.98) // White-Hot FLIR
        }

        // Hard Tabletop Floor Clamping (never punch beneath diorama base)
        let safeTargetPos = SIMD3<Float>(targetPos.x, max(0.0005, targetPos.y), targetPos.z)

        // Trigger Swarm Panic Scatter in live ants around impact point
        if let npcsRoot = parent.findEntity(named: "npcs") ?? parent.parent?.findEntity(named: "npcs") {
            NPCSystem.triggerScatter(around: safeTargetPos, radius: 0.110, in: npcsRoot)
        }

        // 1. Vertical Orbital Beam of Light descending straight down (0.24m tall)
        let beamHeight: Float = 0.24
        let beamMid = safeTargetPos + SIMD3<Float>(0, beamHeight / 2.0, 0)

        // Outer glowing corona
        var auraMat = UnlitMaterial(color: beamColor)
        auraMat.blending = .transparent(opacity: 0.85)
        let auraBeam = ModelEntity(mesh: unitCylinderMesh, materials: [auraMat])
        auraBeam.scale = SIMD3<Float>(0.0055, beamHeight, 0.0055)
        auraBeam.position = beamMid
        parent.addChild(auraBeam)

        // Inner white-hot laser core
        var coreMat = UnlitMaterial(color: .white)
        coreMat.blending = .transparent(opacity: 0.95)
        let coreBeam = ModelEntity(mesh: unitCylinderMesh, materials: [coreMat])
        coreBeam.scale = SIMD3<Float>(0.0022, beamHeight, 0.0022)
        coreBeam.position = beamMid
        parent.addChild(coreBeam)

        // 2. Radiant Ground Impact Flare Disc
        var groundMat = UnlitMaterial(color: beamColor)
        groundMat.blending = .transparent(opacity: 0.95)
        let groundFlare = ModelEntity(mesh: unitDiscMesh, materials: [groundMat])
        groundFlare.scale = SIMD3<Float>(0.016, 1.0, 0.016)
        groundFlare.position = safeTargetPos + SIMD3<Float>(0, 0.0004, 0)
        parent.addChild(groundFlare)

        // Animate strike ray persistence and dissolve over 0.35s using native OpacityComponent
        var opacity: Float = 0.95
        var currentGroundRadius: Float = 0.016
        let timer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { t in
            opacity -= 0.075
            currentGroundRadius += 0.0025
            groundFlare.scale = SIMD3<Float>(currentGroundRadius, 1.0, currentGroundRadius)

            if opacity <= 0.05 {
                t.invalidate()
                auraBeam.removeFromParent()
                coreBeam.removeFromParent()
                groundFlare.removeFromParent()
            } else {
                auraBeam.components.set(OpacityComponent(opacity: opacity * 0.85))
                coreBeam.components.set(OpacityComponent(opacity: opacity))
                groundFlare.components.set(OpacityComponent(opacity: opacity))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Spawns a thick, visible forward tracer streaking from drone camera origin to target
    @MainActor
    static func spawnTracer(from start: SIMD3<Float>, to end: SIMD3<Float>, in parent: Entity) {
        let prestige = GameState.shared.prestigeLevel
        let color: UIColor
        switch prestige {
        case 0: color = UIColor(red: 0.20, green: 0.85, blue: 1.0, alpha: 0.95)
        case 1: color = UIColor(red: 1.00, green: 0.45, blue: 0.12, alpha: 0.95)
        case 2: color = UIColor(red: 0.20, green: 0.95, blue: 0.40, alpha: 0.95)
        default: color = UIColor(white: 1.0, alpha: 0.95)
        }

        let diff = end - start
        let dist = simd_length(diff)
        guard dist > 0.005 else { return }

        let dir = diff / dist
        let mid = (start + end) * 0.5

        // Generous 3.0mm thickness using pre-allocated unit cylinder mesh
        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: 0.95)
        let tracer = ModelEntity(mesh: unitCylinderMesh, materials: [mat])
        tracer.scale = SIMD3<Float>(0.0030, dist, 0.0030)
        tracer.position = mid

        let yAxis = SIMD3<Float>(0, 1, 0)
        let rotAxis = simd_cross(yAxis, dir)
        let lenRot = simd_length(rotAxis)
        if lenRot > 1e-4 {
            let rotAngle = acos(max(-1.0, min(1.0, simd_dot(yAxis, dir))))
            tracer.orientation = simd_quatf(angle: rotAngle, axis: rotAxis / lenRot)
        }

        parent.addChild(tracer)

        var opacity: Float = 0.95
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { t in
            opacity -= 0.12
            if opacity <= 0.05 {
                t.invalidate()
                tracer.removeFromParent()
            } else {
                tracer.components.set(OpacityComponent(opacity: opacity))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    @MainActor
    static func spawnImpactPuff(at pos: SIMD3<Float>, in parent: Entity) {
        let safePos = SIMD3<Float>(pos.x, max(0.0005, pos.y), pos.z)
        let prestige = GameState.shared.prestigeLevel
        let color = (prestige == 1) ? UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0.85) : UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.85)
        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: 0.85)
        let puff = ModelEntity(mesh: unitSphereMesh, materials: [mat])
        puff.scale = SIMD3<Float>(repeating: 0.005)
        puff.position = safePos
        parent.addChild(puff)

        // Trigger Swarm Panic Scatter in live ants around impact point
        if let npcsRoot = parent.findEntity(named: "npcs") ?? parent.parent?.findEntity(named: "npcs") {
            NPCSystem.triggerScatter(around: safePos, radius: 0.110, in: npcsRoot)
        }

        var currentRadius: Float = 0.005
        var opacity: Float = 0.85
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { t in
            currentRadius += 0.0018
            opacity -= 0.12
            puff.scale = SIMD3<Float>(repeating: currentRadius)
            if opacity <= 0.05 {
                t.invalidate()
                puff.removeFromParent()
            } else {
                puff.components.set(OpacityComponent(opacity: opacity))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

// MARK: - Hostile NPC Combat System (Ants & Hostiles Fight Back!)

@MainActor
final class NPCCombatSystem {
    static let shared = NPCCombatSystem()

    struct Projectile {
        let entity: ModelEntity
        var position: SIMD3<Float>
        let velocity: SIMD3<Float>
        var life: Float
    }

    private var activeProjectiles: [Projectile] = []
    private var ambientRetaliationTimer: Float = 4.0

    private init() {}

    /// Main frame update: advances in-flight projectiles toward drone camera and detects hits
    func update(dronePos: SIMD3<Float>, npcsRoot: Entity, dt: Float) {
        ambientRetaliationTimer -= dt
        if ambientRetaliationTimer <= 0 {
            ambientRetaliationTimer = Float.random(in: 3.5...5.5)
            // On ALL levels, active hostiles/citizens launch periodic counter-attacks while targets remain
            if GameState.shared.targetsRemaining > 0 && !GameState.shared.isConnectionLost {
                launchHostileCounterFire(dronePos: dronePos, npcsRoot: npcsRoot)
            }
        }

        // Update in-flight projectiles
        var remaining: [Projectile] = []
        for var proj in activeProjectiles {
            proj.life -= dt
            proj.position += proj.velocity * dt
            proj.entity.position = proj.position

            let distToDrone = simd_length(proj.position - dronePos)
            if distToDrone < 0.045 {
                // Direct Hit on Drone!
                proj.entity.removeFromParent()
                let prestige = GameState.shared.prestigeLevel
                let damageAmount: Float = prestige == 0 ? 10.0 : (prestige == 3 ? 20.0 : 15.0)
                GameState.shared.damageDrone(amount: damageAmount)

                // Impact Haptics & Audio
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                if prestige == 0 {
                    AudioServicesPlaySystemSound(1054) // Cork pop / toy hit
                } else if prestige == 2 {
                    AudioServicesPlaySystemSound(1052) // Ricochet
                } else if prestige == 3 {
                    AudioServicesPlaySystemSound(1073) // Heavy detonation
                } else {
                    AudioServicesPlaySystemSound(1521) // Acid impact
                }
                SessionLogger.shared.log("HOSTILE HIT: [P\(prestige)] counter-fire impacted drone! Shield at \(Int(GameState.shared.droneShield))%", category: "COMBAT")
                continue
            }

            if proj.life <= 0 {
                proj.entity.removeFromParent()
                continue
            }

            remaining.append(proj)
        }
        activeProjectiles = remaining
    }

    /// Retaliation triggered immediately when a fellow ant or citizen is struck on ANY level
    func triggerRetaliation(from struckEntity: Entity, in npcsRoot: Entity, toward targetDronePos: SIMD3<Float>? = nil) {
        guard !GameState.shared.isConnectionLost else { return }

        // Find nearest live, un-tagged NPCs to retaliate
        let struckPos = struckEntity.position(relativeTo: npcsRoot)
        let liveNPCs = npcsRoot.children.filter {
            guard $0.components.has(NPCComponent.self) else { return false }
            let isTagged = $0.components[TargetComponent.self]?.isTagged ?? false
            return !isTagged && $0 != struckEntity
        }

        let sorted = liveNPCs.sorted {
            simd_length($0.position(relativeTo: npcsRoot) - struckPos) < simd_length($1.position(relativeTo: npcsRoot) - struckPos)
        }

        // Take up to 2 nearby retaliators within 120mm
        let retaliators = sorted.prefix(2)
        guard !retaliators.isEmpty else { return }

        // Retaliate after short telegraph reaction time (0.2s - 0.4s)
        for (idx, retaliator) in retaliators.enumerated() {
            let delay = 0.20 + Double(idx) * 0.18
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, let parent = retaliator.parent else { return }
                let shooterPos = retaliator.position(relativeTo: parent)
                let destPos = targetDronePos ?? (shooterPos + SIMD3<Float>(0, 0.08, 0))
                self.fireHostileProjectile(from: shooterPos, toward: destPos, in: parent)
            }
        }
    }

    private func launchHostileCounterFire(dronePos: SIMD3<Float>, npcsRoot: Entity) {
        let liveNPCs = npcsRoot.children.filter {
            guard $0.components.has(NPCComponent.self) else { return false }
            return !($0.components[TargetComponent.self]?.isTagged ?? false)
        }
        guard let shooter = liveNPCs.randomElement(), let parent = shooter.parent else { return }
        let shooterPos = shooter.position(relativeTo: parent)
        fireHostileProjectile(from: shooterPos, toward: dronePos, in: parent)
    }

    private func fireHostileProjectile(from start: SIMD3<Float>, toward target: SIMD3<Float>, in parent: Entity) {
        let prestige = GameState.shared.prestigeLevel
        let color: UIColor
        let warningText: String
        let projScale: Float

        switch prestige {
        case 0:
            color = UIColor(red: 1.0, green: 0.18, blue: 0.65, alpha: 0.95) // Neon Hot Pink Cork Missile
            warningText = "⚠ CITIZEN RESISTANCE // POPPING CORKS"
            projScale = 0.0042
        case 1:
            color = UIColor(red: 0.75, green: 1.0, blue: 0.05, alpha: 0.95) // Toxic Bio-Acid Spit
            warningText = "⚠ BIO-ACID SPIT // CORROSIVE VOLLEY"
            projScale = 0.0038
        case 2:
            color = UIColor(red: 1.0, green: 0.35, blue: 0.05, alpha: 0.95)  // Incandescent 7.62 Tracer
            warningText = "⚠ SMALL ARMS TRACER // HOSTILE FIRE"
            projScale = 0.0030
        default:
            color = UIColor(white: 1.0, alpha: 0.98)                       // White-Hot SAM Missile
            warningText = "⚠ SAM LAUNCH // INFRARED MISSILE LOCK"
            projScale = 0.0045
        }

        let dir = target - start
        let dist = simd_length(dir)
        guard dist > 0.02 else { return }
        let normDir = dir / dist

        // Projectile speed (~0.30 m/s: travels across diorama in ~0.7s, giving player time to react)
        let speed: Float = 0.30
        let velocity = normDir * speed

        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: 0.95)
        let projEntity = ModelEntity(mesh: MissionSystem.unitSphereMesh, materials: [mat])
        projEntity.scale = SIMD3<Float>(repeating: projScale)
        projEntity.position = start + SIMD3<Float>(0, 0.003, 0)
        parent.addChild(projEntity)

        activeProjectiles.append(Projectile(
            entity: projEntity,
            position: projEntity.position,
            velocity: velocity,
            life: 2.5
        ))

        // HUD Alert
        GameState.shared.hostileWarningTimer = 1.3
        GameState.shared.hostileWarningText = warningText
        SessionLogger.shared.log("HOSTILE FIRED: [P\(prestige)] projectile launched from NPC at \(start) toward drone", category: "COMBAT")
    }
}
