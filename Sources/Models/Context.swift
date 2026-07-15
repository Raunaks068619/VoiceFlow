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

    /// Best-effort active-window title from CoreGraphics. Nil when the app
    /// does not expose one or Screen Recording is not granted.
    let windowTitle: String?

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

    /// Optional screenshot of the active window at hotkey-press time. The
    /// binary image data is transient: it is written to `context.jpg` by
    /// RunStore and intentionally omitted from `run.json`.
    let screenshot: ContextScreenshot?

    /// Optional LLM-generated page/window summary derived from screenshot +
    /// metadata. Used only as spelling/casing context for post-processing.
    let summary: ContextSummary?

    /// True when we have meaningful contextual info. Used by router to
    /// decide whether to take the "context-aware" branch vs. plain dictation.
    var hasUsefulContext: Bool {
        !selection.isEmpty || surface != .unknown || summary != nil || screenshot?.status == .captured
    }

    init(
        frontmostBundleID: String?,
        frontmostAppName: String?,
        windowTitle: String? = nil,
        surface: AppSurface,
        selection: String,
        selectionSource: SelectionSource,
        hotkey: HotkeyIdentifier,
        capturedAt: Date,
        screenshot: ContextScreenshot? = nil,
        summary: ContextSummary? = nil
    ) {
        self.frontmostBundleID = frontmostBundleID
        self.frontmostAppName = frontmostAppName
        self.windowTitle = windowTitle
        self.surface = surface
        self.selection = selection
        self.selectionSource = selectionSource
        self.hotkey = hotkey
        self.capturedAt = capturedAt
        self.screenshot = screenshot
        self.summary = summary
    }

    enum CodingKeys: String, CodingKey {
        case frontmostBundleID, frontmostAppName, windowTitle, surface
        case selection, selectionSource, hotkey, capturedAt
        case screenshot, summary
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.frontmostBundleID = try c.decodeIfPresent(String.self, forKey: .frontmostBundleID)
        self.frontmostAppName = try c.decodeIfPresent(String.self, forKey: .frontmostAppName)
        self.windowTitle = try c.decodeIfPresent(String.self, forKey: .windowTitle)
        self.surface = try c.decodeIfPresent(AppSurface.self, forKey: .surface) ?? .unknown
        self.selection = try c.decodeIfPresent(String.self, forKey: .selection) ?? ""
        self.selectionSource = try c.decodeIfPresent(SelectionSource.self, forKey: .selectionSource) ?? .none
        self.hotkey = try c.decodeIfPresent(HotkeyIdentifier.self, forKey: .hotkey) ?? .unknown
        self.capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date()
        self.screenshot = try c.decodeIfPresent(ContextScreenshot.self, forKey: .screenshot)
        self.summary = try c.decodeIfPresent(ContextSummary.self, forKey: .summary)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(frontmostBundleID, forKey: .frontmostBundleID)
        try c.encodeIfPresent(frontmostAppName, forKey: .frontmostAppName)
        try c.encodeIfPresent(windowTitle, forKey: .windowTitle)
        try c.encode(surface, forKey: .surface)
        try c.encode(selection, forKey: .selection)
        try c.encode(selectionSource, forKey: .selectionSource)
        try c.encode(hotkey, forKey: .hotkey)
        try c.encode(capturedAt, forKey: .capturedAt)
        try c.encodeIfPresent(screenshot, forKey: .screenshot)
        try c.encodeIfPresent(summary, forKey: .summary)
    }

    func withSummary(_ summary: ContextSummary) -> ContextSnapshot {
        ContextSnapshot(
            frontmostBundleID: frontmostBundleID,
            frontmostAppName: frontmostAppName,
            windowTitle: windowTitle,
            surface: surface,
            selection: selection,
            selectionSource: selectionSource,
            hotkey: hotkey,
            capturedAt: capturedAt,
            screenshot: screenshot,
            summary: summary
        )
    }
}

struct ContextScreenshot: Codable {
    let status: ScreenshotCaptureStatus
    let filename: String?
    let mimeType: String
    let width: Int
    let height: Int
    let capturedAt: Date
    let imageData: Data?

    init(
        status: ScreenshotCaptureStatus,
        filename: String? = nil,
        mimeType: String = "image/jpeg",
        width: Int = 0,
        height: Int = 0,
        capturedAt: Date = Date(),
        imageData: Data? = nil
    ) {
        self.status = status
        self.filename = filename
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.capturedAt = capturedAt
        self.imageData = imageData
    }

    enum CodingKeys: String, CodingKey {
        case status, filename, mimeType, width, height, capturedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.status = try c.decodeIfPresent(ScreenshotCaptureStatus.self, forKey: .status) ?? .unavailable
        self.filename = try c.decodeIfPresent(String.self, forKey: .filename)
        self.mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType) ?? "image/jpeg"
        self.width = try c.decodeIfPresent(Int.self, forKey: .width) ?? 0
        self.height = try c.decodeIfPresent(Int.self, forKey: .height) ?? 0
        self.capturedAt = try c.decodeIfPresent(Date.self, forKey: .capturedAt) ?? Date()
        self.imageData = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(status, forKey: .status)
        try c.encodeIfPresent(filename, forKey: .filename)
        try c.encode(mimeType, forKey: .mimeType)
        try c.encode(width, forKey: .width)
        try c.encode(height, forKey: .height)
        try c.encode(capturedAt, forKey: .capturedAt)
    }
}

enum ScreenshotCaptureStatus: String, Codable {
    case captured
    case disabled
    case denied
    case unavailable
    case failed
    /// We deliberately did not screenshot this app — it's on the exclusion
    /// list (a dev/text surface by default, or a user override). Distinct
    /// from `.disabled` (feature off globally) so the Run Log can explain
    /// *why* there's no image.
    case skippedApp
}

struct ContextSummary: Codable {
    let model: String
    let prompt: String
    let text: String
    let latencyMs: Int
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
/// "Vordi doesn't detect Zed."
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
    /// the audience for "vordi create" dev-mode features.
    static func isDeveloperSurface(_ surface: AppSurface) -> Bool {
        switch surface {
        case .ide, .terminal, .database: return true
        case .browser, .chat, .notes, .mail, .office, .design, .unknown: return false
        }
    }

    /// True when a window screenshot adds real signal for context
    /// summarization. Dev/text surfaces (IDE, terminal, DB client) are
    /// excluded by default: their content is text the vision model would
    /// just OCR back at high token cost, and the AX/selection path already
    /// captures it more cheaply. Everything else — browsers, design tools,
    /// docs, chat — benefits from the visual layout, so we keep the shot.
    ///
    /// This is only the *category default*. Per-app user overrides are
    /// layered on top in `ContextProvider.shouldCaptureScreenshot`.
    static func benefitsFromScreenshot(_ surface: AppSurface) -> Bool {
        !isDeveloperSurface(surface)
    }
}
