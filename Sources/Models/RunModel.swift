import Foundation

/// Immutable ledger entry for a single dictation run.
/// Once stored, a Run is never mutated — only deleted.
struct Run: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: Double
    let status: RunStatus

    let capture: CaptureStage
    let transcription: TranscriptionStage?
    let postProcessing: PostProcessingStage?

    /// Human-readable failure reason when `status == .failed`.
    /// nil for successful or noSpeech runs. Surfaced in the Run Log UI so
    /// failures don't all collapse to the useless "(no transcript)" row.
    let errorMessage: String?

    // MARK: - Phase 1+ context-aware fields
    //
    // All optional + decoded with `decodeIfPresent` semantics so
    // historical runs written before these fields existed still load
    // cleanly. Don't make any of these required without a migration plan.

    /// Snapshot of frontmost app + selection captured at hotkey-press time.
    /// nil for runs persisted before context capture shipped.
    let context: ContextSnapshot?

    /// Which TransformerProfile produced the final text. nil = unknown
    /// (legacy run). String, not enum, so adding a new ProfileKind doesn't
    /// invalidate old persisted runs.
    let profileUsed: String?

    /// Free-form trace of what the profile decided. Renders as a list in
    /// the run-detail view's "How VoiceFlow handled this" section.
    let profileTrace: [String]?

    /// Estimated dollar cost of all LLM calls in this run (transcription
    /// excluded — we don't bill per-call there in current pricing).
    /// Used by the Insights tab to show cumulative spend.
    let llmCostUSD: Double?

    init(
        id: UUID,
        createdAt: Date,
        durationSeconds: Double,
        status: RunStatus,
        capture: CaptureStage,
        transcription: TranscriptionStage?,
        postProcessing: PostProcessingStage?,
        errorMessage: String?,
        context: ContextSnapshot? = nil,
        profileUsed: String? = nil,
        profileTrace: [String]? = nil,
        llmCostUSD: Double? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.capture = capture
        self.transcription = transcription
        self.postProcessing = postProcessing
        self.errorMessage = errorMessage
        self.context = context
        self.profileUsed = profileUsed
        self.profileTrace = profileTrace
        self.llmCostUSD = llmCostUSD
    }

    // Custom Codable init so old run.json files (without the new fields)
    // still decode cleanly.
    enum CodingKeys: String, CodingKey {
        case id, createdAt, durationSeconds, status
        case capture, transcription, postProcessing
        case errorMessage
        case context, profileUsed, profileTrace, llmCostUSD
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        self.status = try c.decode(RunStatus.self, forKey: .status)
        self.capture = try c.decode(CaptureStage.self, forKey: .capture)
        self.transcription = try c.decodeIfPresent(TranscriptionStage.self, forKey: .transcription)
        self.postProcessing = try c.decodeIfPresent(PostProcessingStage.self, forKey: .postProcessing)
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.context = try c.decodeIfPresent(ContextSnapshot.self, forKey: .context)
        self.profileUsed = try c.decodeIfPresent(String.self, forKey: .profileUsed)
        self.profileTrace = try c.decodeIfPresent([String].self, forKey: .profileTrace)
        self.llmCostUSD = try c.decodeIfPresent(Double.self, forKey: .llmCostUSD)
    }

    /// Full transcript text for list-row display (or error message on failure).
    ///
    /// Previously capped at 80 chars — that decision was made when the row
    /// layout was a single ellipsis-truncated line. The Home timeline now
    /// wraps multi-line so any cap here is destructive: the full transcript
    /// gets baked into `RunSummary` and persisted, losing data even though
    /// the full text is also stored in `run.json`. Trust the UI to handle
    /// length: rows that want a one-liner can apply `.lineLimit(1)` at the
    /// view layer; rows that want full text just don't.
    var previewText: String {
        let source = postProcessing?.finalText ?? transcription?.rawText ?? ""
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if status == .failed, let msg = errorMessage, !msg.isEmpty {
            return "⚠︎ " + msg
        }
        return "(no transcript)"
    }

    var hasFinalText: Bool {
        guard let final = postProcessing?.finalText ?? transcription?.rawText else { return false }
        return !final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum RunStatus: String, Codable {
    case success
    case failed
    case noSpeech
}

struct CaptureStage: Codable {
    /// Relative filename within the run folder (e.g. "audio.wav").
    let audioFilename: String
    let audioSizeBytes: Int
    let voicedBufferRange: String?  // e.g. "12...148 of 200"
}

struct TranscriptionStage: Codable {
    let provider: String       // e.g. "openai/gpt-4o-transcribe" or "groq/whisper-large-v3-turbo"
    let rawText: String
    let latencyMs: Int
}

struct PostProcessingStage: Codable {
    let mode: String           // dictation / rewrite
    let style: String          // verbatim / clean / clean_hinglish
    let model: String          // e.g. "gpt-4.1-mini"
    let prompt: String         // full system prompt used
    let finalText: String
    let latencyMs: Int
    let droppedLanguageGuardTriggered: Bool
}

/// Lightweight summary for the index file — avoids loading full Run JSON
/// just to render the list.
struct RunSummary: Codable, Identifiable {
    let id: UUID
    let createdAt: Date
    let durationSeconds: Double
    let status: RunStatus
    let previewText: String
    /// Mirrored here (not just on Run) so the list view can show the
    /// reason without loading the full run.json for every failed row.
    let errorMessage: String?

    // Phase 1+ context — denormalized into the index so list rows can
    // render the app chip & profile pill without loading run.json.
    // All optional for forward-compat with pre-Phase1 indices.

    /// Bundle ID of the frontmost app at hotkey-press time. Used by the
    /// Insights tab to compute "where you dictate most often".
    let frontmostBundleID: String?
    /// Display name shown in the row's app-chip.
    let frontmostAppName: String?
    /// Profile that produced this run — drives the profile pill in the row.
    let profileUsed: String?
    /// LLM cost for this run, used in cumulative spend totals.
    let llmCostUSD: Double?
    /// Word count of the final injected text. Cached here so the WPM math
    /// in Insights doesn't re-tokenize every previewText on each render.
    let wordCount: Int?

    init(
        id: UUID,
        createdAt: Date,
        durationSeconds: Double,
        status: RunStatus,
        previewText: String,
        errorMessage: String?,
        frontmostBundleID: String? = nil,
        frontmostAppName: String? = nil,
        profileUsed: String? = nil,
        llmCostUSD: Double? = nil,
        wordCount: Int? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.durationSeconds = durationSeconds
        self.status = status
        self.previewText = previewText
        self.errorMessage = errorMessage
        self.frontmostBundleID = frontmostBundleID
        self.frontmostAppName = frontmostAppName
        self.profileUsed = profileUsed
        self.llmCostUSD = llmCostUSD
        self.wordCount = wordCount
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, durationSeconds, status, previewText, errorMessage
        case frontmostBundleID, frontmostAppName, profileUsed, llmCostUSD, wordCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.durationSeconds = try c.decode(Double.self, forKey: .durationSeconds)
        self.status = try c.decode(RunStatus.self, forKey: .status)
        self.previewText = try c.decode(String.self, forKey: .previewText)
        self.errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        self.frontmostBundleID = try c.decodeIfPresent(String.self, forKey: .frontmostBundleID)
        self.frontmostAppName = try c.decodeIfPresent(String.self, forKey: .frontmostAppName)
        self.profileUsed = try c.decodeIfPresent(String.self, forKey: .profileUsed)
        self.llmCostUSD = try c.decodeIfPresent(Double.self, forKey: .llmCostUSD)
        self.wordCount = try c.decodeIfPresent(Int.self, forKey: .wordCount)
    }
}
