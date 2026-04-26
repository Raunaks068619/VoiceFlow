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
    // Background — warm cream, not pure white. The half-degree of warmth
    // reads as "softer, more human" vs. stock macOS white.
    static let canvas          = Color(red: 0.961, green: 0.945, blue: 0.918)   // #F5F1EA
    static let surface         = Color(red: 0.980, green: 0.968, blue: 0.945)   // #FAF7F1
    static let surfaceElevated = Color.white
    // Hero/dark surface — warm dark brown, NOT pure black. Pure black on a
    // cream canvas reads as cheap (the contrast is too violent). A warm
    // brown carries the same "dark, premium" weight without screaming.
    static let surfaceDark     = Color(red: 0.094, green: 0.082, blue: 0.067)   // #18150D
    static let surfaceDarkSoft = Color(red: 0.149, green: 0.129, blue: 0.106)   // #26211B — slightly lighter for nested elements

    // Text
    static let textPrimary     = Color(red: 0.102, green: 0.090, blue: 0.078)   // #1A1714
    static let textSecondary   = Color(red: 0.353, green: 0.329, blue: 0.314)   // #5A5450
    static let textTertiary    = Color(red: 0.557, green: 0.518, blue: 0.486)
    static let textOnDark      = Color(red: 0.961, green: 0.945, blue: 0.918)

    // Accent — the orange "fn" badge. Used sparingly: hotkey pills, active
    // state, primary CTAs.
    static let accent          = Color(red: 1.000, green: 0.549, blue: 0.102)   // #FF8C1A
    static let accentSoft      = Color(red: 1.000, green: 0.549, blue: 0.102).opacity(0.15)

    // Status
    static let success         = Color(red: 0.196, green: 0.647, blue: 0.404)
    static let warning         = Color(red: 0.902, green: 0.549, blue: 0.067)
    static let danger          = Color(red: 0.843, green: 0.275, blue: 0.275)

    // Dividers / borders
    static let divider         = Color.black.opacity(0.06)
    static let dividerStrong   = Color.black.opacity(0.12)

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

    private let cloudPolishOptions: [(id: String, label: String)] = [
        ("openai::gpt-4.1-mini", "OpenAI · gpt-4.1-mini (default)"),
        ("openai::gpt-4.1-nano", "OpenAI · gpt-4.1-nano (cheaper, stronger role adherence)")
    ]

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

            // Content
            Group {
                switch selectedTab {
                case .home:       homeContent
                case .scratchpad: ScratchpadView(runStore: runStore)
                case .runLog:     RunLogView(runStore: runStore)
                case .settings:   settingsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
        .frame(minWidth: 860, minHeight: 640)
        // Lock to light appearance — our Theme is cream-bg / dark-text.
        // Without this, system semantic colors (.primary/.secondary) flip
        // to near-white on dark-mode Macs, making all text invisible.
        .preferredColorScheme(.light)
        // Global accent = orange, so segmented pickers, buttons, and
        // focused text fields use the brand color instead of system blue.
        .tint(Theme.accent)
        .onAppear {
            permissionService.refreshStatus()
            localDetector.detect()
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
    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                // Top section — greeting, hero, stats side-by-side
                greetingBlock
                HStack(alignment: .top, spacing: Theme.Space.md) {
                    heroCard
                    statsCardCompact
                }
                // Full date-grouped transcript timeline
                dictationsTimeline
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            }
            Spacer()
        }
        .padding(Theme.Space.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .themedHeroCard()
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
                    timelineRow(rows[i])
                    if i < rows.count - 1 {
                        Divider().background(Theme.divider)
                    }
                }
            }
            .themedCard(padding: 0)
        }
    }

    private func timelineRow(_ summary: RunSummary) -> some View {
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
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
                Text("Language")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                ThemedPillTabs(
                    options: languages.map { (id: $0.code, label: $0.label) },
                    selection: $selectedLanguage
                )
                .onChange(of: selectedLanguage) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "language")
                }
                Text("Auto-detect picks the language per recording. Lock to Hindi or English if you're always speaking one. Locking to English will also translate any Hindi you speak into English.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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

    private var microphoneFilterCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Microphone Filter")
                    .font(.headline)
                Slider(value: $noiseGateThreshold, in: 0.001...0.05, step: 0.001)
                    .onChange(of: noiseGateThreshold) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "noise_gate_threshold")
                    }
                Text("Sensitivity: \(String(format: "%.3f", noiseGateThreshold)) — higher filters more background noise. Bump this up if quiet room noise is being transcribed as words.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
                footerActions
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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

                ThemedPillTabs(
                    options: [
                        (id: TranscriptionProvider.groq.rawValue,   label: "Groq · Free · English"),
                        (id: TranscriptionProvider.openai.rawValue, label: "OpenAI · Paid · Hi+En")
                    ],
                    selection: $provider
                )
                .onChange(of: provider) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "transcription_provider")
                }

                Divider().background(Theme.divider)

                if provider == TranscriptionProvider.groq.rawValue {
                    keyRow(
                        title: "Groq API Key",
                        placeholder: "gsk_...",
                        help: "Free tier. Get a key at console.groq.com/keys",
                        text: $groqKey,
                        onCommit: {
                            UserDefaults.standard.set(groqKey, forKey: "groq_api_key")
                            flashSaved()
                        }
                    )
                } else {
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

                if showKeySaved {
                    Text("✓ Saved")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
        }
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
                Text("Output Style")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                ThemedPillTabs(
                    options: outputModes.map { (id: $0.id, label: $0.label) },
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
        // ZStack lets the placeholder sit above an empty TextEditor and
        // disappear once the user types or a transcript lands. SwiftUI's
        // TextEditor has no native placeholder API — this is the standard
        // workaround. `.allowsHitTesting(false)` makes sure the placeholder
        // never eats clicks meant for the editor underneath.
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 14))
                .foregroundColor(Theme.textPrimary)
                .scrollContentBackground(.hidden)
                .background(Theme.surface)

            if text.isEmpty {
                // Padding values mirror macOS TextEditor's internal
                // textContainerInset (~5pt horizontal, ~8pt vertical) so
                // the placeholder sits exactly where typed text will
                // appear — no visible jump when the user starts typing.
                Text("Start dictating with fn from anywhere — or just type here. Your scratchpad auto-fills as transcripts come in.")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.textTertiary)
                    .padding(.leading, 5)
                    .padding(.top, 8)
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
