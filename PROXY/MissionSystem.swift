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

        // Auto-advance sector with clean debounce and breathing room (only if not already advancing)
        if GameState.shared.targetsRemaining == 0 && GameState.shared.targetsTotal > 0 && !GameState.shared.isAdvancingSector {
            GameState.shared.isAdvancingSector = true
            let sector = GameState.shared.currentSector
            GameState.shared.tagBannerTitle = "SECTOR [\(sector)] SECURED!"
            GameState.shared.tagBannerSubtitle = "ALL TARGETS NEUTRALIZED · NEXT DEPLOYMENT IMMINENT"
            GameState.shared.tagBannerTimer = 3.5

            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                advanceSector(from: npcEntity)
            }
        }
    }

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
        let ring = ModelEntity(mesh: .generateCylinder(height: 0.0001, radius: 0.006), materials: [mat])
        ring.name = "shockwave"
        ring.position = [0, 0.0003, 0]
        entity.addChild(ring)

        // Animate expanding shockwave over 0.5s
        var scale: Float = 1.0
        var opacity: Float = 0.9
        let timer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            scale += 0.25
            opacity = max(0, opacity - 0.065)
            ring.scale = SIMD3<Float>(scale, 1.0, scale)
            var fadingMat = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)))
            fadingMat.blending = .transparent(opacity: .init(floatLiteral: opacity))
            ring.model?.materials = [fadingMat]

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

        // 1. Vertical Orbital Beam of Light descending straight down (0.24m tall)
        let beamHeight: Float = 0.24
        let beamMid = targetPos + SIMD3<Float>(0, beamHeight / 2.0, 0)

        // Outer glowing corona
        var auraMat = UnlitMaterial(color: beamColor)
        auraMat.blending = .transparent(opacity: 0.85)
        let auraBeam = ModelEntity(
            mesh: .generateCylinder(height: beamHeight, radius: 0.0055),
            materials: [auraMat]
        )
        auraBeam.position = beamMid
        parent.addChild(auraBeam)

        // Inner white-hot laser core
        var coreMat = UnlitMaterial(color: .white)
        coreMat.blending = .transparent(opacity: 0.95)
        let coreBeam = ModelEntity(
            mesh: .generateCylinder(height: beamHeight, radius: 0.0022),
            materials: [coreMat]
        )
        coreBeam.position = beamMid
        parent.addChild(coreBeam)

        // 2. Radiant Ground Impact Flare Disc
        var groundMat = UnlitMaterial(color: beamColor)
        groundMat.blending = .transparent(opacity: 0.95)
        let groundFlare = ModelEntity(
            mesh: .generateCylinder(height: 0.0002, radius: 0.016),
            materials: [groundMat]
        )
        groundFlare.position = targetPos + SIMD3<Float>(0, 0.0004, 0)
        parent.addChild(groundFlare)

        // Animate strike ray persistence and dissolve over 0.35s
        var opacity: Float = 0.95
        var groundScale: Float = 1.0
        let timer = Timer.scheduledTimer(withTimeInterval: 0.025, repeats: true) { t in
            opacity -= 0.075
            groundScale += 0.14
            groundFlare.scale = SIMD3<Float>(groundScale, 1.0, groundScale)

            if opacity <= 0.05 {
                t.invalidate()
                auraBeam.removeFromParent()
                coreBeam.removeFromParent()
                groundFlare.removeFromParent()
            } else {
                var fadingAura = UnlitMaterial(color: beamColor.withAlphaComponent(CGFloat(opacity * 0.85)))
                fadingAura.blending = .transparent(opacity: .init(floatLiteral: opacity * 0.85))
                auraBeam.model?.materials = [fadingAura]

                var fadingCore = UnlitMaterial(color: UIColor.white.withAlphaComponent(CGFloat(opacity)))
                fadingCore.blending = .transparent(opacity: .init(floatLiteral: opacity))
                coreBeam.model?.materials = [fadingCore]

                var fadingGround = UnlitMaterial(color: beamColor.withAlphaComponent(CGFloat(opacity)))
                fadingGround.blending = .transparent(opacity: .init(floatLiteral: opacity))
                groundFlare.model?.materials = [fadingGround]
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

        // Generous 3.0mm thickness so the tracer is boldly visible from all AR angles
        let mesh = MeshResource.generateCylinder(height: dist, radius: 0.0030)
        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: 0.95)
        let tracer = ModelEntity(mesh: mesh, materials: [mat])
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
                var fading = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)))
                fading.blending = .transparent(opacity: .init(floatLiteral: opacity))
                tracer.model?.materials = [fading]
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    @MainActor
    static func spawnImpactPuff(at pos: SIMD3<Float>, in parent: Entity) {
        let prestige = GameState.shared.prestigeLevel
        let color = (prestige == 1) ? UIColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0.85) : UIColor(red: 0.2, green: 0.8, blue: 1.0, alpha: 0.85)
        let mesh = MeshResource.generateSphere(radius: 0.005)
        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: 0.85)
        let puff = ModelEntity(mesh: mesh, materials: [mat])
        puff.position = pos
        parent.addChild(puff)

        var scale: Float = 1.0
        var opacity: Float = 0.85
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { t in
            scale += 0.35
            opacity -= 0.12
            puff.scale = SIMD3<Float>(scale, scale, scale)
            if opacity <= 0.05 {
                t.invalidate()
                puff.removeFromParent()
            } else {
                var fading = UnlitMaterial(color: color.withAlphaComponent(CGFloat(opacity)))
                fading.blending = .transparent(opacity: .init(floatLiteral: opacity))
                puff.model?.materials = [fading]
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
            ambientRetaliationTimer = Float.random(in: 4.0...6.5)
            // In Prestige >= 1, active hostiles launch periodic counter-attacks
            if GameState.shared.prestigeLevel >= 1 && GameState.shared.targetsRemaining > 0 {
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
                GameState.shared.damageDrone(amount: 15.0)

                // Impact Haptics & Audio
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                AudioServicesPlaySystemSound(1521) // Impact audio
                SessionLogger.shared.log("HOSTILE HIT: counter-fire impacted drone! Shield at \(Int(GameState.shared.droneShield))%", category: "COMBAT")
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

    /// Retaliation triggered immediately when a fellow ant or target is struck
    func triggerRetaliation(from struckEntity: Entity, in npcsRoot: Entity, toward targetDronePos: SIMD3<Float>? = nil) {
        guard GameState.shared.prestigeLevel >= 1 else { return }

        // Find nearest live, un-tagged ant to retaliate
        let struckPos = struckEntity.position(relativeTo: npcsRoot)
        let liveAnts = npcsRoot.children.filter {
            guard $0.components.has(NPCComponent.self) else { return false }
            let isTagged = $0.components[TargetComponent.self]?.isTagged ?? false
            return !isTagged && $0 != struckEntity
        }

        guard let retaliator = liveAnts.min(by: {
            simd_length($0.position(relativeTo: npcsRoot) - struckPos) < simd_length($1.position(relativeTo: npcsRoot) - struckPos)
        }) else { return }

        // Retaliate after short 0.25s telegraph reaction time
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, let parent = retaliator.parent else { return }
            let antPos = retaliator.position(relativeTo: parent)
            let destPos = targetDronePos ?? (antPos + SIMD3<Float>(0, 0.08, 0))
            self.fireHostileProjectile(from: antPos, toward: destPos, in: parent)
        }
    }

    private func launchHostileCounterFire(dronePos: SIMD3<Float>, npcsRoot: Entity) {
        let liveAnts = npcsRoot.children.filter {
            guard $0.components.has(NPCComponent.self) else { return false }
            return !($0.components[TargetComponent.self]?.isTagged ?? false)
        }
        guard let shooter = liveAnts.randomElement(), let parent = shooter.parent else { return }
        let antPos = shooter.position(relativeTo: parent)
        fireHostileProjectile(from: antPos, toward: dronePos, in: parent)
    }

    private func fireHostileProjectile(from start: SIMD3<Float>, toward target: SIMD3<Float>, in parent: Entity) {
        let prestige = GameState.shared.prestigeLevel
        let color: UIColor
        switch prestige {
        case 1: color = UIColor(red: 0.85, green: 1.0, blue: 0.1, alpha: 0.95) // Toxic Bio-Acid Spit
        case 2: color = UIColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 0.95)  // Red Anti-Air Rocket
        default: color = UIColor(white: 1.0, alpha: 0.95)                       // EMP White Dart
        }

        let dir = target - start
        let dist = simd_length(dir)
        guard dist > 0.02 else { return }
        let normDir = dir / dist

        // Projectile speed (~0.28 m/s: travels across diorama in ~0.8s, giving player time to react)
        let speed: Float = 0.28
        let velocity = normDir * speed

        var mat = UnlitMaterial(color: color)
        mat.blending = .transparent(opacity: 0.95)
        let mesh = MeshResource.generateSphere(radius: 0.0035)
        let projEntity = ModelEntity(mesh: mesh, materials: [mat])
        projEntity.position = start + SIMD3<Float>(0, 0.003, 0)
        parent.addChild(projEntity)

        activeProjectiles.append(Projectile(
            entity: projEntity,
            position: projEntity.position,
            velocity: velocity,
            life: 2.5
        ))

        // HUD Alert
        GameState.shared.hostileWarningTimer = 1.2
        GameState.shared.hostileWarningText = "⚠ THREAT DETECTED // INCOMING COUNTER-FIRE"
        SessionLogger.shared.log("HOSTILE FIRED: projectile launched from ant at \(start) toward drone", category: "COMBAT")
    }
}
