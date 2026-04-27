import SwiftUI
import AppKit

// MARK: - Theme

/// Design tokens. Single source of truth for colors, typography, radii,
/// spacing, and shadows across the app. Modeled after Wispr Flow's visual
/// language — warm cream bg, rounded cards, serif display type for hero
/// moments, sans-serif for chrome.
///
/// Why a namespace, not a protocol: no runtime swapping needed. Flat static
/// values compile to constants; zero dispatch overhead. If we ever need
/// dark-mode variants, convert to computed properties on a ThemeMode enum.
enum Theme {
    // MARK: - Adaptive color helper
    //
    // Every token has two values — light + dark. Dynamic NSColor resolves
    // at draw time based on the effective appearance, which we override
    // app-wide via .preferredColorScheme(themeManager.colorScheme). So the
    // user's theme toggle flips an environment value, and every surface
    // (cards, text, dividers) repaints itself without per-call ifs.
    private static func adaptive(
        light: (Double, Double, Double),
        dark: (Double, Double, Double)
    ) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let (r, g, b) = isDark ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }))
    }
    private static func adaptiveBlackWhite(
        lightOpacity: Double,
        darkOpacity: Double
    ) -> Color {
        Color(NSColor(name: nil, dynamicProvider: { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return isDark
                ? NSColor.white.withAlphaComponent(darkOpacity)
                : NSColor.black.withAlphaComponent(lightOpacity)
        }))
    }

    // MARK: - Background tones (three-level hierarchy)
    //
    //   canvas      → sidebar / chrome
    //   mainContent → main pane
    //   surface     → cards on top of mainContent
    //
    // Dark mode uses warm, coffee-toned darks (not pure black or cool grey)
    // — it should feel like a warm dim room, not a clinical OLED screen.
    // Multiple levels of dark create depth without harsh contrast.
    static let canvas = adaptive(
        light: (0.961, 0.945, 0.918),   // #F5F1EA cream
        dark:  (0.106, 0.098, 0.086)    // #1B1916 warm coffee
    )
    static let mainContent = adaptive(
        light: (0.984, 0.980, 0.969),   // #FBFAF7 almost-white
        dark:  (0.078, 0.071, 0.063)    // #141210 deeper warm dark
    )
    static let surface = adaptive(
        light: (0.980, 0.968, 0.945),   // #FAF7F1 light card
        dark:  (0.141, 0.129, 0.114)    // #24211D raised card
    )
    static let surfaceElevated = adaptive(
        light: (1.000, 1.000, 1.000),   // pure white
        dark:  (0.180, 0.165, 0.149)    // #2E2A26 highest elevation
    )
    // Hero / dark surface — stays dark in BOTH modes. In light mode it's
    // the high-contrast black hero card; in dark mode it shifts to a
    // slightly different shade so it still feels "elevated" against the
    // already-dark canvas.
    static let surfaceDark = adaptive(
        light: (0.094, 0.082, 0.067),   // #18150D warm black
        dark:  (0.043, 0.039, 0.035)    // #0B0A09 deepest — sub-surface
    )
    static let surfaceDarkSoft = adaptive(
        light: (0.149, 0.129, 0.106),
        dark:  (0.220, 0.204, 0.184)    // brighter in dark for nested element contrast
    )

    // Text — soft warm whites in dark mode, never pure white (eye strain).
    static let textPrimary = adaptive(
        light: (0.102, 0.090, 0.078),   // #1A1714 near-black warm
        dark:  (0.961, 0.945, 0.918)    // #F5F1EA cream (matches light canvas)
    )
    static let textSecondary = adaptive(
        light: (0.353, 0.329, 0.314),   // #5A5450 muted brown
        dark:  (0.706, 0.678, 0.643)    // #B4ADA4 muted warm grey
    )
    static let textTertiary = adaptive(
        light: (0.557, 0.518, 0.486),
        dark:  (0.502, 0.471, 0.439)    // #807870 deeper muted
    )
    static let textOnDark      = Color(red: 0.961, green: 0.945, blue: 0.918)

    // Accent — same orange in both modes. Pops well on either bg.
    static let accent          = Color(red: 1.000, green: 0.549, blue: 0.102)   // #FF8C1A
    static let accentSoft      = Color(red: 1.000, green: 0.549, blue: 0.102).opacity(0.15)

    // Status — slightly desaturated in dark for less harshness on dark bg.
    static let success = adaptive(
        light: (0.196, 0.647, 0.404),
        dark:  (0.337, 0.745, 0.486)
    )
    static let warning = adaptive(
        light: (0.902, 0.549, 0.067),
        dark:  (0.957, 0.671, 0.247)
    )
    static let danger = adaptive(
        light: (0.843, 0.275, 0.275),
        dark:  (0.957, 0.408, 0.408)
    )

    // Dividers — opacity-based black/white that flips per mode.
    static let divider         = adaptiveBlackWhite(lightOpacity: 0.06, darkOpacity: 0.08)
    static let dividerStrong   = adaptiveBlackWhite(lightOpacity: 0.12, darkOpacity: 0.16)

    // Corner radii — continuous style everywhere for that soft, rounded feel
    enum Radius {
        static let chip:   CGFloat = 10
        static let button: CGFloat = 10
        static let card:   CGFloat = 16
        static let hero:   CGFloat = 20
    }

    // Spacing scale (4pt grid)
    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    // Shadow — layered for depth without heaviness
    enum Shadow {
        static let card = (color: Color.black.opacity(0.04), radius: CGFloat(4), y: CGFloat(2))
        static let elevated = (color: Color.black.opacity(0.08), radius: CGFloat(16), y: CGFloat(4))
    }
}

// Reusable view helpers that apply Theme tokens.

extension View {
    /// Standard card: cream-white surface, rounded, hairline border, tiny shadow.
    func themedCard(padding: CGFloat = Theme.Space.lg) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
            .shadow(color: Theme.Shadow.card.color,
                    radius: Theme.Shadow.card.radius,
                    x: 0, y: Theme.Shadow.card.y)
    }

    /// Dark hero card — for the "Hold fn to dictate" promo moment.
    func themedHeroCard() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                    .fill(Theme.surfaceDark)
            )
            .shadow(color: Theme.Shadow.elevated.color,
                    radius: Theme.Shadow.elevated.radius,
                    x: 0, y: Theme.Shadow.elevated.y)
    }
}

/// The "fn" key badge — orange rounded pill, inline with text.
/// Used in hero copy and anywhere we need to represent the hotkey.
struct HotkeyBadge: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.accent)
            )
    }
}

/// Themed replacement for `.pickerStyle(.segmented)`. macOS's native
/// segmented control has hostile padding, uses `.tint` as a fill color
/// (burns bright orange — overkill for a frequent-use control), and
/// doesn't support cream backgrounds cleanly. This gives us Wispr-Flow-
/// shaped pill tabs in 30 lines.
///
/// Generic over `ID` so it works with both `String` raw-values (language
/// codes, mode enums) and custom identifiers.
struct ThemedPillTabs<ID: Hashable>: View {
    let options: [(id: ID, label: String)]
    @Binding var selection: ID

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let opt = options[i]
                Button {
                    selection = opt.id
                } label: {
                    Text(opt.label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(selection == opt.id ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == opt.id ? Theme.surfaceElevated : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.divider)
        )
    }
}

/// Tiny shared observable slice for UI state that multiple views care about.
/// Avoids coupling MainDashboardView to AppDelegate's full surface area.
final class RecordingStateStore: ObservableObject {
    @Published var isRecording: Bool = false
}

/// Primary app window. Opens when the user clicks the Dock icon or launches
/// from /Applications. Sidebar has three tabs:
///   - General  — day-to-day preferences (language, mode, mic filter, status)
///   - Settings — setup + credentials (provider, API keys, polish model)
///   - Run Log  — dictation history
///
/// The General/Settings split matches a common desktop-app convention:
/// "General" is what you touch often; "Settings" is what you configure once
/// and leave alone. Credentials and LLM provider config belong in the latter.
///
/// Architectural note: this view owns nothing — it just observes shared state
/// (PermissionService, RunStore) and delegates actions back to AppDelegate
/// via closures. The separation keeps this view trivially previewable and
/// lets AppDelegate remain the single authority on app-level orchestration.
struct MainDashboardView: View {
    @ObservedObject var permissionService: PermissionService
    @ObservedObject var recordingState: RecordingStateStore
    @ObservedObject var runStore: RunStore
    let onTestRecordStart: () -> Void
    let onTestRecordStop: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    @StateObject private var localDetector = LocalModelDetector.shared
    @ObservedObject private var themeManager = ThemeManager.shared

    private var isRecording: Bool { recordingState.isRecording }

    enum Tab: String, CaseIterable {
        case home       = "Home"
        case scratchpad = "Scratchpad"
        case runLog     = "Run Log"
        case settings   = "Settings"

        var icon: String {
            switch self {
            case .home:       return "house"
            case .scratchpad: return "note.text"
            case .runLog:     return "clock.arrow.circlepath"
            case .settings:   return "gearshape"
            }
        }
    }

    // MARK: - Persisted state
    // All @State fields mirror UserDefaults and write back on change. This
    // keeps SwiftUI bindings simple at the cost of a few extra writes — fine
    // for a settings surface that changes at most a few times per session.

    @State private var selectedTab: Tab = .home

