import SwiftUI
import AppKit

// MARK: - Version helper

/// Single source of truth for the app version string surfaced in UI.
/// Reads from `Info.plist` (CFBundleShortVersionString), which the Xcode
/// build pipeline populates from `MARKETING_VERSION`. Avoids the bug we
/// kept hitting where the sidebar showed "v1.0.0" forever because someone
/// shipped a release without bumping the literal string.
enum VordiVersion {
    static var marketing: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }
    static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }
    /// "v0.5.0" form — what we render in chrome.
    static var userFacing: String { "v\(marketing)" }
}

// MARK: - Theme
// Core design tokens. Extended in DesignSystem.swift with new tokens derived
// from the Wispr Flow reference screenshots. See DesignSystem.swift for all
// new additions (interactive, searchHighlight, Layout, VFButton, etc.)

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

/// Themed key-recorder control for the Settings → Shortcuts pane. Shows the
/// current combo as badges, and on tap captures a new one via the shared
/// AppKit `HotkeyCaptureRepresentable`. Rejected captures surface inline.
private struct ThemedHotkeyRecorder: View {
    let action: HotkeyAction
    let binding: HotkeyBinding
    /// Returns an error string if the capture was rejected, nil on success.
    let commit: (HotkeyBinding) -> String?

    @State private var isRecording = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if isRecording {
                    Text("Press keys…")
                        .font(.vfCaption)
                        .foregroundColor(Theme.textSecondary)
                } else if binding.displayTokens.isEmpty {
                    Text("Unset")
                        .font(.vfCaption)
                        .foregroundColor(Theme.textSecondary)
                } else {
                    ForEach(Array(binding.displayTokens.enumerated()), id: \.offset) { _, token in
                        HotkeyBadge(label: token)
                    }
                }

                Image(systemName: isRecording ? "record.circle" : "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isRecording ? Theme.accent : Theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.sm, style: .continuous)
                    .fill(Theme.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.sm, style: .continuous)
                    .strokeBorder(isRecording ? Theme.accent : Theme.divider,
                                  lineWidth: isRecording ? 2 : 1)
            )
            .overlay(
                HotkeyCaptureRepresentable(
                    modifierOnly: action.isModifierOnly,
                    isRecording: $isRecording,
                    onCapture: { candidate in
                        errorText = commit(candidate)
                        isRecording = false
                    },
                    onCancel: { isRecording = false }
                )
                .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                isRecording.toggle()
                if isRecording { errorText = nil }
            }

            if let errorText {
                Text(errorText)
                    .font(.vfCaption)
                    .foregroundColor(.red)
                    .frame(maxWidth: 190, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
        }
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
                .vfClickableCursor()
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

/// Horizontal mic-level meter with an overlaid threshold tick.
///
/// Both `level` and `threshold` are in the same normalized 0...1 space
/// (see `MicrophoneProbe.normalizedThreshold(_:)` for the curve), so the
/// tick's position is directly comparable to the live fill — i.e. the
/// user can SEE whether their voice peaks past the threshold without
/// having to reason about raw 0.015 RMS values.
///
/// Color semantics: when the live level passes the threshold, the fill
/// switches from accent (orange) to success (green). Mirrors the floating
/// chip's "I heard you" state.
struct LevelMeterView: View {
    let level: Float        // 0...1, normalized
    let threshold: Float    // 0...1, normalized (same scale as level)
    let isActive: Bool

    private let trackHeight: CGFloat = 22
    private let segmentCount = 32

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let fillWidth = max(0, w * CGFloat(min(max(level, 0), 1)))
            let tickX = w * CGFloat(min(max(threshold, 0), 1))
            let aboveThreshold = level >= threshold && level > 0.02

            ZStack(alignment: .leading) {
                // Track — segmented for a hint of "level meter" texture
                // without going all the way to per-LED bars (those steal
                // visual attention from the threshold tick).
                HStack(spacing: 2) {
                    ForEach(0..<segmentCount, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.divider.opacity(0.6))
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: trackHeight)

                // Fill — single rounded rect over the track, masked to
                // current width. Color shifts when level > threshold so
                // the user gets unambiguous "yes this would record" feedback.
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(aboveThreshold ? Theme.success : Theme.accent)
                    .frame(width: fillWidth, height: trackHeight)
                    .opacity(isActive ? 1.0 : 0.55)
                    .animation(.easeOut(duration: 0.08), value: level)

                // Threshold tick. Tall enough to peek above/below the track
                // so it reads as a marker, not part of the bar itself.
                Rectangle()
                    .fill(Theme.textPrimary)
                    .frame(width: 2, height: trackHeight + 8)
                    .offset(x: max(0, tickX - 1), y: -4)

                // Tick caption — small dot label above the tick. Helps
                // first-time users understand "that bar = your threshold".
                Text("threshold")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.surface)
                    )
                    .offset(x: clampedLabelOffsetX(tickX, viewWidth: w), y: -trackHeight - 4)
                    .opacity(0.95)
            }
            .frame(height: trackHeight)
        }
        .frame(height: trackHeight + 14) // room for the floating label above
    }

    /// Keep the "threshold" label inside the meter horizontally — when
    /// the tick sits near the left/right edge, anchor the label so it
    /// doesn't clip off the card.
    private func clampedLabelOffsetX(_ tickX: CGFloat, viewWidth: CGFloat) -> CGFloat {
        let labelWidth: CGFloat = 60 // visual estimate
        let preferred = tickX - labelWidth / 2
        let minX: CGFloat = 0
        let maxX: CGFloat = max(0, viewWidth - labelWidth)
        return min(maxX, max(minX, preferred))
    }
}

