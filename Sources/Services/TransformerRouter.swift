import Foundation
import AppKit

/// Picks the right TransformerProfile for a given transcript + context.
///
/// **Routing priorities** (first match wins):
/// 1. Hotkey identity — `.promptEngineer` always uses PromptEngineerProfile,
///    no matter what the transcript says.
/// 2. Trigger words — "vordi create" → DeveloperModeProfile,
///    "vordi prompt" → PromptEngineerProfile, etc.
/// 3. Magic word match — registry hit takes precedence over standard cleanup.
/// 4. System action phrases — "open Claude", "open Claude and type ..."
/// 5. Surface + dev-mode toggle — IDE/terminal users with dev mode ON get
///    VariableRecognitionProfile wrapped around StandardCleanupProfile.
/// 6. Fallback — StandardCleanupProfile.
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
        /// dictate "vordi create..." and nothing happens, which feels
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
            // a casual mention of "vordi create" in a Slack message to
        // hijack the transcript when the user hasn't opted in.
        if isDevModeEnabled {
            if TriggerWords.isDevCreate(transcript) {
                trace.append("Trigger: vordi create → DeveloperModeProfile (\(isAgenticModeEnabled ? "agentic" : "single-call"))")
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
                trace.append("Trigger: vordi prompt → PromptEngineerProfile")
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

            if let action = SystemActionResolver().resolve(transcript: transcript) {
                trace.append(action.traceSummary)
                return RouterDecision(
                    profile: SystemActionProfile(action: action),
                    trace: trace,
                    isInstantPath: true
                )
            }
        }

        // 5. Surface-based wrap — IDE + dev mode + var recog → wrap standard
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

        // 6. Fallback.
        trace.append("Fallback: StandardCleanupProfile")
        return RouterDecision(
            profile: standard,
            trace: trace,
            isInstantPath: false
        )
    }
}

// MARK: - System Actions

struct SystemAction {
    enum Destination {
        case application(URL)
        case vordiNotes
    }

    let requestedAppName: String
    let destination: Destination
    let appDisplayName: String
    let insertionText: String?

    var traceSummary: String {
        if let insertionText, !insertionText.isEmpty {
            return "System action: open \(appDisplayName) + paste \(insertionText.count) chars"
        }
        return "System action: open \(appDisplayName)"
    }

    var completionSummary: String {
        if let insertionText, !insertionText.isEmpty {
            return "Opened \(appDisplayName) and inserted text"
        }
        return "Opened \(appDisplayName)"
    }
}

final class SystemActionProfile: TransformerProfile {
    let kind: ProfileKind = .systemAction
    let displayLabel = ProfileKind.systemAction.displayLabel

    private let action: SystemAction
    private let executor: SystemActionExecutor

    init(action: SystemAction, executor: SystemActionExecutor = SystemActionExecutor()) {
        self.action = action
        self.executor = executor
    }