    // General tab
    @State private var selectedLanguage: String = UserDefaults.standard.string(forKey: "language") ?? "hi"
    @State private var processingMode: String = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
    @State private var runLogEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "run_log_enabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "run_log_enabled")
    }()
    /// Whether the run log is bounded. Default ON — first-time users get
    /// safe disk usage. Toggle OFF for unlimited history (user pays disk).
    @State private var runLogCapped: Bool = {
        if UserDefaults.standard.object(forKey: "run_log_cap_enabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "run_log_cap_enabled")
    }()
    @State private var noiseGateThreshold: Double = {
        let stored = UserDefaults.standard.double(forKey: "noise_gate_threshold")
        return stored == 0 ? 0.015 : stored
    }()

    // Settings tab
    @State private var provider: String = UserDefaults.standard.string(forKey: "transcription_provider") ?? TranscriptionProvider.openai.rawValue

    // Realtime streaming: off by default. When on, we pipe PCM16 @ 24 kHz
    // directly into OpenAI's Realtime API for lower perceived latency on
    // long dictations. Batch path remains the safety net.
    @State private var realtimeStreaming: Bool = UserDefaults.standard.bool(forKey: "realtime_streaming_enabled")
    @State private var openAIKey: String = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var groqKey: String = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
    @State private var polishBackendId: String = UserDefaults.standard.string(forKey: PolishBackend.userDefaultsKey) ?? PolishBackend.defaultId
    @State private var outputMode: String = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.cleanHinglish.rawValue
    @State private var showKeySaved = false
    /// "Want Hinglish + 100+ languages?" upgrade disclosure on the Groq
    /// tier. Persisted so the open/closed state survives view rebuilds.
    @State private var showOpenAIUpgrade: Bool = false
    /// "Advanced — use my own Groq key" disclosure. Hidden by default;
    /// power users find it when they need it.
    @State private var showAdvancedKeys: Bool = false

    // MARK: - Static option lists

    private let languages: [(code: String, label: String)] = [
        ("hi", "Hindi"),
        ("en", "English"),
        ("auto", "Auto-detect")
    ]

    private let processingModes: [(id: String, label: String)] = [
        (TranscriptProcessingMode.dictation.rawValue, "Dictation"),
        (TranscriptProcessingMode.rewrite.rawValue, "Rewrite")
    ]

    private let outputModes: [(id: String, label: String)] = [
        (TranscriptOutputStyle.verbatim.rawValue, "Verbatim"),
        (TranscriptOutputStyle.clean.rawValue, "Clean"),
        (TranscriptOutputStyle.cleanHinglish.rawValue, "Clean + Hinglish")
    ]

    /// Cloud polish options. Filtered by tier:
    ///   - Always includes Groq llama (free, works with embedded key)
    ///   - OpenAI options ONLY appear when the user has added an OpenAI key
    ///     (otherwise selecting them would just fail at request time)
    private var cloudPolishOptions: [(id: String, label: String)] {
        var opts: [(id: String, label: String)] = [
            ("groq::llama-3.3-70b-versatile",
             "Groq · llama-3.3-70b (free, default)")
        ]
        if !openAIKey.isEmpty {
            opts.append(("openai::gpt-4.1-mini",
                         "OpenAI · gpt-4.1-mini (recommended)"))
            opts.append(("openai::gpt-4.1-nano",
                         "OpenAI · gpt-4.1-nano (cheaper, stronger role adherence)"))
        }
        return opts
    }

    /// Cloud options + detected local models. Updates reactively as
    /// LocalModelDetector.shared.models changes.
    private var polishOptions: [(id: String, label: String)] {
        var opts = cloudPolishOptions
        for model in localDetector.models {
            opts.append((model.id, "\(model.provider.label) · \(model.name)"))
        }
        return opts
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar — cream bg, no hard divider, pill-style selection
            VStack(alignment: .leading, spacing: 16) {
                // Brand mark
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("VoiceFlow")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)

                VStack(spacing: 2) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        sidebarButton(tab)
                    }
                }

                Spacer()

                // Theme toggle — light/dark, persisted via ThemeManager.
                // Lives above the GitHub block so it's discoverable but
                // not the first thing users see.
                ThemeTogglePill(manager: themeManager)
                    .padding(.horizontal, 2)

                // Premium / OpenAI-key upsell — sits above the GitHub
                // block because the conversion intent is higher value.
                // Visual treatment uses accent gradient to differentiate
                // from the surface-tinted star block underneath, so the
                // eye lands here first.
                SidebarPremiumBlock()

                // GitHub Star block — sidebar-sized, replaces the wide
                // StarRepoCard that used to sit on Home. Same intent
                // (drive-by stars + social proof) in the right surface.
                SidebarStarBlock()

                // Footer — subtle, no upsell garbage (aligned with our
                // open-source positioning).
                VStack(alignment: .leading, spacing: 4) {
                    Text("v1.0.0")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                    Text("Local-first · Open source")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 4)
            }
            .frame(width: 200)
            .padding(.vertical, 16)
            .padding(.horizontal, 10)
            .background(Theme.canvas)

            // Content — uses mainContent (almost-white) so the warmer
            // cream sidebar reads as a distinct nav surface. Cards inside
            // each tab use Theme.surface (slightly cream) to define
            // themselves against this background.
            Group {
                switch selectedTab {
                case .home:       homeContent
                case .scratchpad: ScratchpadView(runStore: runStore)
                case .runLog:     RunLogView(runStore: runStore)
                case .settings:   settingsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.mainContent)
        }
        .frame(minWidth: 860, minHeight: 640)
        // Drive the entire window's color scheme from ThemeManager. All
        // Theme.* tokens are dynamic NSColors that respond to whatever
        // scheme is set here, so this single override repaints every
        // surface the moment the user toggles.
        .preferredColorScheme(themeManager.colorScheme)
        // Global accent = orange, so segmented pickers, buttons, and
        // focused text fields use the brand color instead of system blue.
        .tint(Theme.accent)
        .onAppear {
            permissionService.refreshStatus()
            localDetector.detect()
        }
        // Listen for menu-bar / chip / external requests to jump to a
        // specific tab. AppDelegate's openSettings() now posts this
        // instead of opening the legacy SettingsView popup.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("VoiceFlow.SelectTab"))) { note in
            guard let raw = note.userInfo?["tab"] as? String else { return }
            switch raw {
            case "home":       selectedTab = .home
            case "scratchpad": selectedTab = .scratchpad
            case "runLog":     selectedTab = .runLog
            case "settings":   selectedTab = .settings
            default: break
            }
        }
    }

    @ViewBuilder
    private func sidebarButton(_ tab: Tab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .frame(width: 18)
                    .font(.system(size: 14, weight: .medium))
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(selectedTab == tab ? Theme.surface : Color.clear)
            )
            .foregroundColor(selectedTab == tab ? Theme.textPrimary : Theme.textSecondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Home tab

    /// Home layout, Wispr Flow-inspired:
    /// - Personalized greeting with hotkey badge
    /// - Dark hero card ("Hold fn to dictate")
    /// - Stats row (total dictations, words, seconds saved) — live from RunStore
    /// - Recent dictations preview (top 3)
    /// - Star Repo card (open-source positioning)
    ///
    /// Deeper settings live under the Settings tab. Home stays light and
    /// glanceable — the thing users see first shouldn't be a config dump.
    /// Two-column layout with two sticky regions:
    /// - Left column has a fixed greeting at the top and a scroll view
    ///   underneath containing the hero card + transcript timeline.
    /// - Right column has a fixed stats card pinned to the top.
    ///
    /// "Sticky" here means literally outside the ScrollView, not
    /// LazyVStack pinned headers — that would still let them scroll
    /// off in some configurations. Putting them outside guarantees
    /// they never move regardless of scroll content.
    private var homeContent: some View {
        HStack(alignment: .top, spacing: Theme.Space.md) {
            // Left column — greeting fixed at top, content scrolls below
            VStack(alignment: .leading, spacing: 0) {
                greetingBlock
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.top, Theme.Space.xl)
                    .padding(.bottom, Theme.Space.lg)
                    .background(Theme.mainContent) // mask any content scrolling under

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Space.xl) {
                        heroCard
                        dictationsTimeline
                    }
                    .padding(.horizontal, Theme.Space.xl)
                    .padding(.bottom, Theme.Space.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Right column — stats fixed at top
            statsCardCompact
                .padding(.top, Theme.Space.xl)
                .padding(.trailing, Theme.Space.xl)
        }
    }

    // MARK: Home — Greeting

    private var greetingBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Hey there, get back into the flow with")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textPrimary)
            HotkeyBadge(label: "fn")
            Spacer()
            if isRecording {
                HStack(spacing: 6) {
                    Circle().fill(Theme.danger).frame(width: 8, height: 8)
                    Text("Recording")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.danger)
                }
            }
        }
    }

    // MARK: Home — Hero card

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Hold down")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundColor(Theme.textOnDark)
                    HotkeyBadge(label: "fn")
                    Text("to dictate")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundColor(Theme.textOnDark)
                }

                Text("VoiceFlow works in every app — email, Slack, your editor, a browser tab. Hold fn, speak, release. Your words appear wherever your cursor is.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.textOnDark.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420, alignment: .leading)

                // Hinglish upsell — surfaces the "Groq is free, OpenAI key
                // unlocks Hindi/Marathi/100+ languages" story directly on the
                // hero where users actually look. Without this the upgrade
                // path is buried in Settings and Hindi-speaking users churn
                // assuming the app can't speak their language.
                hinglishCallout
            }
            Spacer()
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedAnimatedHeroCard()
    }

    /// Inline upsell pill inside the dark hero card.
    /// Tap → jumps to Settings (where they can paste an OpenAI key).
    private var hinglishCallout: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("VoiceFlow.SelectTab"),
                object: nil,
                userInfo: ["tab": "settings"]
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.accent)
                Text("Speak Hindi or Marathi?")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textOnDark)
                Text("Unlock Hinglish + 100+ languages with your OpenAI key")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textOnDark.opacity(0.65))
                    .lineLimit(1)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.accent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Add an OpenAI API key in Settings to dictate in Hindi, Marathi, and 100+ other languages.")
    }

    // MARK: Home — Stats (compact right-side card)

    /// Three stats stacked vertically in a single right-side card. Sized
    /// to sit beside the hero so the top of Home reads as one balanced
    /// row instead of a stacked stack of full-width blocks.
    private var statsCardCompact: some View {
        VStack(alignment: .leading, spacing: 14) {
            statLine(value: "\(DashboardStats.totalDictations(runStore))", label: "dictations")
            statLine(value: "\(DashboardStats.totalWords(runStore))",      label: "total words")
            statLine(value: DashboardStats.streakText(runStore),           label: "streak")
        }
        .frame(width: 200, alignment: .leading)
        .themedCard()
    }

    private func statLine(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        }
    }

    // MARK: Home — Date-grouped transcript timeline

    /// Wispr-Flow-style timeline: dictations grouped by calendar day,
    /// each group rendered as TODAY / YESTERDAY / "Mon D, YYYY" header
    /// + a single card with hairline-divided rows.
    ///
    /// Source of truth = `runStore.summaries` (already newest-first by
    /// the ring-buffer insert order). We re-group rather than re-sort —
    /// preserves whatever ordering RunStore considers canonical.
    @ViewBuilder
    private var dictationsTimeline: some View {
        if runStore.summaries.isEmpty {
            emptyTimelinePlaceholder
        } else {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                ForEach(groupedSummaries, id: \.dayKey) { group in
                    dayBlock(label: group.label, rows: group.summaries)
                }
            }
        }
    }

    private var emptyTimelinePlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No dictations yet")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
            Text("Hold fn anywhere on your Mac and start speaking. Your transcripts will appear here.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedCard()
    }

    private func dayBlock(label: String, rows: [RunSummary]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.textTertiary)
                .tracking(0.8)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    HomeTimelineRow(summary: rows[i], runStore: runStore)
                    if i < rows.count - 1 {
                        Divider().background(Theme.divider)
                    }
                }
            }
            .themedCard(padding: 0)
        }
    }

    // Date grouping — derives a stable day key + a human label per group.
    private struct DaySection {
        let dayKey: Date          // start-of-day, used for ForEach identity
        let label: String         // "TODAY" / "YESTERDAY" / "FEB 24, 2026"
        let summaries: [RunSummary]
    }

    private var groupedSummaries: [DaySection] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: runStore.summaries) { summary in
            cal.startOfDay(for: summary.createdAt)
        }
        return buckets.keys
            .sorted(by: >)        // newest day first
            .map { day in
                DaySection(
                    dayKey: day,
                    label: DashboardStats.dayLabel(day),
                    summaries: buckets[day] ?? []
                )
            }
    }

    private var recordingHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("VoiceFlow")
                    .font(.system(size: 22, weight: .bold))
                Text("Hold Fn to dictate anywhere on your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if isRecording {
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("Recording").font(.caption.bold()).foregroundColor(.red)
                }
            }
        }
    }

    private var aboutCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 6) {
                Text("About")
                    .font(.headline)
                Text("VoiceFlow v1.0.0")
                    .font(.subheadline.bold())
                Text("Voice typing for macOS — powered by OpenAI Whisper with optional local LLM post-processing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var languageCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Language")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    if isOnGroqTier {
                        Text("Locked to English")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.divider))
                    }
                }
                ThemedPillTabs(
                    options: languages.map { (id: $0.code, label: $0.label) },
                    selection: $selectedLanguage
                )
                .onChange(of: selectedLanguage) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "language")
                }
                .disabled(isOnGroqTier)
                .opacity(isOnGroqTier ? 0.45 : 1.0)

                if isOnGroqTier {
                    Text("Groq's free tier supports English only. Add your OpenAI API key in Settings → Provider to unlock Hindi, Hinglish, and 100+ other languages.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Auto-detect picks the language per recording. Lock to Hindi or English if you're always speaking one. Locking to English will also translate any Hindi you speak into English.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // Force English when locked to Groq tier — drops a one-shot
        // .onChange-style write so the persisted UserDefaults value
        // matches the locked UI state, even if user had previously
        // selected Hindi on a different provider.
        .onAppear {
            if isOnGroqTier && selectedLanguage != "en" {
                selectedLanguage = "en"
                UserDefaults.standard.set("en", forKey: "language")
            }
        }
        .onChange(of: provider) { _ in
            if isOnGroqTier && selectedLanguage != "en" {
                selectedLanguage = "en"
                UserDefaults.standard.set("en", forKey: "language")
            }
        }
    }

    /// True when the user is on the Groq free tier — i.e. they've selected
    /// Groq as the transcription provider AND haven't added an OpenAI key.
    /// Drives lock states across language + style pickers + polish dropdown.
    private var isOnGroqTier: Bool {
        provider == TranscriptionProvider.groq.rawValue && openAIKey.isEmpty
    }

    /// Output styles available given the current tier. Drops `cleanHinglish`
    /// + `translateEnglish` on the Groq tier — neither works reliably with
    /// the embedded Groq pipeline. The `outputStyleCard` falls through to
    /// `clean` automatically when Groq is selected.
    private var visibleOutputModes: [(id: String, label: String)] {
        if isOnGroqTier {
            return outputModes.filter {
                $0.id == TranscriptOutputStyle.verbatim.rawValue ||
                $0.id == TranscriptOutputStyle.clean.rawValue
            }
        }
        return outputModes
    }

    private var transcriptionModeCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Transcription Mode")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                ThemedPillTabs(
                    options: processingModes.map { (id: $0.id, label: $0.label) },
                    selection: $processingMode
                )
                .onChange(of: processingMode) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "processing_mode")
                }
                Text("Dictation keeps your spoken phrasing. Rewrite converts a spoken draft into cleaner final intent text.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runLogToggleCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Run Log").font(.headline)
                    Spacer()
                    Toggle("", isOn: $runLogEnabled)
                        .labelsHidden()
                        .onChange(of: runLogEnabled) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "run_log_enabled")
                        }
                }

                // Sub-toggle: cap on/off. Disabled when the parent toggle is
                // off — no point capping a log that isn't being written.
                HStack {
                    Text("Cap at 20 runs")
                        .font(.subheadline)
                        .foregroundColor(runLogEnabled ? .primary : .secondary)
                    Spacer()
                    Toggle("", isOn: $runLogCapped)
                        .labelsHidden()
                        .disabled(!runLogEnabled)
                        .onChange(of: runLogCapped) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "run_log_cap_enabled")
                            // Toggling the cap ON with an over-cap history
                            // should feel immediate. Without this, excess
                            // entries linger until the next save() triggers
                            // the ring-buffer trim.
                            if newValue {
                                RunStore.shared.applyCap()
                            }
                        }
                }

                Text(runLogCaptionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Contextual caption — explains what the current toggle combination
    /// actually does. Cheaper to read than a static "Last 20 runs are kept"
    /// when the cap can be off.
    private var runLogCaptionText: String {
        if !runLogEnabled {
            return "Run history is off. No audio, transcripts, or prompts are saved to disk."
        }
        if runLogCapped {
            return "Save audio, transcripts, and prompts locally for each dictation. Last 20 runs are kept; nothing leaves your Mac."
        }
        return "Save audio, transcripts, and prompts locally for each dictation. No cap — history grows until you clear it manually."
    }

    /// Sensitivity = inverse of the noise gate threshold. We want the
    /// slider to feel intuitive: drag right = MORE sensitive (catches
    /// quieter speech). The underlying threshold is the opposite axis,
    /// so we map slider 0..1 → threshold 0.001..0.030.
    private var sensitivityValue: Double {
        // Convert stored threshold back to "sensitivity" 0..1 for the slider.
        let clamped = max(0.001, min(0.030, noiseGateThreshold))
        return 1.0 - ((clamped - 0.001) / (0.030 - 0.001))
    }

    private var microphoneFilterCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Microphone Sensitivity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text(sensitivityLabel)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                }

                // Sensitivity slider — left = strict (only loud speech
                // counts), right = sensitive (catches whispers, also
                // catches typing/AC noise).
                HStack(spacing: 10) {
                    Image(systemName: "speaker.wave.1")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                    Slider(
                        value: Binding(
                            get: { sensitivityValue },
                            set: { newSens in
                                // Reverse: sensitivity 0..1 → threshold 0.030..0.001
                                let threshold = 0.001 + (1.0 - newSens) * (0.030 - 0.001)
                                noiseGateThreshold = threshold
                                UserDefaults.standard.set(threshold, forKey: "noise_gate_threshold")
                            }
                        ),
                        in: 0...1
                    )
                    .accentColor(Theme.accent)
                    Image(systemName: "speaker.wave.3")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                }

                // One-tap presets — easier than fiddling with the slider.
                HStack(spacing: 8) {
                    sensitivityPresetButton(label: "Strict",  threshold: 0.020)
                    sensitivityPresetButton(label: "Balanced", threshold: 0.008)
                    sensitivityPresetButton(label: "Sensitive", threshold: 0.003)
                }

                Text(sensitivityHelpText)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sensitivityLabel: String {
        if noiseGateThreshold >= 0.015 { return "Strict" }
        if noiseGateThreshold >= 0.006 { return "Balanced" }
        return "Sensitive"
    }

    private var sensitivityHelpText: String {
        switch sensitivityLabel {
        case "Strict":
            return "Only loud, clear speech is captured. Use this in noisy rooms — but quiet speech may be dropped."
        case "Sensitive":
            return "Catches quiet speech and whispers. Use this if your fn-presses are producing nothing — but background noise may bleed in."
        default:
            return "Default — works for most setups. Bump UP if room noise is being transcribed; bump DOWN if your speech is being dropped."
        }
    }

    private func sensitivityPresetButton(label: String, threshold: Double) -> some View {
        Button {
            noiseGateThreshold = threshold
            UserDefaults.standard.set(threshold, forKey: "noise_gate_threshold")
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(sensitivityLabel == label ? Theme.textOnDark : Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(sensitivityLabel == label ? Theme.accent : Theme.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }

    private var statusCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Status")
                    .font(.headline)

                permissionLine(
                    title: "Microphone",
                    state: permissionService.microphoneState,
                    fix: { permissionService.openPrivacyPane(.microphone) }
                )
                permissionLine(
                    title: "Accessibility",
                    state: permissionService.accessibilityState,
                    fix: { permissionService.openPrivacyPane(.accessibility) }
                )
                permissionLine(
                    title: "Input Monitoring",
                    state: permissionService.inputMonitoringState,
                    fix: { permissionService.openPrivacyPane(.inputMonitoring) }
                )

                if !permissionService.allRequiredGranted {
                    Text("Global hotkeys will not work until all are granted.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                // Guided fix flows for the two permissions most likely to trip
                // up ad-hoc-signed builds (auto-prompt often no-ops).
                if !permissionService.accessibilityState.isGranted {
                    AccessibilityGuideView(
                        permissionService: permissionService,
                        onDismiss: {}
                    )
                    .padding(.top, 8)
                }

                if !permissionService.inputMonitoringState.isGranted {
                    InputMonitoringGuideView(
                        permissionService: permissionService,
                        onDismiss: {}
                    )
                    .padding(.top, 8)
                }

                Button("Re-check permissions") {
                    permissionService.refreshStatus()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Settings tab

    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsHeader
                providerCard
                realtimeStreamingCard
                polishModelCard
                outputStyleCard
                // Mic sensitivity — was previously defined but orphaned
                // (never composed into the Settings tab). Restored here
                // because users hitting the silence-gate hard-drop need a
                // way to recover: bump sensitivity DOWN to catch quieter
                // speech, or UP if their AC/keyboard is being transcribed.
                microphoneFilterCard
                permissionsCard
                setupCard
                footerActions
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Settings — Permissions card

    /// Live status of the three TCC permissions VoiceFlow requires. Inline
    /// "Open Settings" button per row when the permission isn't granted —
    /// faster than navigating System Settings manually.
    private var permissionsCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Permissions")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Button {
                        permissionService.refreshStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Re-check permission status")
                }

                permissionRow(
                    title: "Microphone",
                    subtitle: "Required to hear your voice",
                    state: permissionService.microphoneState,
                    pane: .microphone
                )
                permissionRow(
                    title: "Accessibility",
                    subtitle: "Required to type the transcript into other apps",
                    state: permissionService.accessibilityState,
                    pane: .accessibility
                )
                permissionRow(
                    title: "Input Monitoring",
                    subtitle: "Required to detect fn key presses",
                    state: permissionService.inputMonitoringState,
                    pane: .inputMonitoring
                )

                if !permissionService.allRequiredGranted {
                    Text("Global hotkeys won't work until all three are granted.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.warning)
                        .padding(.top, 2)
                }
            }
        }
    }

    private func permissionRow(
        title: String,
        subtitle: String,
        state: PermissionState,
        pane: PermissionPane
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: state.isGranted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 16))
                .foregroundColor(state.isGranted ? Theme.success : Theme.textTertiary)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            if state.isGranted {
                Text("Granted")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Theme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.success.opacity(0.12)))
            } else {
                Button {
                    permissionService.openPrivacyPane(pane)
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Settings — Setup card (re-run onboarding)

    /// Escape hatch for users who want to walk the welcome flow again —
    /// useful for support scenarios ("can you walk me through permissions
    /// again?") and for testing the wizard during dev. Posts a notification
    /// that AppDelegate listens for; doesn't drag onboarding state into
    /// MainDashboardView.
    private var setupCard: some View {
        cardContainer {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Text("Walk through the welcome flow again to revisit permissions, API keys, and the test step.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    NotificationCenter.default.post(
                        name: Notification.Name("VoiceFlow.RestartOnboarding"),
                        object: nil
                    )
                } label: {
                    Text("Re-run onboarding")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.dividerStrong, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var settingsHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textPrimary)
            Text("Credentials, providers, and post-processing.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var realtimeStreamingCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Realtime Streaming")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(Theme.textPrimary)
                            Text("BETA")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Theme.accent))
                        }
                        Text("Lower perceived latency by streaming audio to OpenAI while you speak.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: $realtimeStreaming)
                        .labelsHidden()
                        .onChange(of: realtimeStreaming) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "realtime_streaming_enabled")
                        }
                }
                if realtimeStreaming {
                    Text("Requires OpenAI provider and a valid API key. Falls back to the batch upload if the WebSocket drops — you'll never miss a recording because of a bad network.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var providerCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Transcription Provider")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                // Pill picker. Labels reflect the actual capability split:
                // Groq is fast English (we lock language to English on this
                // tier — see languageCard); OpenAI unlocks Hinglish + 100+
                // languages.
                ThemedPillTabs(
                    options: [
                        (id: TranscriptionProvider.groq.rawValue,   label: "Groq · Fast English"),
                        (id: TranscriptionProvider.openai.rawValue, label: "OpenAI · Multilingual")
                    ],
                    selection: $provider
                )
                .onChange(of: provider) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "transcription_provider")
                    // Provider changed — re-evaluate polish default. If
                    // user is moving FROM Groq with no OpenAI key set,
                    // their polish_backend_id might still be groq::llama
                    // which is fine for OpenAI provider too (works either
                    // way). No-op for now; the polish dropdown filters
                    // available options based on key state.
                }

                Divider().background(Theme.divider)

                if provider == TranscriptionProvider.groq.rawValue {
                    groqProviderBody
                } else {
                    openAIProviderBody
                }

                if showKeySaved {
                    Text("✓ Saved")
                        .font(.caption)
                        .foregroundColor(Theme.success)
                        .transition(.opacity)
                }
            }
        }
    }

    /// Body when Groq is the active provider. Free tier badge + the
    /// upgrade-to-OpenAI marketing pitch + an Advanced disclosure for
    /// the user's own Groq key (rare but supported).
    @ViewBuilder
    private var groqProviderBody: some View {
        // Free tier status
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(Theme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("Free tier active")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text("Fast English dictation, no setup needed.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }

        // OpenAI upgrade marketing pitch — visible by default, opens to
        // a key-entry field when user expands.
        DisclosureGroup(
            isExpanded: $showOpenAIUpgrade,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your OpenAI API key to unlock multilingual transcription, Hinglish, and higher-quality polish via GPT-4. You pay OpenAI directly — typically ~$0.18/hour of audio, much cheaper than Wispr Flow's flat subscription.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    keyRow(
                        title: "OpenAI API Key",
                        placeholder: "sk-...",
                        help: "Get a key at platform.openai.com/api-keys",
                        text: $openAIKey,
                        onCommit: {
                            UserDefaults.standard.set(openAIKey, forKey: "openai_api_key")
                            flashSaved()
                        }
                    )
                }
                .padding(.top, 8)
            },
            label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Theme.accent)
                    Text("Want Hinglish + 100+ languages?")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                }
            }
        )
        .tint(Theme.accent)

        // Advanced — bring-your-own Groq key. Hidden by default since
        // 99% of free-tier users don't have one or care.
        DisclosureGroup(
            isExpanded: $showAdvancedKeys,
            content: {
                keyRow(
                    title: "Groq API Key (override)",
                    placeholder: "gsk_...",
                    help: "Optional. Leave empty to keep using the embedded beta key.",
                    text: $groqKey,
                    onCommit: {
                        UserDefaults.standard.set(groqKey, forKey: "groq_api_key")
                        flashSaved()
                    }
                )
                .padding(.top, 8)
            },
            label: {
                Text("Advanced — use my own Groq key")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
            }
        )
        .tint(Theme.textTertiary)
    }

    /// Body when OpenAI is the active provider. Just the API key field.
    @ViewBuilder
    private var openAIProviderBody: some View {
        keyRow(
            title: "OpenAI API Key",
            placeholder: "sk-...",
            help: "Paid. Get a key at platform.openai.com/api-keys",
            text: $openAIKey,
            onCommit: {
                UserDefaults.standard.set(openAIKey, forKey: "openai_api_key")
                flashSaved()
            }
        )
    }

    private var polishModelCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Post-Processing Model")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                Picker("Polish model", selection: $polishBackendId) {
                    ForEach(polishOptions, id: \.id) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .onChange(of: polishBackendId) { newValue in
                    UserDefaults.standard.set(newValue, forKey: PolishBackend.userDefaultsKey)
                }

                HStack(spacing: 8) {
                    Button {
                        localDetector.detect()
                    } label: {
                        if localDetector.isDetecting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh local models", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(localDetector.isDetecting)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if localDetector.models.isEmpty {
                        Text("No local servers detected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("\(localDetector.models.count) local model\(localDetector.models.count == 1 ? "" : "s") detected")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Text("Local models (LM Studio on :1234, Ollama on :11434) run on your machine — no network, no API cost. Start your server, hit Refresh, then pick it above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Warn if the persisted selection isn't currently detected
                if (polishBackendId.hasPrefix("lmstudio::") || polishBackendId.hasPrefix("ollama::"))
                    && !polishOptions.contains(where: { $0.id == polishBackendId }) {
                    Text("⚠️ Selected local model is not currently detected. Dictation will fail until you start the server and refresh.")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var outputStyleCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Output Style")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    if isOnGroqTier {
                        Text("Hinglish requires OpenAI")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.divider))
                    }
                }
                // On Groq tier: hide the Hinglish option entirely so user
                // doesn't pick it expecting it to work. On OpenAI tier:
                // show the full list.
                ThemedPillTabs(
                    options: visibleOutputModes.map { (id: $0.id, label: $0.label) },
                    selection: $outputMode
                )
                .onChange(of: outputMode) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "output_mode")
                }
                Text(outputStyleHelperText)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Mode-specific helper text — describes what the currently selected
    /// output style actually does, factoring in the Language selection
    /// (English locks output to English regardless of spoken language).
    private var outputStyleHelperText: String {
        let isEnglishLocked = (selectedLanguage == "en")
        switch TranscriptOutputStyle(rawValue: outputMode) ?? .cleanHinglish {
        case .verbatim:
            return "Raw transcript with no cleanup. Preserves exact wording, fillers, and source language. Language lock has no effect in this mode."
        case .clean:
            if isEnglishLocked {
                return "Removes fillers, fixes grammar, and translates any Hindi segments to English. Output is always pure English."
            }
            return "Removes fillers and fixes grammar. Keeps the source language unchanged."
        case .cleanHinglish:
            if isEnglishLocked {
                return "Language is locked to English — output will be translated to pure English. (To keep Hinglish, switch Language to Auto-detect.)"
            }
            return "Removes fillers, fixes grammar, and enforces Latin characters for mixed Hindi/English (Devanagari → Latin)."
        case .translateEnglish:
            return "Translates any spoken language to natural English."
        }
    }

    private var footerActions: some View {
        HStack {
            Button(action: onQuit) {
                Label("Quit VoiceFlow", systemImage: "power")
            }
            .buttonStyle(.plain)
            .foregroundColor(.red)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func cardContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedCard()
    }

    @ViewBuilder
    private func keyRow(
        title: String,
        placeholder: String,
        help: String,
        text: Binding<String>,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            HStack(spacing: 8) {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.divider, lineWidth: 1)
                    )
                    .onSubmit(onCommit)

                Button {
                    onCommit()
                } label: {
                    Text("Save")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Theme.textPrimary)
                        )
                }
                .buttonStyle(.plain)
            }
            .onChange(of: text.wrappedValue) { _ in
                // Autosave on every keystroke — the Save button is a visual
                // reassurance, not a gate.
                onCommit()
            }

            Text(help)
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func permissionLine(title: String, state: PermissionState, fix: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: state.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(state.isGranted ? .green : .orange)
            Text(title)
            Spacer()
            if !state.isGranted {
                Button("Open Settings", action: fix)
                    .buttonStyle(.link)
            }
        }
        .font(.subheadline)
    }

    private func flashSaved() {
        withAnimation { showKeySaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showKeySaved = false }
        }
    }
}

