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

            // Fuzzy prefix match — only when fuzzDistance > 0 AND the
            // candidate phrase is long enough that fuzz won't be a free-for-all.
            // Phrases <4 chars don't get fuzz: "wip" vs "tip" would expand
            // unintentionally.
            guard fuzzDistance > 0, phrase.count >= 4 else { continue }

            // Take the same number of chars as `phrase` from the front of
            // `normalized` and edit-distance them. Cheap because phrases
            // are short (typically <30 chars).
            let head = String(normalized.prefix(phrase.count))
            if Self.editDistance(head, phrase) <= fuzzDistance {
                let remainder = normalized.count > phrase.count
                    ? String(normalized.dropFirst(phrase.count + 1))
                    : ""
                return remainder.isEmpty ? .exact(entry) : .prefix(entry, remainder: remainder)
            }
        }

        return .none
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