    func transform(
        _ input: TransformerInput,
        completion: @escaping (Result<TransformerOutput, Error>) -> Void
    ) {
        executor.execute(action) { result in
            switch result {
            case .success(let summary):
                completion(.success(TransformerOutput(
                    finalText: summary,
                    summary: summary,
                    modelUsed: nil,
                    costUSD: 0,
                    llmLatencyMs: 0,
                    usedAgentic: false,
                    trace: [
                        "Profile: system action",
                        "Requested app: \(self.action.requestedAppName)",
                        "Resolved app: \(self.action.appDisplayName)",
                        self.action.insertionText?.isEmpty == false
                            ? "Inserted text: yes"
                            : "Inserted text: no",
                    ],
                    shouldInject: false
                )))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

struct SystemActionResolver {
    private let parser = SystemActionPhraseParser()
    private let appResolver = InstalledApplicationResolver()

    func resolve(transcript: String) -> SystemAction? {
        guard let phrase = parser.parse(transcript) else { return nil }
        if Self.isVordiNotesCommand(phrase.appName) {
            return SystemAction(
                requestedAppName: phrase.appName,
                destination: .vordiNotes,
                appDisplayName: "\(AppBrand.name) Notes",
                insertionText: phrase.insertionText
            )
        }
        guard let app = appResolver.resolve(spokenName: phrase.appName) else { return nil }
        return SystemAction(
            requestedAppName: phrase.appName,
            destination: .application(app.url),
            appDisplayName: app.displayName,
            insertionText: phrase.insertionText
        )
    }

    private static func isVordiNotesCommand(_ appName: String) -> Bool {
        let normalized = InstalledApplicationResolver.normalizeName(appName)
        return [
            "vordi notes",
            "vordi note",
            "vordi notes",
            "vordi note"
        ].contains(normalized)
    }
}

private struct ParsedSystemAction {
    let appName: String
    let insertionText: String?
}

private struct SystemActionPhraseParser {
    private let launchPrefixes = ["open ", "launch ", "start "]
    private let insertionSeparators = [
        " and type ",
        " and paste ",
        " and write ",
        " and enter ",
        " and ask ",
        ", type ",
        ", paste ",
        ", write ",
        ", enter ",
        ", ask ",
    ]

    func parse(_ transcript: String) -> ParsedSystemAction? {
        let trimmed = Self.trimEdges(transcript)
        guard !trimmed.isEmpty else { return nil }

        let lowercased = trimmed.lowercased()
        let command: String
        if let prefix = launchPrefixes.first(where: { lowercased.hasPrefix($0) }) {
            command = String(trimmed.dropFirst(prefix.count))
        } else if let glued = gluedCommand(from: trimmed) {
            command = glued
        } else {
            return nil
        }
        guard !command.isEmpty else { return nil }

        let parts = splitCommand(command)
        let appName = cleanAppName(parts.app)
        guard appName.count >= 2, appName.count <= 60 else { return nil }

        let insertionText = parts.insertion.map(Self.trimEdges).flatMap {
            $0.isEmpty ? nil : $0
        }

        return ParsedSystemAction(appName: appName, insertionText: insertionText)
    }

    /// Whisper frequently glues the launch verb onto the app name as one
    /// CamelCase token — production run-logs show "OpenVordi", "OpenClaude",
    /// "OpenChrome" — very likely because the vocabulary prompt's "OpenAI"
    /// teaches the decoder that Open+Word compounds are a valid style
    /// ("launch" has no such compound in the vocab and never glues). The
    /// glued form made "open <app>" silently fall through to normal cleanup
    /// while "launch <app>" kept working.
    ///
    /// Detection is deliberately conservative: the verb must be immediately
    /// followed by an UPPERCASE letter (a CamelCase boundary). Lowercase
    /// continuations ("opening", "openness", "started") can never match. A
    /// false split like "OpenNodes" is harmless — the remainder only becomes
    /// an action if it resolves to an actually-installed app; otherwise the
    /// transcript flows through cleanup untouched.
    private func gluedCommand(from trimmed: String) -> String? {
        // Real Open-compound words that must never be split. "OpenAI" alone
        // would otherwise yield the query "ai", which can fuzzy-match
        // AI-suffixed app names and launch something the user never asked for.
        let firstToken = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .first.map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) } ?? ""
        if Self.gluedStoplist.contains(firstToken) { return nil }

        let lowercased = trimmed.lowercased()
        for prefix in launchPrefixes {
            let verb = prefix.dropLast() // "open " → "open"
            guard lowercased.hasPrefix(verb) else { continue }
            let rest = trimmed.dropFirst(verb.count)
            guard let first = rest.first, first.isUppercase else { continue }
            return String(rest)
        }
        return nil
    }

    /// Legitimate glued compounds that start with a launch verb. Never split.
    private static let gluedStoplist: Set<String> = [
        "openai", "openoffice", "opengl", "openvpn", "opensource",
        "startup", "startups",
    ]

    private func splitCommand(_ command: String) -> (app: String, insertion: String?) {
        for separator in insertionSeparators {
            if let range = command.range(of: separator, options: [.caseInsensitive]) {
                let app = String(command[..<range.lowerBound])
                let insertion = String(command[range.upperBound...])
                return (app, insertion)
            }
        }
        return (command, nil)
    }

    private func cleanAppName(_ raw: String) -> String {
        var value = Self.trimEdges(raw)
        value = Self.stripPrefix("the ", from: value)
        value = Self.stripSuffix(" app", from: value)
        value = Self.stripSuffix(" application", from: value)
        value = Self.stripSuffix(" desktop", from: value)
        return Self.trimEdges(value)
    }

    private static func stripPrefix(_ prefix: String, from value: String) -> String {
        let lowercased = value.lowercased()
        guard lowercased.hasPrefix(prefix) else { return value }
        return String(value.dropFirst(prefix.count))
    }

    private static func stripSuffix(_ suffix: String, from value: String) -> String {
        let lowercased = value.lowercased()
        guard lowercased.hasSuffix(suffix) else { return value }
        return String(value.dropLast(suffix.count))
    }

    private static func trimEdges(_ value: String) -> String {
        var trimSet = CharacterSet.whitespacesAndNewlines
        trimSet.insert(charactersIn: "\"'.,:;!?")
        return value.trimmingCharacters(in: trimSet)
    }
}

private struct ResolvedApplication {
    let url: URL
    let displayName: String
}

private struct InstalledApplication {
    let url: URL
    let displayName: String
    let normalizedName: String
}

private struct InstalledApplicationResolver {
    private static var cachedApps: [InstalledApplication]?

    private let nameAliases: [String: [String]] = [
        "claude": ["Claude", "Claude Desktop"],
        "cloud": ["Claude", "Claude Desktop"],
        "codex": ["Codex"],
        "chat gpt": ["ChatGPT"],
        "chatgpt": ["ChatGPT"],
        "chrome": ["Google Chrome"],
        "google chrome": ["Google Chrome"],
        "cursor": ["Cursor"],
        "vs code": ["Visual Studio Code"],
        "vscode": ["Visual Studio Code"],
        // Whisper mishearing of "VS Code" observed repeatedly in run-logs
        // ("OpenBS Code"). No real app is named "BS Code", so aliasing is safe.
        "bs code": ["Visual Studio Code"],
        "visual studio code": ["Visual Studio Code"],
        "terminal": ["Terminal"],
        "iterm": ["iTerm", "iTerm2"],
        "notes": ["Notes"],
        "slack": ["Slack"],
    ]

    private let bundleAliases: [String: [String]] = [
        "safari": ["com.apple.Safari"],
        "terminal": ["com.apple.Terminal"],
        "notes": ["com.apple.Notes"],
        "claude": ["com.anthropic.claude", "com.anthropic.claudefordesktop"],
        "cloud": ["com.anthropic.claude", "com.anthropic.claudefordesktop"],
        "chatgpt": ["com.openai.chat"],
        "chat gpt": ["com.openai.chat"],
        "cursor": ["com.todesktop.230313mzl4w4u92"],
        "visual studio code": ["com.microsoft.VSCode"],
        "vs code": ["com.microsoft.VSCode"],
        "vscode": ["com.microsoft.VSCode"],
        "bs code": ["com.microsoft.VSCode"],
        "chrome": ["com.google.Chrome"],
        "google chrome": ["com.google.Chrome"],
        "slack": ["com.tinyspeck.slackmacgap"],
    ]

    func resolve(spokenName: String) -> ResolvedApplication? {
        let query = Self.normalizeName(spokenName)
        guard query.count >= 2 else { return nil }

        if let app = resolveBundleAlias(query: query) {
            return app
        }

        for candidateName in candidateNames(for: spokenName, normalized: query) {
            if let app = resolveLaunchServicesName(candidateName) {
                return app
            }
        }

        return resolveInstalledApp(query: query, aliases: candidateNames(for: spokenName, normalized: query))
    }

    private func resolveBundleAlias(query: String) -> ResolvedApplication? {
        guard let bundleIDs = bundleAliases[query] else { return nil }
        for bundleID in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                return ResolvedApplication(url: url, displayName: Self.displayName(for: url))
            }
        }
        return nil
    }