// MARK: - DashboardStats

/// Pure derivations from RunStore's summary list. Stateless — no caching,
/// no persistence. All three stats recompute on every SwiftUI body pass,
/// but n is bounded by the ring-buffer cap (20 by default), so the cost is
/// negligible vs. the complexity of a separate reactive service.
///
/// Design note: words-per-minute deliberately omitted. Without known audio
/// duration per successful transcript it's either noise or a lie. Added
/// later once we capture per-run timing reliably.
enum DashboardStats {
    /// Count of all saved runs (including errors — gives users a sense of
    /// total engagement, not just success).
    static func totalDictations(_ store: RunStore) -> Int {
        store.summaries.count
    }

    /// Sum of words across preview texts. Approximate — previewText may be
    /// truncated for long runs — but strictly monotonic and directionally
    /// correct. Honest stat, not a vanity metric.
    static func totalWords(_ store: RunStore) -> Int {
        store.summaries.reduce(0) { acc, s in
            acc + s.previewText
                .split(whereSeparator: { $0.isWhitespace })
                .count
        }
    }

    /// Current daily streak — consecutive calendar days with at least one
    /// dictation, anchored on today. Returns "—" if no runs. Presented as
    /// string so the UI doesn't have to branch on zero.
    static func streakText(_ store: RunStore) -> String {
        let days = streakDays(store)
        if days == 0 { return "—" }
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    private static func streakDays(_ store: RunStore) -> Int {
        guard !store.summaries.isEmpty else { return 0 }
        let cal = Calendar.current
        let dates = Set(store.summaries.map { cal.startOfDay(for: $0.createdAt) })
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        // Allow one grace day — if user hasn't dictated today yet, walk
        // back one day before giving up. Otherwise the streak shows 0 for
        // most of the day, which feels punishing.
        if !dates.contains(cursor) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
            if !dates.contains(cursor) { return 0 }
        }
        while dates.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        return streak
    }

