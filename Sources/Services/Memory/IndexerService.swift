import Foundation
import NaturalLanguage
import Combine

/// Manual worker that keeps `MemoryStore` consistent with `RunStore`.
///
/// **Three jobs:**
///   1. **Migration** — on first launch of v0.6.0, scan RunStore for any
///      runs not yet present in MemoryStore and bulk-import them. Runs
///      paginated in the background so the UI stays responsive.
///   2. **Embedding** — for each run in MemoryStore that lacks an
///      embedding (or has a stale one), compute via EmbeddingService.
///   3. **Entity extraction** — local transcript vocabulary first,
///      LLM enrichment second, NLTagger fallback last. This keeps the
///      graph stable for software terms, product names, and user vocab.
///
/// **Concurrency**: the sync pass is serial and cooperative. Embedding model
/// work and entity LLM calls share user resources, and parallelism wins
/// nothing for this derived index.
///
/// **Scheduling**: indexing is explicit. Dictation writes durable run files
/// immediately, then the user clicks Sync in Memory/Insights when they want
/// the derived search index, embeddings, entities, and AI insights updated.
@MainActor
final class IndexerService: ObservableObject {
    /// `nonisolated` so that nonisolated callers (RunStore.save runs
    /// on a serial dispatch queue, not the main actor) can reach
    /// `enqueue` without triggering a Sendable warning on the singleton
    /// itself. Instance state still routes through the main actor via
    /// the class-level @MainActor annotation.
    nonisolated static let shared = IndexerService()

    /// Bucketed status for the Memory tab header.
    enum Status: Equatable {
        case idle
        case migrating(progress: Double)
        case indexing(done: Int, total: Int)
        case error(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var indexedCount: Int = 0
    @Published private(set) var pendingCount: Int = 0

    private let memory = MemoryStore.shared
    private let runStore = RunStore.shared
    private let embedder = EmbeddingService.shared

    /// `nonisolated` so the singleton can be constructed from any
    /// context (the `static let shared` initializer runs on whichever
    /// thread first touches it). No @MainActor state touched here.
    nonisolated private init() {}

    // MARK: - Public API

    var isWorking: Bool {
        switch status {
        case .migrating, .indexing: return true
        case .idle, .error: return false
        }
    }

    /// Refresh counts only. This is safe for app/tab appearance because it
    /// does not compute embeddings or call an LLM.
    func start() {
        Task { @MainActor in
            // Memory is scoped to Vordi's own dictations. Drop any
            // external AI-agent sessions that older builds may have
            // imported, so the corpus is transcription-only.
            memory.purgeAgentSessions()
            await refreshCounts()
        }
    }

    /// Hook retained for older call sites. New dictations are no longer
    /// indexed automatically; Sync owns all derived Memory work.
    nonisolated func enqueue(runID: String) {
        _ = runID
    }

    // MARK: - Batched auto-sync

    /// After this many new dictations accumulate, kick a background Sync so
    /// Memory (embeddings + entities + FTS) never drifts far behind. Batching
    /// amortizes the one-time model load and avoids the per-transcription
    /// indexing that used to hang recording.
    private static let autoSyncThreshold = 20

    /// New successful dictations saved since the last auto-sync fired.
    private var newRunsSinceAutoSync = 0

    /// Call once a dictation run is durably saved (off the hot path — this is
    /// invoked from `RunStore.save`, not the transcription pipeline). Counts
    /// toward the threshold and, when reached, launches a low-priority
    /// background Sync. Never blocks the caller.
    nonisolated func noteSavedRun() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.newRunsSinceAutoSync += 1
            guard self.newRunsSinceAutoSync >= Self.autoSyncThreshold else { return }
            self.newRunsSinceAutoSync = 0
            self.triggerAutoSync()
        }
    }

    /// Fire a Sync in the background at low priority. Skips if a sync is
    /// already running (its backfill sweeps *all* unindexed runs, so nothing
    /// is lost — the tail is picked up on the next threshold). Runs off the
    /// main actor so it yields to any live dictation.
    private func triggerAutoSync() {
        guard !isWorking else { return }
        Task(priority: .background) { [weak self] in
            await self?.syncNow()
        }
    }

    /// User-triggered Sync. Updates the SQLite corpus from run files, then
    /// computes missing embeddings and entity links. This can be expensive,
    /// so callers should only invoke it from explicit UI.
    func syncNow() async {
        guard !isWorking else { return }
        await migrateIfNeeded()
        await backfillEmbeddingsAndEntities()
        await refreshCounts()
    }

