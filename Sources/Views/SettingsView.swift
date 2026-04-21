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
                    Text("Saves audio, transcripts, and prompts locally for each dictation. Last 20 runs are kept.")
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

struct OnboardingView: View {
    @ObservedObject var permissionService: PermissionService
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var groqApiKey: String = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
    @State private var provider: String = UserDefaults.standard.string(forKey: "transcription_provider") ?? TranscriptionProvider.openai.rawValue

    let onOpenSettings: () -> Void
    let onDone: () -> Void

    private var hasValidKeyForProvider: Bool {
        provider == TranscriptionProvider.groq.rawValue
            ? !groqApiKey.isEmpty
            : !apiKey.isEmpty
    }

    var body: some View {
        ScrollView {
            onboardingContent
                .padding(20)
        }
        .frame(width: 560, height: 600)
        .onAppear {
            permissionService.refreshStatus()
        }
    }

    private var onboardingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VoiceFlow Onboarding")
                .font(.title2.bold())

            Text("Complete these quick steps so local testing works reliably.")
                .foregroundColor(.secondary)

            GroupBox("1) Choose transcription provider") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Provider", selection: $provider) {
                        Text("OpenAI (Paid · Hindi+English)").tag(TranscriptionProvider.openai.rawValue)
                        Text("Groq (Free · English only)").tag(TranscriptionProvider.groq.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: provider) { _ in
                        UserDefaults.standard.set(provider, forKey: "transcription_provider")
                    }

                    if provider == TranscriptionProvider.groq.rawValue {
                        SecureField("gsk_...", text: $groqApiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: groqApiKey) { _ in
                                UserDefaults.standard.set(groqApiKey, forKey: "groq_api_key")
                            }
                        Text("Free key: console.groq.com/keys. English only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: apiKey) { _ in
                                UserDefaults.standard.set(apiKey, forKey: "openai_api_key")
                            }
                        Text("Paid key: openai.com/api-keys. Supports Hindi + Hinglish.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("2) Grant permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    if let warning = permissionService.environmentWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    HStack {
                        Text("Microphone")
                        Spacer()
                        permissionBadge(ok: permissionService.microphoneState.isGranted)
                        Button("Request") {
                            permissionService.requestMicrophoneAccess()
                        }
                        Button("Open Settings") {
                            permissionService.openPrivacyPane(.microphone)
                        }
                    }
                }
                .padding(.top, 4)

                // Dedicated guided flows for the two permissions most likely
                // to trip up users on ad-hoc-signed builds. Plain HStack rows
                // don't cut it — the auto-prompt can silently no-op, so we
                // offer a deterministic 3-step fallback per permission.
                AccessibilityGuideView(
                    permissionService: permissionService,
                    onDismiss: {}
                )
                .padding(.top, 8)

                InputMonitoringGuideView(
                    permissionService: permissionService,
                    onDismiss: {}
                )
                .padding(.top, 8)
            }

            GroupBox("3) Test recording") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Press and hold the Fn key to record, then release to transcribe into the active app.")
                    Text("If Fn does not trigger, check System Settings → Keyboard → Globe/Fn key usage and ensure Fn is not remapped.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Re-check permissions") {
                        permissionService.refreshStatus()
                    }
                    Button("Open app settings") {
                        onOpenSettings()
                    }
                }
                .padding(.top, 4)
            }

            HStack(spacing: 12) {
                if !permissionService.allRequiredGranted {
                    Text("⚠️ Some permissions are still missing — you can close this and grant them from the menu later.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                // Only gate on API key presence. Permissions can be granted
                // anytime from the menu; blocking Done on them traps users
                // in the onboarding window when TCC auto-prompt fails.
                .disabled(!hasValidKeyForProvider)
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