    /// Short relative time for timeline rows: "12:08 AM" if today, else
    /// "Apr 23". Keeps the timeline glanceable without a full datestamp.
    static func shortTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            let f = DateFormatter()
            f.dateFormat = "h:mm a"
            return f.string(from: date)
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }

    /// Time component only — used inside date-grouped sections where the
    /// day is already established by the section header. "12:08 AM" form.
    static func timeOnly(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// Day-section header label. "TODAY" / "YESTERDAY" / "FEB 24, 2026".
    /// Uppercased + tracked at the call site for the label-style caption.
    static func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "TODAY" }
        if cal.isDateInYesterday(day) { return "YESTERDAY" }
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f.string(from: day).uppercased()
    }
}

// MARK: - FocusDetector

/// On-demand classifier for the currently-focused UI element. No polling —
/// AppDelegate calls `detectNow()` at the moment fn is pressed, and only
/// then. Polling was wrong: it caused the chip to morph constantly as the
/// user clicked between apps, which is noise. Focus state only matters
/// when the user attempts to dictate.
///
/// Requires Accessibility permission (already held for Fn hotkey).
///
/// Not `@MainActor` — the AX APIs are thread-safe and the class has no
/// shared mutable state. Callers can invoke from any thread.
final class FocusDetector {
    enum FocusState: Equatable {
        case textInput
        case nonText
        case noFocus
    }