    private func resolveLaunchServicesName(_ name: String) -> ResolvedApplication? {
        guard let path = NSWorkspace.shared.fullPath(forApplication: name) else { return nil }
        let url = URL(fileURLWithPath: path)
        return ResolvedApplication(url: url, displayName: Self.displayName(for: url))
    }

    private func resolveInstalledApp(query: String, aliases: [String]) -> ResolvedApplication? {
        let normalizedQueries = ([query] + aliases.map(Self.normalizeName))
            .filter { $0.count >= 2 }

        let matches = Self.installedApps().compactMap { app -> (app: InstalledApplication, score: Int)? in
            let matchScore = normalizedQueries.map { scoreApp(app, query: $0) }.max() ?? 0
            return matchScore >= 80 ? (app, matchScore) : nil
        }

        guard let best = matches.sorted(by: sortMatches).first?.app else { return nil }
        return ResolvedApplication(url: best.url, displayName: best.displayName)
    }

    private func candidateNames(for spokenName: String, normalized: String) -> [String] {
        var names = [spokenName]
        names.append(contentsOf: nameAliases[normalized] ?? [])
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }

    private func scoreApp(_ app: InstalledApplication, query: String) -> Int {
        let name = app.normalizedName
        guard query.count >= 2, name.count >= 2 else { return 0 }

        if name == query { return 100 }
        if name.hasPrefix(query + " ") { return 90 }
        if name.hasSuffix(" " + query) { return 88 }
        if query.hasPrefix(name + " "), name.count >= 4 { return 84 }

        let queryTokens = Set(query.split(separator: " ").map(String.init))
        let nameTokens = Set(name.split(separator: " ").map(String.init))
        if !queryTokens.isEmpty, queryTokens.isSubset(of: nameTokens) { return 82 }

        if query.count >= 4, name.contains(query) { return 80 }
        return 0
    }