    /// Force a full re-index. Used by the "Rebuild Memory" debug
    /// affordance and any time we change the embedding model in a way
    /// that invalidates existing vectors. Drops embeddings + entities
    /// but keeps runs + FTS (those are derived from RunStore and stable).
    func forceReindex() async {
        guard !isWorking else { return }
        await migrateIfNeeded()
        memory.clearDerivedIndex()
        await backfillEmbeddingsAndEntities(force: true)
        await refreshCounts()
    }

    // MARK: - Migration

    /// One-shot migration from RunStore (JSON files) to MemoryStore
    /// (SQLite). Runs once after v0.6.0 ships. Idempotent — re-running
    /// is safe and cheap (each run is upserted; existing rows are
    /// no-op'd by SQLite ON CONFLICT clauses).
    private func migrateIfNeeded() async {
        let jsonSummaries = runStore.summaries
        let toMigrate = jsonSummaries.filter { memory.getRun(id: $0.id.uuidString) == nil }
        guard !toMigrate.isEmpty else { return }

        print("IndexerService: migrating \(toMigrate.count) runs into MemoryStore")
        status = .migrating(progress: 0)

        for (idx, summary) in toMigrate.enumerated() {
            // Re-read the full run from disk to capture the post-process
            // final text + duration. Summary alone only has previewText
            // which can be truncated.
            guard let run = runStore.loadRun(id: summary.id) else { continue }
            let text = RunStore.transcriptText(for: run)
            let wordCount = ComputedStats.wordCount(of: summary)

            memory.upsertRun(
                id: summary.id.uuidString,
                createdAt: summary.createdAt,
                appName: summary.frontmostAppName,
                bundleID: summary.frontmostBundleID,
                profile: summary.profileUsed,
                wordCount: wordCount,
                durationSeconds: summary.durationSeconds,
                status: summary.status.rawValue,
                llmCostUSD: summary.llmCostUSD,
                transcriptText: text
            )

            // Yield occasionally so the UI doesn't choke on a thousand-
            // run backlog. Every 25 records is empirically smooth on
            // M1 base, generous on faster Macs.
            if idx % 25 == 0 {
                let progress = Double(idx + 1) / Double(toMigrate.count)
                status = .migrating(progress: progress)
                try? await Task.sleep(nanoseconds: 10_000_000)  // 10ms
            }
        }

        status = .idle
        print("IndexerService: migration complete")
    }

    // MARK: - Backfill

    private func backfillEmbeddingsAndEntities(force: Bool = false, includeAgentContext: Bool = false) async {
        let modelTag = embedder.modelKind.rawValue == "none"
            ? "pending"
            : modelTagFor(embedder.modelKind)

        // Embeddings — runs without one (or with a stale model tag).
        let needsEmb = memory.unindexedRunIDs(currentModel: modelTag, includeAgentContext: includeAgentContext)
        // Entities — runs that have no entity links yet.
        let needsEnt = memory.unentityRunIDs(includeAgentContext: includeAgentContext)
        // Union for accurate progress reporting.
        let allPending = Array(Set(needsEmb).union(Set(needsEnt))).sorted()

        guard !allPending.isEmpty else {
            status = .idle
            await refreshCounts(includeAgentContext: includeAgentContext)
            return
        }

        pendingCount = allPending.count
        status = .indexing(done: 0, total: allPending.count)

        var done = 0
        for runID in allPending {
            await indexSingleRun(runID: runID, includeAgentContext: includeAgentContext)
            done += 1
            // Republish status without re-allocating the whole queue.
            status = .indexing(done: done, total: allPending.count)
        }

        status = .idle
        await refreshCounts(includeAgentContext: includeAgentContext)
    }

    /// Index a single run: compute its embedding + extract entities.
    /// Idempotent — if either piece is already done, that step skips.
    private func indexSingleRun(runID: String, includeAgentContext: Bool) async {
        guard let text = memory.transcriptText(for: runID), !text.isEmpty else {
            return
        }

        // 1. Embedding (skip if up-to-date).
        let modelTag = modelTagFor(embedder.modelKind)
        if needsEmbedding(runID: runID, currentModel: modelTag, includeAgentContext: includeAgentContext) {
            do {
                let result = try await embedder.embed(text)
                memory.setEmbedding(runID: runID, vec: result.vec, model: result.model)
            } catch {
                print("IndexerService: embed failed for \(runID): \(error.localizedDescription)")
                // Don't fail the whole indexing pass — entities can
                // still be useful even without an embedding.
            }
        }

        // 2. Entity extraction (skip if we already have entries).
        if needsEntities(runID: runID, includeAgentContext: includeAgentContext) {
            let entities = await extractEntities(from: text)
            memory.setEntities(forRun: runID, entities: entities)
        }
    }

