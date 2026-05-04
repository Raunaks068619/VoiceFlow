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
    /// Persistent bottom-of-screen chip — separate from the notch chip.
    /// The notch chip appears DURING recording; this one is always-on as
    /// an "I'm here" affordance and morphs to a warning when the focused
    /// UI element isn't a text input.
    var floatingChip: FloatingChipWindow?
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

    /// Captured at hotkey-press (startRecording), consumed at result-time.
    /// The snapshot must be taken EAGERLY because by the time the LLM
    /// returns, the user may have alt-tabbed and the AX selection is gone.
    private var pendingContext: ContextSnapshot?

    /// Router instance — created lazily because it depends on whisperService.
    private lazy var transformerRouter: TransformerRouter? = {
        guard let whisper = whisperService else { return nil }
        return TransformerRouter(whisper: whisper)
    }()

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
        // Suppression hook: fires when the transcript can't be injected
        // (VoiceFlow foreground, no text input focused, etc.). The
        // transcript is already on the clipboard at this point — we
        // just flash the warning chip to tell the user where it went
        // and how to retrieve it.
        textInjector?.onInjectionSuppressed = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Suppress the warning chip during onboarding — the test
                // step intentionally has no text input to inject into,
                // and the warning would confuse the user (they're doing
                // exactly what onboarding asked them to do).
                //
                // Their transcript still appears in the test step's
                // "YOUR TRANSCRIPT" card via the RunStore observer.
                if self.onboardingWindow?.isVisible == true { return }

                self.floatingChip?.flashNoInputWarning(durationSeconds: 4.5)
            }
        }
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
            // Newly granted → maybe we now have all required permissions.
            // Refresh the chip's passive indicator so the orange dot
            // disappears the moment the user fixes the missing one.
            self?.refreshChipPermissionState()
        }

        // Onboarding gate — three-way decision based on prefs + live TCC state:
        //
        //   1. has_completed_onboarding=false  → first-launch ever, run full
        //      Welcome flow.
        //   2. has_completed_onboarding=true BUT any required permission is
        //      missing → user reinstalled, OS-upgraded, or revoked a perm
        //      between sessions. Jump straight to the Permissions step so
        //      they can re-grant without re-watching the welcome screens.
        //   3. has_completed_onboarding=true and all perms granted → silent
        //      menu-bar launch.
        //
        // Why gate on permissions and not just the prefs flag: ad-hoc signed
        // builds lose TCC entries on every cdhash change (i.e. every brew
        // upgrade). Without this check, a user who ran onboarding once would
        // never see it again — even after their permissions silently broke
        // — and would just see a chip that does nothing on Fn-press. This
        // matches Cap's behavior: any time perms are missing, walk the user
        // back through the grant flow.
        let hasCompleted = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        let allPermsGranted = permissionService.allRequiredGranted
        if !hasCompleted {
            openOnboardingIfNeeded()
        } else if !allPermsGranted {
            openOnboardingIfNeeded(force: true, initialStep: .permissions)
        }

        // Floating chip — always-on bottom-of-screen presence. We install
        // it from second 1, regardless of onboarding state. Two reasons:
        //   (a) discoverability — user sees the app exists even before
        //       finishing setup;
        //   (b) when fn is pressed without permissions, the chip is the
        //       surface that tells the user "click here to fix it."
        // The chip's passive orange dot indicator + permissions-warning
        // state cover the "not ready yet" UX without hiding the chrome.
        installFloatingChip()
        // Initial state push — chip needs to know if it should show
        // the orange dot at first paint, before any permission change
        // notification fires.
        refreshChipPermissionState()
        // Start the periodic safety-net poll so the orange dot clears
        // within ~3s of any permission change, regardless of whether
        // we received an explicit transition event.
        startPermissionPolling()

        // Notification routing for chip side-buttons. SwiftUI views post
        // names when their buttons are tapped; AppDelegate is the
        // single place that knows how to open windows.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VoiceFlow.OpenMainWindow"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.openMainWindow() }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VoiceFlow.OpenSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.openSettings() }
        // Permissions warning chip click → open onboarding's Permissions
        // step. We force-open even if the user has already completed
        // onboarding once, so they can re-walk the permissions flow.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VoiceFlow.OpenOnboardingPermissions"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openOnboardingIfNeeded(force: true, initialStep: .permissions)
        }
        // Floating chip's left button — open the Run Log tab. Same
        // pattern as openSettings: open main window, then post the
        // tab-select notification on a tiny delay so window ordering
        // settles before SwiftUI observes the tab change.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VoiceFlow.OpenRunLog"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openMainWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(
                    name: Notification.Name("VoiceFlow.SelectTab"),
                    object: nil,
                    userInfo: ["tab": "runLog"]
                )
            }
        }
        // "Re-run onboarding" — fired from Settings → Setup card. Forces
        // the wizard window open even though has_completed_onboarding is
        // already true, so users can revisit any step they need.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VoiceFlow.RestartOnboarding"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.openOnboardingIfNeeded(force: true) }
        // App regained focus (typically: user came back from System Settings
        // after granting a permission). Re-poll TCC state so the chip's
        // orange dot disappears the moment they fixed the missing perm.
        // Without this, the orange dot would only clear when the user
        // explicitly triggered a refresh (e.g. clicking the chip).
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.permissionService.refreshStatus()
            self?.refreshChipPermissionState()
        }
        // User clicked X on the warning chip — dismiss immediately
        // instead of waiting for the auto-revert timer. Also restore
        // their previous clipboard since the warning's lifetime is the
        // contract for "transcript is on clipboard, paste now or lose it
        // back to your old content."
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VoiceFlow.DismissChipWarning"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.floatingChip?.setIdle()
            self?.textInjector?.restorePreservedClipboard()
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
        // Provider — Groq beats OpenAI as the free-tier default because we
        // ship an embedded Groq beta key. Without this seed the UI would
        // read OpenAI as the default (its fallback string in 3 places),
        // contradict TranscriptionProvider.current (which now defaults to
        // Groq), and surface "API key not present" on the first dictation.
        // Seeding here makes ALL three reader-fallbacks moot.
        if UserDefaults.standard.string(forKey: "transcription_provider") == nil {
            UserDefaults.standard.set(TranscriptionProvider.groq.rawValue, forKey: "transcription_provider")
        }
        if UserDefaults.standard.string(forKey: "output_mode") == nil {
            // Default to .verbatim ("Original") for first-run. This is the
            // ONLY style that works end-to-end on the free Groq tier
            // (no OpenAI key required). After the v0.4.0 routing change,
            // BOTH .clean (English = translation) AND .cleanHinglish
            // require OpenAI's multilingual STT — defaulting to either
            // would surface "No OpenAI API key configured" on the user's
            // very first dictation, before they've had any chance to add
            // a key. That's the cliff we're avoiding.
            //
            // English / Hinglish remain opt-in upsells: users who add an
            // OpenAI key in Settings see those pills appear in the Output
            // Style picker, and the dashboard's "Unlock English+Hinglish"
            // CTA points them at the right setting.
            UserDefaults.standard.set(TranscriptOutputStyle.verbatim.rawValue, forKey: "output_mode")
        } else {
            // Migration for users upgrading from v0.3.x → v0.4.0+:
            // they may have `output_mode = "clean"` persisted (the old
            // default that worked on Groq pre-v0.4.0). After v0.4.0,
            // .clean = translation = needs OpenAI. If they don't have an
            // OpenAI key configured, snap them to verbatim so the next
            // dictation doesn't fail. Doesn't touch users who DO have a
            // key — they get the upgraded translation behavior they
            // implicitly opted into by having a key.
            let stored = UserDefaults.standard.string(forKey: "output_mode") ?? ""
            let openAIKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
            let needsOpenAI = stored == TranscriptOutputStyle.clean.rawValue
                || stored == TranscriptOutputStyle.cleanHinglish.rawValue
                || stored == TranscriptOutputStyle.translateEnglish.rawValue
            if needsOpenAI && openAIKey.isEmpty {
                print("VoiceFlow: migrating output_mode '\(stored)' → 'verbatim' (no OpenAI key, would fail)")
                UserDefaults.standard.set(TranscriptOutputStyle.verbatim.rawValue, forKey: "output_mode")
            }
        }
        if UserDefaults.standard.string(forKey: "processing_mode") == nil {
            UserDefaults.standard.set(TranscriptProcessingMode.dictation.rawValue, forKey: "processing_mode")
        }
        if UserDefaults.standard.object(forKey: "noise_gate_threshold") == nil {
            // 0.005 is more permissive than the previous 0.008 default —
            // quiet speakers and laptops with budget mics were getting
            // hard-dropped at 0.008. The Sensitivity slider in Settings
            // exposes the full range (0.001 — 0.030) so users in noisy
            // environments can dial it back up.
            UserDefaults.standard.set(0.005, forKey: "noise_gate_threshold")
        }
        // Realtime streaming default ON. The biggest single perceived-latency
        // win we can ship: instead of waiting for Fn-release → upload WAV →
        // transcribe (sequential), we stream PCM16 to OpenAI's Realtime API
        // *while the user speaks*, so by the time Fn is released the
        // transcription is ~80% done. Saves ~350ms per dictation on a typical
        // 5-second utterance. The batch path remains as a safety net — if
        // the WebSocket drops mid-utterance, RealtimeTranscriptionService
        // falls back to the batch upload automatically.
        //
        // Why default ON now (was OFF): the flag was conservative when the
        // realtime path was new. It's been stable for weeks and is the
        // single biggest reason FreeFlow felt faster than us in head-to-head.
        // Works for BOTH providers — Groq exposes the same OpenAI-Realtime
        // protocol on wss://api.groq.com/openai/v1/realtime, so users on
        // Groq keys also get the streaming win (running through their faster
        // whisper-large-v3-turbo model — what FreeFlow uses).
        if UserDefaults.standard.object(forKey: Self.realtimeStreamingKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.realtimeStreamingKey)
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

    /// Spawn the persistent floating chip window. Idempotent — safe to
    /// call multiple times.
    func installFloatingChip() {
        if floatingChip == nil {
            floatingChip = FloatingChipWindow()
        }
        floatingChip?.show()
    }

    /// Sync the chip's passive permission indicator with the current TCC
    /// state. Called on app launch, on app re-activation, and after any
    /// permission change. We refreshStatus FIRST so we don't read a stale
    /// @Published value (TCC grants from System Settings can lag our
    /// cached state by ~100ms). Then we schedule a delayed re-check to
    /// catch the race where TCC has flipped but our cache missed it on
    /// the first read.
    func refreshChipPermissionState() {
        permissionService.refreshStatus()
        let allGranted = permissionService.allRequiredGranted
        floatingChip?.setPermissionsAvailable(allGranted)

        // Belt-and-suspenders: re-check after 0.6s. TCC sometimes lags
        // refreshStatus; a single poll right after grant can read stale.
        // Cheap call, no perceptible cost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            self.permissionService.refreshStatus()
            let recheck = self.permissionService.allRequiredGranted
            self.floatingChip?.setPermissionsAvailable(recheck)
        }
    }

    /// Periodic safety-net poll for the chip's permission indicator.
    /// Catches edge cases where neither onPermissionNewlyGranted nor
    /// didBecomeActive fired (e.g. user granted in System Settings and
    /// switched to a third-party app, then back to ours via cmd-tab —
    /// didBecomeActive fires in some macOS versions but not all).
    /// 3-second cadence is invisible to the user and costs ~one AX call
    /// per check.
    private var permissionPollTimer: Timer?
    func startPermissionPolling() {
        stopPermissionPolling()
        permissionPollTimer = Timer.scheduledTimer(
            withTimeInterval: 3.0,
            repeats: true
        ) { [weak self] _ in
            self?.refreshChipPermissionState()
        }
    }
    func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
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

            // First-launch default. We compute against the visible screen so
            // small displays don't get a window that overflows their bounds —
            // 90% cap leaves room for the dock and menu bar to coexist.
            //
            // After this, `setFrameAutosaveName` takes over: AppKit persists
            // user-driven resizes and positions to UserDefaults under the
            // given name, and restores them on subsequent launches. So this
            // size only applies to a truly fresh install — past that point,
            // the window remembers whatever the user last set.
            let target = NSSize(width: 1280, height: 860)
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame.size
                let safeWidth  = min(target.width,  visible.width  * 0.9)
                let safeHeight = min(target.height, visible.height * 0.9)
                mainWindow?.setContentSize(NSSize(width: safeWidth, height: safeHeight))
            } else {
                mainWindow?.setContentSize(target)
            }
            mainWindow?.center()
            // Persist + restore user-driven resizes. Has to come AFTER the
            // initial setContentSize so our default is what shows on first
            // launch — `setFrameAutosaveName` only overrides if a saved
            // frame exists for this name in UserDefaults.
            mainWindow?.setFrameAutosaveName("VoiceFlowMainWindow")

            mainWindow?.isReleasedWhenClosed = false
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    /// Open the main window with the Settings tab pre-selected.
    ///
    /// Was: a separate popup NSWindow hosting the legacy `SettingsView`.
    /// That created a SECOND settings UI duplicating everything in the main
    /// dashboard's Settings tab — same fields, different visual treatment,
    /// guaranteed drift over time. Now everything lives in one surface.
    ///
    /// Tab selection happens via NotificationCenter (`VoiceFlow.SelectTab`)
    /// rather than mutating a shared store — keeps MainDashboardView's
    /// state self-contained, just adds a listener at the body level.
    func openSettings() {
        openMainWindow()
        // Slight delay — NSWindow ordering needs to settle before SwiftUI
        // observes the notification, otherwise the tab switch can race
        // with the window's first render.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: Notification.Name("VoiceFlow.SelectTab"),
                object: nil,
                userInfo: ["tab": "settings"]
            )
        }
    }

    /// Opens the onboarding wizard. `force` ignores the
    /// has_completed_onboarding flag (used for "Re-run onboarding" + the
    /// chip's permissions warning click). `initialStep` deep-links to a
    /// specific wizard step — the permissions-warning chip uses this to
    /// jump straight to the Permissions screen instead of forcing the
    /// user to click through Welcome.
    func openOnboardingIfNeeded(force: Bool = false, initialStep: OnboardingStep = .welcome) {
        let hasCompleted = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        if !force && hasCompleted {
            return
        }

        // Always rebuild when force-opening with a specific step — the
        // existing window's coordinator might be on a different step.
        if onboardingWindow != nil && force {
            onboardingWindow?.close()
            onboardingWindow = nil
        }

        if onboardingWindow == nil {
            let onboardingView = OnboardingView(
                permissionService: permissionService,
                initialStep: initialStep,
                onOpenSettings: { [weak self] in
                    self?.openSettings()
                },
                onDone: { [weak self] in
                    let wasFirstRun = !UserDefaults.standard.bool(forKey: "has_completed_onboarding")
                    UserDefaults.standard.set(true, forKey: "has_completed_onboarding")
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                    // Chip is now installed from app launch — no longer
                    // need to lazy-init here. installFloatingChip is
                    // idempotent so calling again is harmless, but we
                    // do refresh permission state since the user just
                    // walked through the permissions step.
                    self?.installFloatingChip()
                    self?.refreshChipPermissionState()
                    // First-run only: surface the dashboard once so the user
                    // discovers it exists. Without this, onboarding closes
                    // and the user is left with just a tiny chip — they have
                    // no idea where to find Run Log, Settings, etc. After
                    // this single first-run reveal, returning launches stay
                    // menu-bar-only (the Raycast/Alfred convention).
                    //
                    // Re-grant flows (force=true with initialStep=.permissions)
                    // skip this — those users already know the dashboard
                    // exists, they're just here to fix a missing TCC entry.
                    if wasFirstRun {
                        self?.openMainWindow()
                    }
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

            // EAGERLY capture context (active app + selection). Done at
            // press-time, NOT at result-time, because by the time STT +
            // LLM returns 1–4s later, the user may have alt-tabbed away.
            // ContextProvider is fail-soft — returns an empty snapshot if
            // capture is disabled or AX is unavailable.
            self.pendingContext = ContextProvider.shared.snapshot(hotkey: .primary)

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

            // Hard gate: ALL required permissions must be granted, not just
            // mic. If accessibility or input monitoring is missing, the
            // post-transcribe injection will fail anyway — surface that
            // upfront with one chip warning instead of letting the user
            // record into the void.
            //
            // Note: input monitoring being missing is mostly hypothetical
            // here, because if it were missing we wouldn't have received
            // the fn-press at all. Checking it anyway covers the edge
            // case where it was just revoked between key events.
            let perms = self.permissionService
            if !perms.accessibilityState.isGranted ||
               !perms.inputMonitoringState.isGranted {
                print("Aborting recording: required permissions missing")
                self.isRecording = false
                self.floatingChip?.flashPermissionsWarning()
                return
            }

            // From here down, mic is granted. Everything else is best-effort.
            //
            // Soft gate (no upfront focus check): always record. AX-based
            // role detection produces too many false negatives — apps like
            // VS Code, iTerm, and various Electron tools sometimes expose
            // their text input as AXScrollArea or AXGroup instead of
            // AXTextArea. Blocking those would be hostile.
            //
            // Instead the focus check happens AT INJECTION TIME inside
            // TextInjector. If injection can't land in a real text input,
            // the transcript still goes to the clipboard and the warning
            // chip flashes with paste instructions.
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
            // Recording stopped, polish/transcription in flight → processing.
            // The floating chip stays in this state until handleResult
            // completes (success or failure), which calls hideRecordingOverlay
            // → setIdle.
            self.floatingChip?.setProcessing()

            // Begin a RunLog session to accumulate pipeline data.
            let session = self.runRecorder.beginRun()

            self.audioRecorder?.stopRecording { [weak self] audioData in
                guard let self else { return }
                guard let audioData = audioData else {
                    // No voiced audio captured — AudioRecorder gates this
                    // upstream now (see its stopRecording: when no buffer
                    // crosses the noise threshold, it returns nil rather
                    // than handing us silent audio that Whisper would
                    // hallucinate over).
                    //
                    // We must also tear down any realtime stream that was
                    // running during this attempt; otherwise the WebSocket
                    // stays open, holding a session slot until network
                    // timeout. setupRealtimeStreamIfEnabled() also clears
                    // it at the START of the next session, but that's too
                    // late if the user starts another recording quickly.
                    //
                    // UX feedback: previously this path silently no-op'd
                    // and users saw NOTHING happen after fn-release —
                    // they'd assume the app was broken. We now flash the
                    // chip with a "no audio detected" hint so the user
                    // knows their input was below the noise gate, with
                    // the implicit pointer to Settings → Mic Sensitivity.
                    print("Transcription skipped: no audio data produced (no voice detected)")
                    DispatchQueue.main.async {
                        self.realtimeStream?.close()
                        self.realtimeStream = nil
                        self.realtimeStreamFailed = false
                        self.hideRecordingOverlay()
                        self.floatingChip?.flashNoAudioWarning(durationSeconds: 3.0)
                    }
                    return
                }

                // Stage 1: Capture
                session.captureCompleted(audioData: audioData, voicedRange: nil)

                let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
                // Default to verbatim — the only style that works on
                // the free Groq tier without an OpenAI key. configureDefaultSettings
                // also seeds this on first launch, but the fallback here
                // is the safety belt for any code path that reaches
                // startRecording before configureDefaultSettings has run
                // (e.g. an early hotkey press during cold-launch).
                let outputModeRaw = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.verbatim.rawValue
                let userSelectedStyle = TranscriptOutputStyle(rawValue: outputModeRaw) ?? .verbatim
                let processingModeRaw = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
                let processingMode = TranscriptProcessingMode(rawValue: processingModeRaw) ?? .dictation

                // Policy: style alone drives the output contract.
                //   - Original (verbatim) — raw STT, respects language picker.
                //   - English (.clean) — translates anything to English.
                //   - Hinglish (.cleanHinglish) — preserves bilingual mix.
                //
                // Previous version coupled `language == "en"` with style to
                // trigger translation. That meant the language picker did
                // double duty (Whisper hint + output-language switch), which
                // confused users — picking English style wouldn't translate
                // unless they ALSO set language to English. The style is now
                // the single source of truth; the language picker only
                // affects Verbatim.
                let effectiveStyle: TranscriptOutputStyle = userSelectedStyle

                // STT language hint. For polished styles, WhisperService.route()
                // overrides this anyway (auto-detect for .clean, "hi" for
                // .cleanHinglish). The value here only matters for .verbatim,
                // where the user's explicit language choice wins.
                let transcriptionLanguage = language

                // Streaming path: if we started a stream session and it's still
                // alive, commit and await the final transcript. On any failure
                // we silently fall through to the batch path with the WAV we
                // already captured — user never sees a broken dictation because
                // of a dropped WebSocket.
                let handleResult: (Result<TranscriptionMetadata, Error>) -> Void = { [weak self] result in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.hideRecordingOverlay()
                        switch result {
                        case .success(let metadata):
                            // Stage 2: Transcription
                            session.transcriptionCompleted(
                                provider: metadata.provider,
                                rawText: metadata.rawText,
                                latencyMs: metadata.transcriptionLatencyMs
                            )

                            // Stage 3: Post-processing — record what the
                            // legacy polish path produced so the run log
                            // shows the original cleanup result even when
                            // a router-driven profile overrides finalText.
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

                            // Attach context to the run BEFORE the router
                            // potentially routes — the snapshot is needed
                            // both for routing (trigger detection) AND for
                            // the run log row (per-app insights).
                            let context = self.pendingContext ?? .empty()
                            session.attachContext(context)
                            self.pendingContext = nil

                            // Routing: decide if a non-standard profile
                            // should override the polished finalText.
                            //
                            // Tradeoff: we ALWAYS run the legacy polish
                            // path first, even when the trigger is going
                            // to override it. That's a wasted polish call
                            // when dev mode triggers — the cost is one
                            // extra LLM call (~500ms-1.5s on the cloud
                            // backend). We accept it for now because the
                            // alternative is to refactor the streaming /
                            // batch / fallback paths to bypass polish on
                            // trigger detection, which is high-risk.
                            // FOLLOW-UP: skip polish on detected trigger.
                            self.applyRouterOverride(
                                rawTranscript: metadata.rawText,
                                fallbackFinalText: metadata.finalText,
                                context: context,
                                style: effectiveStyle,
                                mode: processingMode,
                                session: session
                            )

                        case .failure(let error):
                            // Attach context to failed runs too — these are
                            // where debugging value is highest. We need to
                            // know which app they were dictating to when
                            // it broke.
                            if let ctx = self.pendingContext {
                                session.attachContext(ctx)
                                self.pendingContext = nil
                            }
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

    // MARK: - Router-driven profile override

    /// Bridge between the legacy `transcribeAndPolishWithMetadata` pipeline
    /// and the new TransformerProfile router.
    ///
    /// Behavior:
    /// - If the router picks `.standardCleanup`, just inject the polished
    ///   `fallbackFinalText` (no second LLM call — we already polished).
    /// - Otherwise, run `profile.transform(...)` and inject ITS output.
    ///
    /// Why this design over rewriting the pipeline: keeps the existing
    /// streaming/batch/fallback paths untouched. Magic word + dev mode +
    /// var recognition slot in cleanly without a giant refactor.
    private func applyRouterOverride(
        rawTranscript: String,
        fallbackFinalText: String,
        context: ContextSnapshot,
        style: TranscriptOutputStyle,
        mode: TranscriptProcessingMode,
        session: RunSession
    ) {
        // No router available (whisper not yet initialized — shouldn't
        // happen in practice but guards initialization order).
        guard let router = self.transformerRouter else {
            self.persistAndInject(text: fallbackFinalText, session: session)
            return
        }

        // Empty raw transcript → nothing to route. Use polished output
        // (which may also be empty) so the existing hallucination guards
        // continue to work.
        let trimmedRaw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            self.persistAndInject(text: fallbackFinalText, session: session)
            return
        }

        let decision = router.route(transcript: trimmedRaw, context: context)
        session.attachProfile(kind: decision.profile.kind, trace: decision.trace)

        // Standard cleanup → use the polish path's output. We DON'T
        // call StandardCleanupProfile.transform() because that would be
        // a second polish round-trip on the same text.
        if decision.profile.kind == .standardCleanup {
            self.persistAndInject(text: fallbackFinalText, session: session)
            return
        }

        // Non-standard profile → run its transform, override final text.
        let input = TransformerInput(
            rawTranscript: trimmedRaw,
            context: context,
            style: style,
            mode: mode
        )
        decision.profile.transform(input) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let output):
                    session.recordLLMCost(output.costUSD)
                    self.persistAndInject(text: output.finalText, session: session)
                case .failure(let err):
                    // Profile failed — fall back to polished text rather
                    // than dropping the dictation on the floor.
                    print("Profile \(decision.profile.kind.rawValue) failed: \(err.localizedDescription) — falling back to polished text")
                    self.persistAndInject(text: fallbackFinalText, session: session)
                }
            }
        }
    }

    /// Common tail: flush the run to disk + inject text into the focused
    /// app. Called from both the success and profile-failure paths.
    private func persistAndInject(text: String, session: RunSession) {
        session.finish()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("Empty transcript (likely hallucination-filtered); nothing to inject.")
            return
        }
        self.textInjector?.injectText(trimmed)
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

        // Both OpenAI and Groq expose the OpenAI-Realtime WebSocket
        // protocol — same message shape, same intent=transcription, same
        // input_audio_buffer events. Different host + different model.
        // FreeFlow's "fast on a Groq key" experience comes from this exact
        // path running against whisper-large-v3-turbo on Groq's stack.
        let provider = TranscriptionProvider.current
        let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
        let normalizedLanguage = language == "auto" ? "" : language

        let config: RealtimeTranscriptionService.Configuration
        switch provider {
        case .openai:
            let apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
            guard !apiKey.isEmpty else { return }
            config = .openAI(apiKey: apiKey, language: normalizedLanguage)
        case .groq:
            // User-provided key wins; falls back to embedded beta key
            // so the free-tier path "just works" out of the box.
            let userKey = UserDefaults.standard.string(forKey: "groq_api_key") ?? ""
            let apiKey = userKey.isEmpty ? EmbeddedKeys.groq : userKey
            guard !apiKey.isEmpty else { return }
            config = .groq(apiKey: apiKey, language: normalizedLanguage)
        }
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

    /// Recording-state UI lives in the bottom floating chip. The notch
    /// chip (`recordingOverlay`) is silenced — bottom chip is the only
    /// indicator. Focus check happens UPSTREAM in `startRecording`; by
    /// the time this runs, we've already gated and confirmed a text
    /// input exists.
    let focusDetector = FocusDetector()

    private func showRecordingOverlay() {
        floatingChip?.setRecording()
        audioRecorder?.onAmplitude = { [weak chip = floatingChip] level in
            chip?.updateAudioLevel(level)
        }
    }

    private func hideRecordingOverlay() {
        audioRecorder?.onAmplitude = nil
        // Pipeline complete → back to idle. setProcessing() is called
        // separately at the moment fn is released (stopRecording).
        floatingChip?.setIdle()
    }
}
