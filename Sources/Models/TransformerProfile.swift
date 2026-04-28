import Foundation

/// Pluggable transformation strategy for a transcript.
///
/// **Mental model**: every dictation goes through one profile. The router
/// picks which one based on the trigger phrase, the active app, and user
/// settings. Profiles share the same input/output shape, so the pipeline
/// downstream (RunRecorder, TextInjector) doesn't care which one ran.
///
/// **Why a protocol vs. switch on enum**: profiles need their own state
/// (e.g. agentic profile holds a tool registry; magic-word profile reads
/// from a registry on disk). A protocol lets each carry the state it needs.
///
/// **Concurrency**: `transform` is async to allow LLM calls. Implementations
/// MUST be safe to invoke from a non-main queue. They're free to dispatch
/// internally as needed.
protocol TransformerProfile: AnyObject {
    /// Profile identity — used in RunStore + UI labels. Stable string so
    /// historical run-log entries stay valid across renames.
    var kind: ProfileKind { get }

    /// Human-readable label for UI ("Standard", "Dev Mode", "Prompt Engineer").
    /// Drives the chip in the run log row & the pre-injection overlay.
    var displayLabel: String { get }

    /// Transform a raw transcript into the final injection payload.
    /// Must call `completion` exactly once. Errors should be wrapped in
    /// `Result.failure` — the pipeline never throws past this boundary.
    func transform(_ input: TransformerInput,
                   completion: @escaping (Result<TransformerOutput, Error>) -> Void)
}

/// Identity tag for each profile. New profiles add cases; existing run-log
/// rows referencing removed profiles fall back to `displayLabel: "Unknown"`.
enum ProfileKind: String, Codable, CaseIterable {
    case standardCleanup    = "standard_cleanup"
    case developerMode      = "developer_mode"
    case promptEngineer     = "prompt_engineer"
    case variableRecognition = "variable_recognition"
    case magicWordExpansion = "magic_word_expansion"
    case agentic            = "agentic"
    case rewrite            = "rewrite"

    var displayLabel: String {
        switch self {
        case .standardCleanup:     return "Standard"
        case .developerMode:       return "Dev Mode"
        case .promptEngineer:      return "Prompt Engineer"
        case .variableRecognition: return "Variable"
        case .magicWordExpansion:  return "Magic Word"
        case .agentic:             return "Agentic"
        case .rewrite:             return "Rewrite"
        }
    }
}

/// Bundled input to every profile's `transform` call.
struct TransformerInput {
    let rawTranscript: String
    let context: ContextSnapshot
    /// Style hint passed in from settings — profiles MAY ignore.
    let style: TranscriptOutputStyle
    /// Mode hint (dictation vs. rewrite) — profiles MAY ignore.
    let mode: TranscriptProcessingMode
    /// Used to detect & strip trigger prefix words like "voiceflow create".
    /// Profiles often call this on `rawTranscript` before LLM calls.
    var triggerStripped: String {
        TriggerWords.strip(rawTranscript)
    }
}

/// Profile output. Wraps the final text plus telemetry the router records
/// onto the run.
struct TransformerOutput {
    /// Text to inject into the user's active text field.
    let finalText: String
    /// Free-form description of what the profile did, for the run log
    /// "what happened" row. e.g. "Magic Word: get pods → kubectl get pods".
    let summary: String
    /// LLM model used, if any. nil for deterministic profiles
    /// (regex-only, magic-word).
    let modelUsed: String?
    /// Estimated cost of this transformation in USD. 0 for deterministic
    /// or local-model profiles.
    let costUSD: Double
    /// Latency of the LLM step in ms. 0 for deterministic profiles.
    let llmLatencyMs: Int
    /// Whether the profile ran in agentic (tool-use) mode.
    let usedAgentic: Bool
    /// Internal trail of what the profile decided. Surfaced in the detail
    /// view for debugging trigger false-positives.
    let trace: [String]
}

// MARK: - Trigger words

/// Centralized phrase detection. Whisper's transcription of these triggers
/// is fuzzy ("voice flow create", "wide flow create") — match generously.
///
/// **Intent**: detect whether a transcript is a command-style invocation
/// vs. ordinary dictation. False positives steal the user's transcript;
/// false negatives just mean the user's command went into the editor verbatim.
/// Bias toward false negatives.
enum TriggerWords {
    /// Single source of truth for every dev-mode trigger phrase. Order matters:
    /// we strip the LONGEST matching prefix first.
    static let devCreatePrefixes: [String] = [
        "voiceflow create",
        "voice flow create",
        "wideflow create",
        "wide flow create",
        "vf create",
    ]

    static let promptEngineerPrefixes: [String] = [
        "voiceflow prompt",
        "voice flow prompt",
        "vf prompt",
    ]

    static let rewritePrefixes: [String] = [
        "voiceflow rewrite",
        "voice flow rewrite",
        "vf rewrite",
    ]

    /// True when the transcript starts with a dev-create trigger.
    static func isDevCreate(_ transcript: String) -> Bool {
        let normalized = normalize(transcript)
        return devCreatePrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    static func isPromptEngineer(_ transcript: String) -> Bool {
        let normalized = normalize(transcript)
        return promptEngineerPrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    static func isRewrite(_ transcript: String) -> Bool {
        let normalized = normalize(transcript)
        return rewritePrefixes.contains(where: { normalized.hasPrefix($0) })
    }

    /// Strip the longest matching trigger prefix and return the remainder.
    /// If no trigger matches, returns the input verbatim.
    ///
    /// e.g. "voiceflow create insert mock rows" → "insert mock rows"
    static func strip(_ transcript: String) -> String {
        let allPrefixes = devCreatePrefixes + promptEngineerPrefixes + rewritePrefixes
        // Sort by length DESC so "voiceflow create" wins over "voiceflow"
        // for `wideflow create`-shaped input.
        let sorted = allPrefixes.sorted { $0.count > $1.count }

        let normalized = normalize(transcript)
        for prefix in sorted where normalized.hasPrefix(prefix) {
            // Strip via index from the original (preserves casing of the rest).
            let stripLen = prefix.count
            let trimmed = transcript.trimmingCharacters(in: .whitespaces)
            // We applied lowercase to find the prefix; the original may have
            // different casing. Walk char-by-char to find the actual end.
            var consumed = 0
            var result = ""
            var passedPrefix = false
            for ch in trimmed {
                if !passedPrefix && consumed < stripLen {
                    consumed += 1
                    if consumed == stripLen { passedPrefix = true }
                    continue
                }
                result.append(ch)
            }
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lowercase + collapse whitespace for prefix matching. Doesn't touch
    /// punctuation since Whisper rarely emits it for short utterances.
    private static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let trimmed = lowered.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a leading punctuation char Whisper sometimes prepends
        // (e.g. ", voiceflow create...").
        let leading = trimmed.drop { ",.;:!?".contains($0) }
        return String(leading).trimmingCharacters(in: .whitespaces)
    }
}