    // MARK: - Entity extraction (hybrid)

    /// Hybrid extraction for conversational dictations.
    ///
    /// Order matters:
    /// 1. Local transcript vocabulary: deterministic product/tool/concept
    ///    labels, including user vocabulary.
    /// 2. LLM: catches long-tail projects, concepts, and commands.
    /// 3. NLTagger: last-resort people/org/place fallback.
    ///
    /// Local-first prevents Apple's named-entity model from turning
    /// product terms like "Vordi", "Claude", or "UI" into places/people.
    private func extractEntities(from text: String) async -> [(id: String, label: String, type: String)] {
        let local = Self.localTranscriptEntities(in: text)

        // LLM pass for the long-tail. Uses the same provider picker as
        // Memory chat, so Claude/Codex/Gemini auth can power the graph
        // without requiring an OpenAI/Groq API key.
        let llmEntities: [(id: String, label: String, type: String)]
        do {
            llmEntities = try await Self.llmEntities(in: text)
        } catch {
            print("IndexerService: LLM entity extraction failed: \(error)")
            llmEntities = []
        }

        let cheap = Self.nlTaggerEntities(in: text)

        // Merge, de-dup by id (case-insensitive normalized slug).
        var seen = Set<String>()
        var merged: [(id: String, label: String, type: String)] = []
        for entity in (local + llmEntities + cheap) {
            if seen.insert(entity.id).inserted {
                merged.append(entity)
            }
        }
        // Cap per run so dense transcripts don't blow up the graph.
        return Array(merged.prefix(12))
    }

    private struct EntitySeed {
        let label: String
        let type: String
    }

    private static let localEntitySeeds: [EntitySeed] = [
        .init(label: "Vordi", type: "project"),
        .init(label: "Vordi", type: "project"),
        .init(label: "Memory", type: "concept"),
        .init(label: "Knowledge Graph", type: "concept"),
        .init(label: "Run Log", type: "concept"),
        .init(label: "Magic Words", type: "concept"),
        .init(label: "Dictation", type: "concept"),
        .init(label: "Transcription", type: "concept"),
        .init(label: "Whisper", type: "tool"),
        .init(label: "Super Whisper", type: "tool"),
        .init(label: "Wispr Flow", type: "tool"),
        .init(label: "WISPR", type: "tool"),
        .init(label: "Claude", type: "tool"),
        .init(label: "Claude AI", type: "tool"),
        .init(label: "Codex", type: "tool"),
        .init(label: "ChatGPT", type: "tool"),
        .init(label: "OpenAI", type: "tool"),
        .init(label: "OpenAI API", type: "tool"),
        .init(label: "Groq", type: "tool"),
        .init(label: "Grok API", type: "tool"),
        .init(label: "Gemini", type: "tool"),
        .init(label: "GitHub", type: "tool"),
        .init(label: "YouTube", type: "tool"),
        .init(label: "LinkedIn", type: "tool"),
        .init(label: "OnePlus", type: "tool"),
        .init(label: "AirPods", type: "tool"),
        .init(label: "SQL", type: "tool"),
        .init(label: "HTML", type: "tool"),
        .init(label: "Swift", type: "tool"),
        .init(label: "SwiftUI", type: "tool"),
        .init(label: "Xcode", type: "tool"),
        .init(label: "Figma", type: "tool"),
        .init(label: "AI", type: "concept"),
        .init(label: "A.I.", type: "concept"),
        .init(label: "API", type: "concept"),
        .init(label: "UI", type: "concept"),
        .init(label: "UX", type: "concept"),
        .init(label: "Hinglish", type: "concept"),
        .init(label: "Hindi", type: "concept"),
        .init(label: "Marathi", type: "concept"),
        .init(label: "Bookmark", type: "concept"),
        .init(label: "Bookmarks", type: "concept"),
        .init(label: "Raunak", type: "person"),
        .init(label: "Rahul", type: "person")
    ]

    /// Deterministic extractor for the product vocabulary users actually
    /// dictate. It uses Vordi defaults, user vocabulary, and obvious
    /// acronym/camel-case candidates before any model guesses run.
    private static func localTranscriptEntities(in text: String) -> [(id: String, label: String, type: String)] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var seen = Set<String>()
        var out: [(id: String, label: String, type: String)] = []

        func append(_ label: String, type: String) {
            let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 2 else { return }
            let id = slug(trimmed)
            guard !id.isEmpty, seen.insert(id).inserted else { return }
            out.append((id: id, label: trimmed, type: type))
        }