private enum VoiceTransformKind: String, CaseIterable, Identifiable {
    case polish
    case rewrite
    case promptEngineer
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polish: return "Polish"
        case .rewrite: return "Rewrite"
        case .promptEngineer: return "Prompt Engineer"
        case .custom: return "Create your own"
        }
    }

    var shortDescription: String {
        switch self {
        case .polish: return "Clean grammar and filler words while keeping your voice."
        case .rewrite: return "Restructure rough thoughts into clearer prose."
        case .promptEngineer: return "Turn messy spoken intent into a structured AI prompt."
        case .custom: return "Build a custom transform for your own writing workflow."
        }
    }

    var detailDescription: String {
        switch self {
        case .polish:
            return "Polish keeps your phrasing close, removes filler, fixes punctuation, and makes dictated text easier to send."
        case .rewrite:
            return "Rewrite can tighten phrasing, reorder ideas, and add structure when your spoken draft needs stronger shape."
        case .promptEngineer:
            return "Prompt Engineer converts rambling spoken requirements into a clean prompt for ChatGPT, Claude, Cursor, or another AI tool."
        case .custom:
            return "Custom transforms will let you save reusable prompts for specific writing tasks."
        }
    }

    var mode: TranscriptProcessingMode? {
        switch self {
        case .polish: return .dictation
        case .rewrite: return .rewrite
        case .promptEngineer: return .promptEngineer
        case .custom: return nil
        }
    }

    var icon: String {
        switch self {
        case .polish: return "sparkles"
        case .rewrite: return "text.badge.checkmark"
        case .promptEngineer: return "wand.and.stars"
        case .custom: return "plus"
        }
    }

    var exampleBefore: String {
        switch self {
        case .polish, .rewrite:
            return "hey so about the deck i added some slides but im not sure if they go with your part maybe we should remove the market trends thing"
        case .promptEngineer:
            return "i need help writing product descriptions for a skincare brand. it should feel warm and concise and include what inputs i should provide"
        case .custom:
            return "Say what you want the transform to do, then save it as a reusable writing tool."
        }
    }

    var exampleAfter: String {
        switch self {
        case .polish:
            return "I added a few slides to the deck, but I am not sure they fit with your section. We may want to remove the market trends slide before sending it."
        case .rewrite:
            return "I updated the deck with new slides. Before we send it, can you review whether they fit your section? I think the market trends slide may be worth removing."
        case .promptEngineer:
            return """
            Goal: Create skincare product descriptions.

            Inputs available:
            - Product name
            - Ingredients
            - Target customer

            Output requirements:
            - Warm, concise, aspirational copy
            - Clear benefits without medical claims
            """
        case .custom:
            return "Custom transform output preview will appear here once this feature is connected."
        }
    }
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
    let onOpenFloatingNotes: () -> Void
    let onQuit: () -> Void

    @StateObject private var localDetector = LocalModelDetector.shared
    @ObservedObject private var themeManager = ThemeManager.shared
    /// Owned by the dashboard so the live mic meter inside Settings has
    /// a stable lifetime across sub-tab switches. Stops automatically on
    /// dashboard disappear.
    @StateObject private var microphoneProbe = MicrophoneProbe()

    private var isRecording: Bool { recordingState.isRecording }

    enum Tab: String, CaseIterable {
        case home       = "Home"
        case memory     = "Memory"
        case scratchpad = "Notes"
        case insights   = "Insights"
        case magicWords = "Magic Words"
        case transforms = "Transforms"
        case runLog     = "Run Log"
        case devMode    = "Dev Mode"
        case settings   = "Settings"

        var icon: String {
            switch self {
            case .home:       return "house"
            case .scratchpad: return "note.text"
            case .insights:   return "chart.bar.fill"
            case .memory:     return "brain.head.profile"
            case .magicWords: return "wand.and.stars"
            case .transforms: return "sparkles"
            case .runLog:     return "clock.arrow.circlepath"
            case .devMode:    return "hammer"
            case .settings:   return "gearshape"
            }
        }

        /// Whether this tab renders in the sidebar nav. Dev Mode stays
        /// routable, but hidden from the main product navigation.
        var isVisibleInSidebar: Bool {
            self != .devMode
        }
    }

    private enum SettingsPane: String, CaseIterable {
        case general
        case shortcuts
        case aiModels
        case agents
        case permissions
        case dataPrivacy
        case devMode
        case setup

        enum Group: String {
            case settings = "SETTINGS"
            case system = "SYSTEM"
        }

        var title: String {
            switch self {
            case .general: return "General"
            case .shortcuts: return "Shortcuts"
            case .aiModels: return "AI Models"
            case .agents: return "Connect Agents"
            case .permissions: return "Permissions"
            case .dataPrivacy: return "Data & Privacy"
            case .devMode: return "Dev Mode"
            case .setup: return "Setup"
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "Language, output, and feedback."
            case .shortcuts: return "Push-to-talk, hands-free, and exit keys."
            case .aiModels: return "Transcription, API keys, streaming, and model routing."
            case .agents: return "Let Claude, Cursor & Codex read your dictations."
            case .permissions: return "macOS access required for capture and typing."
            case .dataPrivacy: return "Run history and custom vocabulary."
            case .devMode: return "Beta access and developer routing."
            case .setup: return "Onboarding and app actions."
            }
        }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .shortcuts: return "keyboard"
            case .aiModels: return "brain.head.profile"
            case .agents: return "link.badge.plus"
            case .permissions: return "lock.shield"
            case .dataPrivacy: return "externaldrive"
            case .devMode: return "hammer"
            case .setup: return "gearshape"
            }
        }

        var group: Group {
            switch self {
            case .general, .shortcuts, .aiModels, .agents:
                return .settings
            case .permissions, .dataPrivacy, .devMode, .setup:
                return .system
            }
        }

        static let settingsGroup: [SettingsPane] = [.general, .shortcuts, .aiModels, .agents]
        static let systemGroup: [SettingsPane] = [.permissions, .dataPrivacy, .devMode, .setup]
    }

    // MARK: - Persisted state
    // All @State fields mirror UserDefaults and write back on change. This
    // keeps SwiftUI bindings simple at the cost of a few extra writes — fine
    // for a settings surface that changes at most a few times per session.

    @State private var selectedTab: Tab = .home
    @State private var preferredInsightTab: String? = nil
    @State private var selectedSettingsPane: SettingsPane = .general
    @ObservedObject private var hotkeys = HotkeySettingsStore.shared

    // General tab
    @State private var selectedLanguage: String = UserDefaults.standard.string(forKey: "language") ?? "hi"
    @State private var processingMode: String = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
    @State private var runLogEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "run_log_enabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "run_log_enabled")
    }()
    /// Whether the run log is bounded. Default OFF — unlimited history
    /// feeds Insights + the Memory tab. Toggle ON in Settings for users
    /// who want bounded disk usage. Stays in sync with `RunStore.isCapEnabled`.
    @State private var runLogCapped: Bool = {
        if UserDefaults.standard.object(forKey: "run_log_cap_enabled") == nil { return false }
        return UserDefaults.standard.bool(forKey: "run_log_cap_enabled")
    }()
    @State private var noiseGateThreshold: Double = {
        let stored = UserDefaults.standard.double(forKey: "noise_gate_threshold")
        return stored == 0 ? 0.015 : stored
    }()

    /// Custom vocabulary the user wants Whisper + the polish LLM to know
    /// about. Mirrors the same UserDefaults key as `UserVocabulary.rawString`
    /// so any code path reading the parsed list sees changes immediately
    /// (the textfield writes on every keystroke via .onChange).
    @State private var customVocabulary: String = UserDefaults.standard.string(forKey: UserVocabulary.userDefaultsKey) ?? ""

    // Settings tab
    @State private var provider: String = UserDefaults.standard.string(forKey: "transcription_provider") ?? TranscriptionProvider.groq.rawValue

    // Realtime streaming: off by default. When on, we pipe PCM16 @ 24 kHz
    // directly into OpenAI's Realtime API for lower perceived latency on
    // long dictations. Batch path remains the safety net.
    @State private var realtimeStreaming: Bool = UserDefaults.standard.bool(forKey: "realtime_streaming_enabled")
    // PROTOTYPE (Option B): type realtime partials straight into the focused app.
    @State private var liveInject: Bool = UserDefaults.standard.bool(forKey: LiveInjectionController.enabledKey)
    // On-device live preview (Apple STT) → notch. Works on any provider + hands-free.
    @State private var onDevicePreview: Bool = UserDefaults.standard.bool(forKey: AppleSpeechLivePreview.enabledKey)
    @State private var openAIKey: String = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var groqKey: String = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
    @State private var polishBackendId: String = UserDefaults.standard.string(forKey: PolishBackend.userDefaultsKey) ?? PolishBackend.defaultId
    @State private var feedbackSurfaceStyle: String = FeedbackSurfaceStyle.current.rawValue
    // Default to verbatim ("Original"). Matches the seed in
    // VordiApp.configureDefaultSettings — this fallback only fires
    // for the brief window before the seed runs, OR if a user manually
    // wipes the UserDefault. Either way, verbatim is the safe choice
    // since it's the only style that doesn't require an OpenAI key.
    @State private var outputMode: String = {
        let raw = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.verbatim.rawValue
        return raw == TranscriptOutputStyle.clean.rawValue ? TranscriptOutputStyle.translateEnglish.rawValue : raw
    }()
    @State private var showKeySaved = false
    /// "Want Hinglish + 100+ languages?" upgrade disclosure on the Groq
    /// tier. Persisted so the open/closed state survives view rebuilds.
    @State private var showOpenAIUpgrade: Bool = false
    /// "Advanced — use my own Groq key" disclosure. Hidden by default;
    /// power users find it when they need it.
    @State private var showAdvancedKeys: Bool = false
    @State private var isSettingsModalPresented: Bool = false
    @State private var selectedTransform: VoiceTransformKind? = nil
    @State private var pendingHomeDeleteRunID: UUID?
    @State private var isHomeInsightsCardHovered = false
    @State private var promptEngineerPromptDraft: String =
        PromptEngineerProfile.systemPrompt
    @State private var polishRuleStates: [PolishRule: Bool] =
        Dictionary(uniqueKeysWithValues: PolishRule.allCases.map { ($0, PolishRule.isEnabled($0)) })

    // MARK: - Static option lists

    private let languages: [(code: String, label: String)] = [
        ("hi", "Hindi"),
        ("en", "English"),
        ("auto", "Auto-detect")
    ]

    private let processingModes: [(id: String, label: String)] = [
        (TranscriptProcessingMode.dictation.rawValue, "Polish"),
        (TranscriptProcessingMode.rewrite.rawValue, "Rewrite"),
        (TranscriptProcessingMode.promptEngineer.rawValue, "Prompt Engineer")
    ]

    // User-facing labels are deliberately plain ("Original", "English output",
    // Output mode labels — communicate the output contract directly:
    //   Original   — raw transcription, no transformation
    //   English output — any language written in English letters
    //   Translate  — anything spoken gets translated to English
    // Internal raw values stay unchanged so existing UserDefaults parse cleanly.
    private let outputModes: [(id: String, label: String)] = [
        (TranscriptOutputStyle.verbatim.rawValue,         "Original"),
        (TranscriptOutputStyle.cleanHinglish.rawValue,    "English output"),
        (TranscriptOutputStyle.translateEnglish.rawValue, "Translate")
    ]

    /// Cloud polish options. Filtered by tier:
    ///   - Always includes Groq llama (free, works with embedded key)
    ///   - OpenAI options ONLY appear when the user has added an OpenAI key
    ///     (otherwise selecting them would just fail at request time)
    private var cloudPolishOptions: [(id: String, label: String)] {
        var opts: [(id: String, label: String)] = [
            (PolishBackend.defaultIdGroq,
             "Groq · GPT OSS 20B (fast cleanup)")
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
        ZStack {
            HStack(spacing: 0) {
                // Sidebar — cream bg, no hard divider, pill-style selection
                VStack(alignment: .leading, spacing: 16) {
                    // Brand mark
                    HStack(spacing: 10) {
                        VFBrandLogo(size: 32, variant: .automatic, cornerRadius: 7)
                        Text(AppBrand.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 4)

                    VStack(spacing: 2) {
                        // Sidebar shows user-facing tabs only. Memory is now a
                        // first-class product surface; Dev Mode remains hidden.
                        ForEach(Tab.allCases.filter(\.isVisibleInSidebar), id: \.self) { tab in
                            sidebarButton(tab)
                        }
                    }

                    Spacer()

                    // Theme toggle — light/dark, persisted via ThemeManager.
                    // Lives above the GitHub block so it's discoverable but
                    // not the first thing users see.
                    ThemeTogglePill(manager: themeManager)
                        .padding(.horizontal, 2)

                    // GitHub Star block — sidebar-sized, replaces the wide
                    // StarRepoCard that used to sit on Home. Same intent
                    // (drive-by stars + social proof) in the right surface.
                    SidebarStarBlock()

                    // Footer — subtle, aligned with the open-source positioning.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(VordiVersion.userFacing)
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
                    case .scratchpad:
                        ScratchpadView(
                            runStore: runStore,
                            onOpenFloatingNotes: onOpenFloatingNotes
                        )
                    case .insights:   InsightsView(runStore: runStore, initialTab: preferredInsightTab)
                    case .memory:     KnowledgeGraphView()
                    case .magicWords: MagicWordsSettingsView()
                    case .transforms: transformsContent
                    case .runLog:     RunLogView(runStore: runStore)
                    case .devMode:    DevModeSettingsView()
                    case .settings:   homeContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.mainContent)
            }

            if isSettingsModalPresented {
                settingsModalOverlay
            }

            if let transform = selectedTransform {
                transformDetailOverlay(transform)
            }

            if let pendingHomeDeleteRunID {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .onTapGesture { self.pendingHomeDeleteRunID = nil }
                VFConfirmDialog(
                    title: "Delete this transcript?",
                    message: "This removes the saved audio, transcript, and pipeline trace for this dictation.",
                    confirmLabel: "Yes, delete it",
                    onCancel: { self.pendingHomeDeleteRunID = nil },
                    onConfirm: {
                        runStore.deleteRun(id: pendingHomeDeleteRunID)
                        self.pendingHomeDeleteRunID = nil
                    }
                )
                .zIndex(30)
            }
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
        // specific tab. Settings is a modal overlay, not a content tab.
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("Vordi.SelectTab"))) { note in
            guard let raw = note.userInfo?["tab"] as? String else { return }
            switch raw {
            case "home":       selectedTab = .home
            case "scratchpad": selectedTab = .scratchpad
            case "insights":
                preferredInsightTab = "Usage"
                selectedTab = .insights
            case "memory":     selectedTab = .memory
            case "magicWords": selectedTab = .magicWords
            case "transforms": selectedTab = .transforms
            case "runLog":     selectedTab = .runLog
            case "devMode":    selectedTab = .devMode
            case "settings":   presentSettingsModal()
            default: break
            }
        }
    }

    @ViewBuilder
    private func sidebarButton(_ tab: Tab) -> some View {
        let isActive = tab == .settings ? isSettingsModalPresented : selectedTab == tab

        Button {
            if tab == .settings {
                presentSettingsModal()
            } else {
                if tab == .insights {
                    preferredInsightTab = "Usage"
                }
                selectedTab = tab
            }
        } label: {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(isActive ? Theme.sidebarActiveFill : Color.clear)
            )
            .contentShape(Rectangle())
            .foregroundColor(isActive ? Theme.textPrimary : Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .vfClickableCursor()
    }

    // MARK: - Transforms tab

    private var transformsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                transformsHeader
                transformsHero
                transformsGridHeader
                transformsGrid
            }
            .frame(maxWidth: 960, alignment: .leading)
            .padding(.horizontal, Theme.Layout.contentHPad)
            .padding(.top, 36)
            .padding(.bottom, 48)
        }
        .background(Theme.mainContent)
    }

    private var transformsHeader: some View {
        HStack(alignment: .center, spacing: Theme.Space.sm) {
            Text("Transforms")
                .font(.vfPageTitle)
                .foregroundColor(Theme.textPrimary)
            VFBadge(label: "Experimental", style: .experimental)
            Spacer(minLength: Theme.Space.xl)
            transformOutputToggles
        }
    }

    private var transformOutputToggles: some View {
        HStack(spacing: Theme.Space.md) {
            transformCompactToggle(label: "English output", isOn: englishOutputToggleBinding)
            transformCompactToggle(label: "Translate", isOn: translateOutputToggleBinding)
        }
    }

    private func transformCompactToggle(label: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Text(label)
                .font(.vfCalloutMedium)
                .foregroundColor(Theme.textPrimary)
            VFSwitch(isOn: isOn)
        }
        .padding(.leading, Theme.Space.md)
        .padding(.trailing, Theme.Space.sm)
        .padding(.vertical, Theme.Space.sm)
        .background(
            Capsule(style: .continuous)
                .fill(Theme.compactToggleFill)
        )
    }

    private var transformsHero: some View {
        ZStack(alignment: .trailing) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Text("Transform works anywhere you write")
                        .font(.system(size: 26, weight: .semibold, design: .serif))
                        .foregroundColor(Theme.textOnDark)
                    Text("Apply a Transform to rewrite, clean up, or restructure text after you dictate.")
                        .font(.vfBody)
                        .foregroundColor(Theme.textOnDarkSecondary)
                        .lineSpacing(3)
                        .frame(maxWidth: 420, alignment: .leading)
                    transformHeroActions
                        .padding(.top, Theme.Space.md)
                }
                Spacer(minLength: 0)
                transformHeroIconCloud
            }
            .padding(Theme.Space.xxl)
        }
        .frame(minHeight: 172)
        .background {
            VFBlueMeshHeroBackground()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.hero, style: .continuous)
                .strokeBorder(Theme.dividerStrong, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.elevated.color,
                radius: Theme.Shadow.elevated.radius,
                x: 0,
                y: Theme.Shadow.elevated.y)
    }

    private var transformHeroActions: some View {
        HStack(spacing: Theme.Space.xl) {
            Button {
                selectedTransform = .polish
            } label: {
                Text("Try it out")
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textPrimary)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .fill(Theme.surfaceElevated)
                    )
            }
            .buttonStyle(.plain)
            .vfClickableCursor()

            Button {
                selectedTransform = .promptEngineer
            } label: {
                Text("How it works")
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textOnDark)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
        }
    }

    private var transformHeroIconCloud: some View {
        TransformHeroAppIconCloud()
            .frame(width: 240, height: 132)
            .clipped()
    }

    private struct TransformHeroAppIconCloud: View {
        private struct Placement {
            let x: CGFloat
            let y: CGFloat
            let diameter: CGFloat
            let iconSize: CGFloat
        }

        private let placements: [Placement] = [
            Placement(x: 42, y: -38, diameter: 48, iconSize: 29),
            Placement(x: 92, y: -30, diameter: 48, iconSize: 29),
            Placement(x: -12, y: -2, diameter: 44, iconSize: 27),
            Placement(x: 44, y: 3, diameter: 44, iconSize: 27),
            Placement(x: 96, y: 6, diameter: 44, iconSize: 27),
            Placement(x: -54, y: 38, diameter: 42, iconSize: 25),
            Placement(x: 8, y: 42, diameter: 42, iconSize: 25),
            Placement(x: 68, y: 40, diameter: 42, iconSize: 25)
        ]

        private var icons: [TransformHeroAppIconDescriptor] {
            Array(TransformHeroAppIconResolver.resolvedIcons.prefix(placements.count))
        }

        var body: some View {
            ZStack {
                ForEach(icons.indices, id: \.self) { index in
                    let icon = icons[index]
                    let placement = placements[index]
                    TransformHeroAppIconTile(
                        name: icon.name,
                        image: icon.image,
                        diameter: placement.diameter,
                        iconSize: placement.iconSize
                    )
                    .offset(x: placement.x, y: placement.y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .accessibilityLabel("Apps where transforms work")
        }
    }

    private struct TransformHeroAppIconTile: View {
        let name: String
        let image: NSImage
        let diameter: CGFloat
        let iconSize: CGFloat

        var body: some View {
            ZStack {
                Circle()
                    .fill(Theme.textOnDark.opacity(0.16))
                    .overlay(
                        Circle()
                            .strokeBorder(Theme.textOnDark.opacity(0.20), lineWidth: 2)
                    )

                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: iconSize * 0.20, style: .continuous))
            }
            .frame(width: diameter, height: diameter)
            .help(name)
        }
    }

    private struct TransformHeroAppIconDescriptor: Identifiable {
        let id: String
        let name: String
        let image: NSImage
    }

    private struct TransformHeroAppIconCandidate {
        let id: String
        let displayName: String
        let bundleIDs: [String]
        let appNames: [String]
    }

    private enum TransformHeroAppIconResolver {
        static let resolvedIcons: [TransformHeroAppIconDescriptor] = candidates.compactMap { candidate in
            guard let image = icon(for: candidate) else { return nil }
            return TransformHeroAppIconDescriptor(
                id: candidate.id,
                name: candidate.displayName,
                image: image
            )
        }

        private static let candidates: [TransformHeroAppIconCandidate] = [
            TransformHeroAppIconCandidate(
                id: "claude",
                displayName: "Claude",
                bundleIDs: ["com.anthropic.claude", "com.anthropic.Claude", "com.anthropic.claudefordesktop"],
                appNames: ["Claude"]
            ),
            TransformHeroAppIconCandidate(
                id: "cursor",
                displayName: "Cursor",
                bundleIDs: ["com.todesktop.230313mzl4w4u92", "com.cursor.Cursor"],
                appNames: ["Cursor"]
            ),
            TransformHeroAppIconCandidate(
                id: "copilot",
                displayName: "Copilot",
                bundleIDs: ["com.microsoft.copilot", "com.microsoft.Copilot"],
                appNames: ["Microsoft Copilot", "Copilot"]
            ),
            TransformHeroAppIconCandidate(
                id: "notes",
                displayName: "Notes",
                bundleIDs: ["com.apple.Notes"],
                appNames: ["Notes"]
            ),
            TransformHeroAppIconCandidate(
                id: "whatsapp",
                displayName: "WhatsApp",
                bundleIDs: ["net.whatsapp.WhatsApp", "WhatsApp"],
                appNames: ["WhatsApp"]
            ),
            TransformHeroAppIconCandidate(
                id: "slack",
                displayName: "Slack",
                bundleIDs: ["com.tinyspeck.slackmacgap"],
                appNames: ["Slack"]
            ),
            TransformHeroAppIconCandidate(
                id: "gmail",
                displayName: "Gmail",
                bundleIDs: ["com.google.Gmail"],
                appNames: ["Gmail", "Mail for Gmail"]
            ),
            TransformHeroAppIconCandidate(
                id: "linkedin",
                displayName: "LinkedIn",
                bundleIDs: ["com.linkedin.LinkedIn"],
                appNames: ["LinkedIn"]
            ),
            TransformHeroAppIconCandidate(
                id: "codex",
                displayName: "Codex",
                bundleIDs: ["com.openai.codex", "com.openai.Codex"],
                appNames: ["Codex"]
            ),
            TransformHeroAppIconCandidate(
                id: "chatgpt",
                displayName: "ChatGPT",
                bundleIDs: ["com.openai.chat", "com.openai.chatgpt"],
                appNames: ["ChatGPT"]
            ),
            TransformHeroAppIconCandidate(
                id: "chrome",
                displayName: "Google Chrome",
                bundleIDs: ["com.google.Chrome"],
                appNames: ["Google Chrome"]
            ),
            TransformHeroAppIconCandidate(
                id: "vscode",
                displayName: "Visual Studio Code",
                bundleIDs: ["com.microsoft.VSCode"],
                appNames: ["Visual Studio Code"]
            )
        ]

        private static func icon(for candidate: TransformHeroAppIconCandidate) -> NSImage? {
            for bundleID in candidate.bundleIDs {
                if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
                   let icon = sizedIcon(for: url) {
                    return icon
                }
            }

            for appName in candidate.appNames {
                for root in applicationRoots {
                    let url = root.appendingPathComponent("\(appName).app")
                    if FileManager.default.fileExists(atPath: url.path),
                       let icon = sizedIcon(for: url) {
                        return icon
                    }
                }
            }

            return nil
        }

        private static var applicationRoots: [URL] {
            [
                URL(fileURLWithPath: "/Applications"),
                URL(fileURLWithPath: "/System/Applications"),
                FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
            ]
        }

        private static func sizedIcon(for url: URL) -> NSImage? {
            let icon = (NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage)
                ?? NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 64, height: 64)
            return icon
        }
    }

    private var transformsGridHeader: some View {
        HStack(alignment: .center) {
            Text("My Transforms")
                .font(.vfSectionTitle)
                .foregroundColor(Theme.textPrimary)
            Spacer()
            VFButton(title: "Reset to Default", icon: "arrow.counterclockwise", style: .secondary, isCompact: true) {
                resetTransforms()
            }
            VFButton(title: "Add New", icon: "plus", style: .primary, isCompact: true) {
                selectedTransform = .custom
            }
        }
    }

    private var transformsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 280), spacing: Theme.Space.md)],
            alignment: .leading,
            spacing: Theme.Space.md
        ) {
            ForEach(VoiceTransformKind.allCases) { transform in
                transformCard(transform)
            }
        }
    }

    private func transformCard(_ transform: VoiceTransformKind) -> some View {
        let isActive = isTransformActive(transform)

        return Button {
            selectTransform(transform)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                HStack {
                    Image(systemName: transform.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(isActive ? Theme.interactive : Theme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(isActive ? Theme.interactiveSoft : Theme.surface))
                    Spacer()
                    if isActive {
                        VFBadge(label: "Active", style: .promo)
                    }
                }
                Spacer(minLength: 0)
                Text(transform.title)
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textPrimary)
                Text(transform.shortDescription)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Theme.Space.xl)
            .frame(minHeight: 154, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isActive ? Theme.interactive.opacity(0.42) : Theme.divider, lineWidth: isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
    }

    private var englishOutputToggleBinding: Binding<Bool> {
        Binding(
            get: { outputMode == TranscriptOutputStyle.cleanHinglish.rawValue },
            set: { isOn in
                setOutputMode(isOn ? .cleanHinglish : .verbatim)
            }
        )
    }

    private var translateOutputToggleBinding: Binding<Bool> {
        Binding(
            get: {
                outputMode == TranscriptOutputStyle.translateEnglish.rawValue
                    || outputMode == TranscriptOutputStyle.clean.rawValue
            },
            set: { isOn in
                if isOn {
                    setOutputMode(.translateEnglish)
                } else if outputMode == TranscriptOutputStyle.translateEnglish.rawValue
                            || outputMode == TranscriptOutputStyle.clean.rawValue {
                    setOutputMode(.verbatim)
                }
            }
        )
    }

    private func polishRuleBinding(_ rule: PolishRule) -> Binding<Bool> {
        Binding(
            get: { polishRuleStates[rule] ?? PolishRule.isEnabled(rule) },
            set: { isOn in
                polishRuleStates[rule] = isOn
                PolishRule.set(rule, isEnabled: isOn)
            }
        )
    }

    private func transformModeToggleBinding(_ transform: VoiceTransformKind) -> Binding<Bool> {
        Binding(
            get: { isTransformActive(transform) },
            set: { isOn in
                guard let mode = transform.mode else { return }
                setProcessingMode(isOn ? mode : .dictation)
            }
        )
    }

    private func setOutputMode(_ style: TranscriptOutputStyle) {
        outputMode = style.rawValue
        UserDefaults.standard.set(style.rawValue, forKey: "output_mode")
    }

    private func setProcessingMode(_ mode: TranscriptProcessingMode) {
        processingMode = mode.rawValue
        UserDefaults.standard.set(mode.rawValue, forKey: "processing_mode")
    }

    private func isTransformActive(_ transform: VoiceTransformKind) -> Bool {
        switch transform {
        case .polish:
            return processingMode == TranscriptProcessingMode.dictation.rawValue
        case .rewrite:
            return processingMode == TranscriptProcessingMode.rewrite.rawValue
        case .promptEngineer:
            return processingMode == TranscriptProcessingMode.promptEngineer.rawValue
        case .custom:
            return false
        }
    }

    private func selectTransform(_ transform: VoiceTransformKind) {
        selectedTransform = transform
    }

    private func resetTransforms() {
        setProcessingMode(.dictation)
        setOutputMode(.verbatim)
        resetPolishRules()
        promptEngineerPromptDraft = PromptEngineerProfile.defaultSystemPrompt
        UserDefaults.standard.removeObject(forKey: PromptEngineerProfile.userDefaultsKey)
    }

    private func transformDetailOverlay(_ transform: VoiceTransformKind) -> some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    selectedTransform = nil
                }

            transformDetailPanel(transform)
                .transition(.scale(scale: 0.985).combined(with: .opacity))
        }
        .zIndex(18)
        .onExitCommand {
            selectedTransform = nil
        }
    }

    private func transformDetailPanel(_ transform: VoiceTransformKind) -> some View {
        HStack(spacing: 0) {
            transformDetailSidebar(transform)
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)
            transformDetailMain(transform)
        }
        .frame(width: 920, height: 600, alignment: .top)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.elevated.color,
                radius: Theme.Shadow.elevated.radius,
                x: 0,
                y: Theme.Shadow.elevated.y)
    }

    private func transformDetailSidebar(_ transform: VoiceTransformKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            Text(transform.title)
                .font(.custom("Georgia", size: 32))
                .foregroundColor(Theme.textPrimary)

            HStack(spacing: Theme.Space.sm) {
                Image(systemName: transform.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isTransformActive(transform) ? Theme.interactive : Theme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(isTransformActive(transform) ? Theme.interactiveSoft : Theme.secondaryButtonFill)
                    )
                Text(isTransformActive(transform) ? "Default transform" : "Available transform")
                    .font(.vfCalloutMedium)
                    .foregroundColor(Theme.textSecondary)
            }

            Text(transform.detailDescription)
                .font(.vfBody)
                .foregroundColor(Theme.textPrimary)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Example of transformed text")
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textPrimary)
                Text(transform.exampleBefore)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textSecondary)
                    .strikethrough(transform != .custom, color: Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                transformExampleOutput(transform)
            }

            Spacer()
        }
        .padding(Theme.Space.xxl)
        .frame(width: 316)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surfaceElevated)
    }

    private func transformExampleOutput(_ transform: VoiceTransformKind) -> some View {
        Text(transform.exampleAfter)
            .font(.vfCalloutMedium)
            .foregroundColor(transform == .custom ? Theme.textSecondary : Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(transform == .custom ? Theme.Space.md : 4)
            .background(
                RoundedRectangle(cornerRadius: transform == .custom ? Theme.RadiusExtra.input : 5, style: .continuous)
                    .fill(transform == .custom ? Theme.surface : Theme.searchHighlight.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: transform == .custom ? Theme.RadiusExtra.input : 5, style: .continuous)
                    .strokeBorder(transform == .custom ? Theme.divider : Color.clear, lineWidth: 1)
            )
    }

    private func transformDetailMain(_ transform: VoiceTransformKind) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                HStack {
                    Spacer()
                    Text("Autosave On")
                        .font(.vfCalloutMedium)
                        .foregroundColor(Theme.textSecondary)
                    Button {
                        resetTransform(transform)
                    } label: {
                        HStack(spacing: Theme.Space.sm) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset to Default")
                        }
                        .font(.vfBodyMedium)
                        .foregroundColor(Theme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .vfClickableCursor()
                }

                switch transform {
                case .polish, .rewrite:
                    transformModeSection(transform)
                    transformRulesSection(transform)
                case .promptEngineer:
                    transformModeSection(transform)
                    transformRulesSection(transform)
                    promptEngineerEditorSection
                case .custom:
                    customTransformPlaceholder
                }
            }
            .padding(Theme.Space.xxl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.mainContent)
    }

    private func transformModeSection(_ transform: VoiceTransformKind) -> some View {
        VStack(spacing: 0) {
            transformRuleRow(
                title: "Enable \(transform.title)",
                description: transformModeDescription(transform)
            ) {
                VFSwitch(isOn: transformModeToggleBinding(transform))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func transformModeDescription(_ transform: VoiceTransformKind) -> String {
        switch transform {
        case .polish:
            return "Use Polish as the default transform when you release fn."
        case .rewrite:
            return "Use Rewrite as the default transform when you release fn."
        case .promptEngineer:
            return "Use Prompt Engineer as the default transform when you release fn."
        case .custom:
            return "Custom transforms are not available yet."
        }
    }

    private func transformRulesSection(_ transform: VoiceTransformKind) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack {
                Text("Output and model")
                    .font(.vfBodyMedium)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                VFDropdown(
                    options: polishOptions.map { (id: $0.id, label: compactPolishLabel($0.label)) },
                    selection: $polishBackendId,
                    width: 220
                )
                .onChange(of: polishBackendId) { newValue in
                    UserDefaults.standard.set(newValue, forKey: PolishBackend.userDefaultsKey)
                }
            }

            VStack(spacing: 0) {
                transformRuleRow(
                    title: "English output",
                    description: "Write Hindi, Marathi, or mixed speech in English letters without translating."
                ) {
                    VFSwitch(isOn: englishOutputToggleBinding)
                }
                transformRuleDivider
                transformRuleRow(
                    title: "Translate to English",
                    description: "Translate non-English speech into English."
                ) {
                    VFSwitch(isOn: translateOutputToggleBinding)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                    .fill(Theme.surface)
            )

            if transform == .polish {
                polishRulesSection
            }
        }
    }

    private var polishRulesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text("Rules for Polish")
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)

            VStack(spacing: 0) {
                ForEach(Array(PolishRule.allCases.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 {
                        transformRuleDivider
                    }
                    transformRuleRow(
                        title: rule.title,
                        description: rule.description
                    ) {
                        VFSwitch(isOn: polishRuleBinding(rule))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                    .fill(Theme.surface)
            )
        }
    }

    private var transformRuleDivider: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.leading, Theme.Space.xl)
    }

    private func transformRuleRow<Control: View>(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: Theme.Space.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.vfBody)
                    .foregroundColor(Theme.textPrimary)
                Text(description)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Theme.Space.lg)
            control()
        }
        .padding(.horizontal, Theme.Space.xl)
        .frame(minHeight: 72)
    }

    private var promptEngineerEditorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Customize prompt")
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            TextEditor(text: $promptEngineerPromptDraft)
                .font(.system(size: 13))
                .foregroundColor(Theme.textPrimary)
                .padding(Theme.Space.md)
                .frame(minHeight: 286)
                .background(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                        .fill(Theme.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                        .strokeBorder(Theme.dividerStrong, lineWidth: 1)
                )
                .onChange(of: promptEngineerPromptDraft) { newValue in
                    UserDefaults.standard.set(newValue, forKey: PromptEngineerProfile.userDefaultsKey)
                }
            Text("This prompt is used by Prompt Engineer before it creates the final AI prompt.")
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private var customTransformPlaceholder: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Create your own")
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            Text("Custom transforms need saved prompt templates and shortcut routing. This card is visible now so the surface matches the product direction without pretending the workflow is ready.")
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VFButton(title: "Coming soon", icon: "plus", style: .secondary, isCompact: true, isDisabled: true) {}
        }
        .padding(Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func resetTransform(_ transform: VoiceTransformKind) {
        switch transform {
        case .polish:
            setProcessingMode(.dictation)
            resetPolishRules()
        case .rewrite:
            setProcessingMode(.rewrite)
        case .promptEngineer:
            setProcessingMode(.promptEngineer)
            promptEngineerPromptDraft = PromptEngineerProfile.defaultSystemPrompt
            UserDefaults.standard.removeObject(forKey: PromptEngineerProfile.userDefaultsKey)
        case .custom:
            break
        }
    }

    private func resetPolishRules() {
        let resetStates = Dictionary(uniqueKeysWithValues: PolishRule.allCases.map { rule in
            PolishRule.set(rule, isEnabled: true)
            return (rule, true)
        })
        polishRuleStates = resetStates
    }

    // MARK: - Home tab

    private enum HomeLayout {
        static let maxContentWidth: CGFloat = Theme.Layout.appCaptureWidth
            - Theme.Layout.sidebarWidth
            - (Theme.Layout.contentHPad * 2)
        static let insightColumnWidth: CGFloat = 250
        static let columnGap: CGFloat = Theme.Space.xl
        static let timelinePreviewLimit = 48
        static var primaryColumnWidth: CGFloat {
            maxContentWidth - insightColumnWidth - columnGap
        }
    }

    /// Home layout, Wispr Flow-inspired:
    /// - Personalized greeting with hotkey badge
    /// - Dark hero card ("Hold fn to dictate")
    /// - Right insight card — live from RunStore, routes to Insights
    /// - Recent dictations timeline
    ///
    /// Deeper settings live under the Settings tab. Home stays light and
    /// glanceable — the thing users see first shouldn't be a config dump.
    /// The measured wide layout keeps the transcript timeline in the left
    /// column so the right side remains intentional whitespace below Insights.
    private var homeContent: some View {
        ScrollView {
            homeMeasuredLayout
                .frame(maxWidth: HomeLayout.maxContentWidth, alignment: .topLeading)
                .padding(.horizontal, Theme.Layout.contentHPad)
                .padding(.top, Theme.Layout.contentVPad)
                .padding(.bottom, 48)
                // Center the capped content block on wide screens instead of
                // pinning it left (which left a big empty gutter on the right).
                // `.top` = horizontal-center, matching NotesWorkspaceView.
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Theme.mainContent)
    }

    private var homeMeasuredLayout: some View {
        let stats = ComputedStats.compute(from: runStore.summaries)

        return VStack(alignment: .leading, spacing: Theme.Space.xl) {
            greetingBlock
                .frame(maxWidth: HomeLayout.primaryColumnWidth, alignment: .leading)

            HStack(alignment: .top, spacing: HomeLayout.columnGap) {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    heroCard
                    dictationsTimeline
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)

                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    statsCardCompact(stats: stats)
                    HomeVoiceProfileCard(stats: stats) {
                        preferredInsightTab = "Voice"
                        selectedTab = .insights
                    }
                }
                .frame(width: HomeLayout.insightColumnWidth, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Home — Greeting

    private var greetingBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Hey there, get back into the flow with")
                .font(.vfPageTitle)
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
        VFHeroBanner(
            segments: [
                .plain("Hold down "),
                .italic("fn"),
                .plain(" to dictate")
            ],
            bodyText: "Vordi works in every app. Hold fn, speak, release. Your words appear wherever your cursor is.",
            cta: ("See how it works", {
                NotificationCenter.default.post(
                    name: Notification.Name("Vordi.SelectTab"),
                    object: nil,
                    userInfo: ["tab": "transforms"]
                )
            })
        )
        .frame(minHeight: 176)
    }

    // MARK: Home — Stats (compact right-side card)

    /// Three stats stacked vertically in a single right-side card. Sized
    /// to sit beside the hero so the top of Home reads as one balanced
    /// row instead of a stacked stack of full-width blocks.
    private func statsCardCompact(stats: ComputedStats) -> some View {
        let streak = homeStreakMetric(stats: stats)

        return Button {
            preferredInsightTab = "Usage"
            selectedTab = .insights
        } label: {
            VStack(alignment: .leading, spacing: 22) {
                homeInsightMetric(value: "\(stats.totalWords)", label: "total words")
                homeInsightMetric(value: stats.averageWPM > 0 ? "\(stats.averageWPM)" : "—", label: "wpm")
                homeInsightMetric(value: streak.value, label: streak.label)
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, minHeight: 176, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isHomeInsightsCardHovered ? Theme.dividerStrong : Theme.divider, lineWidth: 1)
            )
            .shadow(color: isHomeInsightsCardHovered ? Theme.Shadow.card.color : Color.clear,
                    radius: Theme.Shadow.card.radius,
                    x: 0,
                    y: Theme.Shadow.card.y)
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHomeInsightsCardHovered = hovering
            }
        }
        .help("Open Insights")
        .accessibilityLabel("Open Insights")
    }

    private func homeStreakMetric(stats: ComputedStats) -> (value: String, label: String) {
        guard stats.currentStreakDays > 0 else { return ("—", "streak") }
        return (
            "\(stats.currentStreakDays)",
            "day\(stats.currentStreakDays == 1 ? "" : "s")"
        )
    }

    private func homeInsightMetric(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .monospacedDigit()
            Text(label)
                .font(.vfCallout)
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
        if homeTimelineSummaries.isEmpty {
            emptyTimelinePlaceholder
        } else {
            LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                ForEach(groupedSummaries, id: \.dayKey) { group in
                    dayBlock(label: group.label, rows: group.summaries)
                }

                if hasAdditionalHomeSummaries {
                    homeTimelineFooter
                }
            }
        }
    }

    private var homeTimelineSummaries: [RunSummary] {
        Array(runStore.summaries.prefix(HomeLayout.timelinePreviewLimit))
    }

    private var hasAdditionalHomeSummaries: Bool {
        runStore.summaries.count > HomeLayout.timelinePreviewLimit
    }

    private var emptyTimelinePlaceholder: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No dictations yet")
                .font(.vfBodyMedium)
                .foregroundColor(Theme.textPrimary)
            Text("Hold fn anywhere on your Mac and start speaking. Your transcripts will appear here.")
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
    }

    private func dayBlock(label: String, rows: [RunSummary]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            Text(label)
                .font(.vfDateHeader)
                .foregroundColor(Theme.textTertiary)
                .tracking(0.5)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(rows.indices, id: \.self) { i in
                    HomeTimelineRow(
                        summary: rows[i],
                        runStore: runStore,
                        onDelete: {
                            pendingHomeDeleteRunID = rows[i].id
                        }
                    )
                    if i < rows.count - 1 {
                        Divider().background(Theme.divider)
                    }
                }
            }
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

    // Date grouping — derives a stable day key + a human label per group.
    private struct DaySection {
        let dayKey: Date          // start-of-day, used for ForEach identity
        let label: String         // "TODAY" / "YESTERDAY" / "FEB 24, 2026"
        let summaries: [RunSummary]
    }

    private var groupedSummaries: [DaySection] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: homeTimelineSummaries) { summary in
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

    private var homeTimelineFooter: some View {
        Button {
            selectedTab = .runLog
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Text("Showing latest \(HomeLayout.timelinePreviewLimit)")
                    .font(.vfCalloutMedium)
                    .foregroundColor(Theme.textPrimary)
                Text("View all \(runStore.summaries.count) in Run Log")
                    .font(.vfCallout)
                    .foregroundColor(Theme.textSecondary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.Space.lg)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(Theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help("Open the full Run Log")
    }

    private var recordingHeader: some View {
        HStack(spacing: 12) {
            VFBrandLogo(size: 34, variant: .automatic, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppBrand.name)
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
                Text("\(AppBrand.name) \(VordiVersion.userFacing)")
                    .font(.subheadline.bold())
                Text("Voice typing for macOS — powered by OpenAI Whisper with optional local LLM post-processing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Whisper's `language` hint for the **Original** style (verbatim).
    ///
    /// Why scoped to Original: the polished styles (English / Hinglish) now
    /// resolve their language hint inside `WhisperService.route(forStyle:)`
    /// based on the output contract — `.clean` uses auto-detect so it can
    /// translate from any source, `.cleanHinglish` pins to "hi" so Whisper
    /// emits Latin Hindi. Letting the user override that in those modes
    /// would only break the contract.
    ///
    /// Original is the one path where the user's explicit choice still
    /// drives the wire request, because Original deliberately ships raw
    /// STT output with no LLM rewrite.
    private var languageCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Language")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("Original mode only")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Theme.divider))
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
                Text("Whisper's language hint for raw transcription. Auto-detect picks per recording. Lock to Hindi or English if you stay in one — slightly higher accuracy when the decoder doesn't have to guess.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// True when the user is on the Groq free tier — i.e. they've selected
    /// Groq as the transcription provider AND haven't added an OpenAI key.
    /// Drives lock states across language + style pickers + polish dropdown.
    private var isOnGroqTier: Bool {
        provider == TranscriptionProvider.groq.rawValue && openAIKey.isEmpty
    }

    /// All output styles are available on both tiers. Groq uses
    /// whisper-large-v3 for the multilingual paths (Romanized, English
    /// translation) — no OpenAI key required.
    private var visibleOutputModes: [(id: String, label: String)] {
        return outputModes
    }

    /// Dictation vs. Rewrite — the two-mode toggle that controls how
    /// aggressively the polish LLM transforms your spoken input.
    ///
    ///   - **Dictation** (default): keeps wording close to what you said.
    ///     Removes obvious fillers ("um", "uh"), fixes punctuation,
    ///     normalizes pauses-as-fullstops. Doesn't paraphrase or
    ///     restructure. Use when you want your VOICE in the output.
    ///
    ///   - **Rewrite**: lets the LLM tighten phrasing, fix grammar,
    ///     restructure sentences for clarity, format lists/headers
    ///     when appropriate. Use when you want your INTENT in the
    ///     output, polished. Slower (the LLM does more work), worth
    ///     it for emails / docs / Slack messages where you'd reach
    ///     for Grammarly otherwise.
    ///
    /// In Original style, Dictation skips the polish LLM while Rewrite still
    /// runs the selected polish model.
    private var transcriptionModeCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Polish Mode")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    if outputMode == TranscriptOutputStyle.verbatim.rawValue {
                        Text("Rewrite uses model")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.divider))
                    }
                }
                ThemedPillTabs(
                    options: processingModes.map { (id: $0.id, label: $0.label) },
                    selection: $processingMode
                )
                .onChange(of: processingMode) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "processing_mode")
                }
                Text(transcriptionModeHelperText)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Mode-specific helper text. Different copy per selected mode so
    /// the user understands the tradeoff before choosing.
    private var transcriptionModeHelperText: String {
        switch TranscriptProcessingMode(rawValue: processingMode) ?? .dictation {
        case .dictation:
            return "Polish keeps your spoken phrasing, removes fillers, fixes punctuation, and normalizes pauses. Good for chat and quick capture."
        case .rewrite:
            return "Lets the polish LLM tighten phrasing, fix grammar, restructure for clarity, and add list / header formatting when appropriate. Slower (more LLM work), worth it for emails, docs, and anywhere you'd otherwise paste into Grammarly."
        case .promptEngineer:
            return "Prompt Engineer turns rough dictated intent into a structured AI prompt. Use it when you are speaking to ChatGPT, Claude, Cursor, or another AI tool."
        }
    }

    private var runLogToggleCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Run Log").font(.headline)
                    Spacer()
                    VFSwitch(isOn: Binding(
                        get: { runLogEnabled },
                        set: { newValue in
                            runLogEnabled = newValue
                            UserDefaults.standard.set(newValue, forKey: "run_log_enabled")
                        }
                    ))
                }

                // Cap sub-toggle was here. Removed in v0.5.1 — retention is
                // now unconditionally unlimited. The setting confused users
                // (most never realized history was getting trimmed at 20)
                // and the UI lied if RunStore.maxRuns disagreed.
                //
                // `runLogCapped` @State stays in MainDashboardView for source
                // compatibility with anything that still binds against it
                // but is otherwise inert.

                Text(runLogCaptionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Contextual caption — explains what Run Log does. Since v0.5.1 the
    /// retention cap is gone, so we no longer need to handle capped vs.
    /// uncapped phrasing.
    private var runLogCaptionText: String {
        if !runLogEnabled {
            return "Run history is off. No audio, transcripts, or prompts are saved to disk."
        }
        return "Save audio, transcripts, and prompts locally for each dictation. Nothing leaves your Mac. History grows until you clear it from the Run Log tab."
    }

    private var compactRunHistoryDescription: String {
        if !runLogEnabled {
            return "Run history is off. Nothing is saved to disk."
        }
        return "Save dictation history locally on this Mac."
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
        .vfClickableCursor()
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
                .vfClickableCursor()
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Settings tab

    private func presentSettingsModal(_ pane: SettingsPane = .general) {
        selectedSettingsPane = pane
        withAnimation(.easeOut(duration: 0.16)) {
            isSettingsModalPresented = true
        }
    }

    private func dismissSettingsModal() {
        microphoneProbe.stop()
        withAnimation(.easeOut(duration: 0.14)) {
            isSettingsModalPresented = false
        }
    }

    private var settingsModalOverlay: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissSettingsModal()
                }

            settingsContent
                .transition(.scale(scale: 0.985).combined(with: .opacity))
        }
        .zIndex(20)
        .onExitCommand {
            dismissSettingsModal()
        }
    }

    private var settingsContent: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1)
            settingsPaneBody
        }
        .frame(width: Theme.Layout.settingsPanelWidth,
               height: Theme.Layout.settingsPanelHeight,
               alignment: .top)
        .background(Theme.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.RadiusExtra.modal, style: .continuous)
                .strokeBorder(Theme.divider, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.elevated.color,
                radius: Theme.Shadow.elevated.radius,
                x: 0,
                y: Theme.Shadow.elevated.y)
        // Stop the probe when the user navigates away from the dashboard.
        // We do this here (vs. inside the card) so the probe shuts down
        // even when the user switches tabs without the card going through
        // its own .onDisappear.
        .onDisappear {
            microphoneProbe.stop()
        }
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsSidebarGroup("SETTINGS", panes: SettingsPane.settingsGroup)

            Rectangle()
                .fill(Theme.divider)
                .frame(height: 1)
                .padding(.horizontal, Theme.Space.lg)
                .padding(.vertical, Theme.Space.md)

            settingsSidebarGroup("SYSTEM", panes: SettingsPane.systemGroup)

            Spacer(minLength: Theme.Space.xl)

            VStack(alignment: .leading, spacing: 4) {
                Text(AppBrand.name)
                    .font(.vfCalloutSemibold)
                    .foregroundColor(Theme.textPrimary)
                Text(VordiVersion.userFacing)
                    .font(.vfCaption)
                    .foregroundColor(Theme.textTertiary)
            }
            .padding(.horizontal, Theme.Space.lg)
            .padding(.bottom, Theme.Space.lg)
        }
        .frame(width: Theme.Layout.settingsNavWidth)
        .background(Theme.surfaceElevated)
    }

    private func settingsSidebarGroup(_ title: String, panes: [SettingsPane]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            VFSectionLabel(text: title)
            ForEach(panes, id: \.self) { pane in
                settingsSidebarItem(pane)
            }
        }
        .padding(.top, title == "SETTINGS" ? Theme.Space.lg : 0)
    }

    private func settingsSidebarItem(_ pane: SettingsPane) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) {
                selectedSettingsPane = pane
            }
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: pane.icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(pane.title)
                    .font(.vfBody)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundColor(selectedSettingsPane == pane ? Theme.textPrimary : Theme.textSecondary)
            .padding(.horizontal, Theme.Space.md)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .fill(selectedSettingsPane == pane ? Theme.sidebarActiveFill : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .vfClickableCursor()
        .padding(.horizontal, Theme.Space.sm)
    }

    private var settingsPaneBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(selectedSettingsPane.title)
                        .font(.vfSectionTitle)
                        .foregroundColor(Theme.textPrimary)
                    Text(selectedSettingsPane.subtitle)
                        .font(.vfCallout)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Button {
                    dismissSettingsModal()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(Theme.surface)
                        )
                        .overlay(
                            Circle()
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .help("Close Settings")
            }
            .padding(.horizontal, Theme.Layout.contentHPad)
            .padding(.top, 52)
            .padding(.bottom, Theme.Space.sm)

            ScrollView {
                selectedSettingsPaneContent
                    .padding(.bottom, Theme.Layout.contentVPad)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Layout.settingsPanelHeight, maxHeight: Theme.Layout.settingsPanelHeight, alignment: .top)
        .background(Theme.mainContent)
    }

    @ViewBuilder
    private var selectedSettingsPaneContent: some View {
        switch selectedSettingsPane {
        case .general:
            generalSettingsPane
        case .shortcuts:
            shortcutsSettingsPane
        case .aiModels:
            aiModelsSettingsPane
        case .agents:
            AgentConnectView()
        case .permissions:
            permissionsSettingsPane
        case .dataPrivacy:
            dataPrivacySettingsPane
        case .devMode:
            DevModeSettingsView(
                showsHeader: false,
                wrapsInScrollView: false,
                horizontalPadding: Theme.Layout.contentHPad,
                topPadding: Theme.Space.lg
            )
        case .setup:
            setupSettingsPane
        }
    }

    private var shortcutsSettingsPane: some View {
        VStack(spacing: 0) {
            VFFormSection(header: "Shortcuts") {
                ForEach(Array(HotkeyAction.allCases.enumerated()), id: \.offset) { index, action in
                    if index > 0 {
                        VFDivider(inset: Theme.Space.xl)
                    }
                    VFFormRow(
                        label: action.title,
                        description: action.subtitle
                    ) {
                        ThemedHotkeyRecorder(
                            action: action,
                            binding: hotkeys.config[action],
                            commit: { candidate in
                                hotkeys.setBinding(candidate, for: action)
                            }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: Theme.Space.md) {
                Text("Custom push-to-talk and hands-free shortcuts need a modifier combo (for example ⌃⌥) so a stray key press can't trigger dictation. fn stays the default.")
                    .font(.vfCaption)
                    .foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    hotkeys.resetToDefaults()
                } label: {
                    Text("Reset to defaults")
                        .font(.vfCalloutSemibold)
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.RadiusExtra.sm, style: .continuous)
                                .fill(Theme.surface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.RadiusExtra.sm, style: .continuous)
                                .strokeBorder(Theme.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Layout.contentHPad)
            .padding(.top, Theme.Space.lg)
        }
    }

    private var generalSettingsPane: some View {
        VStack(spacing: 0) {
            VFFormSection(header: "Output") {
                VFFormRow(
                    label: "Language",
                    description: "Whisper language hint for Original output."
                ) {
                    VFDropdown(
                        options: languages.map { (id: $0.code, label: $0.label) },
                        selection: $selectedLanguage,
                        width: 156
                    )
                    .onChange(of: selectedLanguage) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "language")
                    }
                }
                VFDivider(inset: Theme.Space.xl)
                VFFormRow(
                    label: "Output style",
                    description: compactOutputStyleDescription
                ) {
                    VFDropdown(
                        options: visibleOutputModes.map { (id: $0.id, label: $0.label) },
                        selection: $outputMode,
                        width: 156
                    )
                    .onChange(of: outputMode) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "output_mode")
                    }
                }
                VFDivider(inset: Theme.Space.xl)
                VFFormRow(
                    label: "Transform mode",
                    description: compactProcessingModeDescription
                ) {
                    VFDropdown(
                        options: processingModes.map { (id: $0.id, label: $0.label) },
                        selection: $processingMode,
                        width: 156
                    )
                    .onChange(of: processingMode) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "processing_mode")
                    }
                }
            }

            VFFormSection(header: "Feedback") {
                VFFormRow(
                    label: "Feedback surface",
                    description: selectedFeedbackSurfaceStyle.subtitle
                ) {
                    VFDropdown(
                        options: FeedbackSurfaceStyle.allCases.map { (id: $0.rawValue, label: $0.title) },
                        selection: $feedbackSurfaceStyle,
                        width: 188
                    )
                    .onChange(of: feedbackSurfaceStyle) { newValue in
                        UserDefaults.standard.set(newValue, forKey: FeedbackSurfaceStyle.userDefaultsKey)
                        NotificationCenter.default.post(
                            name: .voiceFlowFeedbackSurfaceStyleChanged,
                            object: nil
                        )
                    }
                }
            }

            VFFormSection(header: "Microphone") {
                settingsMicrophoneSensitivity
            }
        }
        .onAppear { reconcileOutputModeForTier() }
        .onChange(of: provider) { _ in reconcileOutputModeForTier() }
        .onChange(of: openAIKey) { _ in reconcileOutputModeForTier() }
    }

    private var aiModelsSettingsPane: some View {
        VStack(spacing: 0) {
            VFFormSection(header: "Transcription") {
                VFFormRow(
                    label: "Transcription provider",
                    description: "The service that turns speech into text."
                ) {
                    VFDropdown(
                        options: [
                            (id: TranscriptionProvider.groq.rawValue, label: "Groq · Free"),
                            (id: TranscriptionProvider.openai.rawValue, label: "OpenAI · 4o mini")
                        ],
                        selection: $provider,
                        width: 180
                    )
                    .onChange(of: provider) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "transcription_provider")
                    }
                }
            }

            VFFormSection(header: "API Keys") {
                if provider == TranscriptionProvider.groq.rawValue {
                    VFFormRow(
                        label: "Free tier",
                        description: "Multilingual dictation with the embedded beta key."
                    ) {
                        VFBadge(label: "Active", style: .promo)
                    }
                    VFDivider(inset: Theme.Space.xl)
                    settingsKeyRow(
                        label: "Groq API key",
                        description: "Optional override for the embedded beta key.",
                        placeholder: "gsk_...",
                        text: $groqKey,
                        save: {
                            UserDefaults.standard.set(groqKey, forKey: "groq_api_key")
                        }
                    )
                } else {
                    settingsKeyRow(
                        label: "OpenAI API key",
                        description: "Required for OpenAI transcription.",
                        placeholder: "sk-...",
                        text: $openAIKey,
                        save: {
                            UserDefaults.standard.set(openAIKey, forKey: "openai_api_key")
                        }
                    )
                }
            }

            VFFormSection(header: "Streaming") {
                VFFormRow(
                    label: "Realtime streaming",
                    description: "Lower perceived latency on long dictations. Falls back to batch upload if needed."
                ) {
                    VFSwitch(isOn: Binding(
                        get: { realtimeStreaming },
                        set: { newValue in
                            realtimeStreaming = newValue
                            UserDefaults.standard.set(newValue, forKey: "realtime_streaming_enabled")
                        }
                    ))
                }
                VFDivider(inset: Theme.Space.xl)
                VFFormRow(
                    label: "Live preview in notch (on-device)",
                    description: "Shows your words live in the notch as you speak, using Apple's on-device recognition. Works on any provider — including free Groq — and in hands-free. The final transcript still comes from your provider."
                ) {
                    VFSwitch(isOn: Binding(
                        get: { onDevicePreview },
                        set: { newValue in
                            onDevicePreview = newValue
                            UserDefaults.standard.set(newValue, forKey: AppleSpeechLivePreview.enabledKey)
                            // Trigger the Speech Recognition permission prompt now
                            // so the first dictation already has a live preview.
                            if newValue { AppleSpeechLivePreview.requestAuthorization { _ in } }
                        }
                    ))
                }
                VFDivider(inset: Theme.Space.xl)
                VFFormRow(
                    label: "Live type-as-you-speak (experimental)",
                    description: "Types words into the focused app as you speak, then swaps in the final polished text. Needs Realtime streaming on (OpenAI only). Can be janky across apps."
                ) {
                    VFSwitch(isOn: Binding(
                        get: { liveInject },
                        set: { newValue in
                            liveInject = newValue
                            UserDefaults.standard.set(newValue, forKey: LiveInjectionController.enabledKey)
                        }
                    ))
                }
            }

            VFFormSection(header: "Post-processing") {
                VFFormRow(
                    label: "Polish model",
                    description: "Used when Vordi cleans, rewrites, or formats the transcript."
                ) {
                    VFDropdown(
                        options: polishOptions.map { (id: $0.id, label: compactPolishLabel($0.label)) },
                        selection: $polishBackendId,
                        width: 236
                    )
                    .onChange(of: polishBackendId) { newValue in
                        UserDefaults.standard.set(newValue, forKey: PolishBackend.userDefaultsKey)
                    }
                }
                VFDivider(inset: Theme.Space.xl)
                VFFormRow(
                    label: "Local models",
                    description: compactLocalModelStatusText
                ) {
                    VFButton(
                        title: localDetector.isDetecting ? "Refreshing" : "Refresh",
                        icon: "arrow.clockwise",
                        style: .secondary,
                        isCompact: true,
                        isLoading: localDetector.isDetecting,
                        isDisabled: localDetector.isDetecting
                    ) {
                        localDetector.detect()
                    }
                }
                if selectedLocalModelUnavailable {
                    VFDivider(inset: Theme.Space.xl)
                    settingsWarningRow("Selected local model is not currently detected. Start the server and refresh before dictating.")
                }
            }

            VFFormSection(header: "Memory & Chat") {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Memory provider")
                                .font(.vfBody)
                                .foregroundColor(Theme.textPrimary)
                            Text("Used by Memory chat and entity extraction.")
                                .font(.vfDescription)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                    }
                    MemoryProviderPicker()
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.lg)
            }
        }
    }

    private var permissionsSettingsPane: some View {
        VStack(spacing: 0) {
            VFFormSection(header: "macOS Permissions") {
                settingsPermissionRow(
                    title: "Microphone",
                    description: "Required to hear your voice.",
                    state: permissionService.microphoneState,
                    pane: .microphone
                )
                VFDivider(inset: Theme.Space.xl)
                settingsPermissionRow(
                    title: "Accessibility",
                    description: "Required to type the transcript into other apps.",
                    state: permissionService.accessibilityState,
                    pane: .accessibility
                )
                VFDivider(inset: Theme.Space.xl)
                settingsPermissionRow(
                    title: "Input Monitoring",
                    description: "Required to detect the fn key.",
                    state: permissionService.inputMonitoringState,
                    pane: .inputMonitoring
                )
                VFDivider(inset: Theme.Space.xl)
                settingsPermissionRow(
                    title: "Screen Recording",
                    description: "Optional for screenshot context summaries.",
                    state: permissionService.screenRecordingState,
                    pane: .screenRecording
                )
            }

            VFFormSection(header: "Status") {
                VFFormRow(
                    label: permissionService.allRequiredGranted ? "Ready" : "Action needed",
                    description: permissionService.allRequiredGranted
                        ? "All required permissions are granted."
                        : "Global hotkeys will not work until required permissions are granted."
                ) {
                    VFButton(title: "Re-check", icon: "arrow.clockwise", style: .secondary, isCompact: true) {
                        permissionService.refreshStatus()
                    }
                }
            }
        }
    }

    private var dataPrivacySettingsPane: some View {
        VStack(spacing: 0) {
            VFFormSection(header: "Run History") {
                VFFormRow(
                    label: "Save run history",
                    description: compactRunHistoryDescription
                ) {
                    VFSwitch(isOn: Binding(
                        get: { runLogEnabled },
                        set: { newValue in
                            runLogEnabled = newValue
                            UserDefaults.standard.set(newValue, forKey: "run_log_enabled")
                        }
                    ))
                }
                VFDivider(inset: Theme.Space.xl)
                settingsStaticRow(
                    label: "Storage",
                    description: "Audio, transcripts, prompts, and diagnostics stay on this Mac.",
                    value: "Local"
                )
            }

            VFFormSection(header: "Custom Vocabulary") {
                settingsVocabularyEditor
            }
        }
    }

    private var setupSettingsPane: some View {
        VStack(spacing: 0) {
            VFFormSection(header: "Welcome Flow") {
                VFFormRow(
                    label: "Run onboarding again",
                    description: "Revisit feature overview, permissions, preferences, and the test step."
                ) {
                    VFButton(title: "Open", icon: "sparkles", style: .secondary, isCompact: true) {
                        NotificationCenter.default.post(
                            name: Notification.Name("Vordi.RestartOnboarding"),
                            object: nil
                        )
                    }
                }
            }

            VFFormSection(header: "App") {
                settingsStaticRow(
                    label: "Version",
                    description: "Current installed Vordi build.",
                    value: VordiVersion.userFacing
                )
                VFDivider(inset: Theme.Space.xl)
                VFFormRow(
                    label: "Quit Vordi",
                    description: "Stop the menu bar helper and close the app."
                ) {
                    VFButton(title: "Quit", icon: "power", style: .destructive, isCompact: true) {
                        onQuit()
                    }
                }
            }
        }
    }

    private var settingsMicrophoneSensitivity: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sensitivity")
                        .font(.vfBody)
                        .foregroundColor(Theme.textPrimary)
                    Text(settingsMicrophoneDescription)
                        .font(.vfDescription)
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                VFButton(
                    title: microphoneProbe.isProbing ? "Stop" : "Test mic",
                    icon: microphoneProbe.isProbing ? "stop.fill" : "mic.fill",
                    style: microphoneProbe.isProbing ? .destructive : .secondary,
                    isCompact: true
                ) {
                    if microphoneProbe.isProbing {
                        microphoneProbe.stop()
                    } else {
                        microphoneProbe.start()
                    }
                }
            }

            LevelMeterView(
                level: microphoneProbe.currentLevel,
                threshold: MicrophoneProbe.normalizedThreshold(noiseGateThreshold),
                isActive: microphoneProbe.isProbing
            )
            .padding(.top, Theme.Space.sm)

            HStack {
                Text("More sensitive")
                    .font(.vfCaption)
                    .foregroundColor(Theme.textTertiary)
                Slider(value: $noiseGateThreshold, in: 0.001...0.05, step: 0.001)
                    .tint(Theme.interactive)
                    .onChange(of: noiseGateThreshold) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "noise_gate_threshold")
                    }
                Text("Filters noise")
                    .font(.vfCaption)
                    .foregroundColor(Theme.textTertiary)
                Text(String(format: "%.3f", noiseGateThreshold))
                    .font(.vfCaption.monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.lg)
    }

    private var settingsVocabularyEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vocabulary")
                        .font(.vfBody)
                        .foregroundColor(Theme.textPrimary)
                    Text("Names, brands, and jargon that should survive dictation.")
                        .font(.vfDescription)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Text(vocabularyCountLabel(parsedVocabularyCount))
                    .font(.vfCaption.monospacedDigit())
                    .foregroundColor(Theme.textTertiary)
            }

            ZStack(alignment: .topLeading) {
                if customVocabulary.isEmpty {
                    Text("e.g. Raunak, Vordi, Shopsense, Fynd")
                        .font(.vfCallout)
                        .foregroundColor(Theme.textTertiary)
                        .padding(.horizontal, Theme.Space.md)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $customVocabulary)
                    .font(.vfCallout)
                    .foregroundColor(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(minHeight: 116)
                    .onChange(of: customVocabulary) { newValue in
                        UserDefaults.standard.set(newValue, forKey: UserVocabulary.userDefaultsKey)
                    }
            }
            .background(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .fill(Theme.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.RadiusExtra.input, style: .continuous)
                    .strokeBorder(Theme.dividerStrong, lineWidth: 1)
            )
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.lg)
    }

    @ViewBuilder
    private func settingsKeyRow(
        label: String,
        description: String,
        placeholder: String,
        text: Binding<String>,
        save: @escaping () -> Void
    ) -> some View {
        VFFormRow(label: label, description: description) {
            SecureField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Theme.textPrimary)
                .vfInputChrome()
                .frame(width: 292)
                .onSubmit {
                    save()
                    flashSaved()
                }
                .onChange(of: text.wrappedValue) { _ in
                    save()
                }
        }
    }

    private func settingsPermissionRow(
        title: String,
        description: String,
        state: PermissionState,
        pane: PermissionPane
    ) -> some View {
        VFFormRow(label: title, description: description) {
            if state.isGranted {
                HStack(spacing: Theme.Space.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.success)
                    Text("Granted")
                        .font(.vfCalloutMedium)
                        .foregroundColor(Theme.success)
                }
            } else {
                VFButton(title: "Open Settings", style: .primary, isCompact: true) {
                    permissionService.openPrivacyPane(pane)
                }
            }
        }
    }

    @ViewBuilder
    private func settingsStaticRow(label: String, description: String, value: String) -> some View {
        VFFormRow(label: label, description: description) {
            Text(value)
                .font(.vfCalloutMedium)
                .foregroundColor(Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.sm, style: .continuous)
                        .fill(Theme.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.RadiusExtra.sm, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                )
        }
    }

    private func settingsWarningRow(_ message: String) -> some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.warning)
            Text(message)
                .font(.vfCallout)
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.md)
    }

    private var localModelStatusText: String {
        if localDetector.models.isEmpty {
            return "No local servers detected. Start LM Studio on :1234 or Ollama on :11434, then refresh."
        }
        return "\(localDetector.models.count) local model\(localDetector.models.count == 1 ? "" : "s") detected."
    }

    private var compactLocalModelStatusText: String {
        if localDetector.models.isEmpty {
            return "No LM Studio or Ollama server detected."
        }
        return "\(localDetector.models.count) local model\(localDetector.models.count == 1 ? "" : "s") detected."
    }

    private var settingsMicrophoneDescription: String {
        if microphoneProbe.isProbing {
            let levelPct = Int((microphoneProbe.currentLevel * 100).rounded())
            return "Speak normally. Live level: \(levelPct)%. Voice should cross the threshold tick."
        }
        return "Test your room level and adjust what counts as speech."
    }

    private var selectedLocalModelUnavailable: Bool {
        (polishBackendId.hasPrefix("lmstudio::") || polishBackendId.hasPrefix("ollama::"))
            && !polishOptions.contains(where: { $0.id == polishBackendId })
    }

    private func compactPolishLabel(_ label: String) -> String {
        label
            .replacingOccurrences(of: " (vision context)", with: "")
            .replacingOccurrences(of: " (recommended)", with: "")
            .replacingOccurrences(of: " (cheaper, stronger role adherence)", with: "")
    }

    private var compactOutputStyleDescription: String {
        switch TranscriptOutputStyle(rawValue: outputMode) ?? .verbatim {
        case .verbatim:
            return "Raw transcription with minimal cleanup."
        case .clean:
            return "Translate spoken language into English."
        case .cleanHinglish:
            return "Multilingual speech written in English letters."
        case .translateEnglish:
            return "Translate spoken language into English."
        }
    }

    private var compactProcessingModeDescription: String {
        switch TranscriptProcessingMode(rawValue: processingMode) ?? .dictation {
        case .dictation:
            return "Polish dictation with clarity, structure, and your tone."
        case .rewrite:
            return "Clean phrasing, structure, and grammar."
        case .promptEngineer:
            return "Format dictated intent for AI agents."
        }
    }

    // MARK: Settings — Permissions card

    /// Live status of the three TCC permissions Vordi requires. Inline
    /// "Open Settings" button per row when the permission isn't granted —
    /// faster than navigating System Settings manually.
    /// Live mic level + threshold slider in one card. The threshold marker
    /// rides on the same 0...1 normalized scale as the level bar (sqrt+1.6×),
    /// so the user can VISUALLY confirm "my voice peaks above the tick" —
    /// far more intuitive than reading 0.015 in isolation and guessing
    /// whether their room qualifies as quiet.
    private var microphoneSensitivityCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Microphone Sensitivity")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Button {
                        if microphoneProbe.isProbing {
                            microphoneProbe.stop()
                        } else {
                            microphoneProbe.start()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: microphoneProbe.isProbing ? "stop.fill" : "mic.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(microphoneProbe.isProbing ? "Stop" : "Test mic")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(microphoneProbe.isProbing ? .white : Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(microphoneProbe.isProbing ? Theme.danger : Theme.surfaceElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    microphoneProbe.isProbing ? Color.clear : Theme.dividerStrong,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .vfClickableCursor()
                    .help("Open the mic for ~12s so you can read out loud and see your level")
                }

                // Live level meter — fills with current RMS amplitude, shows
                // the threshold tick as a vertical bar overlay. Filled portion
                // turns success-green when peaking above threshold so the user
                // gets unambiguous feedback ("yes, my voice would trigger
                // recording").
                LevelMeterView(
                    level: microphoneProbe.currentLevel,
                    threshold: MicrophoneProbe.normalizedThreshold(noiseGateThreshold),
                    isActive: microphoneProbe.isProbing
                )

                // Caption: changes based on probe state to guide the user.
                Text(microphoneSensitivityCaption)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider().background(Theme.divider).padding(.vertical, 2)

                // Threshold slider. Range mirrors the AudioRecorder runtime
                // clamp (0.001…0.05) so the UI never exposes values that
                // would be silently clipped on the next dictation.
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Threshold")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.textPrimary)
                        Spacer()
                        Text(String(format: "%.3f", noiseGateThreshold))
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundColor(Theme.textSecondary)
                    }
                    Slider(value: $noiseGateThreshold, in: 0.001...0.05, step: 0.001)
                        .tint(Theme.accent)
                        .onChange(of: noiseGateThreshold) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "noise_gate_threshold")
                        }
                    HStack {
                        Text("More sensitive")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                        Spacer()
                        Text("Filters more noise")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
        }
    }

    /// Custom vocabulary editor — names, brands, jargon the user dictates
    /// often. Injected into the Whisper STT prompt (biases the decoder)
    /// AND the polish LLM prompt (preserves canonical spelling). Same
    /// pattern as Cursor / Wispr Flow's "Custom Words" feature.
    ///
    /// Storage is a single string in UserDefaults, parsed on read by
    /// `UserVocabulary.terms`. Auto-saves on every keystroke — no save
    /// button, since the change is cheap and the next dictation should
    /// reflect what the user just typed.
    private var vocabularyCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Custom Vocabulary")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        Text("Names, brands, and jargon you dictate often. Improves Whisper transcription and polish-step capitalization.")
                            .font(.system(size: 11))
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }

                // Multiline editor — placeholder overlay since SwiftUI's
                // TextEditor doesn't support a native placeholder until
                // macOS 14. ZStack-with-Text is the standard workaround.
                ZStack(alignment: .topLeading) {
                    if customVocabulary.isEmpty {
                        Text("e.g. Raunak, Vordi, Shopsense, Fynd, my-side-project")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $customVocabulary)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(minHeight: 84)
                        .onChange(of: customVocabulary) { newValue in
                            UserDefaults.standard.set(
                                newValue,
                                forKey: UserVocabulary.userDefaultsKey
                            )
                        }
                }
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .fill(Theme.surfaceElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.divider, lineWidth: 1)
                )

                HStack {
                    Text("Separate terms with commas or new lines.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                    Spacer()
                    let count = parsedVocabularyCount
                    Text(vocabularyCountLabel(count))
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(count > 0 ? Theme.textSecondary : Theme.textTertiary)
                }
            }
        }
    }

    /// Live term count — same parsing rules as `UserVocabulary.terms`
    /// so the UI can't drift from what the prompt actually receives.
    private var parsedVocabularyCount: Int {
        let separators = CharacterSet(charactersIn: ",\n")
        var seen: Set<String> = []
        for raw in customVocabulary.components(separatedBy: separators) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            seen.insert(trimmed.lowercased())
        }
        return seen.count
    }

    private func vocabularyCountLabel(_ count: Int) -> String {
        if count == 0 { return "No terms yet" }
        if count == 1 { return "1 term" }
        return "\(count) terms"
    }

    /// Context-sensitive caption text under the meter.
    private var microphoneSensitivityCaption: String {
        if microphoneProbe.isProbing {
            // While the probe is running, tell the user what success
            // looks like — their voice should land in the green zone
            // (above the threshold tick) when speaking normally.
            let levelPct = Int((microphoneProbe.currentLevel * 100).rounded())
            return "Speak normally. Live level: \(levelPct)%. Your voice should peak past the tick when you talk; ambient noise should stay below it."
        }
        return "Tap Test mic to read aloud and see your live level. Drop the threshold if your voice doesn't trigger; raise it if quiet room noise gets transcribed."
    }

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
                    .vfClickableCursor()
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
                permissionRow(
                    title: "Screen Recording",
                    subtitle: "Optional for screenshot context summaries",
                    state: permissionService.screenRecordingState,
                    pane: .screenRecording
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
                .vfClickableCursor()
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
                        name: Notification.Name("Vordi.RestartOnboarding"),
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
                .vfClickableCursor()
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
                    VFSwitch(isOn: Binding(
                        get: { realtimeStreaming },
                        set: { newValue in
                            realtimeStreaming = newValue
                            UserDefaults.standard.set(newValue, forKey: "realtime_streaming_enabled")
                        }
                    ))
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

    private var feedbackSurfaceCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Feedback Surface")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("Changes instantly")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                }

                HStack(spacing: 8) {
                    ForEach(FeedbackSurfaceStyle.allCases, id: \.self) { style in
                        feedbackSurfaceOption(style)
                    }
                }

                Text(selectedFeedbackSurfaceStyle.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectedFeedbackSurfaceStyle: FeedbackSurfaceStyle {
        FeedbackSurfaceStyle(rawValue: feedbackSurfaceStyle) ?? .dynamicNotch
    }

    private func feedbackSurfaceOption(_ style: FeedbackSurfaceStyle) -> some View {
        let isSelected = feedbackSurfaceStyle == style.rawValue

        return Button {
            feedbackSurfaceStyle = style.rawValue
            UserDefaults.standard.set(style.rawValue, forKey: FeedbackSurfaceStyle.userDefaultsKey)
            NotificationCenter.default.post(name: .voiceFlowFeedbackSurfaceStyleChanged, object: nil)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: style.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(style.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Theme.dividerStrong : Theme.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .help(style.subtitle)
    }

    /// Provider picker for the Memory chat + knowledge-graph entity
    /// extraction pipeline. Polish path is intentionally NOT included
    /// — that stays on whatever the user picked in `polishModelCard`
    /// so dictation latency doesn't pick up subprocess spawn overhead.
    ///
    /// Local CLI detection is manual. The user clicks "Fetch AI CLIs" to
    /// scan for Claude Code, Codex, and Gemini binaries; each detected row
    /// can then be selected or manually probed for auth.
    private var memoryProviderCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Memory & Chat AI")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    Spacer()
                    Text("Used by Memory chat and entity extraction")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.textTertiary)
                }
                MemoryProviderPicker()
            }
        }
    }

    private var providerCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 14) {
                Text("Transcription Provider")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)

                ThemedPillTabs(
                    options: [
                        (id: TranscriptionProvider.groq.rawValue, label: "Groq · Free · Fast"),
                        (id: TranscriptionProvider.openai.rawValue, label: "OpenAI · 4o mini transcribe")
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
                Text("Multilingual dictation (Hindi, Marathi, English + more), no setup needed.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }
            Spacer()
        }

        // Optional OpenAI key — enables GPT-4 polish and higher accuracy.
        DisclosureGroup(
            isExpanded: $showOpenAIUpgrade,
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Add your OpenAI API key to use GPT-4 for post-processing. You pay OpenAI directly — typically ~$0.18/hour of audio. Multilingual transcription (Hindi, Marathi, etc.) already works on the free Groq tier.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    keyRow(
                        title: "OpenAI API Key",
                        placeholder: "sk-...",
                        help: "Get a key at platform.openai.com/api-keys",
                        text: $openAIKey,
                        onCommit: {
                            let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
                            openAIKey = trimmed
                            UserDefaults.standard.set(trimmed, forKey: "openai_api_key")
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
                    Text("Upgrade to GPT-4 polish")
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
                    .vfClickableCursor()
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
                Text("Output Style")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
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
        // Reconcile when the user's tier changes. If they fall back to
        // Groq (e.g. delete their OpenAI key) while .clean / .cleanHinglish
        // is selected, the picker would otherwise have no matching pill —
        // which renders as "nothing selected" and is impossible to recover
        // from without re-clicking. Snap back to Verbatim instead.
        .onAppear { reconcileOutputModeForTier() }
        .onChange(of: provider) { _ in reconcileOutputModeForTier() }
        .onChange(of: openAIKey) { _ in reconcileOutputModeForTier() }
    }

    /// No-op — all output modes work on all tiers. Kept for call-site
    /// compatibility; the .onAppear / .onChange wiring remains in place
    /// in case tier-specific logic is added in the future.
    private func reconcileOutputModeForTier() {}

    /// Mode-specific helper text — single source of truth for what each
    /// output contract delivers. The `.clean` description is tier-aware:
    /// without an OpenAI key it's English cleanup; with a key it adds
    /// translation. The user sees the right contract for their setup.
    private var outputStyleHelperText: String {
        switch TranscriptOutputStyle(rawValue: outputMode) ?? .cleanHinglish {
        case .verbatim:
            return "Raw transcript — no transformation. Dictation injects as-is; Rewrite still runs the polish model for cleaner phrasing. The Language picker controls Whisper's language hint in this mode."
        case .clean:
            return "Legacy English mode. New UI maps this behavior to Translate."
        case .cleanHinglish:
            return "English output writes any language in English letters. Hindi: \u{201C}mera naam Raunak hai\u{201D}. Marathi: \u{201C}me tula bhetnar\u{201D}. No translation."
        case .translateEnglish:
            return "Translates any spoken language to natural English."
        }
    }

    private var footerActions: some View {
        HStack {
            Button(action: onQuit) {
                Label("Quit Vordi", systemImage: "power")
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
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
                .vfClickableCursor()
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
                    .vfClickableCursor()
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
            acc + wordCount(s)
        }
    }

    static func wordsPerMinuteText(_ store: RunStore) -> String {
        let successfulRuns = store.summaries.filter { $0.status == .success && $0.durationSeconds > 0 }
        let seconds = successfulRuns.reduce(0.0) { $0 + $1.durationSeconds }
        guard seconds > 0 else { return "—" }
        let words = successfulRuns.reduce(0) { $0 + wordCount($1) }
        guard words > 0 else { return "—" }
        return "\(Int((Double(words) / seconds * 60).rounded()))"
    }

    private static func wordCount(_ summary: RunSummary) -> Int {
        if let cached = summary.wordCount { return cached }
        return summary.previewText
            .split(whereSeparator: { $0.isWhitespace })
            .count
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

// MARK: - MemoryProviderPicker

/// Settings widget: lets the user pick which AI answers Memory chat
/// questions + extracts knowledge-graph entities. CLI discovery is
/// explicit so opening Settings never spawns local processes.
///
/// **Why a dedicated component** (not inline in the settings card):
/// owns its own `@StateObject` on LLMRouter + CLIRunner state, has
/// per-row async state (probing → response), and re-rendering it
/// shouldn't force the whole settings page to recompute.
struct MemoryProviderPicker: View {
    @ObservedObject private var router = LLMRouter.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(cliFetchSummary)
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textTertiary)
                Spacer()
                fetchCLIsButton
            }

            providerRow(
                title: "Built-in",
                subtitle: "Routes through whatever you picked for the polish backend (OpenAI / Groq / local). Always available.",
                isSelected: router.activeProvider == .builtIn,
                statusBadge: { builtInStatusBadge },
                trailingAction: { EmptyView() }
            ) {
                router.setProvider(.builtIn)
            }

            ForEach(CLIIdentifier.allCases, id: \.self) { cli in
                cliRow(cli)
            }
        }
    }

    // MARK: Row builders

    private var cliFetchSummary: String {
        if router.isFetchingCLIs { return "Scanning local CLI paths..." }
        if router.hasFetchedCLIs {
            let count = router.detectedCLIs.count
            return count == 1 ? "1 AI CLI found" : "\(count) AI CLIs found"
        }
        return "Click Fetch AI CLIs to scan this Mac."
    }

    private var fetchCLIsButton: some View {
        VFButton(
            title: router.isFetchingCLIs ? "Fetching" : "Fetch AI CLIs",
            icon: "terminal",
            style: .secondary,
            isCompact: true,
            isLoading: router.isFetchingCLIs,
            isDisabled: router.isFetchingCLIs
        ) {
            Task { await router.fetchLocalCLIs() }
        }
        .help("Scan for Claude Code, Codex, and Gemini CLI binaries")
    }

    private func cliRow(_ cli: CLIIdentifier) -> some View {
        let isDetected = router.detectedCLIs.contains(cli)
        let isSelected = router.activeProvider == .cli(cli)
        return providerRow(
            title: cli.displayName,
            subtitle: cliSubtitle(cli),
            isSelected: isSelected,
            statusBadge: { cliStatusBadge(cli) },
            trailingAction: {
                Button {
                    Task { _ = await router.probe(cli) }
                } label: {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .foregroundColor(Theme.textSecondary)
                        .background(Capsule().fill(Theme.surfaceElevated))
                        .overlay(Capsule().strokeBorder(Theme.divider, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
                .help("Probe \(cli.displayName) auth")
                .disabled(!isDetected)
            }
        ) {
            guard isDetected else { return }
            router.setProvider(.cli(cli))
        }
        .opacity(isDetected || !router.hasFetchedCLIs ? 1.0 : 0.55)
    }

    private func cliSubtitle(_ cli: CLIIdentifier) -> String {
        guard router.hasFetchedCLIs || router.detectedCLIs.contains(cli) else {
            return "\(cli.settingsCopy) Fetch AI CLIs to check this Mac."
        }
        guard router.detectedCLIs.contains(cli) else {
            return "\(cli.settingsCopy) Binary not found in common shell paths."
        }

        switch router.probeStates[cli] {
        case .authNeeded(let hint):
            return hint
        case .error(let message):
            return message
        default:
            return "\(cli.settingsCopy) Detected locally; probe to verify auth."
        }
    }

    private func providerRow<Badge: View, Trailing: View>(
        title: String,
        subtitle: String,
        isSelected: Bool,
        @ViewBuilder statusBadge: () -> Badge,
        @ViewBuilder trailingAction: () -> Trailing,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 10) {
                // Radio indicator
                ZStack {
                    Circle()
                        .strokeBorder(
                            isSelected ? Theme.interactive : Theme.divider,
                            lineWidth: isSelected ? 5 : 1
                        )
                        .frame(width: 14, height: 14)
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)
                        statusBadge()
                    }
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
                trailingAction()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Theme.interactiveSoft : Theme.surfaceElevated.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Theme.interactive.opacity(0.45) : Theme.divider, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
    }

    // MARK: Status badges

    private var builtInStatusBadge: some View {
        statusPill(text: "Ready", color: Theme.success)
    }

    @ViewBuilder
    private func cliStatusBadge(_ cli: CLIIdentifier) -> some View {
        if !router.hasFetchedCLIs && !router.detectedCLIs.contains(cli) {
            statusPill(text: "Not fetched", color: Theme.textTertiary)
        } else if !router.detectedCLIs.contains(cli) {
            statusPill(text: "Not installed", color: Theme.textTertiary)
        } else if let state = router.probeStates[cli] {
            switch state {
            case .unknown:
                statusPill(text: "Detected", color: Theme.success)
            case .probing:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Probing…")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Theme.textSecondary)
                }
            case .ready:
                statusPill(text: "Ready", color: Theme.success)
            case .authNeeded:
                statusPill(text: "Not authed", color: Theme.warning)
            case .error:
                statusPill(text: "Error", color: Theme.danger)
            }
        } else {
            statusPill(text: "Detected", color: Theme.success)
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(color)
            .background(Capsule().fill(color.opacity(0.14)))
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
    let onDelete: () -> Void

    @State private var isHovering = false

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
        .vfClickableCursor()
        .help("Copy transcript")
    }

    private var ellipsisMenu: some View {
        VFActionMenu(
            actions: transcriptActions,
            iconColor: Theme.textSecondary,
            buttonSize: 22
        )
    }

    private var transcriptActions: [VFActionMenuAction] {
        [
            VFActionMenuAction(
                icon: "arrow.clockwise",
                label: "Retry transcript",
                isDisabled: summary.status == .failed
            ) {
                NotificationCenter.default.post(
                    name: Notification.Name("Vordi.RetryRun"),
                    object: nil,
                    userInfo: ["runID": summary.id]
                )
            },
            VFActionMenuAction(
                icon: "arrow.down.circle",
                label: "Download audio"
            ) {
                downloadAudio()
            },
            .divider(),
            VFActionMenuAction(
                icon: "trash",
                label: "Delete transcript",
                isDestructive: true
            ) {
                onDelete()
            }
        ]
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
        let stem = "Vordi_\(formatter.string(from: summary.createdAt))"
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
                    withAnimation(.easeOut(duration: 0.16)) {
                        manager.mode = mode
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(mode == .light ? "Light" : "Dark")
                            .font(.system(size: 11, weight: manager.mode == mode ? .semibold : .medium))
                    }
                    .foregroundColor(manager.mode == mode ? Theme.textPrimary : Theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(manager.mode == mode ? Theme.segmentedToggleActiveFill : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .vfClickableCursor()
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Theme.segmentedToggleTrackFill)
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
                    colors: [Color.clear, Theme.surfaceDark.opacity(0.30)],
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

// MARK: - Profile cards

private enum VordiOrangeMeshPalette {
    static let hot = Color(red: 1.000, green: 0.231, blue: 0.020)
    static let ember = Color(red: 1.000, green: 0.412, blue: 0.063)
    static let gold = Color(red: 1.000, green: 0.690, blue: 0.196)
    static let rose = Color(red: 1.000, green: 0.318, blue: 0.208)
    static let creamMark = Color(red: 1.000, green: 0.965, blue: 0.895)
}

private enum VoiceProfilePurplePalette {
    static let nearWhite = Color(red: 0.992, green: 0.988, blue: 0.976)
    static let paleLilac = Color(red: 0.938, green: 0.918, blue: 0.992)
    static let lilacEdge = Color(red: 0.812, green: 0.760, blue: 0.965)
    static let night = Color(red: 0.075, green: 0.049, blue: 0.118)
    static let plum = Color(red: 0.145, green: 0.090, blue: 0.235)
    static let aubergine = Color(red: 0.220, green: 0.137, blue: 0.365)
    static let accent = Color(red: 0.314, green: 0.208, blue: 0.565)
    static let accentLift = Color(red: 0.450, green: 0.337, blue: 0.745)
    static let lavenderMark = Color(red: 0.760, green: 0.690, blue: 0.980)

    static func headerBase(for colorScheme: ColorScheme) -> [Color] {
        if colorScheme == .dark {
            return [night, plum, aubergine]
        }
        return [nearWhite, paleLilac, lilacEdge]
    }

    static func primaryGlow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? accentLift : accent
    }

    static func secondaryGlow(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? lavenderMark : accentLift
    }

    static func mark(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? lavenderMark : accent
    }

    static func badgeFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? night : Theme.surfaceElevated
    }
}

private struct VordiOrangeMeshHeader: View {
    var height: CGFloat
    var watermarkOpacity: Double = 0.22

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [
                    VordiOrangeMeshPalette.hot,
                    VordiOrangeMeshPalette.ember,
                    Theme.accent
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    VordiOrangeMeshPalette.gold.opacity(0.72),
                    VordiOrangeMeshPalette.gold.opacity(0.14),
                    Color.clear
                ],
                center: UnitPoint(x: 0.15, y: 1.0),
                startRadius: 4,
                endRadius: 170
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    VordiOrangeMeshPalette.rose.opacity(0.70),
                    VordiOrangeMeshPalette.rose.opacity(0.18),
                    Color.clear
                ],
                center: UnitPoint(x: 0.90, y: 0.18),
                startRadius: 8,
                endRadius: 150
            )
            .blendMode(.screen)

            VordiLogoBars(
                color: VordiOrangeMeshPalette.creamMark.opacity(watermarkOpacity),
                barWidth: 14,
                maxHeight: 82,
                spacing: 8
            )
            .rotationEffect(.degrees(-15))
            .offset(x: 48, y: -4)
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct VoiceProfileMeshHeader: View {
    @Environment(\.colorScheme) private var colorScheme

    var height: CGFloat
    var watermarkOpacity: Double = 0.18

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: VoiceProfilePurplePalette.headerBase(for: colorScheme),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    VoiceProfilePurplePalette.primaryGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.70 : 0.16),
                    VoiceProfilePurplePalette.primaryGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.05),
                    Color.clear
                ],
                center: UnitPoint(x: 0.10, y: 0.92),
                startRadius: 6,
                endRadius: 160
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    VoiceProfilePurplePalette.secondaryGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.34 : 0.26),
                    VoiceProfilePurplePalette.secondaryGlow(for: colorScheme).opacity(colorScheme == .dark ? 0.10 : 0.07),
                    Color.clear
                ],
                center: UnitPoint(x: 0.86, y: 0.18),
                startRadius: 6,
                endRadius: 140
            )
            .blendMode(.screen)

            VordiLogoBars(
                color: VoiceProfilePurplePalette.mark(for: colorScheme)
                    .opacity(colorScheme == .dark ? min(1.0, watermarkOpacity + 0.10) : watermarkOpacity),
                barWidth: 14,
                maxHeight: 82,
                spacing: 8
            )
            .rotationEffect(.degrees(-15))
            .offset(x: 48, y: -4)
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct VordiLogoBars: View {
    var color: Color
    var barWidth: CGFloat
    var maxHeight: CGFloat
    var spacing: CGFloat

    private let heights: [CGFloat] = [0.42, 0.74, 1.0, 0.66, 0.42]

    var body: some View {
        HStack(alignment: .center, spacing: spacing) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(color)
                    .frame(width: barWidth, height: maxHeight * heights[index])
            }
        }
    }
}