    /// One AX call. Returns instantly. Safe to call from main thread.
    func detectNow() -> FocusState {
        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let result = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success, let element = focused else { return .noFocus }
        let role = roleOf(element as! AXUIElement)
        switch role {
        case "AXTextField", "AXTextArea", "AXSearchField", "AXComboBox", "AXWebArea":
            return .textInput
        default:
            return .nonText
        }
    }

    private func roleOf(_ element: AXUIElement) -> String? {
        var role: AnyObject?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        return role as? String
    }
}

// MARK: - FloatingChipWindow

/// Persistent bottom-of-screen chip — VoiceFlow's "I'm here" affordance.
/// Single source of truth for the dictation-state UI; the legacy notch
/// chip is silenced now that this one shows recording state too.
///
/// State machine:
///   - `.idle`            → tiny black capsule with the wave glyph
///   - `.recording`       → capsule with live waveform driven by mic level
///   - `.processing`      → capsule with shimmer (LLM polish in flight)
///   - `.noInputWarning`  → wide capsule with "Click a textbox to dictate".
///                          Only fires when fn is pressed AND no text input
///                          is focused — never a continuous poll.
///
/// Hover behavior: in `.idle`, hovering reveals a small gear button on the
/// right. Click → opens Settings. Other states ignore hover.
final class FloatingChipModel: ObservableObject {
    enum ChipState: Equatable { case idle, recording, processing, noInputWarning, permissionsMissing, noAudioWarning }

    @Published var state: ChipState = .idle
    /// Live mic amplitude during `.recording`. 0...1, normalized.
    @Published var audioLevel: Float = 0
    /// Drives the passive orange-dot indicator on the idle chip. AppDelegate
    /// sets this from PermissionService state and refreshes on every TCC
    /// state change. False = at least one required permission is missing.
    @Published var hasAllPermissions: Bool = true
}

final class FloatingChipWindow: NSPanel {
    let model = FloatingChipModel()

    /// Window-level size — large enough to host the warning state at full
    /// width. Inner SwiftUI shape decides what's actually drawn; window
    /// stays the same size to avoid resize jank during state transitions.
    /// 420pt accommodates the longest copy ("Click a textbox and use
    /// Cmd+V to paste") plus the Tip badge + dismiss button.
    private static let windowSize = NSSize(width: 420, height: 40)

    /// UserDefaults key for the user's preferred chip position. Stored as
    /// "x,y" string of the bottom-left frame origin.
    private static let originKey = "floating_chip_origin"

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false

        // Drag-to-reposition. `isMovableByWindowBackground` lets the user
        // grab the chip's transparent area and drag — buttons inside still
        // receive their click events normally because AppKit hit-tests
        // interactive subviews first. The drag handle is everything that
        // ISN'T a button.
        self.isMovable = true
        self.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: FloatingChipView(model: model))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.windowSize)
        host.autoresizingMask = [.width, .height]
        self.contentView = host
        self.setContentSize(Self.windowSize)

        // Persist position on every drag end. didMoveNotification fires
        // after the user releases the mouse, so we don't write to defaults
        // on every pixel of motion.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowMoved),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    @objc private func handleWindowMoved() {
        let origin = self.frame.origin
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // MARK: - Public state API (called by AppDelegate)

    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.repositionToBottom()
            self.alphaValue = 1
            self.orderFrontRegardless()
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.orderOut(nil)
        }
    }

    func setRecording() {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeInOut(duration: 0.15)) {
                self?.model.state = .recording
            }
        }
    }

    func setProcessing() {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeInOut(duration: 0.15)) {
                self?.model.state = .processing
            }
        }
    }

    func setIdle() {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeInOut(duration: 0.15)) {
                self?.model.state = .idle
                self?.model.audioLevel = 0
            }
        }
    }

    /// Flash the orange permissions warning. Click on it routes to
    /// onboarding's Permissions step. Auto-dismiss after 5s — same idea
    /// as flashNoInputWarning, just longer because permissions are a
    /// deeper task than "click a textbox."
    func flashPermissionsWarning(durationSeconds: Double = 5.0) {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeInOut(duration: 0.15)) {
                self?.model.state = .permissionsMissing
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [weak self] in
            guard let self = self else { return }
            if self.model.state == .permissionsMissing {
                self.setIdle()
            }
        }
    }

    /// Push permission availability — drives the passive orange-dot
    /// indicator on the idle chip. Cheap to call repeatedly; only
    /// republishes when the value actually changes.
    func setPermissionsAvailable(_ available: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.model.hasAllPermissions != available {
                self.model.hasAllPermissions = available
            }
        }
    }

    /// Show the no-input warning briefly, then fall back to idle. Does NOT
    /// block whatever recording flow is happening — purely informational.
    ///
    /// On auto-dismiss we post the same DismissChipWarning notification
    /// the X button uses, so AppDelegate's restore-clipboard logic runs
    /// in both paths through one observer.
    func flashNoInputWarning(durationSeconds: Double = 3.0) {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeInOut(duration: 0.15)) {
                self?.model.state = .noInputWarning
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [weak self] in
            guard let self = self else { return }
            // Only revert if we're still showing the warning — don't clobber
            // a recording/processing state that started during the warning.
            if self.model.state == .noInputWarning {
                NotificationCenter.default.post(
                    name: Notification.Name("VoiceFlow.DismissChipWarning"),
                    object: nil
                )
            }
        }
    }

    /// Fires when AudioRecorder returns nil — no buffer crossed the noise
    /// gate threshold during the entire fn-press window. Without this
    /// signal users see literally nothing happen post-release and assume
    /// the app is broken. The chip states a clear message + implicit
    /// pointer to Mic Sensitivity in Settings.
    func flashNoAudioWarning(durationSeconds: Double = 3.0) {
        DispatchQueue.main.async { [weak self] in
            withAnimation(.easeInOut(duration: 0.15)) {
                self?.model.state = .noAudioWarning
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + durationSeconds) { [weak self] in
            guard let self = self else { return }
            if self.model.state == .noAudioWarning {
                withAnimation(.easeInOut(duration: 0.15)) {
                    self.model.state = .idle
                }
            }
        }
    }

    /// Push live audio amplitude (0...1). Safe from any thread.
    func updateAudioLevel(_ level: Float) {
        if Thread.isMainThread {
            model.audioLevel = level
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.model.audioLevel = level
            }
        }
    }

    // MARK: - Positioning

    /// Restore the user's saved position if present + still on-screen.
    /// Otherwise default to bottom-center, ~24pt above dock.
    private func repositionToBottom() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = Self.windowSize

        // 1. Try to restore saved position from a previous drag
        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let x = CGFloat(parts[0])
                let y = CGFloat(parts[1])
                let candidate = NSRect(x: x, y: y, width: size.width, height: size.height)
                // Only restore if at least 50% of the chip would be on
                // a connected screen — protects against display unplugs
                // putting the chip somewhere unreachable.
                let onScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(candidate) }
                if onScreen {
                    self.setFrame(candidate, display: true)
                    return
                }
            }
        }

        // 2. Default — bottom-center
        let x = visible.midX - size.width / 2
        let y = visible.minY + 24
        self.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }
}

/// Solid dark-grey chip background with a subtle white border.
///
/// Earlier we tried .ultraThinMaterial + tint (glass morphism) but that
/// stayed transparent enough to vanish on white backgrounds. A solid
/// fill is honest about what it is: a dark UI chip that needs to be
/// visible on every conceivable background. The white border at ~22%
/// opacity gives definition on dark bgs (where the dark fill alone
/// can blend into a dark window).
///
/// Single source of truth for the colors so all chip variants stay
/// consistent: `Color.chipFill` for the body, `Color.chipBorder` for
/// the outline.
extension Color {
    /// Body of the chip — dark charcoal, intentionally NOT pure black
    /// (pure black is too aggressive on light bgs and looks like a hole).
    static let chipFill   = Color(red: 0.13, green: 0.13, blue: 0.15)
    /// 1pt outline color. White at low opacity reads on any bg.
    static let chipBorder = Color.white.opacity(0.22)
}

private struct ChipGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                Capsule(style: .continuous)
                    .fill(Color.chipFill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.chipBorder, lineWidth: 1)
            )
    }
}

extension View {
    fileprivate func chipGlass() -> some View {
        self.modifier(ChipGlass())
    }
}

