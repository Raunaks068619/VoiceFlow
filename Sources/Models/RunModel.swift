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

    /// First ~80 chars of finalText (or rawText) for list-row preview.
    /// On failure falls back to the error message so the log row tells you
    /// *why* it failed (e.g. "401 Unauthorized") instead of lying about
    /// empty audio.
    var previewText: String {
        let source = postProcessing?.finalText ?? transcription?.rawText ?? ""
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return String(trimmed.prefix(80)) }
        if status == .failed, let msg = errorMessage, !msg.isEmpty {
            return "⚠︎ " + String(msg.prefix(80))
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
}