        for seed in localEntitySeeds where containsTerm(seed.label, in: text) {
            append(seed.label, type: seed.type)
        }

        for term in UserVocabulary.terms where containsTerm(term, in: text) {
            append(term, type: classifyLocalEntity(label: term))
        }

        for candidate in regexEntityCandidates(in: text) {
            append(candidate, type: classifyLocalEntity(label: candidate))
        }

        return Array(out.prefix(12))
    }

    private static func regexEntityCandidates(in text: String) -> [String] {
        let patterns = [
            #"(?<![\p{L}\p{N}])(?:[A-Z][A-Za-z0-9]+(?:\.[A-Za-z0-9]+)+)(?![\p{L}\p{N}])"#,
            #"(?<![\p{L}\p{N}])(?:[A-Z]{2,8})(?![\p{L}\p{N}])"#,
            #"(?<![\p{L}\p{N}])(?:[A-Z][a-z0-9]+(?:[A-Z][a-z0-9]+)+)(?![\p{L}\p{N}])"#,
            #"(?<![\p{L}\p{N}])(?:[A-Z][A-Za-z0-9]+(?:[ -][A-Z][A-Za-z0-9]+){1,2})(?![\p{L}\p{N}])"#
        ]

        var seen = Set<String>()
        var candidates: [String] = []
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: fullRange) {
                let raw = nsText.substring(with: match.range)
                let label = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard shouldKeepRegexCandidate(label) else { continue }
                let id = slug(label)
                guard seen.insert(id).inserted else { continue }
                candidates.append(label)
            }
        }

        return Array(candidates.prefix(10))
    }

    private static func shouldKeepRegexCandidate(_ label: String) -> Bool {
        let normalized = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count >= 2 else { return false }

        let lower = normalized.lowercased()
        let stopWords: Set<String> = [
            "and", "but", "for", "from", "into", "like", "then", "this",
            "that", "with", "without", "because", "today", "tomorrow",
            "yesterday", "user", "people", "tools", "places"
        ]
        guard !stopWords.contains(lower) else { return false }

        if normalized.contains(".") || normalized.contains("-") || normalized.contains(" ") {
            return true
        }

        let scalars = normalized.unicodeScalars
        let uppercaseCount = scalars.filter { CharacterSet.uppercaseLetters.contains($0) }.count
        if uppercaseCount >= 2 { return true }

        return normalized.dropFirst().contains { $0.isUppercase }
    }

    private static func classifyLocalEntity(label: String) -> String {
        let lower = label.lowercased()
        let slugged = slug(label)

        if ["raunak", "rahul"].contains(slugged) {
            return "person"
        }
        if ["ai", "a-i", "api", "ui", "ux", "memory", "knowledge-graph", "run-log", "magic-words", "dictation", "transcription", "hinglish", "hindi", "marathi", "bookmark", "bookmarks"].contains(slugged) {
            return "concept"
        }
        if lower.contains("api")
            || lower.hasSuffix(".io")
            || lower.hasSuffix(".ai")
            || lower.contains("github")
            || lower.contains("openai")
            || lower.contains("claude")
            || lower.contains("codex")
            || lower.contains("whisper")
            || lower.contains("sql")
            || lower.contains("html")
            || lower.contains("swift")
            || lower.contains("xcode")
            || lower.contains("figma") {
            return "tool"
        }
        if ["vordi", "vordi"].contains(slugged) {
            return "project"
        }
        return "concept"
    }

    private static func containsTerm(_ term: String, in text: String) -> Bool {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive], range: range) {
            if isBoundary(text, before: found.lowerBound)
                && isBoundary(text, after: found.upperBound) {
                return true
            }
            guard found.upperBound < text.endIndex else { break }
            range = found.upperBound..<text.endIndex
        }
        return false
    }

    private static func isBoundary(_ text: String, before index: String.Index) -> Bool {
        guard index > text.startIndex else { return true }
        let previous = text[text.index(before: index)]
        return !isEntityWordCharacter(previous)
    }

    private static func isBoundary(_ text: String, after index: String.Index) -> Bool {
        guard index < text.endIndex else { return true }
        return !isEntityWordCharacter(text[index])
    }

    private static func isEntityWordCharacter(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) }
            || char == "_"
    }

    /// NLTagger-driven extraction. Cheap and built into macOS. Returns
    /// people / organizations / places.
    private static func nlTaggerEntities(in text: String) -> [(id: String, label: String, type: String)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        var out: [(id: String, label: String, type: String)] = []
        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .nameType,
            options: options
        ) { tag, range in
            guard let tag else { return true }
            let label = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard label.count >= 2 else { return true }
            let type: String?
            switch tag {
            case .personalName:     type = "person"
            case .organizationName: type = "tool"
            // Apple's `placeName` maps to physical locations. We keep
            // it for completeness but most Vordi transcripts will
            // talk about software, so this should be rare.
            case .placeName:        type = "place"
            default: type = nil
            }
            guard let type else { return true }
            let id = Self.slug(label)
            guard !id.isEmpty else { return true }
            out.append((id: id, label: label, type: type))
            return true
        }
        return out
    }

    /// LLM-driven extraction for the conceptual long-tail. Same prompt
    /// shape as the v0.5 KnowledgeGraphService had — we move it here so
    /// the indexer owns ALL extraction in one place.
    private static func llmEntities(in text: String) async throws -> [(id: String, label: String, type: String)] {
        let systemPrompt = """
        Extract the most important entities mentioned in this transcript.
        Focus on types that named-entity recognition can't catch:
          - project   — project / product / feature names
          - tool      — software, frameworks, libraries
          - concept   — domain ideas, techniques, terms
          - command   — shell or code commands
        Skip people and places (other tools handle those). Skip generic words.

        At most 6 entities. IDs lowercase, alphanumerics + hyphens only.

        Respond with ONLY a JSON array, no markdown fences:
        [{"id":"kubectl","label":"kubectl","type":"tool"}]
        """

        let response = try await LLMRouter.shared.complete(
            system: systemPrompt,
            user: text,
            timeout: 60
        )
        return parseEntityJSON(response)
    }

    private static func parseEntityJSON(_ raw: String) -> [(id: String, label: String, type: String)] {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let r = cleaned.range(of: "```json") {
            cleaned.removeSubrange(cleaned.startIndex..<r.upperBound)
        }
        if let r = cleaned.range(of: "```", options: .backwards) {
            cleaned = String(cleaned[..<r.lowerBound])
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let data = cleaned.data(using: .utf8),
            let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return arr.compactMap { e in
            guard
                let labelRaw = (e["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                !labelRaw.isEmpty
            else { return nil }
            let id = slug((e["id"] as? String) ?? labelRaw)
            guard !id.isEmpty else { return nil }
            let validTypes = ["person", "project", "tool", "concept", "command", "place", "other"]
            let type = validTypes.contains((e["type"] as? String) ?? "")
                ? (e["type"] as! String)
                : "concept"
            return (id: id, label: labelRaw, type: type)
        }
    }

    // MARK: - Helpers

    private func needsEmbedding(runID: String, currentModel: String, includeAgentContext: Bool) -> Bool {
        // The simplest correct check: ask MemoryStore. The
        // unindexedRunIDs query already encodes "no embedding OR stale
        // model"; we just need to scope it to one run.
        let ids = memory.unindexedRunIDs(currentModel: currentModel, includeAgentContext: includeAgentContext)
        return ids.contains(runID)
    }

    private func needsEntities(runID: String, includeAgentContext: Bool) -> Bool {
        let ids = memory.unentityRunIDs(includeAgentContext: includeAgentContext)
        return ids.contains(runID)
    }

    private func modelTagFor(_ kind: EmbeddingService.ModelKind) -> String {
        switch kind {
        case .contextual: return "apple-contextual-en-v1"
        case .word:       return "apple-word-en-v1"
        case .none:       return "pending"
        }
    }

    private static func slug(_ raw: String) -> String {
        let lowered = raw.lowercased()
        let mapped = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "-" {
                return Character(scalar)
            }
            return " "
        }
        let parts = String(mapped)
            .split(separator: " ")
            .joined(separator: "-")
        return parts.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    func refreshCounts(includeAgentContext: Bool = false) async {
        indexedCount = memory.runCount(includeAgentContext: includeAgentContext)
        pendingCount = pendingWorkCount(includeAgentContext: includeAgentContext)
    }

    private func pendingWorkCount(includeAgentContext: Bool = false) -> Int {
        let modelTag = embedder.modelKind.rawValue == "none"
            ? "pending"
            : modelTagFor(embedder.modelKind)
        let derivedPending = Set(memory.unindexedRunIDs(currentModel: modelTag, includeAgentContext: includeAgentContext))
            .union(Set(memory.unentityRunIDs(includeAgentContext: includeAgentContext)))
            .count
        let runFilePending = max(0, runStore.summaries.count - memory.runCount(includeAgentContext: false))
        return runFilePending + derivedPending
    }
}