/// SwiftUI body for the floating chip. State-driven via FloatingChipModel.
/// No FocusDetector polling here — the warning state is pushed in by
/// AppDelegate when fn-press happens without a text-input focus.
struct FloatingChipView: View {
    @ObservedObject var model: FloatingChipModel
    @State private var hovering = false

    var body: some View {
        HStack {
            Spacer()
            chipShape
                .animation(.easeInOut(duration: 0.18), value: model.state)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var chipShape: some View {
        switch model.state {
        case .idle:
            idleChip
        case .recording:
            recordingChip
        case .processing:
            processingChip
        case .noInputWarning:
            warningChip
        case .permissionsMissing:
            permissionsWarningChip
        case .noAudioWarning:
            noAudioWarningChip
        }
    }

    /// Shown when fn was held but no audio crossed the noise gate. The
    /// click target opens Settings — bumping Mic Sensitivity up is the
    /// cure for "fn does nothing on quiet speech" complaints.
    private var noAudioWarningChip: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("VoiceFlow.OpenSettings"),
                object: nil
            )
        } label: {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Quiet")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(red: 1.0, green: 0.85, blue: 0.55))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.white.opacity(0.14))
                )

                Text("Didn't catch that — adjust Mic Sensitivity")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .chipGlass()
        }
        .buttonStyle(.plain)
        .help("Open Settings to adjust Mic Sensitivity")
    }

    // MARK: Idle — tiny capsule with VoiceFlow logo + hover-revealed gear

    /// Idle layout — Run Log button on the left, main pill centered,
    /// Settings gear on the right. Both side buttons reveal on hover with
    /// a spring anchored toward the center pill, so they appear to spring
    /// OUT of the chip rather than popping into existence.
    ///
    /// Symmetry isn't just aesthetic — it puts the main pill at true screen
    /// center regardless of hover state, since the side buttons are
    /// equal-weight rendered (opacity-toggled) on both sides.
    ///
    /// Hover detection sits on the OUTER HStack with `.contentShape`.
    /// Side buttons are always rendered so HStack bounds stay stable
    /// across hover transitions — without this, moving the mouse into
    /// the gap between pill and a button would unmount it (because
    /// neither child's onHover would fire), causing flicker.
    private var idleChip: some View {
        HStack(spacing: 6) {
            // Left button — Run Log (clock+arrow icon, matches the sidebar)
            Button {
                NotificationCenter.default.post(name: Notification.Name("VoiceFlow.OpenRunLog"), object: nil)
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(Color.chipFill)
                    )
                    .overlay(
                        Circle().strokeBorder(Color.chipBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Open Run Log")
            .opacity(hovering ? 1 : 0)
            .scaleEffect(hovering ? 1 : 0.4, anchor: .trailing)
            .offset(x: hovering ? 0 : 8)
            .allowsHitTesting(hovering)

            // Main pill. Two visual modes:
            //  • Hovered    → full 58×22 capsule with waveform glyph (clickable
            //                 if permissions are missing, routes to onboarding)
            //  • Not hovered → slim 36×4 bar — barely there, drag-only. Stays
            //                 out of the way of click targets at the dock area.
            // Hit area is fixed via the outer HStack frame so hover detection
            // stays reliable on the slim variant.
            Button {
                if !model.hasAllPermissions {
                    NotificationCenter.default.post(
                        name: Notification.Name("VoiceFlow.OpenOnboardingPermissions"),
                        object: nil
                    )
                }
            } label: {
                HStack(spacing: 0) {
                    if hovering {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .transition(.opacity)
                    }
                }
                .frame(
                    width:  hovering ? 64 : 40,
                    height: hovering ? 24 : 4
                )
                // Solid dark-grey fill in BOTH variants — no transparency.
                // Visible on white backgrounds (as a dark shape) AND on
                // dark backgrounds (the white border outlines it).
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.chipFill)
                )
                .overlay(
                    // Border on slim AND hovered. Slim chip is 4pt tall
                    // so use a thinner stroke; full chip gets the standard
                    // 1pt for clean edge definition.
                    Capsule(style: .continuous)
                        .strokeBorder(
                            Color.chipBorder,
                            lineWidth: hovering ? 1 : 0.5
                        )
                )
                .overlay(alignment: .topTrailing) {
                    if !model.hasAllPermissions && hovering {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 7, height: 7)
                            .overlay(
                                Circle().stroke(Color.black, lineWidth: 1.5)
                            )
                            .offset(x: 2, y: -2)
                            .transition(.scale.combined(with: .opacity))
                    } else if !model.hasAllPermissions && !hovering {
                        // Slim mode: tint the slim bar orange instead of
                        // showing a separate dot — same signal, fits the
                        // small footprint.
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: 40, height: 4)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(model.hasAllPermissions ? "" : "Click to fix permissions")
            .animation(.easeInOut(duration: 0.2), value: model.hasAllPermissions)

            // Right button — Settings
            Button {
                NotificationCenter.default.post(name: Notification.Name("VoiceFlow.OpenSettings"), object: nil)
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(Color.chipFill)
                    )
                    .overlay(
                        Circle().strokeBorder(Color.chipBorder, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Open Settings")
            .opacity(hovering ? 1 : 0)
            .scaleEffect(hovering ? 1 : 0.4, anchor: .leading)
            .offset(x: hovering ? 0 : -8)
            .allowsHitTesting(hovering)
        }
        // Fixed hit area — bigger than ANY visible state so the cursor
        // can find the slim 4px chip easily. Also stabilizes hover
        // detection: bounds don't change as the chip morphs between
        // slim and full, so hover doesn't flicker on/off mid-transition.
        .frame(width: 180, height: 30)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: hovering)
    }

    // MARK: Recording — pill with live waveform

    private var recordingChip: some View {
        ChipWaveform(audioLevel: model.audioLevel)
            .frame(width: 100, height: 24)
            .chipGlass()
    }

    // MARK: Processing — pill with shimmer

    private var processingChip: some View {
        ChipShimmer()
            .frame(width: 100, height: 24)
            .chipGlass()
    }

    // MARK: Warning — bigger pill with Tip badge + dismiss button

    /// Shown after a dictation that couldn't be injected into a text
    /// input. Transcript is already on the clipboard at this point.
    /// Bigger and more present than the old single-line version — this
    /// surface is informational and should *read* like a notification,
    /// not a thin status pill.
    private var warningChip: some View {
        HStack(spacing: 10) {
            // Tip badge — soft purple to differentiate from recording
            // (waveform) and idle (logo) states.
            HStack(spacing: 4) {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Tip")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Color(red: 0.85, green: 0.70, blue: 1.0))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.white.opacity(0.14))
            )

            Text("Click a textbox and use Cmd+V to paste")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Spacer(minLength: 4)

            // Dismiss — fires the same setIdle path as the auto-timer,
            // gives the user agency. Wispr Flow has the same pattern.
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("VoiceFlow.DismissChipWarning"),
                    object: nil
                )
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .chipGlass()
    }

    // MARK: Permissions warning — orange-tinted, click to open onboarding

    /// Fires when fn is pressed without all required permissions granted.
    /// Distinguished from the "no input field" warning (purple Tip badge)
    /// by an orange-tinted shield icon — orange is the universal "needs
    /// action" color in our palette and matches the passive idle dot.
    ///
    /// Entire capsule is clickable (button-shaped). Click → posts
    /// VoiceFlow.OpenOnboardingPermissions, which AppDelegate routes to
    /// the Permissions step of the onboarding wizard.
    private var permissionsWarningChip: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("VoiceFlow.OpenOnboardingPermissions"),
                object: nil
            )
        } label: {
            HStack(spacing: 10) {
                // Action badge — orange instead of purple to read as
                // "you need to do something" vs informational tip.
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Action")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Theme.accent.opacity(0.18))
                )

                Text("Grant permissions to dictate")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 4)

                // Visual affordance — chevron tells the user "this is
                // clickable" without needing a separate button.
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .chipGlass()
        }
        .buttonStyle(.plain)
        .help("Open onboarding to grant permissions")
    }
}

/// Mini waveform used inside the recording-state chip. 7 bars driven by
/// the same `audioLevel` scalar with static multipliers — same FreeFlow
/// pattern we use in the (now-silenced) notch overlay, but smaller so
/// it fits in a 22pt-tall capsule.
private struct ChipWaveform: View {
    let audioLevel: Float

    private static let barCount = 7
    private static let multipliers: [CGFloat] = [0.45, 0.65, 0.85, 1.0, 0.85, 0.65, 0.45]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<Self.barCount, id: \.self) { i in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: barHeight(for: i))
                    .animation(.spring(response: 0.18, dampingFraction: 0.85), value: audioLevel)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        let minH: CGFloat = 3
        let maxH: CGFloat = 14
        let amp = min(level * Self.multipliers[index], 1.0)
        return minH + (maxH - minH) * amp
    }
}

/// Self-driving processing animation. Shows a left-to-right shimmer
/// across 7 dim bars while waiting for the polish LLM response.
private struct ChipShimmer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { i in
                    let phase = sin(t * 4.0 - Double(i) * 0.4) * 0.5 + 0.5
                    Capsule()
                        .fill(Color.white.opacity(0.35 + phase * 0.5))
                        .frame(width: 2, height: 8)
                }
            }
        }
    }
}

// MARK: - HomeTimelineRow

/// One row in the Home page's date-grouped timeline. Hover-revealed
/// action cluster (copy + ellipsis menu) sits on the right and only
/// appears when the row is mouseover'd, keeping the resting state
/// uncluttered.
///
/// Why a separate struct (vs. a `func` builder): per-row hover state.
/// SwiftUI's `@State` lives per-View-instance; if we built rows from
/// a parent function, all rows would share one `@State` and only the
/// last-hovered one would reveal actions.
struct HomeTimelineRow: View {
    let summary: RunSummary
    let runStore: RunStore

