import Foundation

/// User-supplied custom vocabulary — names, brands, jargon — that gets
/// injected into BOTH the Whisper STT prompt (biases the decoder toward
/// these spellings) AND the polish LLM prompt (preserves them as-typed).
///
/// **Mental model**: TextExpander dictionary, but for transcription accuracy.
/// Storing "Raunak, Vordi, Shopsense, Fynd" makes Whisper less likely to
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
        // split a term mid-word ("Voice" instead of "Vordi"). If
        // somehow there's no comma (one giant pasted blob), fall back to
        // hard char truncation.
        let head = String(joined.prefix(maxPromptInjectionChars))
        if let lastComma = head.lastIndex(of: ",") {
            return String(head[..<lastComma])
        }
        return head
    }

    // MARK: - Local find-and-replace
    //
    // Whisper's prompt-field biasing is unreliable (~30-40% miss rate),
    // and on Verbatim mode no polish LLM runs to repair mishears. So
    // proper-noun fixes need a LOCAL deterministic step that runs on
    // every transcript path, including verbatim.
    //
    // The function does case-insensitive exact match + Levenshtein-1
    // fuzzy match for terms ≥4 chars. Every match → replaced with the
    // canonical user-typed form. Sub-millisecond, no network.
    //
    // Examples (with vocab term "Groq"):
    //   "I use grok"     → "I use Groq"   (case fix, distance 0)
    //   "I use Grok"     → "I use Groq"   (homophone, distance 1)
    //   "I use GROQ"     → "I use Groq"   (case fix, distance 0)
    //   "Crock is fast"  → "Crock is fast" (distance 2 → no match, stays)
    //
    // Edge cases handled:
    //   - Word boundaries enforced — "groove" doesn't match "Groq"
    //     (would otherwise be distance 2 from "groov")
    //   - Multi-word vocab terms ("Vordi Studio") match across whitespace
    //     in the input ("vordi studio" / "Vordi Studio")
    //   - When the same input span matches multiple vocab terms, the
    //     LONGER term wins (so "Vordi Studio" beats "Vordi")

    /// Apply the user's vocabulary as case-insensitive + fuzzy
    /// find-and-replace. Returns the input unchanged when there are no
    /// vocab terms.
    static func applyTo(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        let vocab = terms
        guard !vocab.isEmpty else { return text }

        // Sort by length DESC so longer canonical forms win when two
        // terms could both match the same input span (e.g. user has
        // "Voice" + "Vordi" — we want "Vordi" to win).
        let sortedVocab = vocab.sorted { $0.count > $1.count }

        var result = text
        for canonical in sortedVocab {
            result = replaceMatches(in: result, canonical: canonical)
        }
        return result
    }

    /// Replace every fuzzy-or-exact case-insensitive match of `canonical`
    /// in `text` with `canonical` (preserving the user-typed casing).
    private static func replaceMatches(in text: String, canonical: String) -> String {
        // Word-boundary tokenization: split on whitespace + punctuation,
        // keep the separators so we can rejoin without losing structure.
        // `componentsSeparatedByCharacterSet` drops separators; we need
        // them. Use a manual scan instead.
        var output = ""
        output.reserveCapacity(text.count)

        // Multi-word canonical needs space-collapsed comparison.
        let canonicalTokens = canonical
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).lowercased() }

        // Tokenize input keeping byte offsets so we can rebuild with the
        // canonical form swapped in.
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            // Pass through any non-letter/digit/apostrophe character.
            if !isWordCharacter(chars[i]) {
                output.append(chars[i])
                i += 1
                continue
            }

            // Try to match canonical starting at position `i`.
            if let consumed = matchAt(chars: chars, start: i, canonicalTokens: canonicalTokens) {
                output += canonical
                i += consumed
                continue
            }

            // No match — pass through this word verbatim.
            while i < chars.count, isWordCharacter(chars[i]) {
                output.append(chars[i])
                i += 1
            }
        }
        return output
    }

    /// Try to match the canonical token sequence starting at chars[start].
    /// Returns the number of characters consumed on success, or nil on
    /// no match. Allows whitespace between input tokens for multi-word
    /// canonical terms.
    private static func matchAt(
        chars: [Character],
        start: Int,
        canonicalTokens: [String]
    ) -> Int? {
        var pos = start
        for (idx, expected) in canonicalTokens.enumerated() {
            // Skip separator whitespace before each token EXCEPT the first.
            if idx > 0 {
                while pos < chars.count, chars[pos].isWhitespace {
                    pos += 1
                }
                // For SINGLE-token canonical, we never reach here. For
                // multi-token, expecting at least some whitespace OR a
                // direct concatenation ("voice" "flow" → "vordi")
                // both work — we already consumed any whitespace above.
            }

            // Read the next input token (run of word chars).
            let tokenStart = pos
            while pos < chars.count, isWordCharacter(chars[pos]) {
                pos += 1
            }
            let tokenEnd = pos
            if tokenStart == tokenEnd { return nil } // no token here
            let inputToken = String(chars[tokenStart..<tokenEnd]).lowercased()

            // For all-tokens-concatenated canonical (e.g. canonical
            // tokens = ["voice", "flow"], user input = "vordi"),
            // try matching the WHOLE remaining canonical against this
            // single input token.
            if idx == 0 && canonicalTokens.count > 1 {
                let joined = canonicalTokens.joined()
                // EXACT only here — a fuzzy match would split a single real
                // word into the multi-token canonical (e.g. "react" → "re act").
                if inputToken == joined.lowercased() {
                    return tokenEnd - start
                }
            }

            if !matches(inputToken, expected: expected) { return nil }
        }
        return pos - start
    }

    /// True if input token matches expected token (case-insensitive)
    /// either exactly or within Levenshtein distance 1 (only for tokens
    /// ≥4 chars to avoid "yes" matching "yet" type false positives).
    private static func matches(_ input: String, expected: String) -> Bool {
        if input == expected.lowercased() { return true }
        // Fuzzy (Levenshtein-1) gating. The old 4-char floor silently
        // rewrote common English words to vocab canonicals — "from"→"form",
        // "word"→"ward", "were"→"here" — because they're one edit apart.
        // Require BOTH terms ≥6 chars and the input no shorter than the
        // canonical, so we only repair Whisper misspellings of genuinely
        // long, distinctive proper nouns, never hijack short real words.
        guard expected.count >= 6,
              input.count >= max(6, expected.count),
              abs(input.count - expected.count) <= 1
        else { return false }
        return levenshtein(input, expected.lowercased()) <= 1
    }

    /// Returns true if char is a word-component (letter/digit/apostrophe).
    /// Apostrophes count so contractions ("don't") stay together.
    private static func isWordCharacter(_ c: Character) -> Bool {
        return c.isLetter || c.isNumber || c == "'"
    }

    /// Standard two-row Levenshtein. O(m·n), but n is at most ~30 (vocab
    /// term length) so cost is negligible vs. the URLSession round trip.
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a), bChars = Array(b)
        if aChars.isEmpty { return bChars.count }
        if bChars.isEmpty { return aChars.count }
        var prev = Array(0...bChars.count)
        var curr = Array(repeating: 0, count: bChars.count + 1)
        for i in 1...aChars.count {
            curr[0] = i
            for j in 1...bChars.count {
                let cost = aChars[i-1] == bChars[j-1] ? 0 : 1
                curr[j] = min(curr[j-1] + 1, prev[j] + 1, prev[j-1] + cost)
            }
            (prev, curr) = (curr, prev)
        }
        return prev[bChars.count]
    }
}
