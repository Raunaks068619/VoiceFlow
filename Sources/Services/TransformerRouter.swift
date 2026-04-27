import Foundation

/// Picks the right TransformerProfile for a given transcript + context.
///
/// **Routing priorities** (first match wins):
/// 1. Hotkey identity — `.promptEngineer` always uses PromptEngineerProfile,
///    no matter what the transcript says.
/// 2. Trigger words — "voiceflow create" → DeveloperModeProfile,
///    "voiceflow prompt" → PromptEngineerProfile, etc.
/// 3. Magic word match — registry hit takes precedence over standard cleanup.
/// 4. Surface + dev-mode toggle — IDE/terminal users with dev mode ON get
///    VariableRecognitionProfile wrapped around StandardCleanupProfile.
/// 5. Fallback — StandardCleanupProfile.
///
/// **Why deterministic over LLM-driven**: the routing decision affects
/// EVERY dictation. We can't afford a 200ms classifier API call to decide
/// "is this a magic word?". The deterministic precedence is dense but
/// predictable — bias toward false-cleanup over false-trigger so users
/// never lose a dictation to an over-eager profile match.
struct RouterDecision {
    let profile: TransformerProfile
    let trace: [String]
    /// Whether the resolved profile changed the transcript before STT
    /// completed (e.g. magic word resolved with the trigger phrase only —
    /// no LLM call needed). Lets the chip skip the "polishing" overlay
    /// frame for instant feedback.
    let isInstantPath: Bool
}

final class TransformerRouter {
    private let whisper: WhisperService
    private let llm: LLMService
    private let magicWordStore: MagicWordStore

    init(
        whisper: WhisperService,
        llm: LLMService = .shared,
        magicWordStore: MagicWordStore = .shared
    ) {
        self.whisper = whisper
        self.llm = llm
        self.magicWordStore = magicWordStore
    }

    // MARK: - User defaults keys

    enum Keys {
        /// Master toggle for Dev Mode features (triggers, var recognition,
        /// file tagging). Default ON — the user explicitly opted in by
        /// installing/enabling these features; OFF-by-default means they
        /// dictate "voiceflow create…" and nothing happens, which feels
        /// broken.
        static let devModeEnabled = "dev_mode_enabled"
        /// Whether magic-word matching runs. Default ON; no-op when the
        /// registry is empty anyway.
        static let magicWordsEnabled = "magic_words_enabled"
        /// Whether variable recognition runs in IDE surfaces. Subset of
        /// devMode — set independently for users who want triggers without
        /// auto var-style.
        static let variableRecognitionEnabled = "variable_recognition_enabled"
        /// Whether agentic mode replaces single-call dev mode (Phase 4 A/B).
        /// Default OFF — single-call is the proven path; agentic is the
        /// experiment.
        static let agenticModeEnabled = "agentic_mode_enabled"
    }

    var isDevModeEnabled: Bool {
        if UserDefaults.standard.object(forKey: Keys.devModeEnabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Keys.devModeEnabled)
    }

    var isMagicWordsEnabled: Bool {
        if UserDefaults.standard.object(forKey: Keys.magicWordsEnabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Keys.magicWordsEnabled)
    }

    var isVariableRecognitionEnabled: Bool {
        if UserDefaults.standard.object(forKey: Keys.variableRecognitionEnabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Keys.variableRecognitionEnabled)
    }

    var isAgenticModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.agenticModeEnabled)
    }

    // MARK: - Routing

    /// Decide which profile handles this transcript+context. The router
    /// is a pure function of input — easy to unit test, easy to reason
    /// about. NO side effects (no logging that affects state, no UI calls).
    func route(transcript: String, context: ContextSnapshot) -> RouterDecision {
        var trace: [String] = []

        // 1. Hotkey identity — secondary hotkey forces its profile.
        switch context.hotkey {
        case .promptEngineer:
            trace.append("Hotkey: prompt_engineer → PromptEngineerProfile")
            return RouterDecision(
                profile: PromptEngineerProfile(llm: llm),
                trace: trace,
                isInstantPath: false
            )
        case .devCreate:
            trace.append("Hotkey: dev_create → DeveloperModeProfile")
            return RouterDecision(
                profile: DeveloperModeProfile(llm: llm),
                trace: trace,
                isInstantPath: false
            )
        case .primary, .unknown:
            break
        }

        // 2. Trigger words. Only when dev mode is enabled — we don't want
        // a casual mention of "voiceflow create" in a Slack message to
        // hijack the transcript when the user hasn't opted in.
        if isDevModeEnabled {
            if TriggerWords.isDevCreate(transcript) {
                trace.append("Trigger: voiceflow create → DeveloperModeProfile (\(isAgenticModeEnabled ? "agentic" : "single-call"))")
                if isAgenticModeEnabled {
                    return RouterDecision(
                        profile: AgenticDeveloperModeProfile(llm: llm),
                        trace: trace,
                        isInstantPath: false
                    )
                }
                return RouterDecision(
                    profile: DeveloperModeProfile(llm: llm),
                    trace: trace,
                    isInstantPath: false
                )
            }
            if TriggerWords.isPromptEngineer(transcript) {
                trace.append("Trigger: voiceflow prompt → PromptEngineerProfile")
                return RouterDecision(
                    profile: PromptEngineerProfile(llm: llm),
                    trace: trace,
                    isInstantPath: false
                )
            }
        }

        // 3. Magic word lookup — instant path when matched.
        if isMagicWordsEnabled {
            let entries = magicWordStore.snapshot()
            if !entries.isEmpty {
                let resolver = MagicWordResolver(entries: entries)
                let match = resolver.resolve(transcript: transcript, surface: context.surface)
                switch match {
                case .exact(let entry):
                    trace.append("Magic word exact: \"\(entry.phrase)\"")
                    return RouterDecision(
                        profile: MagicWordExpansionProfile(matchedEntry: entry, remainder: ""),
                        trace: trace,
                        isInstantPath: true
                    )
                case .prefix(let entry, let remainder):
                    trace.append("Magic word prefix: \"\(entry.phrase)\" + \"\(remainder.prefix(40))\"")
                    return RouterDecision(
                        profile: MagicWordExpansionProfile(matchedEntry: entry, remainder: remainder),
                        trace: trace,
                        isInstantPath: true
                    )
                case .none:
                    trace.append("Magic word: no match")
                }
            }
        }

        // 4. Surface-based wrap — IDE + dev mode + var recog → wrap standard
        // cleanup with VariableRecognitionProfile.
        let standard = StandardCleanupProfile(whisper: whisper)
        if isDevModeEnabled
            && isVariableRecognitionEnabled
            && AppSurfaceCatalog.isDeveloperSurface(context.surface) {
            trace.append("Surface: \(context.surface.rawValue) → wrap standard with VariableRecognitionProfile")
            return RouterDecision(
                profile: VariableRecognitionProfile(inner: standard, llm: llm),
                trace: trace,
                isInstantPath: false
            )
        }

        // 5. Fallback.
        trace.append("Fallback: StandardCleanupProfile")
        return RouterDecision(
            profile: standard,
            trace: trace,
            isInstantPath: false
        )
    }
}
