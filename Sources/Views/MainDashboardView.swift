import SwiftUI
import AppKit

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
        case general = "General"
        case settings = "Settings"
        case runLog = "Run Log"

        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .settings: return "slider.horizontal.3"
            case .runLog:   return "clock.arrow.circlepath"
            }
        }
    }

    // MARK: - Persisted state
    // All @State fields mirror UserDefaults and write back on change. This
    // keeps SwiftUI bindings simple at the cost of a few extra writes — fine
    // for a settings surface that changes at most a few times per session.

    @State private var selectedTab: Tab = .general

    // General tab
    @State private var selectedLanguage: String = UserDefaults.standard.string(forKey: "language") ?? "hi"
    @State private var processingMode: String = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
    @State private var runLogEnabled: Bool = {
        if UserDefaults.standard.object(forKey: "run_log_enabled") == nil { return true }
        return UserDefaults.standard.bool(forKey: "run_log_enabled")
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
            // Sidebar
            VStack(spacing: 4) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    sidebarButton(tab)
                }
                Spacer()
            }
            .frame(width: 140)
            .padding(.vertical, 12)
            .padding(.horizontal, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))

            Divider()

            // Content
            Group {
                switch selectedTab {
                case .general:  generalContent
                case .settings: settingsContent
                case .runLog:   RunLogView(runStore: runStore)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 720, minHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            permissionService.refreshStatus()
            localDetector.detect()
        }
    }

    @ViewBuilder
    private func sidebarButton(_ tab: Tab) -> some View {
        Button(action: { selectedTab = tab }) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.subheadline)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundColor(selectedTab == tab ? .accentColor : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - General tab

    /// Layout order per product spec:
    /// 1. About   2. Language   3. Transcription Mode
    /// 4. Run Log toggle   5. Microphone Filter   6. Status
    private var generalContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                recordingHeader
                StarRepoCard()
                aboutCard
                languageCard
                transcriptionModeCard
                runLogToggleCard
                microphoneFilterCard
                statusCard
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(alignment: .leading, spacing: 10) {
                Text("Language")
                    .font(.headline)
                Picker("Language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.code) { lang in
                        Text(lang.label).tag(lang.code)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: selectedLanguage) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "language")
                }
                Text("Auto-detect picks the language per recording. Lock to Hindi or English if you're always speaking one. Locking to English will also translate any Hindi you speak into English.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var transcriptionModeCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                Text("Transcription Mode")
                    .font(.headline)
                Picker("Mode", selection: $processingMode) {
                    ForEach(processingModes, id: \.id) { m in
                        Text(m.label).tag(m.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: processingMode) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "processing_mode")
                }
                Text("Dictation keeps your spoken phrasing. Rewrite converts a spoken draft into cleaner final intent text.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var runLogToggleCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Run Log").font(.headline)
                    Spacer()
                    Toggle("", isOn: $runLogEnabled)
                        .labelsHidden()
                        .onChange(of: runLogEnabled) { newValue in
                            UserDefaults.standard.set(newValue, forKey: "run_log_enabled")
                        }
                }
                Text("Save audio, transcripts, and prompts locally for each dictation. Last 20 runs are kept; nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 26))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Settings")
                    .font(.system(size: 20, weight: .bold))
                Text("Credentials, providers, and post-processing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }

    private var realtimeStreamingCard: some View {
        cardContainer {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Realtime Streaming")
                                .font(.headline)
                            Text("BETA")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.orange))
                        }
                        Text("Lower perceived latency by streaming audio to OpenAI while you speak.")
                            .font(.caption)
                            .foregroundColor(.secondary)
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
                    .font(.headline)

                Picker("", selection: $provider) {
                    Text("OpenAI  ·  Paid  ·  Hindi+English").tag(TranscriptionProvider.openai.rawValue)
                    Text("Groq  ·  Free  ·  English only").tag(TranscriptionProvider.groq.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: provider) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "transcription_provider")
                }

                Divider()

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
                    .font(.headline)

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
            VStack(alignment: .leading, spacing: 10) {
                Text("Output Style")
                    .font(.headline)
                Picker("Output style", selection: $outputMode) {
                    ForEach(outputModes, id: \.id) { mode in
                        Text(mode.label).tag(mode.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: outputMode) { newValue in
                    UserDefaults.standard.set(newValue, forKey: "output_mode")
                }
                Text(outputStyleHelperText)
                    .font(.caption)
                    .foregroundColor(.secondary)
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )
    }

    @ViewBuilder
    private func keyRow(
        title: String,
        placeholder: String,
        help: String,
        text: Binding<String>,
        onCommit: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).fontWeight(.medium)
            HStack {
                SecureField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onCommit)
                Button("Save") { onCommit() }
                    .buttonStyle(.bordered)
            }
            .onChange(of: text.wrappedValue) { _ in
                // Autosave on every keystroke — no reliance on Save button.
                onCommit()
            }
            Text(help).font(.caption).foregroundColor(.secondary)
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
