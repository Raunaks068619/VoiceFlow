import AppKit
import Foundation

/// Turns a hands-free utterance into an executed action when it is *addressed to
/// Verba* via a wake phrase ("Verba, open Claude").
///
/// In hands-free mode every utterance is normally typed as dictation — there is
/// no key-release to say "stop, act on this." The wake phrase is what
/// disambiguates **"type these words"** from **"do this thing"**: only utterances
/// whose first word is the wake token are treated as commands; everything else
/// falls straight through to dictation, untouched.
///
/// v1 scope (matches the shipped decision): launch or focus a macOS app. The
/// parser is deliberately forgiving because it runs on STT output — the wake word
/// and app name both arrive as best-effort transcription, so we match a small set
/// of near-homophones and alias common app names rather than demanding exact hits.
///
/// The app is unsandboxed (see `Vordi.entitlements` — no `app-sandbox` key), so
/// launching another app via `/usr/bin/open` needs no special entitlement and
/// triggers no automation-permission prompt (we launch, we don't script).
enum VoiceCommandRouter {

    /// What happened when we looked at an utterance.
    enum Outcome: Equatable {
        /// Not addressed to Verba — the caller should type it as normal dictation.
        case notACommand
        /// A command ran; `confirmation` is a short human phrase ("Opening Claude").
        case executed(confirmation: String)
        /// It *was* a command but could not be carried out (e.g. app not found).
        case failed(reason: String)
    }

    /// A parsed, executable command. Kept separate from `Outcome` so parsing is
    /// unit-testable without launching anything.
    enum Command: Equatable {
        case launchApp(name: String)
    }

    // First-word tokens we accept as the wake word. Brand is "Vordi" (rebranding
    // to "Verba"); STT mangles both, so we accept a spread of common mishears.
    private static let wakeTokens: Set<String> = [
        "verba", "verbah", "verber", "verva", "verba's", "herba", "verb",
        "vordi", "vordy", "wordy", "vardi", "hordi", "vordie"
    ]

    // Optional politeness/attention words that may precede or follow the wake word.
    private static let leadingFillers: Set<String> = ["hey", "ok", "okay", "yo"]
    private static let postWakeFillers: Set<String> = ["please", "can", "you", "could"]

    // Verbs that all mean "bring this app up" for v1.
    private static let launchVerbs: Set<String> = [
        "open", "launch", "start", "run", "focus", "switch", "goto", "show", "bring"
    ]

    /// Common spoken names → the actual macOS app name `open -a` expects. Anything
    /// not listed is passed through and resolved by LaunchServices' own fuzzy match.
    private static let appAliases: [String: String] = [
        "claude": "Claude",
        "claude code": "Claude",
        "chrome": "Google Chrome",
        "google chrome": "Google Chrome",
        "code": "Visual Studio Code",
        "vs code": "Visual Studio Code",
        "vscode": "Visual Studio Code",
        "visual studio code": "Visual Studio Code",
        "cursor": "Cursor",
        "safari": "Safari",
        "terminal": "Terminal",
        "iterm": "iTerm",
        "slack": "Slack",
        "spotify": "Spotify",
        "notes": "Notes",
        "finder": "Finder",
        "xcode": "Xcode",
        "notion": "Notion",
        "figma": "Figma",
        "messages": "Messages",
        "imessage": "Messages",
        "mail": "Mail",
        "whatsapp": "WhatsApp",
        "settings": "System Settings",
        "system settings": "System Settings",
        "system preferences": "System Settings"
    ]

    /// Look at a transcript and, if it is a wake-phrase command, run it.
    static func interpret(_ transcript: String) -> Outcome {
        guard let command = parse(transcript) else { return .notACommand }
        switch command {
        case .launchApp(let name):
            if let confirmation = launchApp(named: name) {
                return .executed(confirmation: confirmation)
            }
            return .failed(reason: "Couldn't find an app called \"\(name)\"")
        }
    }

    /// Parse a transcript into a command, or nil when it isn't addressed to Verba.
    /// Pure + side-effect-free so it can be tested directly.
    static func parse(_ transcript: String) -> Command? {
        // Normalize: lowercase, punctuation → spaces, collapse to tokens.
        var tokens = transcript
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9' ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map(String.init)
        guard !tokens.isEmpty else { return nil }

        // Optional "hey"/"ok" before the wake word.
        if let first = tokens.first, leadingFillers.contains(first) {
            tokens.removeFirst()
        }

        // 1. Wake word must lead.
        guard let head = tokens.first, wakeTokens.contains(head) else { return nil }
        tokens.removeFirst()

        // Optional "please / can you" after the wake word.
        while let next = tokens.first, postWakeFillers.contains(next) {
            tokens.removeFirst()
        }
        guard !tokens.isEmpty else { return nil }

        // 2. A launch verb.
        var verb = tokens.removeFirst()
        if verb == "go" { verb = "goto" }
        guard launchVerbs.contains(verb) else { return nil }
        // Drop a trailing "to"/"up" from "switch to", "go to", "bring up".
        while let next = tokens.first, next == "to" || next == "up" {
            tokens.removeFirst()
        }

        // 3. The remainder is the app name.
        let appName = tokens.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !appName.isEmpty else { return nil }
        return .launchApp(name: appName)
    }

    /// Launch or focus an app by spoken name. Returns a confirmation phrase on
    /// success, nil if LaunchServices couldn't resolve it.
    private static func launchApp(named spoken: String) -> String? {
        let key = spoken.lowercased().trimmingCharacters(in: .whitespaces)
        let target = appAliases[key] ?? spoken

        // `open -a` focuses the app if it's already running, launches it if not,
        // and exits non-zero when no matching app exists. Fast — it hands the
        // launch request to LaunchServices and returns, it doesn't wait for the
        // app to finish launching.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        proc.arguments = ["-a", target]
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0 ? "Opening \(target)" : nil
        } catch {
            return nil
        }
    }
}