private struct VordiProfileBadge: View {
    @Environment(\.colorScheme) private var colorScheme

    var diameter: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .fill(VoiceProfilePurplePalette.badgeFill(for: colorScheme))
            Circle()
                .strokeBorder(
                    VoiceProfilePurplePalette.accent.opacity(colorScheme == .dark ? 0.92 : 0.64),
                    lineWidth: 3
                )

            VFBrandLogo(size: diameter * 0.58, variant: .automatic, cornerRadius: diameter * 0.10)
                .frame(width: diameter, height: diameter, alignment: .center)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 4, x: 0, y: 2)
    }
}

private enum GitHubLogoAsset {
    private static let resourceName = "github-6980894_640"

    static let image: NSImage? = {
        if let namedImage = NSImage(named: resourceName) {
            return namedImage
        }
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()
}

private enum GitHubBrandPalette {
    static let ink = Color(red: 0.051, green: 0.067, blue: 0.090)
    static let navy = Color(red: 0.020, green: 0.028, blue: 0.180)
    static let midnight = Color(red: 0.025, green: 0.018, blue: 0.115)
    static let violet = Color(red: 0.330, green: 0.255, blue: 0.810)
    static let glow = Color(red: 0.690, green: 0.590, blue: 1.000)
    static let mark = Color(red: 0.965, green: 0.965, blue: 0.980)
}

private struct GitHubBrandHeader: View {
    var height: CGFloat

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [
                    GitHubBrandPalette.ink,
                    GitHubBrandPalette.navy,
                    GitHubBrandPalette.midnight
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    GitHubBrandPalette.violet.opacity(0.88),
                    GitHubBrandPalette.violet.opacity(0.22),
                    Color.clear
                ],
                center: UnitPoint(x: 0.70, y: 1.06),
                startRadius: 4,
                endRadius: 170
            )
            .blendMode(.screen)

