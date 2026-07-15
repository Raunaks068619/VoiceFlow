import Foundation

/// Read-only access to Vordi's dictation history on disk. No app process needed.
/// All methods return plain JSON-serializable values so the MCP layer can emit
/// them directly as tool results.
final class VordiStore {
    private let fm = FileManager.default
    private lazy var index: SearchIndex? = {
        let idx = SearchIndex(runsDir: runsDir)
        return idx.open() ? idx : nil
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601   // matches RunStore's encoder
        return d
    }()

    private let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// ~/Library/Application Support/Vordi/runs — same path RunStore writes.
    private var runsDir: URL {
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Vordi/runs", isDirectory: true)
    }

    // MARK: - Loads

    private func loadSummaries() -> [RunSummaryLite] {
        let url = runsDir.appendingPathComponent("index.json")
        guard let data = try? Data(contentsOf: url),
              let arr = try? decoder.decode([RunSummaryLite].self, from: data) else {
            return []
        }
        return arr
    }

    private func runFolder(forID id: String) -> URL? {
        guard let items = try? fm.contentsOfDirectory(at: runsDir, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return nil
        }
        let needle = id.lowercased()
        return items.first { $0.lastPathComponent.lowercased().contains(needle) }
    }

    // MARK: - Tool backings

    /// Most recent runs, newest first (index.json is already newest-first).
    func listRuns(limit: Int) -> [[String: Any]] {
        Array(loadSummaries().prefix(max(0, limit))).map { summaryDict($0) }
    }

    /// Full-text search over the complete transcripts via SQLite FTS5, ranked by
    /// relevance with highlighted snippets. Falls back to a case-insensitive
    /// substring scan over `previewText` if the index can't be opened.
    func search(query: String, limit: Int) -> [[String: Any]] {
        if let index = index {
            index.refresh()   // pick up any dictations added since last call
            return index.search(query: query, limit: limit)
        }
        let q = query.lowercased()
        let hits = loadSummaries().filter { $0.previewText.lowercased().contains(q) }
        return Array(hits.prefix(max(0, limit))).map { summaryDict($0) }
    }

    /// Full detail for one run, including raw + polished transcript.
    func getRun(id: String) -> [String: Any]? {
        guard let folder = runFolder(forID: id) else { return nil }
        let url = folder.appendingPathComponent("run.json")
        guard let data = try? Data(contentsOf: url),
              let run = try? decoder.decode(RunLite.self, from: data) else {
            return nil
        }
        return runDict(run)
    }

    // MARK: - Shaping

    private func summaryDict(_ s: RunSummaryLite) -> [String: Any] {
        var d: [String: Any] = [
            "id": s.id.uuidString,
            "date": isoOut.string(from: s.createdAt),
            "status": s.status,
            "durationSeconds": s.durationSeconds,
            "text": s.previewText,
        ]
        if let a = s.frontmostAppName { d["app"] = a }
        if let p = s.profileUsed { d["profile"] = p }
        if let w = s.wordCount { d["wordCount"] = w }
        return d
    }

    private func runDict(_ r: RunLite) -> [String: Any] {
        var d: [String: Any] = [
            "id": r.id.uuidString,
            "date": isoOut.string(from: r.createdAt),
            "status": r.status,
            "durationSeconds": r.durationSeconds,
        ]
        if let t = r.transcription {
            d["rawTranscript"] = t.rawText
            d["sttProvider"] = t.provider
            d["sttLatencyMs"] = t.latencyMs
        }
        if let p = r.postProcessing {
            d["finalTranscript"] = p.finalText
            d["polishModel"] = p.model
            d["style"] = p.style
            d["mode"] = p.mode
            d["polishLatencyMs"] = p.latencyMs
        }
        if let c = r.context {
            var ctx: [String: Any] = [:]
            if let a = c.frontmostAppName { ctx["app"] = a }
            if let b = c.frontmostBundleID { ctx["bundleID"] = b }
            if !ctx.isEmpty { d["context"] = ctx }
        }
        if let pr = r.profileUsed { d["profile"] = pr }
        return d
    }

    /// Pretty JSON text for a tool result payload.
    func jsonText(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return s
    }
}