    private func sortMatches(
        _ lhs: (app: InstalledApplication, score: Int),
        _ rhs: (app: InstalledApplication, score: Int)
    ) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }

        let lhsPreferred = lhs.app.url.path.hasPrefix("/Applications/")
        let rhsPreferred = rhs.app.url.path.hasPrefix("/Applications/")
        if lhsPreferred != rhsPreferred { return lhsPreferred }

        return lhs.app.displayName.count < rhs.app.displayName.count
    }

    private static func installedApps() -> [InstalledApplication] {
        if let cachedApps { return cachedApps }

        let fileManager = FileManager.default
        let roots = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
        ]

        var apps: [InstalledApplication] = []
        for root in roots {
            let rootURL = URL(fileURLWithPath: root, isDirectory: true)
            guard fileManager.fileExists(atPath: rootURL.path) else { continue }

            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "app" else { continue }
                let displayName = displayName(for: url)
                apps.append(InstalledApplication(
                    url: url,
                    displayName: displayName,
                    normalizedName: normalizeName(displayName)
                ))
            }
        }

        cachedApps = apps
        return apps
    }

    private static func displayName(for url: URL) -> String {
        if let bundle = Bundle(url: url) {
            if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
               !display.isEmpty {
                return display
            }
            if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
               !name.isEmpty {
                return name
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    fileprivate static func normalizeName(_ value: String) -> String {
        let lowercased = value.lowercased()
        let scalars = lowercased.unicodeScalars.map { scalar -> UnicodeScalar in
            CharacterSet.alphanumerics.contains(scalar) ? scalar : UnicodeScalar(" ")
        }
        let collapsed = String(String.UnicodeScalarView(scalars))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return ["application", "desktop", "app"].reduce(collapsed) { current, suffix in
            current.hasSuffix(" " + suffix)
                ? String(current.dropLast(suffix.count + 1))
                : current
        }
    }
}

private enum SystemActionError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message):
            return message
        }
    }
}

final class SystemActionExecutor {
    func execute(_ action: SystemAction, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.main.async {
            if case .vordiNotes = action.destination {
                var userInfo: [String: String] = [:]
                if let insertionText = action.insertionText,
                   !insertionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    userInfo["text"] = insertionText
                }
                NotificationCenter.default.post(
                    name: Notification.Name("Vordi.OpenFloatingNotes"),
                    object: nil,
                    userInfo: userInfo
                )
                completion(.success(action.completionSummary))
                return
            }

            guard case .application(let appURL) = action.destination else {
                completion(.failure(SystemActionError.launchFailed("Unsupported system action")))
                return
            }

            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true

            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { runningApp, error in
                DispatchQueue.main.async {
                    if let error {
                        completion(.failure(SystemActionError.launchFailed(error.localizedDescription)))
                        return
                    }

                    runningApp?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

                    guard let insertionText = action.insertionText,
                          !insertionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        completion(.success(action.completionSummary))
                        return
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                        runningApp?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                        TextInjector.pasteTextIntoFrontmostApp(insertionText)
                        completion(.success(action.completionSummary))
                    }
                }
            }
        }
    }
}
