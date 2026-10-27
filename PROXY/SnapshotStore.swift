import RealityKit
import UIKit

/// Saves what the AR view shows (camera plus overlay; the SwiftUI pill and panel are not part of
/// the ARView, so they're left out) as JPEGs in Documents/Snapshots/, visible in Files and
/// pullable with devicectl (Info.plist: UIFileSharingEnabled, LSSupportsOpeningDocumentsInPlace).
/// Taken ~2 s after each lock and on the debug panel's "Snapshot" button.
final class SnapshotStore {
    static let lockDelay: TimeInterval = 2
    static let quality: CGFloat = 0.9

    /// Snapshots taken this launch, for the file name.
    private var count = 0

    static var folder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Snapshots", isDirectory: true)
    }

    /// `tag`: "lock<k>", "relock<k>" or "manual". `lock` is the lock count so far (0 if none),
    /// `mode` the last lock's sampling mode, `opacity` the city opacity (0–1). Call on main.
    func capture(_ arView: ARView, tag: String, lock: Int, mode: String, setup: String, opacity: Float) {
        count += 1
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "snap_\(formatter.string(from: Date()))_\(count)_\(tag).jpg"
        arView.snapshot(saveToHDR: false) { image in
            guard let image else {
                print("[PROXY] SNAPSHOT failed: no image (\(name)).")
                return
            }
            // Encode and write off the main thread.
            Task.detached(priority: .utility) {
                let folder = SnapshotStore.folder
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    guard let data = image.jpegData(compressionQuality: SnapshotStore.quality) else {
                        print("[PROXY] SNAPSHOT failed: JPEG encoding (\(name)).")
                        return
                    }
                    try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                    print(String(format: "[PROXY] SNAPSHOT file=%@ lock=%d mode=%@ setup=%@ opacity=%.0f",
                                 name, lock, mode, setup, opacity * 100))
                } catch {
                    print("[PROXY] SNAPSHOT failed: \(error.localizedDescription) (\(name)).")
                }
            }
        }
    }
}
