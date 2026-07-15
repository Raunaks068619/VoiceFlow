import Foundation
import SQLite3

// SQLite needs to know whether a bound string can be freed immediately (STATIC)
// or must be copied (TRANSIENT). Swift String bridging is transient.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Full-text search over the *complete* transcripts (polished + raw), backed by
/// SQLite FTS5. The old path only matched `previewText` from index.json — this
/// indexes the whole `finalText` and `rawText` of every run.
///
/// The index is the server's own cache at
/// `~/Library/Application Support/Vordi/mcp-index.db`. It is built incrementally:
/// each refresh lists the run folders, parses the run id from the folder name
/// (cheap, no file read), and only reads + indexes runs not already present.
/// Read-only w.r.t. Vordi's own data — it never touches the run files.
final class SearchIndex {
    private let runsDir: URL
    private let dbURL: URL
    private var db: OpaquePointer?
    private let fm = FileManager.default

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
    private let isoOut: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // Column order in runs_fts (content is the only indexed column).
    // 0 runId | 1 createdAt | 2 app | 3 status | 4 wordCount | 5 finalText | 6 content
    private let contentColumn: Int32 = 6

    init(runsDir: URL) {
        self.runsDir = runsDir
        self.dbURL = runsDir.deletingLastPathComponent().appendingPathComponent("mcp-index.db")
    }

    /// Open the DB and ensure the FTS5 table exists. Returns false if FTS5 or the
    /// file is unavailable (caller falls back to substring search).
    func open() -> Bool {
        if db != nil { return true }
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
            logErr("search index: could not open \(dbURL.path)")
            db = nil
            return false
        }
        let create = """
        CREATE VIRTUAL TABLE IF NOT EXISTS runs_fts USING fts5(
            runId UNINDEXED, createdAt UNINDEXED, app UNINDEXED,
            status UNINDEXED, wordCount UNINDEXED, finalText UNINDEXED, content
        );
        """
        if sqlite3_exec(db, create, nil, nil, nil) != SQLITE_OK {
            logErr("search index: FTS5 unavailable — \(lastError())")
            sqlite3_close(db); db = nil
            return false
        }
        return true
    }

    // MARK: - Incremental build

    /// Index any runs present on disk but not yet in the FTS table.
    func refresh() {
        guard db != nil else { return }
        let indexed = indexedIDs()
        guard let folders = try? fm.contentsOfDirectory(
            at: runsDir, includingPropertiesForKeys: nil) else { return }

        var inserted = 0
        for folder in folders where folder.hasDirectoryPath {
            guard let id = runID(fromFolder: folder.lastPathComponent),
                  !indexed.contains(id.lowercased()) else { continue }
            let runURL = folder.appendingPathComponent("run.json")
            guard let data = try? Data(contentsOf: runURL),
                  let run = try? decoder.decode(RunLite.self, from: data) else { continue }
            insert(run)
            inserted += 1
        }
        if inserted > 0 { logErr("search index: indexed \(inserted) new run(s)") }
    }

    private func indexedIDs() -> Set<String> {
        var ids = Set<String>()
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT runId FROM runs_fts", -1, &stmt, nil) == SQLITE_OK
        else { return ids }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let c = sqlite3_column_text(stmt, 0) {
                ids.insert(String(cString: c).lowercased())
            }
        }
        return ids
    }

    /// Folder name is `<ISO timestamp>_<UUID>`; the UUID after the first '_' is the run id.
    private func runID(fromFolder name: String) -> String? {
        guard let us = name.firstIndex(of: "_") else { return nil }
        let id = String(name[name.index(after: us)...])
        return id.isEmpty ? nil : id
    }

    private func insert(_ r: RunLite) {
        let finalText = r.postProcessing?.finalText ?? ""
        let rawText = r.transcription?.rawText ?? ""
        // Index polished + raw so a search hits words either kept or removed by polish.
        var content = finalText
        if !rawText.isEmpty && rawText != finalText { content += "\n" + rawText }
        let displayText = finalText.isEmpty ? rawText : finalText
        let wordCount = displayText.split { $0 == " " || $0 == "\n" }.count

        let sql = "INSERT INTO runs_fts (runId, createdAt, app, status, wordCount, finalText, content) VALUES (?,?,?,?,?,?,?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, r.id.uuidString)
        bind(stmt, 2, isoOut.string(from: r.createdAt))
        bind(stmt, 3, r.context?.frontmostAppName ?? "")
        bind(stmt, 4, r.status)
        bind(stmt, 5, String(wordCount))
        bind(stmt, 6, displayText)
        bind(stmt, 7, content)
        sqlite3_step(stmt)
    }

    // MARK: - Query

    /// Returns matching runs ranked by FTS5 relevance, with a highlighted snippet.
    func search(query: String, limit: Int) -> [[String: Any]] {
        guard db != nil else { return [] }
        let match = ftsMatch(for: query)
        guard !match.isEmpty else { return [] }

        let sql = """
        SELECT runId, createdAt, app, status, wordCount, finalText,
               snippet(runs_fts, \(contentColumn), '«', '»', '…', 12)
        FROM runs_fts WHERE runs_fts MATCH ? ORDER BY rank LIMIT ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, match)
        sqlite3_bind_int(stmt, 2, Int32(max(0, limit)))

        var out: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            var d: [String: Any] = [
                "id": col(stmt, 0),
                "date": col(stmt, 1),
                "status": col(stmt, 3),
                "text": col(stmt, 5),
                "snippet": col(stmt, 6),
            ]
            let app = col(stmt, 2); if !app.isEmpty { d["app"] = app }
            if let w = Int(col(stmt, 4)) { d["wordCount"] = w }
            out.append(d)
        }
        return out
    }

    /// Turn free text into a safe FTS5 MATCH expression: each token becomes a
    /// quoted phrase, ANDed together. Quoting neutralizes FTS5 operators so a
    /// stray `"` or `*` from the user can't produce a syntax error.
    private func ftsMatch(for query: String) -> String {
        query
            .replacingOccurrences(of: "\"", with: " ")
            .split { $0 == " " || $0 == "\n" || $0 == "\t" }
            .map { "\"\($0)\"" }
            .joined(separator: " ")
    }

    // MARK: - Helpers

    private func bind(_ stmt: OpaquePointer?, _ idx: Int32, _ value: String) {
        sqlite3_bind_text(stmt, idx, value, -1, SQLITE_TRANSIENT)
    }
    private func col(_ stmt: OpaquePointer?, _ idx: Int32) -> String {
        guard let c = sqlite3_column_text(stmt, idx) else { return "" }
        return String(cString: c)
    }
    private func lastError() -> String {
        guard let db = db, let c = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: c)
    }
}
