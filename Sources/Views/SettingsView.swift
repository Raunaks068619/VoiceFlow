import SwiftUI
import AppKit
import AVFoundation

struct SettingsView: View {
    @ObservedObject var permissionService: PermissionService
    @StateObject private var localDetector = LocalModelDetector.shared
    @State private var apiKey: String = ""
    @State private var groqApiKey: String = ""
    @State private var provider: String = TranscriptionProvider.openai.rawValue
    @State private var selectedLanguage: String = "hi"
    @State private var outputMode: String = TranscriptOutputStyle.cleanHinglish.rawValue
    @State private var processingMode: String = TranscriptProcessingMode.dictation.rawValue
    @State private var polishBackendId: String = PolishBackend.defaultId
    @State private var noiseGateThreshold: Double = 0.015
    @State private var runLogEnabled: Bool = true
    @State private var runLogCapped: Bool = true
    @State private var showSaveConfirmation = false

    /// Cloud polish-model options. `gpt-4.1-nano` is included as an escape
    /// hatch — it's cheaper and empirically less eager to answer questions
    /// than `gpt-4.1-mini`, at the cost of slightly worse Hinglish.
    private let cloudPolishOptions: [(id: String, label: String)] = [
        ("openai::gpt-4.1-mini", "OpenAI · gpt-4.1-mini (default)"),
        ("openai::gpt-4.1-nano", "OpenAI · gpt-4.1-nano (cheaper, stronger role adherence)")
    ]

    /// Computed dropdown options: cloud first, then discovered local models.
    /// Local models appear only when a server (LM Studio / Ollama) is running
    /// — graceful degradation on no detection.
    private var polishOptions: [(id: String, label: String)] {
        var opts = cloudPolishOptions
        for model in localDetector.models {
            opts.append((model.id, "\(model.provider.label) · \(model.name)"))
        }
        return opts
    }

    let providers = [
        (TranscriptionProvider.openai.rawValue, "OpenAI (Paid · Hindi+English)"),
        (TranscriptionProvider.groq.rawValue, "Groq (Free · English only)")
    ]
    
    let languages = [
        ("hi", "Hindi"),
        ("en", "English"),
        ("auto", "Auto-detect")
    ]

    let outputModes = [
        (TranscriptOutputStyle.verbatim.rawValue, "Verbatim"),
        (TranscriptOutputStyle.clean.rawValue, "Clean"),
        (TranscriptOutputStyle.cleanHinglish.rawValue, "Clean + Hinglish")
    ]

    let processingModes = [
        (TranscriptProcessingMode.dictation.rawValue, "Dictation"),
        (TranscriptProcessingMode.rewrite.rawValue, "Rewrite")
    ]
    
