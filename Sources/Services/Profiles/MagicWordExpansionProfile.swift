import Foundation

/// Deterministic expansion profile — hits the magic-word registry.
/// Zero LLM calls, zero cost, sub-millisecond latency.
///
/// **Match semantics**: prefix-only via `MagicWordResolver`. If the
/// transcript is "git wip 'fixing build'", we expand the prefix and
/// append the remainder. e.g.:
///   transcript: "git wip 'fixing build'"
///   matched:    "git wip" → "git add -A && git commit -m \"wip\" && git push"
///   final:      "git add -A && git commit -m \"wip\" && git push 'fixing build'"
///
/// Whether to append the remainder is debatable — for some entries the
/// remainder is noise. Currently we DO append (the user can edit the
/// expansion to ignore it). Future: a `acceptsRemainder` flag on the entry.
final class MagicWordExpansionProfile: TransformerProfile {
    let kind: ProfileKind = .magicWordExpansion
    let displayLabel = ProfileKind.magicWordExpansion.displayLabel

    let matchedEntry: MagicWord
    let remainder: String

    init(matchedEntry: MagicWord, remainder: String) {
        self.matchedEntry = matchedEntry
        self.remainder = remainder
    }

    func transform(
        _ input: TransformerInput,
        completion: @escaping (Result<TransformerOutput, Error>) -> Void
    ) {
        let final: String = {
            if remainder.isEmpty { return matchedEntry.expansion }
            return matchedEntry.expansion + " " + remainder
        }()

        let trace: [String] = [
            "Profile: magic word",
            "Matched: \"\(matchedEntry.phrase)\"",
            remainder.isEmpty ? "Remainder: (none)" : "Remainder: \"\(remainder)\"",
            "Expansion (\(matchedEntry.expansion.count) chars)",
        ]

        let output = TransformerOutput(
            finalText: final,
            summary: "Magic word: \(matchedEntry.phrase)",
            modelUsed: nil,
            costUSD: 0,
            llmLatencyMs: 0,
            usedAgentic: false,
            trace: trace
        )
        completion(.success(output))
    }
}
