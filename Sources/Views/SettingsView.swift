import SwiftUI
import AppKit
import AVFoundation

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var selectedLanguage: String = "hi"
    @State private var outputMode: String = TranscriptOutputStyle.cleanHinglish.rawValue
    @State private var processingMode: String = TranscriptProcessingMode.dictation.rawValue
    @State private var noiseGateThreshold: Double = 0.015
    @State private var showSaveConfirmation = false
    
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

            Section("Microphone Filter") {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(value: $noiseGateThreshold, in: 0.001...0.05, step: 0.001)
                    Text("Sensitivity: \(String(format: "%.3f", noiseGateThreshold)) (higher filters more background noise)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 460)
        .padding()
        .onAppear {
            loadSettings()
        }
        .onChange(of: apiKey) { _ in
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
        .onChange(of: noiseGateThreshold) { _ in
            saveSettings()
        }
    }
    
    private func loadSettings() {
        apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        selectedLanguage = UserDefaults.standard.string(forKey: "language") ?? "hi"
        outputMode = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.cleanHinglish.rawValue
        processingMode = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
        let storedThreshold = UserDefaults.standard.double(forKey: "noise_gate_threshold")
        noiseGateThreshold = storedThreshold == 0 ? 0.015 : storedThreshold
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(apiKey, forKey: "openai_api_key")
        UserDefaults.standard.set(selectedLanguage, forKey: "language")
        UserDefaults.standard.set(outputMode, forKey: "output_mode")
        UserDefaults.standard.set(processingMode, forKey: "processing_mode")
        UserDefaults.standard.set(noiseGateThreshold, forKey: "noise_gate_threshold")
    }
}

struct OnboardingView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
    @State private var micGranted: Bool = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @State private var accessibilityGranted: Bool = AXIsProcessTrusted()

    let onOpenSettings: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("VoiceFlow Onboarding")
                .font(.title2.bold())

            Text("Complete these quick steps so local testing works reliably.")
                .foregroundColor(.secondary)

            GroupBox("1) Add OpenAI API Key") {
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: apiKey) { _ in
                            UserDefaults.standard.set(apiKey, forKey: "openai_api_key")
                        }
                    Text("Used for transcription requests.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 4)
            }

            GroupBox("2) Grant permissions") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Microphone")
                        Spacer()
                        permissionBadge(ok: micGranted)
                        Button("Request") {
                            AVCaptureDevice.requestAccess(for: .audio) { granted in
                                DispatchQueue.main.async {
                                    micGranted = granted
                                }
                            }
                        }
                    }
                    HStack {
                        Text("Accessibility (for global Fn hotkey + text injection)")
                        Spacer()
                        permissionBadge(ok: accessibilityGranted)
                        Button("Open Prompt") {
                            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
                            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                accessibilityGranted = AXIsProcessTrusted()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }

            GroupBox("3) Test recording") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Press and hold Fn (or Right Option) to record, then release to transcribe into the active app.")
                    Text("If Fn does not trigger, use Right Option as fallback and ensure Fn is not remapped in Keyboard settings.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Open app settings") {
                        onOpenSettings()
                    }
                }
                .padding(.top, 4)
            }

            HStack {
                Spacer()
                Button("Done") {
                    onDone()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(apiKey.isEmpty || !micGranted || !accessibilityGranted)
            }
        }
        .padding(20)
        .frame(width: 520, height: 420)
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
