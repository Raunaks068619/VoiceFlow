import Foundation
import Combine

/// Disk-backed run history with a ring-buffer cap.
///
/// Storage layout:
/// ```
/// ~/Library/Application Support/Vordi/runs/
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
    private let queue = DispatchQueue(label: "com.vordi.runstore", qos: .utility)

    /// Maximum retained runs. Always `nil` — capping is permanently
    /// disabled.
    ///
    /// **History note**: pre-v0.5.0 capped history at 20 runs. v0.5.0
    /// flipped the *default* off, but existing users had
    /// `run_log_cap_enabled = true` baked into their UserDefaults
    /// from the first launch, so the new default never applied. This
    /// hard-codes the answer: no cap, ever. Users who care about disk
    /// usage can purge from Settings → Run Log.
    ///
    /// Why this matters: Insights' user-type classifier needs ≥20
    /// substantive runs to unlock, Memory needs the full corpus to
    /// build a useful graph, and Run Log itself is the audit trail.
    /// Silently throwing away history defeats all three.
    var maxRuns: Int? { nil }

    /// Cap enablement flag — preserved for backwards source compatibility
    /// (Settings UI still binds against it) but the value is fixed at
    /// `false`. Reads to UserDefaults are bypassed entirely.
    var isCapEnabled: Bool { false }

    var isEnabled: Bool {
        // Default ON — user can toggle off in settings.
        let key = "run_log_enabled"
        if UserDefaults.standard.object(forKey: key) == nil { return true }
        return UserDefaults.standard.bool(forKey: key)
    }

    private var runsDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Vordi/runs", isDirectory: true)
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

                // Write optional screenshot context. The image bytes are
                // intentionally transient on ContextSnapshot and omitted from
                // run.json; the file is the source of truth for playback.
                if
                    let screenshot = run.context?.screenshot,
                    screenshot.status == .captured,
                    let filename = screenshot.filename,
                    let imageData = screenshot.imageData
                {
                    try imageData.write(to: folderURL.appendingPathComponent(filename))
                }

                // Write full run record
                let runData = try self.encoder.encode(run)
                try runData.write(to: folderURL.appendingPathComponent("run.json"))

                // Update index — denormalize the new context fields so
                // list rows can render the app-chip + profile pill without
                // loading run.json. Word count cached for Insights' WPM math.
                let wordCount = run.previewText
                    .components(separatedBy: .whitespacesAndNewlines)
                    .filter { !$0.isEmpty }
                    .count
                let summary = RunSummary(
                    id: run.id,
                    createdAt: run.createdAt,
                    durationSeconds: run.durationSeconds,
                    status: run.status,
                    previewText: run.previewText,
                    errorMessage: run.errorMessage,
                    frontmostBundleID: run.context?.frontmostBundleID,
                    frontmostAppName: run.context?.frontmostAppName,
                    profileUsed: run.profileUsed,
                    llmCostUSD: run.llmCostUSD,
                    wordCount: wordCount
                )
                var current = self.loadIndexSync()
                current.insert(summary, at: 0)

                // Ring buffer: trim excess only when cap is enabled.
                // Nil cap → unlimited growth, user pays the disk cost.
                if let cap = self.maxRuns {
                    while current.count > cap {
                        let removed = current.removeLast()
                        self.deleteRunFolder(id: removed.id)
                    }
                }

                try self.writeIndex(current)

                DispatchQueue.main.async {
                    self.summaries = current
                }

                print("RunStore: saved run \(run.id) (\(run.previewText))")

                // MemoryStore is a derived index. We intentionally do not
                // update it inline here; instead we tick the auto-sync counter
                // so a *batched* background Sync fires every N dictations,
                // keeping recording cheap while bounding index staleness.
                // Only successful runs carry a usable transcript to embed.
                if run.status == .success {
                    IndexerService.shared.noteSavedRun()
                }
            } catch {
                print("RunStore: failed to save run — \(error)")
            }
        }
    }

    /// Extract the most-useful transcript text for indexing. Prefers the
    /// polished output over raw STT (polished is what the user actually
    /// saw); falls back to raw if polish failed, then to the legacy
    /// previewText. Trimmed at the edges so leading/trailing whitespace
    /// doesn't poison FTS tokenization.
    static func transcriptText(for run: Run) -> String {
        let primary = run.postProcessing?.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let primary, !primary.isEmpty { return primary }
        let raw = run.transcription?.rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return run.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// URL of the context screenshot for detail view.
    func screenshotURL(for run: Run) -> URL? {
        guard
            let filename = run.context?.screenshot?.filename,
            !filename.isEmpty
        else { return nil }

        let candidates = runFolders().filter { $0.lastPathComponent.contains(run.id.uuidString) }
        guard let folder = candidates.first else { return nil }
        let url = folder.appendingPathComponent(filename)
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
            // Cascade the delete into MemoryStore. We don't gate on a
            // success/failure result — MemoryStore is derivable from
            // RunStore, so the worst case is a stale index entry that
            // IndexerService can sweep on next launch.
            MemoryStore.shared.deleteRun(id: id.uuidString)
        }
    }

    /// Apply the current retention cap immediately.
    ///
    /// Called when the user toggles the cap ON after accumulating an
    /// unlimited history. Without this, the over-cap runs would stick
    /// around until the next `save()` triggered the ring-buffer trim,
    /// which feels broken from the user's side ("I just said cap at 20,
    /// why do I still see 500?").
    ///
    /// No-op when cap is disabled or when history is already within cap.
    func applyCap() {
        queue.async { [weak self] in
            guard let self, let cap = self.maxRuns else { return }
            var current = self.loadIndexSync()
            guard current.count > cap else { return }

            while current.count > cap {
                let removed = current.removeLast()
                self.deleteRunFolder(id: removed.id)
            }

            do {
                try self.writeIndex(current)
                DispatchQueue.main.async {
                    self.summaries = current
                }
                print("RunStore: cap applied, trimmed to \(cap) runs")
            } catch {
                print("RunStore: applyCap failed to write index — \(error)")
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
