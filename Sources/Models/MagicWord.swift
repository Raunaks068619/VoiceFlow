import Foundation

/// A single phrase → expansion mapping. Stored as JSON in
/// `~/Library/Application Support/VoiceFlow/magicwords.json`.
///
/// **Mental model**: like TextExpander snippets, but voice-triggered.
/// User says "get pods recommendation" → gets `kubectl get pods -n zenith ...`
/// pasted into their editor.
///
/// **Match semantics**: prefix-only (the transcript must START with the phrase).
/// Substring matching was rejected as too false-positive-prone — saying
/// "get pods recommendation" inside a sentence shouldn't trigger expansion.
struct MagicWord: Codable, Identifiable, Hashable {
    let id: UUID
    /// What the user says. Lowercased + whitespace-collapsed at match time.
    /// Stored as the user typed it for editing UX.
    var phrase: String
    /// What gets injected. Newlines preserved verbatim.
    var expansion: String
    /// Optional category tag for organizing the registry UI.
    /// e.g. "k8s", "git", "sql".
    var tag: String?
    /// Optional surface scope — when set, this magic word ONLY fires in
    /// matching surfaces. Lets the user define different "wip" expansions
    /// for terminal vs. notes apps.
    var surfaceScope: AppSurface?
    /// Whether the entry is enabled. Disabled entries stay in the registry
    /// for editing but are skipped at match time.
    var enabled: Bool
    /// Last edit time — used by the UI for sort & "recently added" sections.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        phrase: String,
        expansion: String,
        tag: String? = nil,
        surfaceScope: AppSurface? = nil,
        enabled: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.phrase = phrase
        self.expansion = expansion
        self.tag = tag
        self.surfaceScope = surfaceScope
        self.enabled = enabled
        self.updatedAt = updatedAt
    }

    /// Normalized phrase for matching: lowercased, whitespace-collapsed,
    /// punctuation-stripped. Cached on each match call rather than stored
    /// because the registry is small (<100 entries) and editing complicates
    /// the cache.
    var normalizedPhrase: String {
        Self.normalize(phrase)
    }

    static func normalize(_ s: String) -> String {
        let lowered = s.lowercased()
        let collapsed = lowered.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let stripped = collapsed.unicodeScalars.filter { scalar in
            CharacterSet.letters.contains(scalar)
                || CharacterSet.decimalDigits.contains(scalar)
                || scalar == " "
                || scalar == "-"
                || scalar == "_"
        }
        return String(String.UnicodeScalarView(stripped))
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Result of a magic-word match attempt. Returned by MagicWordResolver.
enum MagicWordMatch {
    /// No match. Pipeline continues with normal profile.
    case none
    /// Exact match — full transcript IS the trigger phrase.
    /// Replace transcript with expansion.
    case exact(MagicWord)
    /// Prefix match with trailing content — the trailing content is
    /// preserved as a "remainder" the profile can use however it wants.
    /// e.g. "git wip 'fixing build'" → expansion "git add -A && git commit -m"
    /// + remainder "'fixing build'". Currently we just append the remainder
    /// to the expansion, but the data is kept separately for future use.
    case prefix(MagicWord, remainder: String)
}
