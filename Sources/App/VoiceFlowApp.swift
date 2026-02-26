import SwiftUI
import AppKit
import AVFoundation
import Carbon

@main
struct VoiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Window("VoiceFlow", id: "main") {
            Text("VoiceFlow is running in the menu bar")
                .padding()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var recordingOverlay: RecordingOverlayWindow?
    var audioRecorder: AudioRecorder?
    var whisperService: WhisperService?
    var textInjector: TextInjector?
    var hotKeyListener: HotKeyListener?
    var isRecording = false
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureDefaultSettings()
        setupMenuBar()
        
        audioRecorder = AudioRecorder()
        whisperService = WhisperService()
        textInjector = TextInjector()
        hotKeyListener = HotKeyListener()
        hotKeyListener?.onKeyDown = { [weak self] in
            self?.handleHotKeyDown()
        }
        hotKeyListener?.onKeyUp = { [weak self] in
            self?.handleHotKeyUp()
        }
        hotKeyListener?.start()
        
        requestPermissions()
        openOnboardingIfNeeded()
    }

    private func configureDefaultSettings() {
        if UserDefaults.standard.string(forKey: "output_mode") == nil {
            UserDefaults.standard.set(TranscriptOutputStyle.cleanHinglish.rawValue, forKey: "output_mode")
        }
        if UserDefaults.standard.string(forKey: "processing_mode") == nil {
            UserDefaults.standard.set(TranscriptProcessingMode.dictation.rawValue, forKey: "processing_mode")
        }
        if UserDefaults.standard.object(forKey: "noise_gate_threshold") == nil {
            UserDefaults.standard.set(0.008, forKey: "noise_gate_threshold")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyListener?.stop()
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "waveform.circle", accessibilityDescription: "VoiceFlow")
            button.action = #selector(handleMenuBarClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp])
        }
        
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 240)
        popover?.behavior = .transient
        refreshPopoverContent()
    }
    
    @objc func handleMenuBarClick() {
        if let popover = popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        if let button = statusItem?.button, let popover = popover {
            refreshPopoverContent()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func refreshPopoverContent() {
        popover?.contentViewController = NSHostingController(rootView: MenuBarView(
            isRecording: isRecording,
            onStartRecording: { [weak self] in
                guard let self = self, !self.isRecording else { return }
                self.isRecording = true
                self.startRecording()
                self.refreshPopoverContent()
            },
            onStopRecording: { [weak self] in
                guard let self = self, self.isRecording else { return }
                self.isRecording = false
                self.stopRecording()
                self.refreshPopoverContent()
            },
            onSettings: { [weak self] in
                self?.openSettings()
            },
            onOnboarding: { [weak self] in
                self?.openOnboardingIfNeeded(force: true)
            },
            onQuit: { NSApplication.shared.terminate(nil) }
        ))
    }
    
    func openSettings() {
        popover?.performClose(nil)
        
        if settingsWindow == nil {
            let settingsView = SettingsView()
            let hostingController = NSHostingController(rootView: settingsView)
            
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "VoiceFlow Settings"
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.setContentSize(NSSize(width: 460, height: 500))
            settingsWindow?.center()
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openOnboardingIfNeeded(force: Bool = false) {
        let hasCompleted = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        if !force && hasCompleted {
            return
        }

        if onboardingWindow == nil {
            let onboardingView = OnboardingView(
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onDone: { [weak self] in
                    UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                }
            )
            let hostingController = NSHostingController(rootView: onboardingView)

            onboardingWindow = NSWindow(contentViewController: hostingController)
            onboardingWindow?.title = "Welcome to VoiceFlow"
            onboardingWindow?.styleMask = [.titled, .closable]
            onboardingWindow?.setContentSize(NSSize(width: 520, height: 420))
            onboardingWindow?.center()
        }

        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func requestPermissions() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted {
                print("Microphone access denied")
            }
        }
        
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    private func handleHotKeyDown() {
        guard !isRecording else { return }
        isRecording = true
        startRecording()
        refreshPopoverContent()
    }

    private func handleHotKeyUp() {
        guard isRecording else { return }
        isRecording = false
        stopRecording()
        refreshPopoverContent()
    }

    private func toggleRecording() {
        if isRecording {
            isRecording = false
            stopRecording()
        } else {
            isRecording = true
            startRecording()
        }
        refreshPopoverContent()
    }
    
    private func startRecording() {
        DispatchQueue.main.async { [weak self] in
            self?.showRecordingOverlay()
            self?.audioRecorder?.startRecording()
        }
    }
    
    private func stopRecording() {
        DispatchQueue.main.async { [weak self] in
            self?.hideRecordingOverlay()
            
            self?.audioRecorder?.stopRecording { [weak self] audioData in
                guard let audioData = audioData else {
                    print("Transcription skipped: no audio data produced")
                    return
                }

                let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
                let outputModeRaw = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.cleanHinglish.rawValue
                let outputMode = TranscriptOutputStyle(rawValue: outputModeRaw) ?? .cleanHinglish
                let processingModeRaw = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
                let processingMode = TranscriptProcessingMode(rawValue: processingModeRaw) ?? .dictation
                let transcriptionLanguage = (outputMode == .cleanHinglish && language == "en") ? "auto" : language

                self?.whisperService?.transcribeAndPolish(
                    audioData: audioData,
                    language: transcriptionLanguage,
                    style: outputMode,
                    processingMode: processingMode
                ) { result in
                    switch result {
                    case .success(let text):
                        print("Transcription success: \(text.count) chars")
                        self?.textInjector?.injectText(text)
                    case .failure(let error):
                        print("Transcription error: \(error)")
                    }
                }
            }
        }
    }
    
    private func showRecordingOverlay() {
        if recordingOverlay == nil {
            recordingOverlay = RecordingOverlayWindow()
        }
        recordingOverlay?.show()
    }
    
    private func hideRecordingOverlay() {
        recordingOverlay?.hide()
    }
}