    @State private var isHovering = false
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(DashboardStats.timeOnly(summary.createdAt))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.textTertiary)
                .frame(width: 64, alignment: .leading)

            Text(summary.previewText.isEmpty ? "—" : summary.previewText)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

            // Hover actions — copy + ellipsis menu. Opacity-toggled so
            // the row layout doesn't jump when actions appear.
            HStack(spacing: 6) {
                copyButton
                ellipsisMenu
            }
            .opacity(isHovering ? 1 : 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            // Subtle highlight on hover — gives the row mass when its
            // actions become interactive.
            isHovering
                ? Theme.canvas.opacity(0.6)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .alert("Delete this transcript?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                runStore.deleteRun(id: summary.id)
            }
        }
    }

    // MARK: Actions

    private var copyButton: some View {
        Button {
            copyTranscript()
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Copy transcript")
    }

    private var ellipsisMenu: some View {
        Menu {
            Button {
                NotificationCenter.default.post(
                    name: Notification.Name("VoiceFlow.RetryRun"),
                    object: nil,
                    userInfo: ["runID": summary.id]
                )
            } label: {
                Label("Retry transcript", systemImage: "arrow.clockwise")
            }
            .disabled(summary.status == .failed)

            Button {
                downloadAudio()
            } label: {
                Label("Download audio", systemImage: "arrow.down.circle")
            }

            Divider()

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete transcript", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: Action implementations

    private func copyTranscript() {
        // Load the full Run to get the un-truncated final text — the
        // RunSummary index might still hold an older 80-char-capped
        // value for runs saved before that limit was removed.
        let full = runStore.loadRun(id: summary.id)?.previewText ?? summary.previewText
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(full, forType: .string)
    }

    private func downloadAudio() {
        guard let run = runStore.loadRun(id: summary.id),
              let sourceURL = runStore.audioURL(for: run) else { return }

        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let stem = "VoiceFlow_\(formatter.string(from: summary.createdAt))"
        var dest = downloads.appendingPathComponent("\(stem).wav")
        var counter = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = downloads.appendingPathComponent("\(stem)_\(counter).wav")
            counter += 1
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
        } catch {
            print("HomeTimelineRow: download failed — \(error)")
        }
    }
}

// MARK: - Theme management

enum ThemeMode: String, CaseIterable {
    case light, dark

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark:  return "moon.fill"
        }
    }
}

/// Persists + publishes the active theme. SwiftUI views observe `mode`
/// and the root view applies `.preferredColorScheme(manager.colorScheme)`
/// so the entire window flips at once. All Theme tokens are dynamic
/// NSColors that resolve based on the effective appearance — flipping the
/// scheme paints every surface in one render pass.
@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()

    @Published var mode: ThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: "theme_mode")
        }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: "theme_mode") ?? ThemeMode.light.rawValue
        self.mode = ThemeMode(rawValue: stored) ?? .light
    }

    var colorScheme: ColorScheme {
        switch mode {
        case .light: return .light
        case .dark:  return .dark
        }
    }
}

/// Compact two-state toggle for the sidebar. Same shape language as the
/// rest of the chrome — pill background, hover-revealing nothing fancy,
/// just a clear "this is the active mode" indicator.
struct ThemeTogglePill: View {
    @ObservedObject var manager: ThemeManager

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ThemeMode.allCases, id: \.self) { mode in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        manager.mode = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode == .light ? "Light" : "Dark")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(manager.mode == mode ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(manager.mode == mode ? Theme.surfaceElevated : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.divider)
        )
    }
}

// MARK: - AnimatedDarkBackground (slow-flowing nebula on dark canvas)

/// Cinematic dark background — a near-black base with two large, heavily
/// blurred radial-gradient blobs orbiting slowly in opposite directions.
/// Approximates componentry.fun's "Closing Plasma" / fluid-motion look
/// using only SwiftUI primitives (no Metal, no shader).
///
/// Why blurred RadialGradients instead of an animated AngularGradient:
/// angular gradients on a flat surface produce visible "spoke" artifacts
/// that read as cheap. Layered radial blobs with heavy blur look like
/// slow nebula clouds — the eye reads it as depth, not rotation.
///
/// Performance:
///   - Two layers, both with .blur(radius: 60+) — offloaded to GPU.
///   - TimelineView(.animation) auto-pauses when window is occluded.
///   - Slow orbit (40-60s per loop) keeps frame-to-frame deltas tiny,
///     so the GPU can interpolate cheaply.
///
/// Color tuning: the two blob colors (deep indigo + plum) are hand-picked
/// to stay below ~25% luminance even at peak. White hero text on top
/// stays comfortably above 7:1 contrast — accessible by default.
struct AnimatedDarkBackground: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            // Two independent slow orbits in opposite directions. The
            // counter-rotation is what gives the "flowing" feel —
            // co-rotating blobs would just look like the whole canvas
            // is sliding, which is uncanny.
            let phase1 = (t / 22.0).truncatingRemainder(dividingBy: 1.0) * 2 * .pi
            let phase2 = (t / 30.0).truncatingRemainder(dividingBy: 1.0) * 2 * .pi + .pi

            // CRITICAL: blob centers expressed as UnitPoint (0..1, relative
            // to the parent's bounds) instead of fixed-size Circles + offset.
            // Previous version used Circle().frame(width: 560) — that fixed
            // child size made the ZStack claim 560×560 of layout space when
            // wrapped in .drawingGroup(), which then bled into the hero
            // card's height calculation and made it ~600pt tall. Using
            // UnitPoint with no fixed-size children, the ZStack inherits
            // the parent's size correctly.
            let center1 = UnitPoint(
                x: 0.45 + CGFloat(cos(phase1)) * 0.35,
                y: 0.50 + CGFloat(sin(phase1)) * 0.30
            )
            let center2 = UnitPoint(
                x: 0.55 + CGFloat(cos(phase2)) * 0.40,
                y: 0.50 + CGFloat(sin(phase2)) * 0.25
            )

            ZStack {
                // Base layer — near-black with a faint blue cast so the
                // colored blobs read as "glow" instead of "splotch".
                Color(red: 0.025, green: 0.025, blue: 0.040)

                // Blob 1 — deep indigo. RadialGradient fills available
                // space; the gradient's bright core is at center1 and
                // fades transparent toward the edges. Moving center1
                // slides the bright core around without resizing anything.
                RadialGradient(
                    colors: [
                        Color(red: 0.18, green: 0.22, blue: 0.70).opacity(0.65),
                        Color(red: 0.12, green: 0.15, blue: 0.50).opacity(0.30),
                        Color.clear
                    ],
                    center: center1,
                    startRadius: 5,
                    endRadius: 320
                )
                .blendMode(.screen)

                // Blob 2 — plum/magenta, slightly tighter spread, counter orbit.
                RadialGradient(
                    colors: [
                        Color(red: 0.55, green: 0.15, blue: 0.55).opacity(0.55),
                        Color(red: 0.40, green: 0.10, blue: 0.45).opacity(0.22),
                        Color.clear
                    ],
                    center: center2,
                    startRadius: 5,
                    endRadius: 280
                )
                .blendMode(.screen)

                // Subtle edge vignette — pulls focus to the text by
                // dimming the perimeter so the brightest blob doesn't
                // pull the eye away from the headline.
                RadialGradient(
                    colors: [Color.clear, Color.black.opacity(0.30)],
                    center: .center,
                    startRadius: 100,
                    endRadius: 500
                )
            }
        }
    }
}

extension View {
    /// Dark hero card with an animated nebula background. Drop-in
    /// replacement for `.themedHeroCard()` on any surface that wants
    /// motion. Keeps `.themedHeroCard()` available for the static
    /// callers (settings preview, etc.) that don't need flair.
    func themedAnimatedHeroCard() -> some View {
        self
            .background(
                AnimatedDarkBackground()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
            )
            .shadow(color: Theme.Shadow.elevated.color,
                    radius: Theme.Shadow.elevated.radius,
                    x: 0, y: Theme.Shadow.elevated.y)
    }
}

// MARK: - BorderBeam (animated traveling-light stroke)

/// ViewModifier that strokes the receiver's bounds with a rotating
/// angular gradient. The bright stop of the gradient slides around the
/// rectangle, producing a "beam of light traveling along the border"
/// effect — same look as componentry.fun's BorderBeam, no Metal needed.
///
/// Mechanism: a single `AngularGradient` with one bright stop at
/// `location = phase` and transparent stops on either side. Driving
/// `phase` from 0→1 with `TimelineView(.animation)` is what makes the
/// bright spot travel. macOS pauses TimelineView when the window is
/// occluded, so this is battery-respectful by default.
///
/// Why a ViewModifier and not a wrapper view: composes with any
/// existing background/overlay stack without requiring callers to
/// restructure their hierarchy.
struct BorderBeam: ViewModifier {
    var cornerRadius: CGFloat = 14
    var beamColor: Color = .cyan
    var lineWidth: CGFloat = 1.5
    /// Seconds per full revolution. Slower = calmer; we use 5s — fast
    /// enough to read as "alive", slow enough not to feel like an alert.
    var duration: Double = 5.0
    /// Width of the bright segment as a fraction of the perimeter. 0.15
    /// = comet with a tail; lower values = pinprick light.
    var beamWidth: Double = 0.15

    func body(content: Content) -> some View {
        content.overlay(
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let phase = (t / duration).truncatingRemainder(dividingBy: 1.0)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: beamStops(phase: phase)),
                            center: .center
                        ),
                        lineWidth: lineWidth
                    )
            }
            .allowsHitTesting(false) // never block clicks on the wrapped content
        )
    }

    /// Build the gradient stops so the bright peak is at `phase` with a
    /// transparent fall-off on both sides. We add wrap-around stops so
    /// the comet can cross the 0/1 seam without flickering.
    private func beamStops(phase: Double) -> [Gradient.Stop] {
        let half = beamWidth / 2
        let peak = phase
        let leftEdge  = peak - half
        let rightEdge = peak + half

        var stops: [Gradient.Stop] = [
            .init(color: beamColor.opacity(0), location: 0),
            .init(color: beamColor.opacity(0), location: max(0, leftEdge)),
            .init(color: beamColor,            location: max(0, min(1, peak))),
            .init(color: beamColor.opacity(0), location: min(1, rightEdge)),
            .init(color: beamColor.opacity(0), location: 1)
        ]
        // Wrap handling: when the comet straddles 0/1, mirror the bright
        // stop on the opposite end so it appears continuous. Without this
        // there's a visible blink each loop.
        if leftEdge < 0 {
            let wrapped = 1.0 + leftEdge
            stops.append(.init(color: beamColor.opacity(0), location: wrapped - 0.001))
            stops.append(.init(color: beamColor,            location: wrapped))
        }
        if rightEdge > 1 {
            let wrapped = rightEdge - 1.0
            stops.insert(.init(color: beamColor,            location: wrapped),     at: 0)
            stops.insert(.init(color: beamColor.opacity(0), location: wrapped + 0.001), at: 1)
        }
        return stops.sorted { $0.location < $1.location }
    }
}

extension View {
    func borderBeam(
        cornerRadius: CGFloat = 14,
        color: Color = .cyan,
        lineWidth: CGFloat = 1.5,
        duration: Double = 5.0,
        beamWidth: Double = 0.15
    ) -> some View {
        modifier(BorderBeam(
            cornerRadius: cornerRadius,
            beamColor: color,
            lineWidth: lineWidth,
            duration: duration,
            beamWidth: beamWidth
        ))
    }
}

