import Foundation
import Combine

/// Disk-backed run history with a ring-buffer cap.
///
/// Storage layout:
/// ```
/// ~/Library/Application Support/VoiceFlow/runs/
/// ├── index.json                         // [RunSummary]
/// └── 2026-04-16T10-32-45_<uuid>/
///     ├── audio.wav
///     └── run.json                       // full Run record
/// ```
///
/// Design decisions:
/// - Filesystem over Core Data: audio files are already files, human-inspectable,
///   trivial purge semantics (`removeItem`).
/// - index.json is <100 rows; JSONEncoder round-trip is fine.
/// - Ring buffer: on write, if count > maxRuns, delete oldest.
final class RunStore: ObservableObject {
    static let shared = RunStore()

    @Published private(set) var summaries: [RunSummary] = []

    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let queue = DispatchQueue(label: "com.voiceflow.runstore", qos: .utility)

    var maxRuns: Int {
        let stored = UserDefaults.standard.integer(forKey: "run_log_max_count")
        return stored > 0 ? stored : 20
    }

    var isEnabled: Bool {
        // Default ON — user can toggle off in settings.
        let key = "run_log_enabled"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private var runsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("VoiceFlow/runs", isDirectory: true)
    }

    private var indexURL: URL {
        runsDirectory.appendingPathComponent("index.json")
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectory()
        loadIndex()
    }

    // MARK: - Public API

    /// Persist a completed Run + its audio data. Thread-safe.
    func save(run: Run, audioData: Data) {
        guard isEnabled else { return }

        queue.async { [weak self] in
            guard let self else { return }
            do {
                let folderName = self.folderName(for: run)
                let folderURL = self.runsDirectory.appendingPathComponent(folderName, isDirectory: true)
                try self.fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

                // Write audio
                let audioURL = folderURL.appendingPathComponent(run.capture.audioFilename)
                try audioData.write(to: audioURL)

                // Write full run record
                let runData = try self.encoder.encode(run)
                try runData.write(to: folderURL.appendingPathComponent("run.json"))

                // Update index
                let summary = RunSummary(
                    id: run.id,
                    createdAt: run.createdAt,
                    durationSeconds: run.durationSeconds,
                    status: run.status,
                    previewText: run.previewText,
                    errorMessage: run.errorMessage
                )
                var current = self.loadIndexSync()
                current.insert(summary, at: 0)

                // Ring buffer: trim excess
                while current.count > self.maxRuns {
                    let removed = current.removeLast()
                    self.deleteRunFolder(id: removed.id)
                }

                try self.writeIndex(current)

                DispatchQueue.main.async {
                    self.summaries = current
                }

                print("RunStore: saved run \(run.id) (\(run.previewText))")
            } catch {
                print("RunStore: failed to save run — \(error)")
            }
        }
    }

    /// Load the full Run record for detail view.
    func loadRun(id: UUID) -> Run? {
        let candidates = runFolders().filter { $0.lastPathComponent.contains(id.uuidString) }
        guard let folder = candidates.first else { return nil }
        let runURL = folder.appendingPathComponent("run.json")
        guard let data = try? Data(contentsOf: runURL) else { return nil }
        return try? decoder.decode(Run.self, from: data)
    }

    /// URL of the audio file for playback.
    func audioURL(for run: Run) -> URL? {
        let candidates = runFolders().filter { $0.lastPathComponent.contains(run.id.uuidString) }
        guard let folder = candidates.first else { return nil }
        let url = folder.appendingPathComponent(run.capture.audioFilename)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Delete a single run.
    func deleteRun(id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            self.deleteRunFolder(id: id)
            var current = self.loadIndexSync()
            current.removeAll { $0.id == id }
            try? self.writeIndex(current)
            DispatchQueue.main.async {
                self.summaries = current
            }
        }
    }

    /// Nuke all history.
    func clearAll() {
        queue.async { [weak self] in
            guard let self else { return }
            for folder in self.runFolders() {
                try? self.fileManager.removeItem(at: folder)
            }
            try? self.writeIndex([])
            DispatchQueue.main.async {
                self.summaries = []
            }
        }
    }

    // MARK: - Private helpers

    private func ensureDirectory() {
        try? fileManager.createDirectory(at: runsDirectory, withIntermediateDirectories: true)
    }

    private func folderName(for run: Run) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate]
        let dateString = formatter.string(from: run.createdAt)
            .replacingOccurrences(of: ":", with: "-")
        return "\(dateString)_\(run.id.uuidString)"
    }

    private func loadIndex() {
        queue.async { [weak self] in
            guard let self else { return }
            let loaded = self.loadIndexSync()
            DispatchQueue.main.async {
                self.summaries = loaded
            }
        }
    }

    private func loadIndexSync() -> [RunSummary] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        return (try? decoder.decode([RunSummary].self, from: data)) ?? []
    }

    private func writeIndex(_ summaries: [RunSummary]) throws {
        let data = try encoder.encode(summaries)
        try data.write(to: indexURL, options: .atomic)
    }

    private func runFolders() -> [URL] {
        (try? fileManager.contentsOfDirectory(
            at: runsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ).filter { $0.hasDirectoryPath }) ?? []
    }

    private func deleteRunFolder(id: UUID) {
        let idString = id.uuidString
        for folder in runFolders() where folder.lastPathComponent.contains(idString) {
            try? fileManager.removeItem(at: folder)
        }
    }
}
