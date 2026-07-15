import Foundation

/// Pure-function matcher for the magic-word registry.
///
/// **Match semantics**: prefix-only. The transcript must start with the
/// phrase (after normalization). This is intentional — substring matching
/// produces too many false positives when the user is dictating prose
/// that happens to contain a registered phrase.
///
/// **Fuzzy tolerance**: small Levenshtein distance (≤2) on the prefix to
/// absorb Whisper variability ("git whip" → "git wip"). Bigger distance
/// would catch more variations but starts firing on legitimate dictation.
///
/// **Surface filtering**: entries with a `surfaceScope` only match when
/// the snapshot's surface matches. Lets users define different "wip"
/// expansions for terminal vs. notes apps.
struct MagicWordResolver {
    /// Maximum edit distance allowed on the prefix-match attempt.
    /// 0 = strict, 2 = generous. Empirically: 1 catches 95% of Whisper
    /// transcription noise without misfiring; we go with 1 by default.
    static let defaultFuzzDistance = 1

    let entries: [MagicWord]
    let fuzzDistance: Int

    init(entries: [MagicWord], fuzzDistance: Int = MagicWordResolver.defaultFuzzDistance) {
        self.entries = entries
        self.fuzzDistance = fuzzDistance
    }

    /// Returns the first matching entry, or .none. Sorted by phrase
    /// length DESC so "list k8s namespaces" wins over "list k8s" when
    /// both could prefix-match.
    func resolve(transcript: String, surface: AppSurface) -> MagicWordMatch {
        let normalized = MagicWord.normalize(transcript)
        guard !normalized.isEmpty else { return .none }

        // Spaceless variant of the transcript. We collapse all internal
        // whitespace so a user who registered "get pods" still matches
        // when Whisper transcribed the utterance as one token "getpods"
        // (or vice-versa).
        //
        // **Why this exists**: STT is inconsistent about word boundaries
        // for short technical phrases. Users say "GETPODS" as a single
        // chunk and Whisper sometimes splits, sometimes doesn't. Without
        // this path, the fuzz check fails because the edit distance
        // between "getpods" and "get pods" already eats the entire
        // fuzzDistance=1 budget on the missing space — leaving nothing
        // for actual Whisper noise.
        let normalizedNoSpace = normalized.replacingOccurrences(of: " ", with: "")

        let candidates = entries
            .filter { $0.enabled }
            .filter { $0.surfaceScope == nil || $0.surfaceScope == surface }
            .sorted { $0.normalizedPhrase.count > $1.normalizedPhrase.count }

        for entry in candidates {
            let phrase = entry.normalizedPhrase
            guard !phrase.isEmpty else { continue }

            // Strict prefix match path — fast & exact.
            if normalized == phrase {
                return .exact(entry)
            }
            if normalized.hasPrefix(phrase + " ") {
                let remainder = String(normalized.dropFirst(phrase.count + 1))
                return .prefix(entry, remainder: remainder)
            }

            // Spaceless equality / prefix. Cheaper than fuzz and handles
            // the dominant failure mode (missing-space tokenization).
            //
            // Prefix carries remainder only when the spaceless phrase is
            // a strict prefix of the spaceless transcript AND the next
            // char in the original normalized transcript is a space —
            // otherwise we can't tell where the trigger ended (e.g.
            // "getpods" matching phrase "get" with remainder "pods"
            // would be a false positive). Length-DESC sort handles
            // multi-word ambiguity ("get pods all" beats "get").
            let phraseNoSpace = phrase.replacingOccurrences(of: " ", with: "")
            if !phraseNoSpace.isEmpty {
                if normalizedNoSpace == phraseNoSpace {
                    return .exact(entry)
                }
                // Min-length floor mirrors the fuzzy path: phrases <4 chars
                // ("get", "wip") must not prefix-match unrelated longer words.
                if phraseNoSpace.count >= 4, normalizedNoSpace.hasPrefix(phraseNoSpace) {
                    // Find the original-space split point so the remainder
                    // is recoverable. Walk the original transcript chars
                    // consuming non-space chars until we've eaten
                    // `phraseNoSpace.count` of them.
                    if let remainder = Self.remainderAfterSpacelessPrefix(
                        in: normalized,
                        consuming: phraseNoSpace.count
                    ) {
                        return remainder.isEmpty ? .exact(entry) : .prefix(entry, remainder: remainder)
                    }
                }
            }

            // Fuzzy prefix match — only when fuzzDistance > 0 AND the
            // candidate phrase is long enough that fuzz won't be a free-for-all.
            // Phrases <4 chars don't get fuzz: "wip" vs "tip" would expand
            // unintentionally.
            guard fuzzDistance > 0, phrase.count >= 4 else { continue }

            // Take the same number of chars as `phrase` from the front of
            // `normalized` and edit-distance them. Cheap because phrases
            // are short (typically <30 chars).
            // Require a word boundary right after the fuzzy-matched head:
            // either the head IS the whole transcript, or the next char is a
            // space. Without this, a short trigger fuzzy-matches the prefix of
            // an unrelated longer word ("wipe" in "wiped out") and we slice a
            // corrupted remainder.
            let nchars = Array(normalized)
            let headEndsOnBoundary = nchars.count == phrase.count
                || (nchars.count > phrase.count && nchars[phrase.count] == " ")
            let head = String(normalized.prefix(phrase.count))
            if headEndsOnBoundary, Self.editDistance(head, phrase) <= fuzzDistance {
                let remainder = normalized.count > phrase.count
                    ? String(normalized.dropFirst(phrase.count + 1))
                    : ""
                return remainder.isEmpty ? .exact(entry) : .prefix(entry, remainder: remainder)
            }
        }

        return .none
    }

    /// Given a space-aware normalized transcript and a count of
    /// non-space chars consumed by a spaceless-phrase prefix match,
    /// return the remainder of the transcript after the consumed chars
    /// (skipping the following whitespace if present).
    ///
    /// Returns nil if the prefix length exceeds the available non-space
    /// chars — shouldn't happen if the caller already confirmed the
    /// spaceless-prefix relation, but the guard makes the function safe
    /// in isolation.
    private static func remainderAfterSpacelessPrefix(
        in normalized: String,
        consuming targetCount: Int
    ) -> String? {
        var consumed = 0
        var idx = normalized.startIndex
        while idx < normalized.endIndex && consumed < targetCount {
            if normalized[idx] != " " {
                consumed += 1
            }
            idx = normalized.index(after: idx)
        }
        guard consumed == targetCount else { return nil }
        // Word-boundary guard: the consumed prefix must end at a real
        // boundary (a space or end-of-string) in the original transcript.
        // If the next char is a word char, the phrase matched the START of
        // a longer word ("get" inside "getting") — reject, don't slice a
        // corrupted remainder.
        if idx < normalized.endIndex && normalized[idx] != " " {
            return nil
        }
        // Skip a single trailing space — that's the natural break after
        // the trigger. Anything after that is the user's remainder.
        if idx < normalized.endIndex && normalized[idx] == " " {
            idx = normalized.index(after: idx)
        }
        return String(normalized[idx...])
    }

    /// Standard Levenshtein edit distance. Implemented inline to avoid
    /// pulling in a dependency for one ~30-line algorithm.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }

        // Two-row optimization — we only need the previous row to compute
        // the current one. Saves O(min(m, n)) memory vs. full matrix.
        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)

        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(
                    curr[j - 1] + 1,        // insertion
                    prev[j] + 1,            // deletion
                    prev[j - 1] + cost      // substitution
                )
            }
            (prev, curr) = (curr, prev)
        }
        return prev[bChars.count]
    }
}
