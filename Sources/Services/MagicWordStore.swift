import Foundation
import Combine

/// Disk-backed registry of magic-word entries.
///
/// Storage: `~/Library/Application Support/VoiceFlow/magicwords.json`
/// — same parent dir as `runs/` for tidiness.
///
/// **Why JSON, not Core Data**: 1–200 entries, schema is trivial,
/// human-readable & shareable (export → import via Settings UI).
final class MagicWordStore: ObservableObject {
    static let shared = MagicWordStore()

    @Published private(set) var entries: [MagicWord] = []

    private let queue = DispatchQueue(label: "com.voiceflow.magicwords", qos: .utility)
    private let fileManager = FileManager.default
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private var storeURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("VoiceFlow", isDirectory: true)
            .appendingPathComponent("magicwords.json")
    }

    private init() {
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        ensureDirectory()
        loadInitial()
    }

    // MARK: - Public API

    func add(_ word: MagicWord) {
        queue.async { [weak self] in
            guard let self else { return }
            var current = self.loadSync()
            current.append(word)
            self.persist(current)
        }
    }

    func update(_ word: MagicWord) {
        queue.async { [weak self] in
            guard let self else { return }
            var current = self.loadSync()
            if let idx = current.firstIndex(where: { $0.id == word.id }) {
                var updated = word
                updated.updatedAt = Date()
                current[idx] = updated
                self.persist(current)
            }
        }
    }

    func delete(id: UUID) {
        queue.async { [weak self] in
            guard let self else { return }
            var current = self.loadSync()
            current.removeAll { $0.id == id }
            self.persist(current)
        }
    }

    /// Replace the entire registry. Used by import flow.
    func replaceAll(_ entries: [MagicWord]) {
        queue.async { [weak self] in
            self?.persist(entries)
        }
    }

    /// Synchronous read — fast (<5ms), safe to call from the matcher hot
    /// path. We return a snapshot, NOT a live array, so callers can't
    /// race against `update()` mid-iteration.
    func snapshot() -> [MagicWord] {
        // Prefer the published copy when it's fresh; otherwise read disk.
        // This avoids hitting disk on every dictation (called once per run).
        let published = entries
        if !published.isEmpty { return published }
        return loadSync()
    }

    // MARK: - Defaults

    /// Seeds a small set of starter entries on first launch — created
    /// DISABLED so the user discovers them in the registry but they don't
    /// silently fire on dictation. Once the user toggles one ON they
    /// effectively endorsed it.
    ///
    /// Only runs if the registry file doesn't exist on disk yet.
    private func seedDefaultsIfFirstLaunch() {
        guard !fileManager.fileExists(atPath: storeURL.path) else { return }
        let defaults: [MagicWord] = [
            MagicWord(
                phrase: "git wip",
                expansion: "git add -A && git commit -m \"wip\" && git push",
                tag: "git",
                surfaceScope: .terminal,
                enabled: false
            ),
            MagicWord(
                phrase: "list namespaces",
                expansion: "kubectl get ns",
                tag: "k8s",
                surfaceScope: .terminal,
                enabled: false
            ),
            MagicWord(
                phrase: "describe pods",
                expansion: "kubectl describe pods",
                tag: "k8s",
                surfaceScope: .terminal,
                enabled: false
            ),
            MagicWord(
                phrase: "todo",
                expansion: "// TODO(raunak): ",
                tag: "code",
                surfaceScope: .ide,
                enabled: false
            ),
        ]
        persist(defaults)
    }

    // MARK: - Internals

    private func ensureDirectory() {
        let dir = storeURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func loadInitial() {
        seedDefaultsIfFirstLaunch()
        let loaded = loadSync()
        DispatchQueue.main.async { [weak self] in
            self?.entries = loaded
        }
    }

    private func loadSync() -> [MagicWord] {
        guard let data = try? Data(contentsOf: storeURL) else { return [] }
        return (try? decoder.decode([MagicWord].self, from: data)) ?? []
    }

    private func persist(_ list: [MagicWord]) {
        do {
            let data = try encoder.encode(list)
            try data.write(to: storeURL, options: .atomic)
            DispatchQueue.main.async { [weak self] in
                self?.entries = list
            }
        } catch {
            print("MagicWordStore: failed to persist — \(error)")
        }
    }
}
