import Foundation

/// User-supplied custom vocabulary — names, brands, jargon — that gets
/// injected into BOTH the Whisper STT prompt (biases the decoder toward
/// these spellings) AND the polish LLM prompt (preserves them as-typed).
///
/// **Mental model**: TextExpander dictionary, but for transcription accuracy.
/// Storing "Raunak, VoiceFlow, Shopsense, Fynd" makes Whisper less likely to
/// emit "Ronaka" / "vo'isalopa" / "Shop sense" / "Find" for those words.
///
/// **Why injection in both layers**:
/// - STT prompt biases the acoustic decoder. Whisper's "prompt" field is
///   limited to ~244 tokens (~1000 chars) — beyond that it's silently
///   truncated. Critical for proper-noun pronunciation matching.
/// - Polish prompt is the safety net. Even when STT mangles a name, the
///   LLM has the canonical spelling and can repair it during cleanup.
///
/// **Storage**: a single freeform string in UserDefaults. We accept both
/// commas and newlines as separators so users can paste lists from
/// anywhere — comma-separated copy/pastes, line-per-item edits, mixed.
enum UserVocabulary {
    static let userDefaultsKey = "user_vocabulary"

    /// Cap on the prompt-injected payload. Whisper's prompt field truncates
    /// at ~244 tokens (≈1000 chars) — staying well below avoids the silent
    /// trim. Polish LLMs have plenty of room but bigger means more cost.
    /// 800 chars ≈ 100-150 vocabulary terms, plenty for a personal dictionary.
    static let maxPromptInjectionChars = 800

    /// Raw user-typed string. May contain commas, newlines, mixed.
    static var rawString: String {
        UserDefaults.standard.string(forKey: userDefaultsKey) ?? ""
    }

    /// Parsed term list. Splits on commas + newlines, trims whitespace,
    /// drops empties + duplicates (case-insensitive). Order preserved
    /// from user input.
    static var terms: [String] {
        let separators = CharacterSet(charactersIn: ",\n")
        var seen: Set<String> = []
        var result: [String] = []
        for raw in rawString.components(separatedBy: separators) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            if seen.insert(key).inserted {
                result.append(trimmed)
            }
        }
        return result
    }

    /// Comma-joined list, capped at `maxPromptInjectionChars`. Empty when
    /// the user hasn't added any terms (callers should treat empty as
    /// "skip the vocab line in the prompt entirely").
    static var promptInjection: String {
        let joined = terms.joined(separator: ", ")
        guard joined.count > maxPromptInjectionChars else { return joined }

        // Truncate at the LAST comma boundary inside the cap so we never
        // split a term mid-word ("Voice" instead of "VoiceFlow"). If
        // somehow there's no comma (one giant pasted blob), fall back to
        // hard char truncation.
        let head = String(joined.prefix(maxPromptInjectionChars))
        if let lastComma = head.lastIndex(of: ",") {
            return String(head[..<lastComma])
        }
        return head
    }
}
