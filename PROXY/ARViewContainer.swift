import ARKit
import RealityKit
import SwiftUI

struct ARViewContainer: UIViewRepresentable {
    let settings: PlacementSettings

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
        // Reading these here registers them with Observation, so slider changes re-run this.
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
                applyVisibility()
            }
        }

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

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            updateScan(with: frame)
            if settings.markerSeenTwice,
               ProcessInfo.processInfo.systemUptime - lastMarkerSample > Self.seenTwiceTimeout {
                settings.markerSeenTwice = false  // back to "Locate your Field Unit"
            }
            if !settings.isLocked { tryLock() }  // timeout and fallback paths
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