// MARK: - PrismGradientHeader

/// Animated multi-color gradient surface — drop-in replacement for any
/// solid header rectangle. Approximates componentry.fun's "Dither Prism"
/// without a Metal shader: an `AngularGradient` rotated continuously
/// over time produces a slow-shifting prismatic field, and a soft
/// sparkles glyph layered on top reads as the focal point.
///
/// Pure SwiftUI — works on macOS 13. Same TimelineView budget rules as
/// BorderBeam apply: paused when the window is occluded.
struct PrismGradientHeader: View {
    var height: CGFloat = 80
    var cornerRadius: CGFloat = 10

    private let prismColors: [Color] = [
        Color(red: 0.55, green: 0.30, blue: 0.95),  // violet
        Color(red: 0.95, green: 0.40, blue: 0.65),  // pink
        Color(red: 1.00, green: 0.55, blue: 0.10),  // orange (Theme.accent)
        Color(red: 0.30, green: 0.80, blue: 0.95),  // cyan
        Color(red: 0.55, green: 0.30, blue: 0.95)   // violet (loop)
    ]

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            // 12s per full rotation — slow enough to feel ambient, not
            // disco. The eye notices the colors at the corners shifting
            // without ever feeling pulled-at.
            let angle = (t * 30).truncatingRemainder(dividingBy: 360)

            ZStack {
                AngularGradient(
                    gradient: Gradient(colors: prismColors),
                    center: .center,
                    angle: .degrees(angle)
                )
                // Soft white core in the center — gives the eye an anchor
                // and "lifts" the colors so they don't feel muddy.
                RadialGradient(
                    colors: [Color.white.opacity(0.35), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 50
                )
                // Sparkles glyph — system iconography for "premium".
                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.2), radius: 6, y: 1)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}

// MARK: - SidebarPremiumBlock

/// Sidebar upsell card that nudges users to add an OpenAI API key for
/// Hinglish + multilingual support.
///
/// Why the visual treatment is intentionally louder than SidebarStarBlock:
/// the GitHub star block is a community ask (low conversion stakes); this
/// one is the primary monetization-adjacent surface — without an OpenAI
/// key the app is English-only via Groq, and Hindi-speaking users churn
/// in 30 seconds if they don't see this exists.
///
/// Composition (top → bottom):
///   1. PrismGradientHeader — animated prism block, sparkles centered.
///      Approximates componentry.fun's "Dither Prism Hero" without Metal.
///   2. "Unlock Hinglish" headline + arrow.
///   3. Sub-line: "Hindi · Marathi · 100+ languages" — names users search.
///   4. Footer hint: "Add OpenAI key in Settings →".
///
/// The whole card is wrapped in `.borderBeam(...)` — a slow cyan comet
/// travels around the perimeter. Two animations layered (prism rotation
/// + border beam) tested at low frequencies (12s and 5s respectively)
/// stay below the perception threshold for "distracting". They register
/// as "this thing is alive" without pulling focus.
struct SidebarPremiumBlock: View {
    @State private var isHovered = false

    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: Notification.Name("VoiceFlow.SelectTab"),
                object: nil,
                userInfo: ["tab": "settings"]
            )
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Animated prism header — the "premium hero" of the card.
                PrismGradientHeader(height: 76, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 4) {
                        Text("Unlock Hinglish")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.accent)
                            .opacity(isHovered ? 1.0 : 0.6)
                            .offset(x: isHovered ? 2 : 0)
                            .animation(.easeOut(duration: 0.15), value: isHovered)
                    }

                    Text("Hindi · Marathi · 100+ languages")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textPrimary.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text("Add OpenAI key in Settings →")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Theme.accent.opacity(0.10),
                                Theme.accent.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                // Static accent border — replaces the traveling-beam
                // animation. The prism header above already provides
                // motion; a second moving element on the same card was
                // visually noisy. One animation per card is the cap.
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        .help("Add an OpenAI API key in Settings to unlock Hindi, Marathi, and 100+ other languages.")
    }
}

// MARK: - SidebarStarBlock

/// Compact GitHub star prompt for the sidebar. Different design from
/// the wide `StarRepoCard` — narrow column means we can't show avatars
/// or stargazer rows. Distilled to the essentials: live star count +
/// one-tap CTA. Whole block is itself the link target.
///
/// Why a separate component instead of resizing StarRepoCard: the wide
/// card has horizontal HStacks and avatar rows that don't compose into
/// a 180pt-wide column. Two intents → two components, both pulling from
/// the same `GitHubMetadataCache.shared` so the data stays coherent.
struct SidebarStarBlock: View {
    @ObservedObject private var github = GitHubMetadataCache.shared

    private let openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var body: some View {
        Button {
            openURL(GitHubMetadataCache.repoHTMLURL)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.accent)
                    Text(starCountLabel)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                }

                Text("Star on GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                // Recent stargazer avatars — overlapping circles (negative
                // HStack spacing). Capped at 4 because the sidebar is
                // narrow; "+N" badge follows when there are more.
                if !github.recentStargazers.isEmpty {
                    stargazerAvatarRow
                }

                Text("\(GitHubMetadataCache.repoOwner)/\(GitHubMetadataCache.repoName)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help("Open the VoiceFlow repo on GitHub — a star helps this project grow.")
        .task { github.refreshIfStale() }
    }

    /// Overlapping avatar row — visual proof that real people are starring
    /// the project. Each avatar is bordered with the surface color so
    /// the negative-spacing overlap reads cleanly.
    private var stargazerAvatarRow: some View {
        let visible = Array(github.recentStargazers.prefix(4))
        let extra = max(0, github.recentStargazers.count - visible.count)
        return HStack(spacing: -6) {
            ForEach(visible) { star in
                AsyncImage(url: star.user.avatarThumbnailUrl) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Circle().fill(Color.gray.opacity(0.18))
                    }
                }
                .frame(width: 18, height: 18)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Theme.surface, lineWidth: 1.5)
                )
                .help(star.user.login)
            }
            if extra > 0 {
                Text("+\(extra)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.leading, 8)
            }
        }
    }

    /// Star count label: shows "—" while loading first time, then the
    /// formatted count. Avoids a spinner — the block is glanceable
    /// chrome, not the focus of attention.
    private var starCountLabel: String {
        if let count = github.starCount {
            return count.formatted()
        }
        return "—"
    }
}

// MARK: - ScratchpadView

/// In-app dictation target. Solves the "where do I safely practice /
/// test dictation without it bleeding into Slack" problem that every
/// first-time user hits.
///
/// Implementation: rather than plumb a new injection path through
/// AppDelegate (would require touching the hot path), we observe the
/// RunStore and append new transcripts to the local text buffer as
/// they land. Pub-sub via @Published — zero coupling to the recorder.
///
/// Tradeoff: the transcript ALSO gets injected wherever the user's
/// external cursor is (standard VoiceFlow behavior). For Scratchpad
/// use, the user should leave the app focused (which also means the
/// TextInjector suppresses external injection — clean outcome). If
/// they alt-tab mid-dictation, they'll get the transcript in both
/// places, which is harmless.
struct ScratchpadView: View {
    @ObservedObject var runStore: RunStore

    @State private var text: String = ""
    @State private var lastSeenRunId: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header

                // Instruction card — only shown when scratchpad is empty.
                if text.isEmpty {
                    emptyStateCard
                }

                editor
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onReceive(runStore.$summaries) { summaries in
            // Append any new successful transcript to the scratchpad.
            // Seed on first render with the newest known id so we don't
            // replay history into the editor.
            guard let latest = summaries.first else { return }
            if lastSeenRunId == nil {
                lastSeenRunId = latest.id
                return
            }
            if latest.id != lastSeenRunId {
                let incoming = latest.previewText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !incoming.isEmpty {
                    if text.isEmpty {
                        text = incoming
                    } else {
                        text += "\n\n" + incoming
                    }
                }
                lastSeenRunId = latest.id
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Scratchpad")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textPrimary)
            Spacer()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Text("Clear")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(Theme.textSecondary)
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Hold")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textOnDark)
                HotkeyBadge(label: "fn")
                Text("and speak — your words land here.")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textOnDark)
            }
            Text("A safe place to practice dictation without it bleeding into Slack or your editor. Transcripts auto-append as you dictate.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textOnDark.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedHeroCard()
    }

    private var editor: some View {
        // ScratchpadTextView (NSViewRepresentable wrapping NSTextView) lets
        // us pin the textContainerInset to a known value, which we then
        // match exactly with the placeholder's padding. SwiftUI's plain
        // TextEditor doesn't expose textContainerInset, so the cursor
        // position depends on host OS defaults that we can't anchor to.
        ZStack(alignment: .topLeading) {
            ScratchpadTextView(text: $text)

            if text.isEmpty {
                // These padding values are the ONLY source of truth for
                // the placeholder offset. Whatever we set here, the
                // ScratchpadTextView's textContainerInset must match —
                // see ScratchpadTextView.placeholderInset.
                Text("Start dictating with fn from anywhere — or just type here. Your scratchpad auto-fills as transcripts come in.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.leading, ScratchpadTextView.placeholderInset.width)
                    .padding(.top, ScratchpadTextView.placeholderInset.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: 300)
        .padding(Theme.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }
}

// MARK: - ScratchpadTextView

/// NSTextView wrapper with a deterministic text origin. Exists because
/// SwiftUI's `TextEditor` has no API to set `textContainerInset`, which
/// means the cursor's draw position varies across macOS versions and we
/// can never make a placeholder line up with it via guesswork.
///
/// Single source of truth for the inset: `placeholderInset`. The Scratchpad
/// view reads this and uses it as `.padding(.leading: ..., .top: ...)` on
/// the placeholder text, guaranteeing pixel alignment with the cursor.
struct ScratchpadTextView: NSViewRepresentable {
    @Binding var text: String

    /// Single source of truth for text origin. Cursor will draw at exactly
    /// this offset from the editor's frame edge; placeholder uses the same
    /// values via SwiftUI .padding so they sit on top of each other.
    static let placeholderInset = CGSize(width: 8, height: 8)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = Self.placeholderInset
        // Line fragment padding is the OTHER hidden-but-real source of
        // horizontal offset. Zeroing it means the only horizontal offset
        // is textContainerInset.width — exactly what the placeholder
        // matches via .padding(.leading:).
        textView.textContainer?.lineFragmentPadding = 0
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.usesFontPanel = false
        textView.usesRuler = false
        textView.delegate = context.coordinator
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only update if it actually changed — otherwise we clobber the
        // cursor position and selection on every state-change of any
        // ancestor view.
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchpadTextView
        init(_ parent: ScratchpadTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
