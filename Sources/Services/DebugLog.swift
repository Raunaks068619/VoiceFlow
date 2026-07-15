import Foundation

/// Dead-simple append-only file logger for diagnosing issues that the unified
/// log / stdout can't capture (Swift `print` is block-buffered when stdout is a
/// pipe, and LaunchServices-launched apps don't reliably forward it).
///
/// Writes to `~/Library/Logs/Vordi-debug.log`, one flushed line per call, off a
/// serial queue so callers never block on disk. TEMPORARY — added to trace the
/// hands-free path; remove once that's resolved.
enum DebugLog {
    private static let queue = DispatchQueue(label: "com.vordi.debuglog")
    private static let url: URL = {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("Vordi-debug.log")
    }()

    static func log(_ message: String) {
        // ISO-ish timestamp without pulling in a DateFormatter per call.
        let t = Date().timeIntervalSince1970
        let line = "[\(String(format: "%.3f", t))] \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? data.write(to: url)
            }
        }
    }
}
