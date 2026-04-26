import SwiftUI
import AppKit
import AVFoundation
import Carbon
import ApplicationServices
import IOKit.hid

@main
struct VoiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // SwiftUI MenuBarExtra — macOS handles positioning, focus,
        // fullscreen behavior, and dismissal automatically. Zero
        // custom window management needed. This is the same approach
        // FreeFlow, Whisper Transcription, and other modern macOS
        // menu bar apps use.
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appDelegate)
        } label: {
            Image(systemName: "waveform.circle")
        }

        // Placeholder Settings scene so ⌘, behaves natively.
        Settings {
            EmptyView()
        }
    }
}

enum PermissionState {
    case granted
    case denied
    case notDetermined
    case restrictedOrUnknown

    var isGranted: Bool {
        self == .granted
    }
}

enum PermissionPane {
    case microphone
    case accessibility
    case inputMonitoring
}

final class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published private(set) var microphoneState: PermissionState = .notDetermined
    @Published private(set) var accessibilityState: PermissionState = .notDetermined
    @Published private(set) var inputMonitoringState: PermissionState = .notDetermined
    @Published private(set) var environmentWarning: String?
    private var lastMicDebugSnapshot: String = ""
    private var observedWorkingMicrophoneInput = false

    /// Fires whenever any previously-missing permission flips to granted.
    /// Used by AppDelegate to hot-reload the HotKeyListener without
    /// forcing the user to quit + relaunch the app.
    var onPermissionNewlyGranted: ((PermissionPane) -> Void)?

    private var lastAllStates: [PermissionPane: Bool] = [
        .microphone: false, .accessibility: false, .inputMonitoring: false
    ]
    private var pollingTimer: Timer?

    var allRequiredGranted: Bool {
        microphoneState.isGranted && accessibilityState.isGranted && inputMonitoringState.isGranted
    }

    private init() {
        refreshStatus()
        startPolling()
    }

    /// Polls every 2s. Cheap — these APIs all read local in-memory state.
    /// Once all permissions are granted, polling stops entirely.
    private func startPolling() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.refreshStatus()
            // Stop polling once everything is granted — no need to burn cycles.
            if self.allRequiredGranted {
                self.pollingTimer?.invalidate()
                self.pollingTimer = nil
            }
        }
    }

    func refreshStatus() {
        DispatchQueue.main.async {
            let newMic = self.currentMicrophoneState()
            let newAx = AXIsProcessTrusted() ? PermissionState.granted : .denied
            let newInput = self.preflightInputMonitoringAccess() ? PermissionState.granted : .denied

            // Detect granted-transitions before mutating state, so
            // onPermissionNewlyGranted fires exactly once per flip.
            self.detectNewlyGranted(pane: .microphone, wasGranted: self.lastAllStates[.microphone] ?? false, isGranted: newMic.isGranted)
            self.detectNewlyGranted(pane: .accessibility, wasGranted: self.lastAllStates[.accessibility] ?? false, isGranted: newAx.isGranted)
            self.detectNewlyGranted(pane: .inputMonitoring, wasGranted: self.lastAllStates[.inputMonitoring] ?? false, isGranted: newInput.isGranted)

            self.lastAllStates[.microphone] = newMic.isGranted
            self.lastAllStates[.accessibility] = newAx.isGranted
            self.lastAllStates[.inputMonitoring] = newInput.isGranted

            // CRITICAL: Only assign @Published properties when the value
            // actually changed. @Published fires objectWillChange on EVERY
            // set — even same-value assignments. Without these guards, every
            // 2s poll triggers a full SwiftUI view re-evaluation cascade
            // through MenuBarExtra → EnvironmentObject → all child views.
            if self.microphoneState != newMic { self.microphoneState = newMic }
            if self.accessibilityState != newAx { self.accessibilityState = newAx }
            if self.inputMonitoringState != newInput { self.inputMonitoringState = newInput }
            let newWarning = self.currentEnvironmentWarning()
            if self.environmentWarning != newWarning { self.environmentWarning = newWarning }

            let micDebug = self.currentMicrophoneDebugSnapshot()
            if micDebug != self.lastMicDebugSnapshot {
                self.lastMicDebugSnapshot = micDebug
                print("VoiceFlow microphone status: \(micDebug)")
            }
        }
    }

    private func detectNewlyGranted(pane: PermissionPane, wasGranted: Bool, isGranted: Bool) {
        if !wasGranted && isGranted {
            print("Permission newly granted: \(pane)")
            onPermissionNewlyGranted?(pane)
        }
    }

    func markMicrophoneOperational() {
        observedWorkingMicrophoneInput = true
        refreshStatus()
    }

    func requestMicrophoneAccess() {
        // Call BOTH APIs. On ad-hoc signed builds, one may silently no-op
        // while the other triggers the system prompt correctly. Belt +
        // suspenders — the second call is a no-op if the first succeeds.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            self?.refreshStatusAfterDelay()
        }
        if #available(macOS 14.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] _ in
                self?.refreshStatusAfterDelay()
            }
        }
    }

    func requestAccessibilityAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        refreshStatusAfterDelay()
    }

    func preflightInputMonitoringAccess() -> Bool {
        // IOHIDCheckAccess is the modern replacement. Cross-check both
        // so we're correct regardless of which path macOS has recorded
        // the grant on (they share a TCC entry but sometimes desynchronize
        // on version upgrades).
        let hidGranted = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        return hidGranted || CGPreflightListenEventAccess()
    }

    /// Request Input Monitoring access.
    ///
    /// **Why `IOHIDRequestAccess` instead of `CGRequestListenEventAccess`:**
    /// `CGRequestListenEventAccess` has been quietly broken since Monterey
    /// for ad-hoc-signed apps — it silently returns `false` without prompting.
    /// The HID-layer equivalent (`IOHIDRequestAccess`) actually triggers the
    /// system prompt reliably. This is what Raycast / Karabiner / BTT use.
    ///
    /// Runs on a background queue because the HID call blocks until the user
    /// either responds to the prompt or dismisses it; we don't want to stall
    /// the main thread for 30+ seconds if the prompt sits around.
    func requestInputMonitoringAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
            print("IOHIDRequestAccess returned: \(granted)")
            // Fall back to the legacy API if the HID path silently denies
            // (happens on some older macOS + ad-hoc signature combinations).
            if !granted {
                _ = CGRequestListenEventAccess()
            }
            self.refreshStatusAfterDelay()
        }
    }

    /// Opens the app's location in Finder so the user can manually drag
    /// VoiceFlow into the Input Monitoring list — this is the documented
    /// Apple-blessed escape hatch when the prompt refuses to appear.
    func revealAppInFinder() {
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openPrivacyPane(_ pane: PermissionPane) {
        let urlString: String
        switch pane {
        case .microphone:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        case .accessibility:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        case .inputMonitoring:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        }
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Synchronous, side-effect-free snapshot of the current mic TCC state.
    /// Used by the pre-flight check in `startRecording()` where we can't
    /// tolerate a stale @Published value — `refreshStatus()` is main-queue
    /// async and returns before the property is updated, so callers that
    /// need an up-to-the-microsecond read should use this instead.
    func snapshotMicrophoneState() -> PermissionState {
        return currentMicrophoneState()
    }

    private func currentMicrophoneState() -> PermissionState {
        var hasGranted = false
        var hasDenied = false

        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                hasGranted = true
            case .denied:
                hasDenied = true
            case .undetermined:
                break
            @unknown default:
                break
            }
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            hasGranted = true
        case .denied:
            hasDenied = true
        case .notDetermined:
            break
        case .restricted:
            return .restrictedOrUnknown
        @unknown default:
            return .restrictedOrUnknown
        }

        if hasDenied {
            return .denied
        }
        if hasGranted || observedWorkingMicrophoneInput {
            return .granted
        }
        return .notDetermined
    }

    private func currentMicrophoneDebugSnapshot() -> String {
        let captureStatus: String
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            captureStatus = "authorized"
        case .denied:
            captureStatus = "denied"
        case .notDetermined:
            captureStatus = "notDetermined"
        case .restricted:
            captureStatus = "restricted"
        @unknown default:
            captureStatus = "unknown"
        }

        var audioAppStatus = "unavailable"
        if #available(macOS 14.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                audioAppStatus = "granted"
            case .denied:
                audioAppStatus = "denied"
            case .undetermined:
                audioAppStatus = "undetermined"
            @unknown default:
                audioAppStatus = "unknown"
            }
        }

        return "path=\(Bundle.main.bundleURL.path), capture=\(captureStatus), avAudio=\(audioAppStatus)"
    }

    private func refreshStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            self.refreshStatus()
        }
    }

    private func currentEnvironmentWarning() -> String? {
        let appPath = Bundle.main.bundleURL.path

        if appPath.contains("/Volumes/") {
            return "VoiceFlow is running from a DMG volume. Drag it to /Applications and launch that copy so permissions persist."
        }

        if appPath.contains("/DerivedData/") || appPath.contains("/build/") {
            return "VoiceFlow is running from an Xcode build folder. Permissions can look mismatched; use a single /Applications install for testing."
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "com.voiceflow.app"
        let runningCount = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }.count
        if runningCount > 1 {
            return "Multiple VoiceFlow instances are running. Quit all duplicates and relaunch one copy from /Applications."
        }

        return nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var mainWindow: NSWindow?
    var recordingOverlay: RecordingOverlayWindow?
    var audioRecorder: AudioRecorder?
    var whisperService: WhisperService?
    var textInjector: TextInjector?

    /// Per-recording streaming session. Lives only while Fn is held.
    /// Created in startRecording (when the feature flag is on) and torn
    /// down in stopRecording regardless of success path. We always keep
    /// a reference to the batch audio too — if streaming errors out,
    /// we can still upload the WAV and recover.
    private var realtimeStream: RealtimeTranscriptionService?
    private var realtimeStreamStart: CFAbsoluteTime = 0
    private var realtimeStreamFailed: Bool = false
    var hotKeyListener: HotKeyListener?
    var permissionService = PermissionService.shared
    let recordingState = RecordingStateStore()
    let runStore = RunStore.shared
    lazy var runRecorder = RunRecorder(store: runStore)

    /// Condense an Error into a short string for the Run Log.
    /// We prefer HTTP-style reasons ("401 Unauthorized") over Swift's default
    /// `Error` description which tends to be noisy for URLSession failures.
    static func shortErrorDescription(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorTimedOut:            return "Request timed out"
            case NSURLErrorCannotConnectToHost: return "Cannot connect to host"
            case NSURLErrorNotConnectedToInternet: return "Offline — no internet"
            case NSURLErrorNetworkConnectionLost:  return "Connection lost"
            default: break
            }
        }
        let desc = ns.localizedDescription
        return desc.isEmpty ? "Unknown error" : desc
    }

    /// Published so MenuBarView (via MenuBarExtra) can observe changes.
    @Published var isRecording: Bool = false {
        didSet { recordingState.isRecording = isRecording }
    }
    @Published var hotKeyStartStatus: HotKeyStartResult = .failedUnknown
    var allowTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular activation: full app with Dock icon + proper window.
        // Menu bar extra still registered for quick access.
        NSApp.setActivationPolicy(.regular)
        configureDefaultSettings()

        audioRecorder = AudioRecorder()
        whisperService = WhisperService()
        // Kick off connection pre-warm immediately. TLS + HTTP/2 handshake
        // to api.openai.com costs ~150-300ms on a cold URLSession pool and
        // shows up as fixed overhead on the FIRST dictation after launch.
        // RunLog p50 STT latency is ~2s — shaving that handshake off a
        // 3s median utterance is a free ~10% latency win.
        whisperService?.prewarmConnections()
        textInjector = TextInjector()
        hotKeyListener = HotKeyListener()
        hotKeyListener?.onKeyDown = { [weak self] in
            self?.handleHotKeyDown()
        }
        hotKeyListener?.onKeyUp = { [weak self] in
            self?.handleHotKeyUp()
        }

        // Microphone is essential — request it on launch so VoiceFlow
        // appears in System Settings > Microphone immediately. This is a
        // single, expected prompt for a voice app. Delayed slightly so the
        // run loop is settled and the system prompt can render. We call
        // both the legacy and modern APIs for maximum compatibility with
        // ad-hoc signed builds.
        permissionService.refreshStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            if !self.permissionService.microphoneState.isGranted {
                self.permissionService.requestMicrophoneAccess()
            }
        }
        startHotKeyListener()

        // Hot-reload: whenever any required permission flips from denied
        // to granted, re-attempt the hotkey listener start. This removes
        // the "quit and relaunch" step users currently have to do after
        // manually dragging VoiceFlow into the Input Monitoring list.
        permissionService.onPermissionNewlyGranted = { [weak self] pane in
            print("Restarting hotkey listener after \(pane) grant")
            self?.startHotKeyListener()
        }

        let hasCompleted = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        if !hasCompleted {
            // First launch: open onboarding window and let the user drive.
            // The guided cards inside the window will trigger each system
            // prompt individually when the user clicks "Grant".
            openOnboardingIfNeeded()
        }
        // Returning users: stay menu-bar only. Window is reachable via Dock
        // icon click (applicationShouldHandleReopen) or menu bar → Open
        // VoiceFlow. Matches the behavior of Raycast, Rectangle, Alfred,
        // etc. — no unsolicited window on every launch.
    }

    /// Re-opens the main dashboard when the user clicks the Dock icon
    /// after having closed the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTermination {
            return .terminateNow
        }

        if let event = NSApp.currentEvent,
           event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            return .terminateNow
        }

        print("Blocked unexpected terminate request; use Quit VoiceFlow to exit.")
        return .terminateCancel
    }
    
    /// Computed permission warning for the menu bar view.
    var permissionWarning: String {
        switch hotKeyStartStatus {
        case .started:
            return ""
        case .failedMissingAccessibility:
            return "Accessibility permission is missing. Open Onboarding to fix."
        case .failedMissingInputMonitoring:
            return "Input Monitoring permission is missing. Open Onboarding to fix."
        case .failedUnknown:
            return "Hotkey listener failed to start. Check permissions in Onboarding."
        }
    }

    func openMainWindow() {

        if mainWindow == nil {
            let dashboard = MainDashboardView(
                permissionService: permissionService,
                recordingState: recordingState,
                runStore: runStore,
                onTestRecordStart: { [weak self] in
                    guard let self = self, !self.isRecording else { return }
                    self.isRecording = true
                    self.startRecording()
                },
                onTestRecordStop: { [weak self] in
                    guard let self = self, self.isRecording else { return }
                    self.isRecording = false
                    self.stopRecording()
                },
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onQuit: { [weak self] in
                    self?.allowTermination = true
                    NSApplication.shared.terminate(nil)
                }
            )
            let hostingController = NSHostingController(rootView: dashboard)
            mainWindow = NSWindow(contentViewController: hostingController)
            mainWindow?.title = "VoiceFlow"
            mainWindow?.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            // Generous default — Wispr-Flow-shape proportions. The
            // dashboard's content (hero + stats row, full timeline, sidebar)
            // breathes much better at ~1100×780 than the cramped 720×620 it
            // used to open at. Window is .resizable so users can shrink if
            // needed.
            mainWindow?.setContentSize(NSSize(width: 1100, height: 780))
            mainWindow?.center()
            mainWindow?.isReleasedWhenClosed = false
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func openSettings() {
        if settingsWindow == nil {
            let settingsView = SettingsView(permissionService: permissionService)
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
                permissionService: permissionService,
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
            onboardingWindow?.setContentSize(NSSize(width: 600, height: 640))
            onboardingWindow?.center()
        }

        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Removed `requestPermissions()` — auto-firing all three system prompts on
    // launch was the ambush pattern that stacked system dialogs on top of the
    // onboarding window. Permission prompts now fire only when the user clicks
    // a specific "Grant" button in the guided cards (Accessibility,
    // InputMonitoring) or implicitly on first microphone use.

    private func startHotKeyListener() {
        guard let hotKeyListener else { return }
        hotKeyStartStatus = hotKeyListener.start()
        switch hotKeyStartStatus {
        case .started:
            print("Hotkey listener started")
        case .failedMissingAccessibility:
            print("Hotkey listener blocked: missing Accessibility permission")
        case .failedMissingInputMonitoring:
            print("Hotkey listener blocked: missing Input Monitoring permission")
        case .failedUnknown:
            print("Hotkey listener failed to start for unknown reason")
        }
    }

    private func handleHotKeyDown() {
        guard !isRecording else { return }
        isRecording = true
        startRecording()
    }

    private func handleHotKeyUp() {
        guard isRecording else { return }
        isRecording = false
        stopRecording()
    }

    private func toggleRecording() {
        if isRecording {
            isRecording = false
            stopRecording()
        } else {
            isRecording = true
            startRecording()
        }
    }
    
    func startRecording() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // -----------------------------------------------------------------
            // Pre-flight permission check.
            //
            // Previously, we always called AVAudioEngine.start() and only
            // reacted to failure. That had two bugs:
            //   1. On `.notDetermined` + ad-hoc signatures, engine.start()
            //      can succeed but silently capture zero samples. The empty
            //      buffer flowed to Whisper, which fell back to echoing its
            //      multipart prompt — which then got "cleaned" by the polish
            //      LLM and injected into the user's editor.
            //   2. On `.denied`, users saw the recording overlay flash and
            //      then disappear with no feedback about WHY.
            //
            // New flow: synchronously refresh TCC state, gate on mic BEFORE
            // touching the audio engine, and route each state to a clear
            // recovery path. Mic is the only hard blocker here — accessibility
            // is needed for injection but checked at inject-time, and input
            // monitoring was already needed for the hotkey to fire.
            // -----------------------------------------------------------------
            // Read TCC state synchronously — `microphoneState` is @Published
            // and updated via a main-async refresh, which won't have run
            // yet if we called refreshStatus() from this same main-queue
            // block. snapshotMicrophoneState() bypasses the pub/sub layer.
            let micState = self.permissionService.snapshotMicrophoneState()
            // Fire-and-forget refresh so downstream observers (overlay,
            // dashboard) catch up — doesn't gate this decision.
            self.permissionService.refreshStatus()

            switch micState {
            case .granted:
                break // fall through to the real recording path
            case .notDetermined, .restrictedOrUnknown:
                // First-time launch: trigger the system prompt. Do NOT start
                // the engine — the user hasn't decided yet, and a speculative
                // capture produces the empty-audio + prompt-echo failure mode.
                print("Mic permission not determined — requesting access, aborting this recording attempt")
                self.isRecording = false
                self.permissionService.requestMicrophoneAccess()
                return
            case .denied:
                // User previously denied. Give clear audible feedback and
                // open the privacy pane so they can fix it. No overlay — a
                // flashing chip with no dictation is worse than silence.
                print("Mic permission denied — opening Privacy pane")
                self.isRecording = false
                NSSound.beep()
                self.permissionService.openPrivacyPane(.microphone)
                return
            }

            // From here down, mic is granted. Everything else is best-effort.
            self.showRecordingOverlay()
            // Spin up realtime streaming BEFORE starting the tap so the
            // PCM16 callback is already set. If the flag is off, skip
            // entirely — we don't want to pay WebSocket connect cost for
            // users who haven't opted in.
            self.setupRealtimeStreamIfEnabled()
            let didStart = self.audioRecorder?.startRecording() ?? false
            if didStart {
                self.permissionService.markMicrophoneOperational()
            } else {
                // Engine failed to start despite granted permission — usually
                // a device contention issue (another app holding the mic).
                // Bail cleanly; the pre-flight already covered the common
                // "no permission" case.
                print("Audio engine failed to start despite granted mic permission")
                self.isRecording = false
                self.hideRecordingOverlay()
                NSSound.beep()
            }
        }
    }
    
    func stopRecording() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.recordingOverlay?.setState(.processing)

            // Begin a RunLog session to accumulate pipeline data.
            let session = self.runRecorder.beginRun()

            self.audioRecorder?.stopRecording { [weak self] audioData in
                guard let self else { return }
                guard let audioData = audioData else {
                    print("Transcription skipped: no audio data produced")
                    DispatchQueue.main.async { self.hideRecordingOverlay() }
                    return
                }

                // Stage 1: Capture
                session.captureCompleted(audioData: audioData, voicedRange: nil)

                let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
                let outputModeRaw = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.cleanHinglish.rawValue
                let userSelectedStyle = TranscriptOutputStyle(rawValue: outputModeRaw) ?? .cleanHinglish
                let processingModeRaw = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
                let processingMode = TranscriptProcessingMode(rawValue: processingModeRaw) ?? .dictation

                // Policy: Language acts as output-language lock.
                //   - Language = "en" + any non-verbatim style → translate to English
                //   - Verbatim always wins (explicit opt-out of any transformation)
                //   - Otherwise, respect the user's selected style as-is
                // This keeps the UI matrix honest (Language = target language,
                // Style = polish intensity) without a 4th redundant picker.
                let effectiveStyle: TranscriptOutputStyle = {
                    if userSelectedStyle == .verbatim { return .verbatim }
                    if language == "en" { return .translateEnglish }
                    return userSelectedStyle
                }()

                // STT hint: when forcing English output from Hindi speech, the
                // transcription model needs to SEE the original Hindi — forcing
                // language="en" to STT would make Whisper hallucinate English
                // over Hindi audio. Use "auto" so STT captures source faithfully
                // and let the polish LLM do the translation.
                let transcriptionLanguage = (effectiveStyle == .translateEnglish && language == "en") ? "auto" : language

                // Streaming path: if we started a stream session and it's still
                // alive, commit and await the final transcript. On any failure
                // we silently fall through to the batch path with the WAV we
                // already captured — user never sees a broken dictation because
                // of a dropped WebSocket.
                let handleResult: (Result<TranscriptionMetadata, Error>) -> Void = { [weak self] result in
                    DispatchQueue.main.async {
                        self?.hideRecordingOverlay()
                        switch result {
                        case .success(let metadata):
                            // Stage 2: Transcription
                            session.transcriptionCompleted(
                                provider: metadata.provider,
                                rawText: metadata.rawText,
                                latencyMs: metadata.transcriptionLatencyMs
                            )

                            // Stage 3: Post-processing
                            if let mode = metadata.postProcessMode {
                                session.postProcessCompleted(
                                    mode: mode,
                                    style: metadata.postProcessStyle ?? "unknown",
                                    model: metadata.postProcessModel ?? "none",
                                    prompt: metadata.postProcessPrompt ?? "",
                                    finalText: metadata.finalText,
                                    latencyMs: metadata.postProcessLatencyMs,
                                    languageGuardTriggered: metadata.languageGuardTriggered
                                )
                            }

                            // Flush to RunStore
                            session.finish()

                            let text = metadata.finalText
                            print("Transcription success: \(text.count) chars")
                            guard !text.isEmpty else {
                                print("Empty transcript (likely hallucination-filtered); nothing to inject.")
                                return
                            }
                            self?.textInjector?.injectText(text)

                        case .failure(let error):
                            print("Transcription error: \(error)")
                            session.fail(reason: Self.shortErrorDescription(error))
                        }
                    }
                }

                // Decide which pipeline produces the transcript.
                if let stream = self.realtimeStream, !self.realtimeStreamFailed {
                    let streamStart = self.realtimeStreamStart
                    Task { @MainActor in
                        do {
                            let finalText = try await stream.commitAndAwaitFinal()
                            let streamLatency = Int((CFAbsoluteTimeGetCurrent() - streamStart) * 1000)
                            stream.close()
                            self.realtimeStream = nil
                            self.whisperService?.polishOnlyWithMetadata(
                                rawTranscript: finalText,
                                providerLabel: "openai/gpt-4o-mini-transcribe/realtime",
                                transcriptionLatencyMs: streamLatency,
                                style: effectiveStyle,
                                processingMode: processingMode,
                                completion: handleResult
                            )
                        } catch {
                            // Streaming failed — drop the socket and recover
                            // via the batch path using the WAV we already have.
                            print("Realtime stream failed, falling back to batch: \(error)")
                            stream.close()
                            self.realtimeStream = nil
                            self.realtimeStreamFailed = true
                            self.whisperService?.transcribeAndPolishWithMetadata(
                                audioData: audioData,
                                language: transcriptionLanguage,
                                style: effectiveStyle,
                                processingMode: processingMode,
                                completion: handleResult
                            )
                        }
                    }
                } else {
                    self.whisperService?.transcribeAndPolishWithMetadata(
                        audioData: audioData,
                        language: transcriptionLanguage,
                        style: effectiveStyle,
                        processingMode: processingMode,
                        completion: handleResult
                    )
                }
            }
        }
    }

    // MARK: - Realtime streaming wiring

    /// Feature flag lives in UserDefaults so users can toggle from Settings.
    /// Default OFF — streaming is additive, not a replacement, until we've
    /// proven the latency win and error rate on real recordings.
    static let realtimeStreamingKey = "realtime_streaming_enabled"

    private func setupRealtimeStreamIfEnabled() {
        // Clear old state regardless of flag, so a previous failure doesn't
        // poison the next session.
        realtimeStream?.close()
        realtimeStream = nil
        realtimeStreamFailed = false
        audioRecorder?.onPCM16Samples = nil

        guard UserDefaults.standard.bool(forKey: Self.realtimeStreamingKey) else { return }

        // Streaming only makes sense with OpenAI — Groq's Realtime endpoint
        // has a different shape and we don't support it yet. Silently skip
        // for other providers; batch path will handle the recording fine.
        guard TranscriptionProvider.current == .openai else { return }

        let apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        guard !apiKey.isEmpty else { return }

        let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
        let config = RealtimeTranscriptionService.Configuration.openAI(
            apiKey: apiKey,
            language: language == "auto" ? "" : language
        )
        let stream = RealtimeTranscriptionService(config: config)
        realtimeStream = stream
        realtimeStreamStart = CFAbsoluteTimeGetCurrent()

        // Wire the PCM16 pump. We buffer chunks while the socket is still
        // connecting; once connect completes, the audio already in-flight
        // will have been dropped. For now we accept that first ~100-200ms
        // loss — the WAV fallback still has everything if it matters.
        audioRecorder?.onPCM16Samples = { [weak stream] data in
            Task { @MainActor [weak stream] in
                stream?.appendPCM16(data)
            }
        }

        stream.onError = { [weak self] error in
            print("Realtime stream error during capture: \(error.localizedDescription)")
            self?.realtimeStreamFailed = true
        }

        Task { @MainActor [weak stream] in
            do {
                try await stream?.connect()
            } catch {
                print("Realtime stream connect failed: \(error.localizedDescription)")
                self.realtimeStreamFailed = true
            }
        }
    }

    private func showRecordingOverlay() {
        if recordingOverlay == nil {
            recordingOverlay = RecordingOverlayWindow()
        }
        recordingOverlay?.show(state: .recording)
        // Wire live audio amplitude → overlay waveform. We capture the
        // overlay weakly so the audio recorder can outlive the panel
        // without keeping it pinned in memory. Cleared in hideRecordingOverlay.
        audioRecorder?.onAmplitude = { [weak overlay = recordingOverlay] level in
            overlay?.updateAudioLevel(level)
        }
    }

    private func hideRecordingOverlay() {
        // Drop the amplitude callback BEFORE hiding so trailing buffers
        // from the engine teardown don't try to update a panel that's
        // already animating off-screen.
        audioRecorder?.onAmplitude = nil
        recordingOverlay?.hide()
    }
}
