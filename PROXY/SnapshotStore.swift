import RealityKit
import UIKit

/// Saves high-resolution action and calibration snapshots as JPEGs in Documents/Snapshots/,
/// visible in Files and pullable with devicectl.
/// Captures both the pure 3D AR view and the full-screen HUD composite during action moments.
final class SnapshotStore: @unchecked Sendable {
    static let shared = SnapshotStore()
    static let lockDelay: TimeInterval = 2
    static let quality: CGFloat = 0.92

    weak var activeARView: ARView?
    private var lastActionSnapshotTime: TimeInterval = 0
    private let actionCooldown: TimeInterval = 0.85

    /// Snapshots taken this launch, for the file name sequence.
    private var count = 0

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapshots", isDirectory: true)
    }

    /// Triggers an automatic or manual action snapshot (e.g. strike, hostile retaliation, swarm panic, hero shot).
    func captureAction(tag: String) {
        let now = CACurrentMediaTime()
        guard now - lastActionSnapshotTime > actionCooldown else { return }
        lastActionSnapshotTime = now

        DispatchQueue.main.async { [weak self] in
            guard let self, let arView = self.activeARView else { return }
            self.capture(arView, tag: tag, lock: 0, mode: "action", setup: "action", opacity: 1.0)
        }
    }

    /// Captures the ARView and window hierarchy, saving both pure AR and composite HUD images.
    func capture(_ arView: ARView, tag: String, lock: Int = 0, mode: String = "auto", setup: String = "auto", opacity: Float = 1.0) {
        count += 1
        let currentCount = count
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let baseName = "snap_\(timestamp)_\(currentCount)_\(tag)"

        // Optional full-screen HUD window composite capture
        var hudImageData: Data? = nil
        if let window = arView.window {
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let composite = renderer.image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
            hudImageData = composite.jpegData(compressionQuality: SnapshotStore.quality)
        }

        // 3D RealityKit Framebuffer snapshot
        arView.snapshot(saveToHDR: false) { image in
            guard let image else {
                SessionLogger.shared.log("SNAPSHOT failed: no image (\(baseName))", category: "SNAPSHOT")
                return
            }

            let arImageData = image.jpegData(compressionQuality: SnapshotStore.quality)

            // Encode and write off the main thread.
            Task.detached(priority: .utility) {
                let folder = SnapshotStore.folder
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

                    // 1. Save AR 3D View
                    if let arData = arImageData {
                        let arFile = folder.appendingPathComponent("\(baseName)_ar.jpg")
                        try arData.write(to: arFile, options: .atomic)
                    }

                    // 2. Save Full-Screen HUD Composite
                    if let hudData = hudImageData {
                        let hudFile = folder.appendingPathComponent("\(baseName)_hud.jpg")
                        try hudData.write(to: hudFile, options: .atomic)
                    }

                    SessionLogger.shared.log("ACTION SNAPSHOT: \(baseName) [lock=\(lock) tag=\(tag)]", category: "SNAPSHOT")
                    print(String(format: "[PROXY] SNAPSHOT file=%@ lock=%d mode=%@ setup=%@ opacity=%.0f",
                                 baseName, lock, mode, setup, opacity * 100))
                } catch {
                    SessionLogger.shared.log("SNAPSHOT save error: \(error.localizedDescription) (\(baseName))", category: "SNAPSHOT")
                }
            }
        }
    }
}
