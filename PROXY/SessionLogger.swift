import Foundation
import UIKit

/// Session-wide debug logger that records events to both console and a timestamped file
/// in the app's Documents/Logs directory for retrieval via `devicectl`.
final class SessionLogger: @unchecked Sendable {
    static let shared = SessionLogger()

    private let fileQueue = DispatchQueue(label: "com.cassiuspalacio.proxy.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private let dateFormatter: DateFormatter
    private let logDateFormatter: DateFormatter

    private init() {
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd-HHmmss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        logDateFormatter = DateFormatter()
        logDateFormatter.dateFormat = "HH:mm:ss.SSS"
        logDateFormatter.locale = Locale(identifier: "en_US_POSIX")

        setupLogFile()
    }

    private func setupLogFile() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logsDir = docs.appendingPathComponent("Logs", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
            let filename = "session_\(dateFormatter.string(from: Date())).log"
            let logFile = logsDir.appendingPathComponent(filename)

            if !FileManager.default.fileExists(atPath: logFile.path) {
                FileManager.default.createFile(atPath: logFile.path, contents: nil)
            }

            fileHandle = try FileHandle(forWritingTo: logFile)
            fileHandle?.seekToEndOfFile()

            let header = "=== PROXY Session Log Started at \(Date()) ===\nDevice: iPhone 17 Pro Max\n\n"
            if let data = header.data(using: .utf8) {
                fileHandle?.write(data)
            }
            print("[PROXY] SessionLogger initialized: \(logFile.path)")
        } catch {
            print("[PROXY] SessionLogger failed to create log file: \(error.localizedDescription)")
        }
    }

    func log(_ message: String, category: String = "GENERAL") {
        let timestamp = logDateFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"

        // Also print to console
        print("[PROXY][\(category)] \(message)")

        fileQueue.async { [weak self] in
            guard let self, let handle = self.fileHandle, let data = line.data(using: .utf8) else { return }
            handle.write(data)
        }
    }

    deinit {
        try? fileHandle?.close()
    }
}