    var body: some View {
        Form {
            Section("Transcription Provider") {
                Picker("Provider", selection: $provider) {
                    ForEach(providers, id: \.0) { value, label in
                        Text(label).tag(value)
                    }
                }
                .pickerStyle(.segmented)

                Text("Groq is free but English-only. OpenAI supports Hindi + Hinglish.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.headline)

                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Get your API key from openai.com/api-keys")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Groq API Key")
                        .font(.headline)

                    SecureField("gsk_...", text: $groqApiKey)
                        .textFieldStyle(.roundedBorder)

                    Text("Free tier: console.groq.com/keys — English only.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Language") {
                Picker("Transcription Language", selection: $selectedLanguage) {
                    ForEach(languages, id: \.0) { code, name in
                        Text(name).tag(code)
                    }
                }
                .pickerStyle(.segmented)
                
                Text("Select 'Auto-detect' to automatically identify the language")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section("About") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("VoiceFlow v1.0.0")
                        .font(.headline)
                    Text("Voice typing app powered by OpenAI Whisper")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Output Quality") {
                Picker("Text Style", selection: $outputMode) {
                    ForEach(outputModes, id: \.0) { mode, label in
                        Text(label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Clean + Hinglish removes fillers, fixes grammar, and enforces English characters only.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Post-Processing Model") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Polish model", selection: $polishBackendId) {
                        ForEach(polishOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            localDetector.detect()
                        } label: {
                            if localDetector.isDetecting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Refresh local models")
                            }
                        }
                        .disabled(localDetector.isDetecting)

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

                    // Hint when user is on a local model but server might be down
                    if polishBackendId.hasPrefix("lmstudio::") || polishBackendId.hasPrefix("ollama::") {
                        if !polishOptions.contains(where: { $0.id == polishBackendId }) {
                            Text("⚠️ Selected local model is not currently detected. Dictation will fail until you start the server and refresh.")
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            Section("Transcription Mode") {
                Picker("Mode", selection: $processingMode) {
                    ForEach(processingModes, id: \.0) { mode, label in
                        Text(label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text("Dictation keeps spoken phrasing. Rewrite converts to cleaner final intent text.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Run Log") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Keep run history", isOn: $runLogEnabled)
                    Toggle("Cap at 20 runs", isOn: $runLogCapped)
                        .disabled(!runLogEnabled)
                    Text(runLogCaptionText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Microphone Filter") {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $noiseGateThreshold, in: 0.001...0.05, step: 0.001)
                    Text("Sensitivity: \(String(format: "%.3f", noiseGateThreshold)) (higher filters more background noise)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Permission Health") {
                if let warning = permissionService.environmentWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                permissionRow(
                    title: "Microphone",
                    state: permissionService.microphoneState,
                    onRequest: { permissionService.requestMicrophoneAccess() },
                    onOpenSettings: { permissionService.openPrivacyPane(.microphone) }
                )
                permissionRow(
                    title: "Accessibility",
                    state: permissionService.accessibilityState,
                    onRequest: { permissionService.requestAccessibilityAccess() },
                    onOpenSettings: { permissionService.openPrivacyPane(.accessibility) }
                )
                permissionRow(
                    title: "Input Monitoring",
                    state: permissionService.inputMonitoringState,
                    onRequest: { permissionService.requestInputMonitoringAccess() },
                    onOpenSettings: { permissionService.openPrivacyPane(.inputMonitoring) }
                )

                if !permissionService.allRequiredGranted {
                    Text("Global hotkeys will not work until required permissions are granted.")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Button("Re-check permissions") {
                    permissionService.refreshStatus()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 460)
        .padding()
        .onAppear {
            loadSettings()
            permissionService.refreshStatus()
            // Kick off a local-model probe on every Settings open. Cheap (1.5s
            // timeout per provider, runs in parallel) and keeps the picker fresh.
            localDetector.detect()
        }
        .onChange(of: apiKey) { _ in
            saveSettings()
        }
        .onChange(of: groqApiKey) { _ in
            saveSettings()
        }
        .onChange(of: provider) { _ in
            saveSettings()
        }
        .onChange(of: selectedLanguage) { _ in
            saveSettings()
        }
        .onChange(of: outputMode) { _ in
            saveSettings()
        }
        .onChange(of: processingMode) { _ in
            saveSettings()
        }
        .onChange(of: polishBackendId) { _ in
            saveSettings()
        }
        .onChange(of: noiseGateThreshold) { _ in
            saveSettings()
        }
        .onChange(of: runLogEnabled) { _ in
            saveSettings()
        }
        .onChange(of: runLogCapped) { newValue in
            saveSettings()
            // Toggling the cap ON with an over-cap history should feel
            // immediate. Without this, the list would keep showing the
            // extra runs until the next dictation triggered a save().
            if newValue {
                RunStore.shared.applyCap()
            }
        }
    }

    /// Contextual caption under the Run Log toggles — explains what the
    /// current combination of switches actually does. More useful than a
    /// static string, and cheap to compute.
    private var runLogCaptionText: String {
        if !runLogEnabled {
            return "Run history is off. No audio, transcripts, or prompts are saved to disk."
        }
        if runLogCapped {
            return "Saves audio, transcripts, and prompts locally. Oldest entries are pruned after 20 runs."
        }
        return "Saves audio, transcripts, and prompts locally. No cap — history grows until you clear it manually."
    }
    
    private func loadSettings() {
        apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        groqApiKey = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
        provider = UserDefaults.standard.string(forKey: "transcription_provider") ?? TranscriptionProvider.openai.rawValue
        selectedLanguage = UserDefaults.standard.string(forKey: "language") ?? "hi"
        outputMode = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.cleanHinglish.rawValue
        processingMode = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
        polishBackendId = UserDefaults.standard.string(forKey: PolishBackend.userDefaultsKey) ?? PolishBackend.defaultId
        let storedThreshold = UserDefaults.standard.double(forKey: "noise_gate_threshold")
        noiseGateThreshold = storedThreshold == 0 ? 0.015 : storedThreshold
        if UserDefaults.standard.object(forKey: "run_log_enabled") != nil {
            runLogEnabled = UserDefaults.standard.bool(forKey: "run_log_enabled")
        } else {
            runLogEnabled = true
        }
        if UserDefaults.standard.object(forKey: "run_log_cap_enabled") != nil {
            runLogCapped = UserDefaults.standard.bool(forKey: "run_log_cap_enabled")
        } else {
            runLogCapped = true
        }
    }

    private func saveSettings() {
        UserDefaults.standard.set(apiKey, forKey: "openai_api_key")
        UserDefaults.standard.set(groqApiKey, forKey: "groq_api_key")
        UserDefaults.standard.set(provider, forKey: "transcription_provider")
        UserDefaults.standard.set(selectedLanguage, forKey: "language")
        UserDefaults.standard.set(outputMode, forKey: "output_mode")
        UserDefaults.standard.set(processingMode, forKey: "processing_mode")
        UserDefaults.standard.set(polishBackendId, forKey: PolishBackend.userDefaultsKey)
        UserDefaults.standard.set(noiseGateThreshold, forKey: "noise_gate_threshold")
        UserDefaults.standard.set(runLogEnabled, forKey: "run_log_enabled")
        UserDefaults.standard.set(runLogCapped, forKey: "run_log_cap_enabled")
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        state: PermissionState,
        onRequest: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            permissionBadge(ok: state.isGranted)
            Button("Request") {
                onRequest()
            }
            Button("Open Settings") {
                onOpenSettings()
            }
        }
    }

    @ViewBuilder
    private func permissionBadge(ok: Bool) -> some View {
        Text(ok ? "Granted" : "Missing")
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ok ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
            .foregroundColor(ok ? .green : .orange)
            .clipShape(Capsule())
    }
}

// MARK: - Onboarding Wizard

/// Four-step onboarding flow. Isolated from the main dashboard — first-run
/// only (or user-initiated re-run from Settings → Reset).
///
/// Steps:
///   1. Welcome       — what VoiceFlow does, in 15 seconds
///   2. Permissions   — mic + accessibility + input monitoring, with
///                      guided fallbacks for when TCC auto-prompt no-ops
///   3. API Key       — provider choice + key entry, Groq-first (free)
///   4. Test          — hold-fn demo with live transcript feedback
///
/// Design decisions:
/// - State lives in OnboardingCoordinator (ObservableObject), not in a
///   god-view struct. Each step view takes bindings/closures from the
///   coordinator — testable, decoupled.
/// - Linear nav (back/next) but back is always available. No "jump to
///   step 3" affordance — order matters (permissions gate test, API key
///   gates usefulness).
/// - "Skip for now" available on Permissions + API Key for the power-user
///   who knows what they're doing and doesn't want to be trapped.
/// - Completion criteria: user successfully reaches the end of Test step
///   (clicks Finish). We don't require a successful recording — some
///   setups have broken Fn mapping and will only work after external fixes.
enum OnboardingStep: Int, CaseIterable {
    case welcome, permissions, apiKey, test

    var title: String {
        switch self {
        case .welcome:     return "Welcome"
        case .permissions: return "Permissions"
        case .apiKey:      return "API Key"
        case .test:        return "Test"
        }
    }
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome

    func advance() {
        let next = OnboardingStep(rawValue: currentStep.rawValue + 1)
        if let next {
            withAnimation(.easeInOut(duration: 0.25)) { currentStep = next }
        }
    }

    func back() {
        let prev = OnboardingStep(rawValue: currentStep.rawValue - 1)
        if let prev {
            withAnimation(.easeInOut(duration: 0.25)) { currentStep = prev }
        }
    }

    var isFirstStep: Bool { currentStep == .welcome }
    var isLastStep:  Bool { currentStep == .test }
}

struct OnboardingView: View {
    @ObservedObject var permissionService: PermissionService
    let onOpenSettings: () -> Void
    let onDone: () -> Void

    @StateObject private var coordinator = OnboardingCoordinator()
    @ObservedObject private var runStore = RunStore.shared

    var body: some View {
        VStack(spacing: 0) {
            progressBar
            Divider().background(Theme.divider)

            ScrollView {
                Group {
                    switch coordinator.currentStep {
                    case .welcome:
                        OnboardingWelcomeStep()
                    case .permissions:
                        OnboardingPermissionsStep(permissionService: permissionService)
                    case .apiKey:
                        OnboardingAPIKeyStep()
                    case .test:
                        OnboardingTestStep(runStore: runStore)
                    }
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().background(Theme.divider)
            navBar
        }
        .frame(width: 600, height: 640)
        .background(Theme.canvas)
        .preferredColorScheme(.light)
        .tint(Theme.accent)
        .onAppear {
            permissionService.refreshStatus()
        }
    }

    // MARK: Progress indicator

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= coordinator.currentStep.rawValue
                          ? Theme.accent
                          : Theme.divider)
                    .frame(height: 3)
            }
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, Theme.Space.lg)
        .padding(.bottom, Theme.Space.md)
    }

    // MARK: Nav bar (Back / Skip / Next / Finish)

    private var navBar: some View {
        HStack(spacing: Theme.Space.md) {
            // Back — hidden on first step so users don't hit dead-end
            if !coordinator.isFirstStep {
                Button("Back") { coordinator.back() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textSecondary)
                    .font(.system(size: 13, weight: .medium))
            }

            Spacer()

            // Skip — only on non-first, non-last steps. Lets power users
            // bypass without being trapped.
            if !coordinator.isFirstStep && !coordinator.isLastStep {
                Button("Skip") { coordinator.advance() }
                    .buttonStyle(.plain)
                    .foregroundColor(Theme.textTertiary)
                    .font(.system(size: 12, weight: .medium))
            }

            // Next / Finish
            Button {
                if coordinator.isLastStep {
                    UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
                    onDone()
                } else {
                    coordinator.advance()
                }
            } label: {
                Text(coordinator.isLastStep ? "Finish" : "Next")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .fill(Theme.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.vertical, Theme.Space.md)
    }
}

// MARK: - Step 1: Welcome

private struct OnboardingWelcomeStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            // Hero title
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Voice typing,")
                    .font(.system(size: 32, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textPrimary)
                HotkeyBadge(label: "fn")
                Text("fast.")
                    .font(.system(size: 32, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textPrimary)
            }

            Text("VoiceFlow turns speech into clean text, anywhere you can type on your Mac. Hold the fn key, speak, release — it just works.")
                .font(.system(size: 15))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, Theme.Space.md)

            VStack(alignment: .leading, spacing: 14) {
                bulletRow(
                    icon: "lock.shield",
                    title: "Stays on your Mac",
                    copy: "Audio + transcripts never leave your device except to your own Whisper provider. No account, no cloud, no telemetry.")
                bulletRow(
                    icon: "globe",
                    title: "Hindi, English, Hinglish",
                    copy: "Speak naturally — the polish layer handles code-switching, fixes grammar, and respects your spoken phrasing.")
                bulletRow(
                    icon: "bolt.fill",
                    title: "Fn-hold, anywhere",
                    copy: "Works system-wide: Slack, Mail, your editor, a terminal, a GitHub comment. One hotkey, one mental model.")
            }
            .padding(Theme.Space.lg)
            .themedCard()

            Text("Next up: a quick 3-step setup. Takes ~2 minutes.")
                .font(.system(size: 12))
                .foregroundColor(Theme.textTertiary)
                .padding(.top, Theme.Space.sm)
        }
    }

    private func bulletRow(icon: String, title: String, copy: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Theme.accent)
                .frame(width: 20, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(copy)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Step 2: Permissions

private struct OnboardingPermissionsStep: View {
    @ObservedObject var permissionService: PermissionService

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Grant three permissions.")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textPrimary)

            Text("VoiceFlow needs to hear you (microphone), type for you (accessibility), and know when you press the fn key (input monitoring). macOS won't let us do any of this silently — that's a feature.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let warning = permissionService.environmentWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(Theme.warning)
                    Text(warning)
                        .font(.system(size: 12))
                        .foregroundColor(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .themedCard(padding: 0)
            }

            VStack(spacing: Theme.Space.md) {
                permissionCard(
                    title: "Microphone",
                    subtitle: "Required — to hear your voice",
                    state: permissionService.microphoneState,
                    pane: .microphone,
                    request: { permissionService.requestMicrophoneAccess() }
                )
                permissionCard(
                    title: "Accessibility",
                    subtitle: "Required — to type the transcript into other apps",
                    state: permissionService.accessibilityState,
                    pane: .accessibility,
                    request: { permissionService.requestAccessibilityAccess() }
                )
                permissionCard(
                    title: "Input Monitoring",
                    subtitle: "Required — to detect fn key presses",
                    state: permissionService.inputMonitoringState,
                    pane: .inputMonitoring,
                    request: { permissionService.requestInputMonitoringAccess() }
                )
            }

            if !permissionService.allRequiredGranted {
                Text("TCC prompts sometimes silently no-op on ad-hoc builds. If a toggle doesn't appear after clicking Grant, use Open Settings to enable it manually.")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.sm)
            }
        }
    }

    private func permissionCard(
        title: String,
        subtitle: String,
        state: PermissionState,
        pane: PermissionPane,
        request: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Theme.Space.md) {
            Image(systemName: state.isGranted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundColor(state.isGranted ? Theme.success : Theme.textTertiary)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            if !state.isGranted {
                Button("Grant") { request() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                            .fill(Theme.accent)
                    )
                    .foregroundColor(.white)
                Button {
                    permissionService.openPrivacyPane(pane)
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Space.md)
        .themedCard(padding: 0)
    }
}

// MARK: - Step 3: API Key

private struct OnboardingAPIKeyStep: View {
    @State private var provider: String = UserDefaults.standard.string(forKey: "transcription_provider")
        ?? TranscriptionProvider.groq.rawValue   // default to Groq — free escape hatch
    @State private var openAIKey: String = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var groqKey:   String = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            Text("Connect a transcription provider.")
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .foregroundColor(Theme.textPrimary)

            Text("Bring your own key. VoiceFlow doesn't proxy your audio — it hits your provider directly, so you pay cents, not a subscription.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Provider picker — segmented, Groq-first because it's free
            HStack(spacing: 0) {
                providerPill(
                    id: TranscriptionProvider.groq.rawValue,
                    title: "Groq",
                    sub: "Free · English only")
                providerPill(
                    id: TranscriptionProvider.openai.rawValue,
                    title: "OpenAI",
                    sub: "Paid · Hindi + English")
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                    .fill(Theme.divider)
            )

            // Key entry card — contents flip based on provider
            VStack(alignment: .leading, spacing: 10) {
                if provider == TranscriptionProvider.groq.rawValue {
                    Text("Groq API Key")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    SecureField("gsk_...", text: $groqKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: groqKey) { _ in
                            UserDefaults.standard.set(groqKey, forKey: "groq_api_key")
                        }
                    Text("Get your free key at [console.groq.com/keys](https://console.groq.com/keys). English-only but ~10× faster than Whisper.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .tint(Theme.accent)
                } else {
                    Text("OpenAI API Key")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                    SecureField("sk-...", text: $openAIKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: openAIKey) { _ in
                            UserDefaults.standard.set(openAIKey, forKey: "openai_api_key")
                        }
                    Text("Get your key at [openai.com/api-keys](https://platform.openai.com/api-keys). Supports Hindi + Hinglish transcription.")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textSecondary)
                        .tint(Theme.accent)
                }
            }
            .themedCard()

            Text("You can change this later in Settings, or switch to a local model (LM Studio, Ollama) for a zero-cost, zero-network setup.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.sm)
        }
        .onChange(of: provider) { newValue in
            UserDefaults.standard.set(newValue, forKey: "transcription_provider")
        }
    }

    private func providerPill(id: String, title: String, sub: String) -> some View {
        let isSelected = provider == id
        return Button {
            provider = id
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isSelected ? Theme.textPrimary : Theme.textSecondary)
                Text(sub)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? Theme.textSecondary : Theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.surfaceElevated : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Step 4: Test

/// Final step: invite the user to try dictation. We observe RunStore and
/// show the last transcript inline — works whether injection goes
/// elsewhere or gets suppressed because the onboarding window is front.
private struct OnboardingTestStep: View {
    @ObservedObject var runStore: RunStore

    @State private var initialCount: Int?
    @State private var latestTranscript: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Give it a try.")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textPrimary)
            }

            Text("Hold the fn key and say something — anything. Release when you're done. Your transcript will show up below.")
                .font(.system(size: 13))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            // Hero prompt
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Press and hold")
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundColor(Theme.textOnDark)
                HotkeyBadge(label: "fn")
            }
            .padding(Theme.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .themedHeroCard()

            // Live transcript display
            VStack(alignment: .leading, spacing: 10) {
                Text("YOUR TRANSCRIPT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textTertiary)
                    .tracking(0.8)

                if latestTranscript.isEmpty {
                    Text("Waiting for you to speak…")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textTertiary)
                        .italic()
                } else {
                    Text(latestTranscript)
                        .font(.system(size: 14))
                        .foregroundColor(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 100, alignment: .topLeading)
            .themedCard()

            Text("If fn doesn't trigger, check System Settings → Keyboard → \"Press Fn key to\" and set it to Do Nothing, or use the Settings tab to pick a different hotkey.")
                .font(.system(size: 11))
                .foregroundColor(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.sm)
        }
        .onReceive(runStore.$summaries) { summaries in
            // First render — seed, don't backfill with history.
            if initialCount == nil {
                initialCount = summaries.count
                return
            }
            // Only surface transcripts landed since onboarding started.
            if let newest = summaries.first, summaries.count > (initialCount ?? 0) {
                latestTranscript = newest.previewText
            }
        }
    }
}
