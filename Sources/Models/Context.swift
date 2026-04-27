import Foundation

/// Snapshot of "what the user was doing" at the moment they pressed the
/// hotkey. Captured EAGERLY at press-time — never lazily at result-time —
/// because by the time STT + LLM finish (1–4s), the user may have
/// alt-tabbed, lost selection, or quit the source app.
///
/// Treat instances as immutable. `ContextProvider.snapshot()` is the only
/// blessed factory.
struct ContextSnapshot: Codable {
    /// Bundle ID of the frontmost app at hotkey-press time.
    /// e.g. "com.todesktop.230313mzl4w4u92" (Cursor), "com.apple.dt.Xcode".
    let frontmostBundleID: String?

    /// Human-readable name for log/UI display. e.g. "Cursor", "Xcode".
    let frontmostAppName: String?

    /// Inferred surface category — drives profile defaults & UI hints.
    /// "I'm in an IDE" enables variable-recognition; "I'm in a chat" doesn't.
    let surface: AppSurface

    /// Selected text at hotkey-press time. Empty string when nothing was
    /// selected OR when capture failed (caller can't tell the difference;
    /// see `selectionSource` to disambiguate).
    let selection: String

    /// How we got the selection — drives confidence + telemetry.
    let selectionSource: SelectionSource

    /// Hotkey identifier — lets profiles & router treat the secondary
    /// hotkey (Opt+2 → PromptEngineer) differently from the primary.
    let hotkey: HotkeyIdentifier

    /// When the snapshot was taken — used for staleness checks (e.g. if the
    /// pipeline took 30s, the selection is probably no longer the user's
    /// current intent).
    let capturedAt: Date

    /// True when we have meaningful contextual info. Used by router to
    /// decide whether to take the "context-aware" branch vs. plain dictation.
    var hasUsefulContext: Bool {
        !selection.isEmpty || surface != .unknown
    }
}

/// High-level app category. Coarse on purpose — fine-grained "exactly which
/// IDE" detection lives in `IDEDetector` (extension below).
///
/// Priority of detection: bundleID exact match → bundleID prefix → fallback.
enum AppSurface: String, Codable {
    case ide              // VS Code, Cursor, Windsurf, Xcode, JetBrains
    case terminal         // iTerm2, Terminal.app, Warp
    case chat             // Slack, Discord, iMessage
    case browser          // Chrome, Safari, Arc, Firefox
    case mail             // Mail.app, Spark, Superhuman
    case notes            // Notes.app, Obsidian, Bear
    case office           // Word, Excel, Pages
    case database         // TablePlus, Postico, BigQuery (web — see browser fallback)
    case design           // Figma desktop, Sketch
    case unknown
}

/// Where the selection came from — affects how much we trust it.
enum SelectionSource: String, Codable {
    case ax              // AXUIElementCopyAttributeValue → kAXSelectedTextAttribute
    case clipboard       // Cmd+C round-trip fallback
    case none            // No selection captured (or feature disabled)
    case failed          // Tried, both paths failed (AX denied, clipboard timed out)
}

/// Distinguishes which keybind fired the dictation. Used by the router to
/// pick a profile when the user has multiple hotkeys configured.
enum HotkeyIdentifier: String, Codable {
    case primary         // Fn (default)
    case promptEngineer  // Opt+2 (Phase 3)
    case devCreate       // Reserved — explicit dev-mode-only key
    case unknown
}

// MARK: - IDE / Surface mapping

/// Static bundle-ID → surface map. Kept as a plain dict so we can extend
/// without recompiling, and so the table is greppable when a user reports
/// "VoiceFlow doesn't detect Zed."
enum AppSurfaceCatalog {
    /// Exact bundle-ID matches. Highest priority.
    static let exact: [String: AppSurface] = [
        // IDEs
        "com.microsoft.VSCode":                          .ide,
        "com.microsoft.VSCodeInsiders":                  .ide,
        "com.todesktop.230313mzl4w4u92":                 .ide,   // Cursor
        "com.exafunction.windsurf":                      .ide,   // Windsurf
        "com.zed.Zed":                                   .ide,
        "com.zed.Zed-Preview":                           .ide,
        "com.apple.dt.Xcode":                            .ide,
        "com.sublimetext.4":                             .ide,
        "com.sublimetext.3":                             .ide,
        "com.panic.Nova":                                .ide,
        // JetBrains family — covered by prefix below, but pinning common ones
        "com.jetbrains.intellij":                        .ide,
        "com.jetbrains.WebStorm":                        .ide,
        "com.jetbrains.PyCharm":                         .ide,
        "com.jetbrains.GoLand":                          .ide,
        "com.jetbrains.RubyMine":                        .ide,
        "com.jetbrains.AppCode":                         .ide,

        // Terminals
        "com.googlecode.iterm2":                         .terminal,
        "com.apple.Terminal":                            .terminal,
        "dev.warp.Warp-Stable":                          .terminal,
        "co.zeit.hyper":                                 .terminal,
        "io.alacritty":                                  .terminal,
        "net.kovidgoyal.kitty":                          .terminal,

        // Chat / messaging
        "com.tinyspeck.slackmacgap":                     .chat,
        "com.hnc.Discord":                               .chat,
        "com.apple.MobileSMS":                           .chat,   // iMessage
        "com.microsoft.teams2":                          .chat,
        "com.linear":                                    .chat,
        "company.thebrowser.Browser":                    .browser, // Arc
        "us.zoom.xos":                                   .chat,

        // Browsers
        "com.google.Chrome":                             .browser,
        "com.google.Chrome.canary":                      .browser,
        "org.mozilla.firefox":                           .browser,
        "com.apple.Safari":                              .browser,
        "com.brave.Browser":                             .browser,
        "com.microsoft.edgemac":                         .browser,

        // Mail
        "com.apple.mail":                                .mail,
        "com.readdle.smartemail-Mac":                    .mail,
        "com.superhuman.electron":                       .mail,

        // Notes
        "com.apple.Notes":                               .notes,
        "md.obsidian":                                   .notes,
        "net.shinyfrog.bear":                            .notes,
        "notion.id":                                     .notes,
        "com.craft.craft":                               .notes,

        // Office
        "com.microsoft.Word":                            .office,
        "com.microsoft.Excel":                           .office,
        "com.apple.iWork.Pages":                         .office,
        "com.apple.iWork.Numbers":                       .office,

        // Design
        "com.figma.Desktop":                             .design,
        "com.bohemiancoding.sketch3":                    .design,

        // Database
        "com.tinyapp.TablePlus":                         .database,
        "se.juvet.Postico":                              .database,
    ]

    /// Bundle-ID prefix matches. Lower priority than exact.
    static let prefix: [(String, AppSurface)] = [
        ("com.jetbrains.",   .ide),     // catches every JetBrains IDE
        ("com.todesktop.",   .ide),     // todesktop-built IDEs (Cursor lineage)
        ("com.microsoft.VSCode", .ide), // insider variants
    ]

    static func surface(for bundleID: String?) -> AppSurface {
        guard let id = bundleID else { return .unknown }
        if let exact = exact[id] { return exact }
        for (p, surface) in prefix where id.hasPrefix(p) {
            return surface
        }
        return .unknown
    }

    /// True when this surface routinely takes code/SQL/scripts as input —
    /// the audience for "voiceflow create" dev-mode features.
    static func isDeveloperSurface(_ surface: AppSurface) -> Bool {
        switch surface {
        case .ide, .terminal, .database: return true
        case .browser, .chat, .notes, .mail, .office, .design, .unknown: return false
        }
    }
}