            RadialGradient(
                colors: [
                    GitHubBrandPalette.glow.opacity(0.46),
                    GitHubBrandPalette.glow.opacity(0.12),
                    Color.clear
                ],
                center: UnitPoint(x: 0.98, y: 0.18),
                startRadius: 5,
                endRadius: 110
            )
            .blendMode(.screen)

            GitHubMarkShape()
                .fill(GitHubBrandPalette.mark.opacity(0.16))
                .frame(width: 112, height: 112)
                .rotationEffect(.degrees(-12))
                .offset(x: 40, y: 5)
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

private struct GitHubLogoBadge: View {
    var diameter: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.surfaceElevated)
            Circle()
                .strokeBorder(GitHubBrandPalette.mark.opacity(0.84), lineWidth: 3)
            if let githubLogo = GitHubLogoAsset.image {
                Image(nsImage: githubLogo)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: diameter * 1.08, height: diameter * 1.08)
            } else {
                GitHubMarkShape()
                    .fill(GitHubBrandPalette.ink)
                    .padding(diameter * 0.20)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.black.opacity(0.14), radius: 5, x: 0, y: 3)
    }
}

private struct GitHubMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 16
        let xOffset = rect.midX - (8 * scale)
        let yOffset = rect.midY - (8 * scale)

        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: xOffset + (x * scale), y: yOffset + (y * scale))
        }

        var path = Path()
        path.move(to: point(8.0, 14.6))
        path.addCurve(to: point(2.2, 8.3), control1: point(4.5, 14.6), control2: point(2.2, 11.6))
        path.addCurve(to: point(4.0, 4.6), control1: point(2.2, 6.8), control2: point(2.9, 5.4))
        path.addCurve(to: point(3.7, 2.0), control1: point(3.7, 3.3), control2: point(3.7, 2.5))
        path.addCurve(to: point(6.0, 3.0), control1: point(4.4, 2.0), control2: point(5.4, 2.5))
        path.addCurve(to: point(8.0, 2.8), control1: point(6.7, 2.9), control2: point(7.3, 2.8))
        path.addCurve(to: point(10.0, 3.0), control1: point(8.7, 2.8), control2: point(9.3, 2.9))
        path.addCurve(to: point(12.3, 2.0), control1: point(10.6, 2.5), control2: point(11.6, 2.0))
        path.addCurve(to: point(12.0, 4.6), control1: point(12.3, 2.5), control2: point(12.3, 3.3))
        path.addCurve(to: point(13.8, 8.3), control1: point(13.1, 5.4), control2: point(13.8, 6.8))
        path.addCurve(to: point(10.2, 13.8), control1: point(13.8, 10.9), control2: point(12.3, 13.0))
        path.addCurve(to: point(8.0, 14.6), control1: point(9.6, 14.2), control2: point(8.7, 14.6))
        path.closeSubpath()
        return path
    }
}

