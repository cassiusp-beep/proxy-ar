import ARKit
import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let settings: PlacementSettings
    var zoomFactor: Float = 1.0

    func makeCoordinator() -> Coordinator {
        Coordinator(settings: settings)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        context.coordinator.arView = arView
        arView.session.delegate = context.coordinator

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.toggleDebug))
        tap.numberOfTouchesRequired = 3
        arView.addGestureRecognizer(tap)

        context.coordinator.runSession()
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        // Reading these here registers them with Observation
        _ = GameState.shared.prestigeLevel

        // Hardware-accelerated optical zoom scaling directly on ARView
        let targetScale = CGFloat(zoomFactor)
        if abs(arView.transform.a - targetScale) > 0.01 {
            UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseOut, .beginFromCurrentState]) {
                arView.transform = CGAffineTransform(scaleX: targetScale, y: targetScale)
            }
        }

        context.coordinator.offsetEntity.transform = settings.transform
        context.coordinator.handleSync(settings.syncRequest)
        context.coordinator.handleRelock(settings.relockRequest)
        context.coordinator.handleFit(settings.fitRequest)
        context.coordinator.handleSnapshot(settings.snapshotRequest)
        context.coordinator.applyVisibility()
        // RealityKit applies person segmentation automatically; this only switches it off.
        if settings.handOcclusion {
            arView.renderOptions.remove(.disablePersonOcclusion)
        } else {
            arView.renderOptions.insert(.disablePersonOcclusion)
        }
        if settings.showMesh {
            arView.debugOptions.insert(.showSceneUnderstanding)
        } else {
            arView.debugOptions.remove(.showSceneUnderstanding)
        }
        // LiDAR mesh occlusion: hands and loose objects hide content, but the coarse mesh also
        // clips the city where it sits on the pins, so it's off by default (DECISIONS 007).
        if settings.lidarOcclusion {
            arView.environment.sceneUnderstanding.options.insert(.occlusion)
        } else {
            arView.environment.sceneUnderstanding.options.remove(.occlusion)
        }
    }

    final class Coordinator: NSObject, ARSessionDelegate {
        let settings: PlacementSettings
        weak var arView: ARView?

        /// Carries the MARKER_TO_ORIGIN offset, yaw and scale. Content hangs beneath it.
        let offsetEntity = Entity()
        // The lock (MarkerLock.swift) sets these.
        var anchorEntity: AnchorEntity?
        var worldAnchor: ARAnchor?
        /// The previous lock in this world frame; cleared by Sync, kept by "Re-lock (keep world)".
        var lastLock: MarkerLock.Record?
        /// Consecutive pair refusals where only the right marker failed (`MarkerLock.rightOnlyRefusalStreak`).
        /// Reset by Sync, Re-lock (both via `unlock`) and any lock.
        var rightOnlyRefusals = 0
        private var lastSyncRequest = 0
        private var lastRelockRequest = 0
        private var lastFitRequest = 0
        private var lastSnapshotRequest = 0
        /// Locks made this launch and the last one's sampling mode, for the snapshot log line.
        var lockCount = 0
        var lastLockMode = "none"
        private let snapshots = SnapshotStore()
        private var scan: DepthScan?
        /// One sampler per reference image name: the setup's lock marker and, for the pair setups
        /// (Diorama, pin block), the right one ("CalibrationMarkerRight").
        var samplers: [String: MarkerSampler] = [:]
        /// The marker the lock anchors to: "CalibrationMarker" (Diorama / pin block LEFT, Field Unit 50) or
        /// "DockMarker" (Field Unit 100).
        var leftMarker: String { settings.setup.primaryMarker }
        let rightMarker = MarkerName.right
        /// System uptime of the last marker sample. A refused lock's "seen twice" pill clears once
        /// no marker has been sampled for `seenTwiceTimeout`; a duplicate still in view keeps
        /// feeding samples (and refusing every ~30 of them), so the pill stays without flicker.
        private var lastMarkerSample: TimeInterval = 0
        static let seenTwiceTimeout: TimeInterval = 1.0
        /// Cleared if the session ever rejects segmentation alongside scene reconstruction.
        private var useSegmentation = true
        private var isProcessingFrame = false
        private var content: ContentLoader.Content?

        init(settings: PlacementSettings) {
            self.settings = settings
            super.init()
            Task { @MainActor in
                let content = await ContentLoader.loadContent()
                for entity in [content.city, content.occluder, content.placeholder, content.npcs].compactMap({ $0 }) {
                    offsetEntity.addChild(entity)
                }
                if content.city == nil { settings.showPlaceholder = true }
                self.content = content
                PrestigeManager.shared.cacheOriginals(city: content.city, npcs: content.npcs)
                applyVisibility()
            }
        }

        @MainActor
        func applyVisibility() {
            // Read the settings unconditionally so Observation tracks them before content loads.
            let showCity = settings.showCity, pinOcclusion = settings.pinOcclusion
            let showPlaceholder = settings.showPlaceholder, showNPCs = settings.showNPCs
            let cityOpacity = settings.cityOpacity
            guard let content else { return }
            content.city?.components.set(OpacityComponent(opacity: cityOpacity))
            content.npcs?.isEnabled = showNPCs
            content.city?.isEnabled = showCity
            // The pins only matter as an occluder when the city isn't covering them, and only
            // with real pins (Field Unit, pin block): the diorama has none.
            content.occluder?.isEnabled = pinOcclusion && !showCity && settings.setup.hasPins
            content.placeholder.isEnabled = showPlaceholder

            // Apply prestige filter material swap to city and NPCs
            PrestigeManager.shared.apply(level: GameState.shared.prestigeLevel, city: content.city, npcs: content.npcs)
        }

        /// `reset: false` keeps the world map and anchors; used to switch marker tracking off after a lock.
        func runSession(reset: Bool = true) {
            guard let arView else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            config.environmentTexturing = .automatic
            // LiDAR mesh of the room and terrain model: steadier world tracking, and
            // something real to check alignment against with "Show mesh".
            if ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
                config.sceneReconstruction = .mesh
            } else {
                print("[PROXY] Scene reconstruction unsupported on this device (needs LiDAR).")
            }
            // Hands (and people) in front of the city cover it, so a pointing finger reads.
            if useSegmentation, ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) {
                config.frameSemantics.insert(.personSegmentationWithDepth)
            }
            // Raw LiDAR depth per frame, for the fidelity scan.
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            if let images = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: nil) {
                // Track both markers while sampling their poses (MarkerSampler); once locked, no
                // detection at all, so a moving marker can't drag the city and ARKit stops
                // spending CPU re-finding the markers. Sync and Re-lock restore it.
                config.detectionImages = settings.isLocked ? [] : images
                config.maximumNumberOfTrackedImages = settings.isLocked ? 0 : 2
                // Scale estimation stays off: ARKit would silently rescale the anchors'
                // translation by an undocumented rule. The pair's err_mm (and print_scale_pct)
                // already measures print scale against the known 96.35 mm spacing.
                config.automaticImageScaleEstimationEnabled = false
            } else {
                print("[PROXY] AR Resources group missing; marker detection disabled.")
            }
            arView.session.run(config, options: reset ? [.resetTracking, .removeExistingAnchors] : [])
        }

        @objc func toggleDebug() {
            settings.showDebug.toggle()
        }

        func handleSync(_ request: Int) {
            guard request != lastSyncRequest else { return }
            lastSyncRequest = request
            unlock()
            lastLock = nil  // a new world frame: nothing to compare against
            // Rerun so ARKit reports the marker again even if it is already in view.
            runSession()
        }

        /// Debug: drop our anchor and sample the markers again in the same world frame (no
        /// .resetTracking), so successive locks can be compared directly (logged as RELOCK).
        func handleRelock(_ request: Int) {
            guard request != lastRelockRequest else { return }
            lastRelockRequest = request
            unlock()
            print("[PROXY] Re-lock requested (world kept).")
            runSession(reset: false)  // detection and tracking back on
        }

        private func unlock() {
            if let anchorEntity { arView?.scene.removeAnchor(anchorEntity) }
            if let worldAnchor { arView?.session.remove(anchor: worldAnchor) }
            anchorEntity = nil
            worldAnchor = nil
            samplers = [:]
            rightOnlyRefusals = 0
            settings.isSampling = false
            settings.needsBothMarkers = false
            settings.markerSeenTwice = false
            settings.isLocked = false
        }

        func handleSnapshot(_ request: Int) {
            guard request != lastSnapshotRequest else { return }
            lastSnapshotRequest = request
            takeSnapshot(tag: "manual")
        }

        /// After a lock; skipped if the lock is gone by then (Sync, Re-lock, session restart).
        func scheduleLockSnapshot(tag: String) {
            let lock = lockCount
            DispatchQueue.main.asyncAfter(deadline: .now() + SnapshotStore.lockDelay) { [weak self] in
                guard let self, self.settings.isLocked, self.lockCount == lock else { return }
                self.takeSnapshot(tag: tag)
            }
        }

        private func takeSnapshot(tag: String) {
            guard let arView else { return }
            snapshots.capture(arView, tag: tag, lock: lockCount, mode: lastLockMode,
                              setup: settings.setup.rawValue.replacingOccurrences(of: " ", with: "_"),
                              opacity: settings.cityOpacity)
        }

        func handleFit(_ request: Int) {
            guard request != lastFitRequest else { return }
            lastFitRequest = request
            runFit()
        }

        /// Feeds the depth scan while "Start scan" is on, and fits once coverage is high enough.
        private func updateScan(with frame: ARFrame) {
            guard settings.isScanning else {
                scan = nil
                return
            }
            guard settings.isLocked, let terrain = TerrainData.shared else {
                settings.isScanning = false
                settings.fitStatus = "Lock onto the marker first."
                print("[PROXY] Scan refused: not locked.")
                return
            }
            if scan == nil {
                scan = DepthScan()
                settings.fitResult = nil
                settings.fitStatus = nil
                print("[PROXY] Scan started.")
            }
            guard let scan else { return }
            scan.add(frame, worldToContent: offsetEntity.transformMatrix(relativeTo: nil).inverse, terrain: terrain)
            if scan.points.count != settings.scanPoints {
                settings.scanPoints = scan.points.count
                settings.scanCoverage = scan.coverage
            }
            if scan.coverage >= DepthScan.autoFitCoverage && scan.points.count >= DepthScan.minPointsToFit {
                runFit()
            }
        }

        private func runFit() {
            guard let scan, let terrain = TerrainData.shared else {
                settings.fitStatus = "Tap Start scan first."
                return
            }
            let points = scan.points
            let coverage = scan.coverage
            self.scan = nil
            settings.isScanning = false
            settings.fitStatus = "Fitting \(points.count) points…"
            print(String(format: "[PROXY] Scan finished: %d points, %.0f%% coverage. Fitting…", points.count, coverage * 100))
            Task.detached(priority: .userInitiated) { [settings] in
                let result = FidelityFit.solve(points: points, terrain: terrain)
                await MainActor.run {
                    if let result {
                        settings.fitResult = result
                        settings.fitStatus = result.summary
                        print("[PROXY] LiDAR fit: \(result.summary.replacingOccurrences(of: "\n", with: " · "))")
                    } else {
                        settings.fitStatus = "Too few points on the model (\(points.count)). Scan again closer, 20–40 cm away."
                        print("[PROXY] LiDAR fit failed: \(points.count) points.")
                    }
                }
            }
        }

        // MARK: ARSessionDelegate

        private var reticleHoverTime: TimeInterval = 0
        private var currentHoveredNpc: Entity?

        @MainActor
        private func updateReticle(frame: ARFrame) {
            guard let arView, settings.isLocked else { return }
            let gameState = GameState.shared
            let gameInput = GameInput.shared

            let screenCenter = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            let activeReticle = CGPoint(
                x: screenCenter.x + GameState.shared.reticleOffset.x,
                y: screenCenter.y + GameState.shared.reticleOffset.y
            )
            let camTransform = frame.camera.transform
            let camPos = SIMD3<Float>(camTransform.columns.3.x, camTransform.columns.3.y, camTransform.columns.3.z)
            let camFwd = -SIMD3<Float>(camTransform.columns.2.x, camTransform.columns.2.y, camTransform.columns.2.z)

            // Gather all active NPCs walking on the terrain
            let npcs = content?.npcs?.children.filter { $0.components.has(NPCComponent.self) } ?? []

            // Update hostile counter-combat system (in-flight projectiles, retaliation)
            if let npcsRoot = content?.npcs {
                let camInContent = offsetEntity.convert(position: camPos, from: nil)
                NPCCombatSystem.shared.update(dronePos: camInContent, npcsRoot: npcsRoot, dt: 1.0 / 60.0)
            }

            struct Candidate {
                let entity: Entity
                let screenDist: CGFloat
                let rayDist: Float
                let depth: Float
                let isTagged: Bool
                let targetId: Int
            }

            var candidates: [Candidate] = []

            for npc in npcs {
                let worldPos = npc.position(relativeTo: nil)
                let toNpc = worldPos - camPos
                let depth = simd_dot(toNpc, camFwd)
                guard depth > 0.05 else { continue } // Must be in front of the camera

                let projOnRay = camPos + camFwd * depth
                let rayDist = simd_length(worldPos - projOnRay)

                var screenDist: CGFloat = 9999.0
                if let pt = arView.project(worldPos) {
                    let unzoomed = hypot(pt.x - activeReticle.x, pt.y - activeReticle.y)
                    // Screen distance in unscaled reticle points
                    screenDist = unzoomed
                }

                let targetComp = npc.components[TargetComponent.self]
                let isTagged = targetComp?.isTagged ?? false
                let targetId = targetComp?.targetId ?? 0

                candidates.append(Candidate(
                    entity: npc,
                    screenDist: screenDist,
                    rayDist: rayDist,
                    depth: depth,
                    isTagged: isTagged,
                    targetId: targetId
                ))
            }

            // In high zoom, optical aim assist expands lock-on cone and electronic lock speed
            let isZoomed = gameState.zoomFactor > 1.5
            let screenConeThreshold: CGFloat = isZoomed ? 100.0 : 85.0
            let rayConeThreshold: Float = isZoomed ? 0.045 : 0.035

            let inReticle = candidates
                .filter { !$0.isTagged && ($0.screenDist < screenConeThreshold || $0.rayDist < rayConeThreshold) }
                .sorted { min($0.screenDist, CGFloat($0.rayDist * 1000.0)) < min($1.screenDist, CGFloat($1.rayDist * 1000.0)) }

            let bestTarget = inReticle.first

            if let targetCandidate = bestTarget {
                let targetEntity = targetCandidate.entity

                if currentHoveredNpc == targetEntity {
                    reticleHoverTime += 1.0 / 60.0
                } else {
                    currentHoveredNpc = targetEntity
                    reticleHoverTime = 0
                }

                gameState.isTargetLocked = true
                gameState.lockedTargetId = targetCandidate.targetId
                let lockRequiredTime = isZoomed ? 0.35 : 0.8
                gameState.lockProgress = Float(min(1.0, reticleHoverTime / lockRequiredTime))

                // Strike ONLY when the player pulls the trigger (✕, □, or tap TAG)!
                if gameInput.tagTriggered {
                    gameInput.tagTriggered = false

                    // Ammunition Check: Must have rounds to fire
                    guard gameState.fireWeapon() else {
                        AudioServicesPlaySystemSound(1053) // Dry fire click
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        SessionLogger.shared.log("DRY FIRE / RELOAD: ammunition empty (ammo=\(gameState.ammo))", category: "WEAPONS")
                        return
                    }

                    // Firing discharge audio & recoil haptic
                    AudioServicesPlaySystemSound(1520)
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

                    // Optical Zoom Precision Hit Bonus
                    if isZoomed {
                        gameState.score += 25
                        gameState.strikePopupText = "★ OPTICAL PRECISION HIT +25 ★"
                        gameState.strikePopupTimer = 1.0
                    }

                    // Spawn 3D ballistic tracer and orbital strike ray of light to target
                    let camInContent = offsetEntity.convert(position: camPos, from: nil)
                    let targetInContent = targetEntity.position(relativeTo: offsetEntity)
                    MissionSystem.spawnTracer(from: camInContent, to: targetInContent, in: offsetEntity)
                    MissionSystem.spawnStrikeRay(targetPos: targetInContent, in: offsetEntity)

                    reticleHoverTime = 0
                    gameState.isTargetLocked = false
                    gameState.lockProgress = 0

                    MissionSystem.tag(npcEntity: targetEntity)
                    if let npcsRoot = content?.npcs {
                        NPCCombatSystem.shared.triggerRetaliation(from: targetEntity, in: npcsRoot, toward: camInContent)
                    }
                    SessionLogger.shared.log("DIRECT STRIKE: fired round (\(gameState.ammo)/\(gameState.maxAmmo)) at screenDist=\(Int(targetCandidate.screenDist))pt, rayDist=\(Int(targetCandidate.rayDist * 1000))mm [zoom=\(gameState.zoomFactor)X]", category: "RETICLE")
                }
            } else {
                currentHoveredNpc = nil
                reticleHoverTime = 0
                gameState.isTargetLocked = false
                gameState.lockedTargetId = nil
                gameState.lockProgress = 0

                // If Attack/Tag button was pressed while NOT hovering a target dead-center,
                // check for assisted aim within an expanded cone (up to 140 pt / 60 mm)
                if gameInput.tagTriggered {
                    gameInput.tagTriggered = false

                    // Ammunition Check: Must have rounds to fire
                    guard gameState.fireWeapon() else {
                        AudioServicesPlaySystemSound(1053) // Dry fire click
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        SessionLogger.shared.log("DRY FIRE / RELOAD: ammunition empty (ammo=\(gameState.ammo))", category: "WEAPONS")
                        return
                    }

                    // Firing discharge audio & recoil haptic
                    AudioServicesPlaySystemSound(1520)
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

                    // Optical Zoom Precision Hit Bonus
                    if isZoomed {
                        gameState.score += 25
                        gameState.strikePopupText = "★ OPTICAL PRECISION HIT +25 ★"
                        gameState.strikePopupTimer = 1.0
                    }

                    let camInContent = offsetEntity.convert(position: camPos, from: nil)

                    let nearby = candidates
                        .filter { !$0.isTagged && ($0.screenDist < 140.0 || $0.rayDist < 0.060) }
                        .sorted { $0.screenDist < $1.screenDist }

                    if let assistedTarget = nearby.first {
                        let targetInContent = assistedTarget.entity.position(relativeTo: offsetEntity)
                        MissionSystem.spawnTracer(from: camInContent, to: targetInContent, in: offsetEntity)
                        MissionSystem.spawnStrikeRay(targetPos: targetInContent, in: offsetEntity)
                        MissionSystem.tag(npcEntity: assistedTarget.entity)
                        if let npcsRoot = content?.npcs {
                            NPCCombatSystem.shared.triggerRetaliation(from: assistedTarget.entity, in: npcsRoot, toward: camInContent)
                        }
                        SessionLogger.shared.log("ASSISTED STRIKE: fired round (\(gameState.ammo)/\(gameState.maxAmmo)) at screenDist=\(Int(assistedTarget.screenDist))pt, rayDist=\(Int(assistedTarget.rayDist * 1000))mm [zoom=\(gameState.zoomFactor)X]", category: "RETICLE")
                    } else {
                        // Blank fire through active reticle into diorama space
                        let ray = arView.ray(through: activeReticle)
                        let impactWorld = ray != nil ? ray!.origin + ray!.direction * 0.25 : (camPos + camFwd * 0.20)
                        let impactInContent = offsetEntity.convert(position: impactWorld, from: nil)
                        MissionSystem.spawnTracer(from: camInContent, to: impactInContent, in: offsetEntity)
                        MissionSystem.spawnImpactPuff(at: impactInContent, in: offsetEntity)
                        MissionSystem.spawnStrikeRay(targetPos: impactInContent, in: offsetEntity)
                        SessionLogger.shared.log("BLANK STRIKE: fired round (\(gameState.ammo)/\(gameState.maxAmmo)) into diorama terrain", category: "RETICLE")
                    }
                }
            }
        }

        // Drone Gimbal Aiming System (Joystick Reticle Control)
        @MainActor
        private func updateGimbalAim(dt: Float) {
            let input = GameInput.shared
            let gameState = GameState.shared

            let hasInput = abs(input.moveVector.x) > 0.04 || abs(input.moveVector.y) > 0.04

            if hasInput {
                let speed: CGFloat = 260.0 // points per second across the screen
                var newX = gameState.reticleOffset.x + CGFloat(input.moveVector.x) * speed * CGFloat(dt)
                var newY = gameState.reticleOffset.y - CGFloat(input.moveVector.y) * speed * CGFloat(dt)

                // Clamp to comfortable on-screen targeting bounds (inset from margins)
                newX = max(-160, min(160, newX))
                newY = max(-90, min(90, newY))

                gameState.reticleOffset = CGPoint(x: newX, y: newY)
                gameState.isGimbalAimActive = true
            }
        }

        @MainActor
        private func updateCameraTelemetry(frame: ARFrame) {
            guard anchorEntity != nil else { return }
            let dt: Float = 1.0 / 60.0
            updateGimbalAim(dt: dt)

            let invOffset = offsetEntity.transformMatrix(relativeTo: nil).inverse
            let camWorld = frame.camera.transform.columns.3
            let cam4 = invOffset * SIMD4<Float>(camWorld.x, camWorld.y, camWorld.z, 1.0)
            let camContent = SIMD3<Float>(cam4.x, cam4.y, cam4.z)

            if let terrain = TerrainData.shared {
                let groundY = terrain.height(x: camContent.x, z: camContent.z)
                let altMM = max(0, (camContent.y - groundY) * 1000)
                GameState.shared.droneAltitudeMM = altMM
            }

            // Camera heading in content frame (-Z in camera frame)
            let camFwdCol = frame.camera.transform.columns.2
            let camFwdWorld = -SIMD3<Float>(camFwdCol.x, camFwdCol.y, camFwdCol.z)
            let fwd4 = invOffset * SIMD4<Float>(camFwdWorld.x, camFwdWorld.y, camFwdWorld.z, 0.0)
            let fwdContent = SIMD2<Float>(fwd4.x, fwd4.z)
            let len = simd_length(fwdContent)
            if len > 1e-4 {
                let norm = fwdContent / len
                var deg = atan2(norm.x, -norm.y) * 180.0 / .pi
                if deg < 0 { deg += 360.0 }
                GameState.shared.droneHeadingDeg = deg
            }

            // Comfortable fuel drain rate for critique (~5.5 minutes of continuous full flight)
            if !GameState.shared.isFuelEmpty {
                GameState.shared.fuel = max(0, GameState.shared.fuel - dt * 0.3)
            }

            // Update weapon reload and recoil timers
            GameState.shared.updateWeapons(dt: dt)

            // Decrement active game UI timers
            if GameState.shared.tagBannerTimer > 0 {
                GameState.shared.tagBannerTimer = max(0, GameState.shared.tagBannerTimer - dt)
            }
            if GameState.shared.strikePopupTimer > 0 {
                GameState.shared.strikePopupTimer = max(0, GameState.shared.strikePopupTimer - dt)
            }
            if GameState.shared.screenFlashTimer > 0 {
                GameState.shared.screenFlashTimer = max(0, GameState.shared.screenFlashTimer - dt)
            }
            if GameState.shared.hostileWarningTimer > 0 {
                GameState.shared.hostileWarningTimer = max(0, GameState.shared.hostileWarningTimer - dt)
            }
            if GameState.shared.droneDamageFlashTimer > 0 {
                GameState.shared.droneDamageFlashTimer = max(0, GameState.shared.droneDamageFlashTimer - dt)
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            updateScan(with: frame)
            if settings.markerSeenTwice,
               ProcessInfo.processInfo.systemUptime - lastMarkerSample > Self.seenTwiceTimeout {
                settings.markerSeenTwice = false  // back to "Locate your Field Unit"
            }
            if !settings.isLocked {
                tryLock()  // timeout and fallback paths
            } else {
                // 60FPS Optimization: Drop queueing frames when main thread is busy
                guard !isProcessingFrame else { return }
                isProcessingFrame = true
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    defer { self.isProcessingFrame = false }
                    self.updateCameraTelemetry(frame: frame)
                    self.updateReticle(frame: frame)
                }
            }
        }

        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            sample(anchors, trackedOnly: true)
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("[PROXY] AR session failed: \(error.localizedDescription)")
            if useSegmentation {
                useSegmentation = false
                print("[PROXY] Retrying without hand segmentation.")
                // The retry resets tracking, so the old anchor's world frame is gone. Unlock first
                // so runSession turns detection back on and the city relocks instead of vanishing.
                if settings.isLocked { print("[PROXY] Session restarted after lock; re-detecting markers.") }
                unlock()
                lastLock = nil
                runSession()
            }
        }

        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            sample(anchors, trackedOnly: false)
        }

        private func sample(_ anchors: [ARAnchor], trackedOnly: Bool) {
            guard !settings.isLocked else { return }
            // The camera pose these anchors were seen from, for viewpoint-diverse sampling.
            let camera = arView?.session.currentFrame?.camera.transform
            let diverse = settings.diverseSampling
            for case let marker as ARImageAnchor in anchors {
                guard let name = marker.referenceImage.name else { continue }
                // Only the setup's own images: Diorama and pin block ignore DockMarker, Field Unit
                // 100 ignores both 50 mm markers, Field Unit 50 ignores the right one and DockMarker.
                guard settings.setup.uses(name) else { continue }
                if trackedOnly && !marker.isTracked { continue }
                // The untracked first detection (didAdd) stays out of the viewpoint set.
                samplers[name, default: MarkerSampler(diverse: diverse)].diverse = diverse
                samplers[name]?.add(marker.transform, camera: marker.isTracked ? camera : nil)
                lastMarkerSample = ProcessInfo.processInfo.systemUptime
                if !settings.isSampling { settings.isSampling = true }
            }
            if diverse { updateViewpointProgress() }
            tryLock()
        }
    }
}