private struct HomeVoiceProfileCard: View {
    let stats: ComputedStats
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var classifier = UserTypeClassifier.shared
    @State private var isHovered = false

    let onOpenInsights: () -> Void

    var body: some View {
        Button(action: onOpenInsights) {
            VStack(spacing: 0) {
                VoiceProfileMeshHeader(height: 78, watermarkOpacity: 0.20)

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                                .offset(x: isHovered ? 2 : 0, y: isHovered ? -2 : 0)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(profileTitle)
                                .font(.vfCalloutMedium)
                                .foregroundColor(Theme.textPrimary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(profileSubtitle)
                                .font(.vfCaption)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        HStack(spacing: 8) {
                            profileStat(value: wordsLabel, label: "words")
                            profileStat(value: wpmLabel, label: "wpm")
                            profileStat(value: styleLabel, label: "style")
                        }

                        if let signalLabel {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkle")
                                    .font(.system(size: 8, weight: .semibold))
                                Text(signalLabel)
                                    .font(.vfMicro)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .foregroundColor(Theme.textPrimary)
                            .padding(.horizontal, 8)
                            .frame(height: 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Capsule(style: .continuous).fill(signalChipFill))
                            .overlay(Capsule(style: .continuous).strokeBorder(signalChipBorder, lineWidth: 1))
                        }
                    }
                    .padding(14)
                    .padding(.top, 24)

                    VordiProfileBadge(diameter: 52)
                        .offset(x: 14, y: -28)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(cardBorder, lineWidth: 1)
            )
            .shadow(color: isHovered ? Theme.Shadow.card.color : Color.clear,
                    radius: Theme.Shadow.card.radius,
                    x: 0,
                    y: Theme.Shadow.card.y)
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .help("Open the voice profile in Insights")
        .accessibilityLabel("Open voice profile in Insights")
    }

    private var profileTitle: String {
        if let classification = classifier.classification {
            return "\(classification.role.displayLabel) voice"
        }
        if classifier.isClassifying {
            return "Analyzing voice"
        }
        return "Voice profile not generated yet"
    }

    private var profileSubtitle: String {
        if let classification = classifier.classification {
            return classification.headline
        }
        if classifier.isClassifying {
            return "Reading saved transcripts from your local run history."
        }
        let eligibility = classifier.eligibility()
        if eligibility.isUnlocked {
            return "Sync in Insights to generate your working style."
        }
        return "\(eligibility.qualifyingRuns) of \(eligibility.requiredRuns) qualifying dictations captured."
    }

    private var wordsLabel: String {
        guard stats.totalWords > 0 else { return "—" }
        if stats.totalWords >= 1_000 {
            return String(format: "%.1fk", Double(stats.totalWords) / 1_000.0)
        }
        return stats.totalWords.formatted()
    }

    private var wpmLabel: String {
        stats.averageWPM > 0 ? "\(stats.averageWPM)" : "—"
    }

    private var styleLabel: String {
        if let classification = classifier.classification {
            return classification.role.displayLabel
        }
        if classifier.isClassifying {
            return "Syncing"
        }
        return "Pending"
    }

    private var signalLabel: String? {
        if let signal = classifier.classification?.signals.first {
            return signal
        }
        if classifier.isClassifying {
            return "Analyzing saved transcripts"
        }
        let eligibility = classifier.eligibility()
        if eligibility.isUnlocked {
            return "Ready to generate in Insights"
        }
        let remaining = max(0, eligibility.requiredRuns - eligibility.qualifyingRuns)
        return "\(remaining) more qualifying dictations needed"
    }

    private var cardBorder: Color {
        if isHovered {
            return VoiceProfilePurplePalette.accent.opacity(colorScheme == .dark ? 0.44 : 0.24)
        }
        return Theme.divider
    }

    private var signalChipFill: Color {
        colorScheme == .dark
            ? VoiceProfilePurplePalette.night.opacity(0.44)
            : Theme.surface
    }

    private var signalChipBorder: Color {
        colorScheme == .dark
            ? VoiceProfilePurplePalette.accentLift.opacity(0.30)
            : VoiceProfilePurplePalette.accent.opacity(0.14)
    }

    private func profileStat(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.vfCalloutSemibold)
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .monospacedDigit()
            Text(label)
                .font(.vfMicro)
                .foregroundColor(Theme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - SidebarStarBlock

/// Compact GitHub star prompt for the sidebar. Different design from
/// the wide `StarRepoCard`. Narrow column gets a GitHub-branded profile
/// treatment: dark identity header, live star count, and stargazer proof.
/// Whole block is itself the link target.
///
/// Why a separate component instead of resizing StarRepoCard: the wide
/// card has horizontal HStacks and avatar rows that don't compose into
/// a 180pt-wide column. Two intents, two components, both pulling from
/// the same `GitHubMetadataCache.shared` so the data stays coherent.
struct SidebarStarBlock: View {
    @ObservedObject private var github = GitHubMetadataCache.shared
    @State private var isHovered = false

    private let openURL: (URL) -> Void = { NSWorkspace.shared.open($0) }

    var body: some View {
        Button {
            openURL(GitHubMetadataCache.repoHTMLURL)
        } label: {
            VStack(spacing: 0) {
                GitHubBrandHeader(height: 68)

                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 9) {
                        HStack(alignment: .top, spacing: Theme.Space.sm) {
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.textSecondary)
                                .offset(x: isHovered ? 2 : 0, y: isHovered ? -2 : 0)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 7) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Theme.textPrimary)
                                Text(AppBrand.name)
                                    .font(.vfCalloutSemibold)
                                    .foregroundColor(Theme.textPrimary)
                            }
                            Text("Open source dictation app")
                                .font(.vfCaption)
                                .foregroundColor(Theme.textSecondary)
                                .lineLimit(1)
                        }

                        Text("Help more builders discover the local-first tool.")
                            .font(.vfCaption)
                            .foregroundColor(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .center, spacing: Theme.Space.sm) {
                            starCountBadge
                            Spacer(minLength: Theme.Space.sm)
                            if !github.recentStargazers.isEmpty {
                                stargazerAvatarRow
                            }
                        }

                        Text("\(GitHubMetadataCache.repoOwner)/\(GitHubMetadataCache.repoName)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(12)
                    .padding(.top, 24)

                    GitHubLogoBadge(diameter: 48)
                        .offset(x: 12, y: -26)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isHovered ? Theme.dividerStrong : Theme.divider, lineWidth: 1)
            )
            .shadow(color: isHovered ? Theme.Shadow.card.color : Color.clear,
                    radius: Theme.Shadow.card.radius,
                    x: 0,
                    y: Theme.Shadow.card.y)
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) {
                isHovered = hovering
            }
        }
        .help("Open the project repo on GitHub, a star helps this project grow.")
        .task { github.refreshIfStale() }
    }

    private var starCountBadge: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "star.fill")
                .font(.system(size: 10, weight: .semibold))
            Text("\(starCountLabel) stars")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .foregroundColor(Theme.textPrimary)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(Capsule(style: .continuous).fill(Theme.surface))
        .overlay(Capsule(style: .continuous).strokeBorder(Theme.divider, lineWidth: 1))
    }

    /// Overlapping avatar row, visual proof that real people are starring
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
                    Circle().stroke(Theme.surfaceElevated, lineWidth: 1.5)
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

/// Compatibility wrapper for the former Scratchpad tab. The route remains
/// `.scratchpad` so notifications and saved sidebar state keep working, while
/// the user-facing surface is now the persisted rich-text Notes workspace.
struct ScratchpadView: View {
    @ObservedObject var runStore: RunStore
    let onOpenFloatingNotes: () -> Void

    var body: some View {
        NotesWorkspaceView(
            surface: .dashboard,
            onOpenFloatingNotes: onOpenFloatingNotes
        )
    }
}
