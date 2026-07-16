import SwiftUI
import AppKit
import AVFoundation
import Carbon
import ApplicationServices
import IOKit.hid
import Combine

@main
struct VordiApp: App {
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
            VFMenuBarBrandIcon()
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
    case screenRecording
}

final class PermissionService: ObservableObject {
    static let shared = PermissionService()

    @Published private(set) var microphoneState: PermissionState = .notDetermined
    @Published private(set) var accessibilityState: PermissionState = .notDetermined
    @Published private(set) var inputMonitoringState: PermissionState = .notDetermined
    @Published private(set) var screenRecordingState: PermissionState = .notDetermined
    @Published private(set) var environmentWarning: String?
    private var lastMicDebugSnapshot: String = ""
    private var observedWorkingMicrophoneInput = false

    /// Fires whenever any previously-missing permission flips to granted.
    /// Used by AppDelegate to hot-reload the HotKeyListener without
    /// forcing the user to quit + relaunch the app.
    var onPermissionNewlyGranted: ((PermissionPane) -> Void)?

    private var lastAllStates: [PermissionPane: Bool] = [
        .microphone: false, .accessibility: false, .inputMonitoring: false, .screenRecording: false
    ]
    private var pollingTimer: Timer?

    var allRequiredGranted: Bool {
        microphoneState.isGranted && accessibilityState.isGranted && inputMonitoringState.isGranted
    }

    var allOnboardingPermissionsGranted: Bool {
        allRequiredGranted && screenRecordingState.isGranted
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
            // Stop polling once every onboarding permission is granted — no
            // need to burn cycles. Screen Recording is not required for core
            // dictation, but onboarding displays it as part of setup.
            if self.allOnboardingPermissionsGranted {
                self.pollingTimer?.invalidate()
                self.pollingTimer = nil
            }
        }
    }

    func refreshStatus() {
        if Thread.isMainThread {
            performStatusRefresh()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performStatusRefresh()
            }
        }
    }

    private func performStatusRefresh() {
        let newMic = currentMicrophoneState()
        let newAx = AXIsProcessTrusted() ? PermissionState.granted : .denied
        let newInput = preflightInputMonitoringAccess() ? PermissionState.granted : .denied
        let newScreen = preflightScreenRecordingAccess() ? PermissionState.granted : .denied

        var newlyGrantedPanes: [PermissionPane] = []
        if !(lastAllStates[.microphone] ?? false), newMic.isGranted {
            newlyGrantedPanes.append(.microphone)
        }
        if !(lastAllStates[.accessibility] ?? false), newAx.isGranted {
            newlyGrantedPanes.append(.accessibility)
        }
        if !(lastAllStates[.inputMonitoring] ?? false), newInput.isGranted {
            newlyGrantedPanes.append(.inputMonitoring)
        }
        if !(lastAllStates[.screenRecording] ?? false), newScreen.isGranted {
            newlyGrantedPanes.append(.screenRecording)
        }

        lastAllStates[.microphone] = newMic.isGranted
        lastAllStates[.accessibility] = newAx.isGranted
        lastAllStates[.inputMonitoring] = newInput.isGranted
        lastAllStates[.screenRecording] = newScreen.isGranted

        // CRITICAL: Only assign @Published properties when the value
        // actually changed. @Published fires objectWillChange on EVERY
        // set — even same-value assignments. Without these guards, every
        // 2s poll triggers a full SwiftUI view re-evaluation cascade
        // through MenuBarExtra → EnvironmentObject → all child views.
        if microphoneState != newMic { microphoneState = newMic }
        if accessibilityState != newAx { accessibilityState = newAx }
        if inputMonitoringState != newInput { inputMonitoringState = newInput }
        if screenRecordingState != newScreen { screenRecordingState = newScreen }
        let newWarning = currentEnvironmentWarning()
        if environmentWarning != newWarning { environmentWarning = newWarning }

        let micDebug = currentMicrophoneDebugSnapshot()
        if micDebug != lastMicDebugSnapshot {
            lastMicDebugSnapshot = micDebug
            print("Vordi microphone status: \(micDebug)")
        }

        for pane in newlyGrantedPanes {
            notifyPermissionNewlyGranted(pane)
        }
    }

    private func notifyPermissionNewlyGranted(_ pane: PermissionPane) {
        print("Permission newly granted: \(pane)")
        onPermissionNewlyGranted?(pane)
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

    func preflightScreenRecordingAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
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

    func requestScreenRecordingAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            _ = CGRequestScreenCaptureAccess()
            self.refreshStatusAfterDelay()
        }
    }

    /// Opens the app's location in Finder so the user can manually drag
    /// Vordi into the Input Monitoring list — this is the documented
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
        case .screenRecording:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
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
            return "\(AppBrand.name) is running from a DMG volume. Drag it to /Applications and launch that copy so permissions persist."
        }

        if appPath.contains("/DerivedData/") || appPath.contains("/build/") {
            return "\(AppBrand.name) is running from an Xcode build folder. Permissions can look mismatched; use a single /Applications install for testing."
        }

        let bundleId = Bundle.main.bundleIdentifier ?? "com.vordi.app"
        let runningCount = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleId }.count
        if runningCount > 1 {
            return "Multiple \(AppBrand.name) instances are running. Quit all duplicates and relaunch one copy from /Applications."
        }

        return nil
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    var settingsWindow: NSWindow?
    var onboardingWindow: NSWindow?
    var mainWindow: NSWindow?
    var notesWindow: FloatingNotesWindow?
    /// Persistent feedback surfaces. Only one is visible at a time,
    /// controlled by Settings -> Feedback Surface.
    var notchPill: NotchPillWindow?
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
    /// User-configurable shortcut bindings. Observed below so edits in Settings
    /// reconfigure the live listener without a restart.
    let hotkeySettings = HotkeySettingsStore.shared
    private var hotkeyConfigCancellable: AnyCancellable?
    var permissionService = PermissionService.shared
    let recordingState = RecordingStateStore()
    let runStore = RunStore.shared
    let noteStore = VoiceNoteStore.shared
    lazy var runRecorder = RunRecorder(store: runStore)

    /// Captured just after the audio engine starts, consumed at result-time.
    /// Context capture is intentionally deferred off the press-critical path:
    /// screenshot/JPEG work can take hundreds of milliseconds on large windows.
    /// A capture generation prevents a late snapshot from an older recording
    /// from overwriting the current one.
    private var pendingContext: ContextSnapshot?
    private var pendingContextSummaryTask: Task<Void, Never>?
    private var pendingContextCaptureID: UUID?

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

    // MARK: - Hands-free state machine
    //
    // The Fn key has two interaction modes:
    //   1. Hold-to-dictate (legacy): press → record, release → transcribe.
    //   2. Ctrl+Fn → hands-free: continuous listening until next Fn press
    //      OR Escape.
    //
    // Chord detection happens in HotKeyListener, but the state transition
    // stays here because this object owns the recording pipeline.
    //
    // State transitions:
    //   .off → (Ctrl+Fn chord) → .on (hands-free)
    //   .on  → (Fn down OR Escape) → .off (stop & transcribe normally)

    private enum HandsFreeState: Equatable { case off, on }
    private var handsFreeState: HandsFreeState = .off

    /// Drives the continuous chunked-dictation loop while hands-free is active:
    /// each ~2s pause harvests an utterance, which this controller transcribes +
    /// injects in order. See `ContinuousDictationController`.
    private let continuousDictation = ContinuousDictationController()

    /// PROTOTYPE (Option B): types realtime partials straight into the focused
    /// app as you speak, then reconciles to the final polished text. Gated by
    /// `LiveInjectionController.enabledKey` (default OFF). See the controller.
    private let liveInjection = LiveInjectionController()

    /// On-device live preview (Apple SFSpeechRecognizer): drives the notch's live
    /// transcript from a local recognizer so it works on any provider (incl. free
    /// Groq) and in hands-free — while our API still produces the pasted text.
    /// Gated by `AppleSpeechLivePreview.enabledKey` (default OFF).
    private let liveSpeechPreview = AppleSpeechLivePreview()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Regular activation: full app with Dock icon + proper window.
        // Menu bar extra still registered for quick access.
        NSApp.setActivationPolicy(.regular)
        configureDockIcon()
        configureDefaultSettings()

        // Anonymous usage analytics (honors the opt-out internally). app_installed
        // fires once ever; app_open fires each launch.
        if !UserDefaults.standard.bool(forKey: "analytics_has_launched_before") {
            UserDefaults.standard.set(true, forKey: "analytics_has_launched_before")
            AnalyticsClient.shared.track("app_installed")
        }
        AnalyticsClient.shared.track("app_open", params: [
            "onboarded": UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        ])

        audioRecorder = AudioRecorder()
        whisperService = WhisperService()
        // Kick off connection pre-warm immediately. TLS + HTTP/2 handshake
        // to api.openai.com costs ~150-300ms on a cold URLSession pool and
        // shows up as fixed overhead on the FIRST dictation after launch.
        // RunLog p50 STT latency is ~2s — shaving that handshake off a
        // 3s median utterance is a free ~10% latency win.
        whisperService?.prewarmConnections()
        textInjector = TextInjector()

        // Continuous hands-free wiring. The AudioRecorder fires onUtteranceSilence
        // on a ~2s pause; the controller transcribes + injects each harvested
        // segment in order via the closures below.
        audioRecorder?.onUtteranceSilence = { [weak self] in
            self?.handleUtteranceSilence()
        }
        continuousDictation.processSegment = { [weak self] wav, context, alreadyInjected, completion in
            guard let self else { completion(false); return }
            self.transcribeAndInjectHandsFreeSegment(
                audioData: wav,
                context: context,
                alreadyInjectedCount: alreadyInjected,
                completion: completion
            )
        }
        continuousDictation.onExitDrained = { [weak self] in
            self?.finishHandsFreeSession()
        }

        // On-device live preview → notch. Apple's recognizer streams partials as
        // you speak; show them in the notch's live-transcript line. The pasted
        // text still comes from the API pipeline, unchanged.
        liveSpeechPreview.onPartial = { [weak self] text in
            self?.activeFeedbackSurface()?.setLiveTranscript(text)
        }
        // Prime Speech Recognition authorization at launch if the feature is on,
        // so the first dictation already has a live preview (the TCC prompt only
        // appears once).
        if UserDefaults.standard.bool(forKey: AppleSpeechLivePreview.enabledKey) {
            AppleSpeechLivePreview.requestAuthorization { _ in }
        }

        noteStore.observeDictationRuns(from: runStore)
        // Suppression hook: fires after a successful transcript when it
        // can't be injected directly (Vordi foreground, no text input
        // focused, etc.). The transcript is already on the clipboard, so
        // surface this as a clipboard fallback instead of a "no input"
        // transcription failure.
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

                self.activeFeedbackSurface()?.flashTranscriptCopied(durationSeconds: 4.5)
            }
        }
        hotKeyListener = HotKeyListener()
        hotKeyListener?.onKeyDown = { [weak self] in
            self?.handleHotKeyDown()
        }
        hotKeyListener?.onKeyUp = { [weak self] in
            self?.handleHotKeyUp()
        }
        hotKeyListener?.onHandsFreeToggle = { [weak self] in
            self?.handleHandsFreeToggle()
        }
        hotKeyListener?.onEscape = { [weak self] in
            self?.handleEscapeKey()
        }
        // Load the saved bindings and keep the listener in sync with any
        // future edits from Settings. `.dropFirst()` skips @Published's
        // replay of the current value (already applied on the line above).
        applyHotkeyConfig()
        hotkeyConfigCancellable = hotkeySettings.$config
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyHotkeyConfig() }

        // Microphone is essential — request it on launch so Vordi
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
        // manually dragging Vordi into the Input Monitoring list.
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
        //      onboarding from the Features page.
        //   2. has_completed_onboarding=true BUT any required permission is
        //      missing → user reinstalled, OS-upgraded, or revoked a perm
        //      between sessions. Jump straight to the Permissions step so
        //      they can re-grant without re-watching the feature screens.
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
        // Resume takes priority over everything else: if the wizard was open
        // when the app last quit, it was almost certainly a macOS "Quit &
        // Reopen" triggered by granting Screen Recording / Input Monitoring
        // (both require a relaunch to take effect). Without this branch, a user
        // re-running onboarding to add Screen Recording — where
        // has_completed_onboarding is already true AND the three core perms are
        // granted — hits neither branch below and lands on the dashboard, with
        // onboarding silently gone.
        let hasCompleted = UserDefaults.standard.bool(forKey: "has_completed_onboarding")
        if UserDefaults.standard.bool(forKey: OnboardingCoordinator.inProgressKey) {
            openOnboardingIfNeeded(force: true, initialStep: resumeOnboardingStep())
        } else if !hasCompleted {
            openOnboardingIfNeeded()
        } else if !permissionService.allRequiredGranted {
            // Re-onboard returning users ONLY when a CORE-required permission
            // (mic/accessibility/input monitoring) is missing. Screen Recording
            // is optional (powers screenshot context); gating on it here forced
            // onboarding on every launch for anyone who never granted it.
            openOnboardingIfNeeded(force: true, initialStep: .permissions)
        }

        // Feedback surface — always-on presence. The user can choose
        // between the notch-docked pill and the draggable bottom chip.
        // We install it from second 1, regardless of onboarding state,
        // so permission and recording feedback always has a visible surface.
        installFeedbackSurface()
        // Initial state push — pill needs to know if it should show
        // the orange dot at first paint, before any permission change
        // notification fires.
        refreshChipPermissionState()
        // Start the periodic safety-net poll so the orange dot clears
        // within ~3s of any permission change, regardless of whether
        // we received an explicit transition event.
        startPermissionPolling()

        // Memory chat provider detection is cheap and keeps the Memory tab
        // ready. The actual Memory/Insights indexing work is manual-only via
        // Sync so app launch never competes with dictation.
        Task { @MainActor in
            LLMRouter.shared.start()
        }

        // Notification routing for notch pill taps. SwiftUI views post
        // names when their buttons are tapped; AppDelegate is the
        // single place that knows how to open windows.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("Vordi.OpenMainWindow"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.openMainWindow() }
        // Run Log "Retry transcript" → re-run the pipeline on the stored audio.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("Vordi.RetryRun"),
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let runID = note.userInfo?["runID"] as? UUID else { return }
            self?.handleRetryRun(runID: runID)
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("Vordi.OpenSettings"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.openSettings() }
        // Permissions warning chip click → open onboarding's Permissions
        // step. We force-open even if the user has already completed
        // onboarding once, so they can re-walk the permissions flow.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("Vordi.OpenOnboardingPermissions"),
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
            forName: Notification.Name("Vordi.OpenRunLog"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.openMainWindow()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NotificationCenter.default.post(
                    name: Notification.Name("Vordi.SelectTab"),
                    object: nil,
                    userInfo: ["tab": "runLog"]
                )
            }
        }
        NotificationCenter.default.addObserver(
            forName: Notification.Name("Vordi.OpenFloatingNotes"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let text = notification.userInfo?["text"] as? String
            let noteID = notification.userInfo?["noteID"] as? String
            self?.openFloatingNotesFromCommand(seedText: text, noteID: noteID)
        }
        // "Re-run onboarding" — fired from Settings → Setup card. Forces
        // the wizard window open even though has_completed_onboarding is
        // already true, so users can revisit any step they need.
        NotificationCenter.default.addObserver(
            forName: Notification.Name("Vordi.RestartOnboarding"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.openOnboardingIfNeeded(force: true) }
        NotificationCenter.default.addObserver(
            forName: .voiceFlowFeedbackSurfaceStyleChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyFeedbackSurfacePreference()
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyFeedbackSurfacePreference()
        }
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
            forName: Notification.Name("Vordi.DismissChipWarning"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.activeFeedbackSurface()?.setIdle()
            self?.textInjector?.restorePreservedClipboard()
        }
        // Returning users: stay menu-bar only. Window is reachable via Dock
        // icon click (applicationShouldHandleReopen) or menu bar → Open
        // Vordi. Matches the behavior of Raycast, Rectangle, Alfred,
        // etc. — no unsolicited window on every launch.
    }

    private func configureDockIcon() {
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
              let image = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApp.applicationIconImage = roundedDockIcon(from: image)
    }

    private func roundedDockIcon(from image: NSImage) -> NSImage {
        let size = NSSize(width: 1024, height: 1024)
        let cornerRadius = size.width * 0.18

        return NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.imageInterpolation = .high
            NSColor.clear.setFill()
            rect.fill()

            NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            ).addClip()

            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    /// Re-opens the main dashboard when the user clicks the Dock icon
    /// after having closed the window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // While onboarding is unfinished, a reopen (Dock click, or a relaunch
        // that routes through here) should surface the wizard — not the
        // dashboard — so the user is never dropped out of setup mid-flow.
        if UserDefaults.standard.bool(forKey: OnboardingCoordinator.inProgressKey) {
            if let onboardingWindow {
                onboardingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                openOnboardingIfNeeded(force: true, initialStep: resumeOnboardingStep())
            }
            return true
        }
        if !flag {
            openMainWindow()
        }
        return true
    }

    /// The step to resume onboarding at after a relaunch. Defaults to
    /// `.permissions` — the only step whose grant buttons trigger a macOS
    /// "Quit & Reopen" — when no step was persisted.
    private func resumeOnboardingStep() -> OnboardingStep {
        let raw = UserDefaults.standard.object(forKey: OnboardingCoordinator.currentStepKey) as? Int
        return raw.flatMap(OnboardingStep.init(rawValue:)) ?? .permissions
    }

    /// User dismissed the onboarding window themselves (close button / Cmd-W).
    /// Clear the resume flags so the wizard doesn't force itself back open on
    /// the next launch. Not called for programmatic `close()` or app
    /// termination, so a "Quit & Reopen" relaunch still resumes onboarding.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender == onboardingWindow {
            OnboardingCoordinator.markDismissed()
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
            // Default to Romanized on first run — Groq's whisper-large-v3
            // handles multilingual out of the box, so there's no cliff.
            // Users speaking Hindi, Marathi, or English all get a useful
            // result immediately without configuring anything.
            UserDefaults.standard.set(TranscriptOutputStyle.cleanHinglish.rawValue, forKey: "output_mode")
        } else if UserDefaults.standard.string(forKey: "output_mode") == TranscriptOutputStyle.clean.rawValue {
            UserDefaults.standard.set(TranscriptOutputStyle.translateEnglish.rawValue, forKey: "output_mode")
        }
        let polishDefaultMigrationKey = "did_migrate_processing_mode_default_to_polish_v1"
        if UserDefaults.standard.string(forKey: "processing_mode") == nil {
            UserDefaults.standard.set(TranscriptProcessingMode.dictation.rawValue, forKey: "processing_mode")
        } else if !UserDefaults.standard.bool(forKey: polishDefaultMigrationKey),
                  UserDefaults.standard.string(forKey: "processing_mode") == TranscriptProcessingMode.rewrite.rawValue {
            UserDefaults.standard.set(TranscriptProcessingMode.dictation.rawValue, forKey: "processing_mode")
        }
        UserDefaults.standard.set(true, forKey: polishDefaultMigrationKey)
        if let storedPolishBackend = UserDefaults.standard.string(forKey: PolishBackend.userDefaultsKey),
           PolishBackend.legacyGroqModelIds.contains(storedPolishBackend) {
            print("Vordi: migrating polish_backend_id '\(storedPolishBackend)' → '\(PolishBackend.defaultIdGroq)'")
            UserDefaults.standard.set(PolishBackend.defaultIdGroq, forKey: PolishBackend.userDefaultsKey)
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
        if UserDefaults.standard.string(forKey: FeedbackSurfaceStyle.userDefaultsKey) == nil {
            UserDefaults.standard.set(
                FeedbackSurfaceStyle.dynamicNotch.rawValue,
                forKey: FeedbackSurfaceStyle.userDefaultsKey
            )
        }
        // Anonymous usage analytics — default ON, opt-out in Settings → Privacy.
        // Never includes transcript content (see AnalyticsClient).
        if UserDefaults.standard.object(forKey: AnalyticsClient.analyticsEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: AnalyticsClient.analyticsEnabledKey)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyListener?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if allowTermination {
            return .terminateNow
        }

        // User-initiated Cmd+Q.
        if let event = NSApp.currentEvent,
           event.type == .keyDown,
           event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            return .terminateNow
        }

        // System-initiated quit. macOS sends kAEQuitApplication when:
        //   - The user clicks "Quit & Reopen" in the TCC dialog after
        //     granting Input Monitoring / Accessibility (the system needs
        //     us dead before the new permission takes effect).
        //   - Activity Monitor → Quit.
        //   - AppleScript: `tell application "Vordi" to quit`.
        //   - shutdown / logout / reboot.
        // All of these are legitimate quits we should honor.
        //
        // Without this branch, "Quit & Reopen" silently fails — the dialog
        // closes, the user expects the app to relaunch with new permissions,
        // but the old process keeps running and the new permission stays
        // ungranted at runtime until they kill the app manually.
        if let appleEvent = NSAppleEventManager.shared().currentAppleEvent,
           appleEvent.eventClass == AEEventClass(kCoreEventClass),
           appleEvent.eventID == AEEventID(kAEQuitApplication) {
            print("System Apple Event quit (kAEQuitApplication) — terminating")
            return .terminateNow
        }

        print("Blocked unexpected terminate request; use Quit \(AppBrand.name) to exit.")
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

    /// Spawn the preferred feedback surface. Idempotent and safe to call often.
    func installFeedbackSurface() {
        switch FeedbackSurfaceStyle.current {
        case .dynamicNotch:
            floatingChip?.setIdle()
            floatingChip?.hide()
            if notchPill == nil {
                notchPill = NotchPillWindow()
            }
            notchPill?.show()
        case .draggableChip:
            notchPill?.setIdle()
            notchPill?.hide()
            if floatingChip == nil {
                floatingChip = FloatingChipWindow()
            }
            floatingChip?.show()
        }
    }

    private func activeFeedbackSurface() -> FeedbackSurface? {
        switch FeedbackSurfaceStyle.current {
        case .dynamicNotch:
            if notchPill == nil {
                installFeedbackSurface()
            }
            return notchPill
        case .draggableChip:
            if floatingChip == nil {
                installFeedbackSurface()
            }
            return floatingChip
        }
    }

    private func applyFeedbackSurfacePreference() {
        notchPill?.hide()
        floatingChip?.hide()
        installFeedbackSurface()
        refreshChipPermissionState()

        if isRecording {
            if handsFreeState == .on {
                activeFeedbackSurface()?.setHandsFree()
            } else {
                activeFeedbackSurface()?.setRecording()
            }
        }
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
        let missingPermissions = missingRequiredPermissionNames
        activeFeedbackSurface()?.setPermissionsAvailable(missingPermissions.isEmpty)
        activeFeedbackSurface()?.setMissingPermissions(missingPermissions)
        updatePermissionPollingState()

        // Belt-and-suspenders: re-check after 0.6s. TCC sometimes lags
        // refreshStatus; a single poll right after grant can read stale.
        // Cheap call, no perceptible cost.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            self.permissionService.refreshStatus()
            let missingPermissions = self.missingRequiredPermissionNames
            self.activeFeedbackSurface()?.setPermissionsAvailable(missingPermissions.isEmpty)
            self.activeFeedbackSurface()?.setMissingPermissions(missingPermissions)
            self.updatePermissionPollingState()
        }
    }

    private var missingRequiredPermissionNames: [String] {
        var names: [String] = []
        if !permissionService.microphoneState.isGranted {
            names.append("Microphone")
        }
        if !permissionService.accessibilityState.isGranted {
            names.append("Accessibility")
        }
        if !permissionService.inputMonitoringState.isGranted {
            names.append("Input Monitoring")
        }
        return names
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
        guard permissionPollTimer == nil else { return }
        guard !permissionService.allOnboardingPermissionsGranted else {
            stopPermissionPolling()
            return
        }
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

    private func updatePermissionPollingState() {
        if permissionService.allOnboardingPermissionsGranted {
            stopPermissionPolling()
        } else {
            startPermissionPolling()
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
                onOpenFloatingNotes: { [weak self] in
                    self?.openFloatingNotesWindow(hideMainWindow: true)
                },
                onQuit: { [weak self] in
                    self?.allowTermination = true
                    NSApplication.shared.terminate(nil)
                }
            )
            let hostingController = NSHostingController(rootView: dashboard)
            mainWindow = NSWindow(contentViewController: hostingController)
            mainWindow?.title = AppBrand.name
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
            mainWindow?.setFrameAutosaveName("VordiMainWindow")

            mainWindow?.isReleasedWhenClosed = false
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openFloatingNotesWindow(hideMainWindow: Bool = false) {
        if notesWindow == nil {
            notesWindow = FloatingNotesWindow(store: noteStore)
        }
        if hideMainWindow {
            mainWindow?.orderOut(nil)
        }
        notesWindow?.show()
    }

    private func openFloatingNotesFromCommand(seedText: String?, noteID: String?) {
        let trimmedSeedText = seedText?.trimmingCharacters(in: .whitespacesAndNewlines)

        if
            let noteID,
            let uuid = UUID(uuidString: noteID),
            let note = noteStore.notes.first(where: { $0.id == uuid })
        {
            noteStore.select(note)
        } else if trimmedSeedText?.isEmpty == false {
            noteStore.startDraft()
        }

        if let trimmedSeedText, !trimmedSeedText.isEmpty {
            noteStore.appendTranscriptToActiveNote(trimmedSeedText)
        }
        openFloatingNotesWindow(hideMainWindow: true)
    }
    
    /// Open the main window and present the Settings modal.
    ///
    /// Settings is intentionally a modal overlay, not a dashboard content tab:
    /// the dashboard remains the user's working surface while settings behaves
    /// like a focused configuration panel.
    func openSettings() {
        openMainWindow()
        // Slight delay — NSWindow ordering needs to settle before SwiftUI
        // observes the notification, otherwise the tab switch can race
        // with the window's first render.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NotificationCenter.default.post(
                name: Notification.Name("Vordi.SelectTab"),
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
    /// user to click through the Features page.
    func openOnboardingIfNeeded(force: Bool = false, initialStep: OnboardingStep = .features) {
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
                    OnboardingCoordinator.markFinished()
                    self?.onboardingWindow?.close()
                    self?.onboardingWindow = nil
                    // Feedback surface is now installed from app launch — no longer
                    // need to lazy-init here. installFeedbackSurface is
                    // idempotent so calling again is harmless, but we
                    // do refresh permission state since the user just
                    // walked through the permissions step.
                    self?.installFeedbackSurface()
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
            let onboardingSize = OnboardingView.windowSize

            onboardingWindow = NSWindow(contentViewController: hostingController)
            onboardingWindow?.title = "Welcome to \(AppBrand.name)"
            onboardingWindow?.styleMask = [.titled, .closable]
            onboardingWindow?.contentMinSize = onboardingSize
            onboardingWindow?.contentMaxSize = onboardingSize
            onboardingWindow?.setContentSize(onboardingSize)
            onboardingWindow?.center()
            // Detect a user-initiated close (X / Cmd-W) so we can clear the
            // resume flags — see windowShouldClose(_:). Programmatic close()
            // and app termination do NOT fire that delegate method, so the
            // resume-after-"Quit & Reopen" flow stays intact.
            onboardingWindow?.delegate = self
        }

        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Removed `requestPermissions()` — auto-firing all three system prompts on
    // launch was the ambush pattern that stacked system dialogs on top of the
    // onboarding window. Permission prompts now fire only when the user clicks
    // a specific "Grant" button in the guided cards (Accessibility,
    // InputMonitoring) or implicitly on first microphone use.

    /// Push the current bindings into the listener.
    private func applyHotkeyConfig() {
        let config = hotkeySettings.config
        hotKeyListener?.configure(
            pushToTalk: config.pushToTalk,
            handsFree: config.handsFree,
            exit: config.exitHandsFree
        )
    }

    private func startHotKeyListener() {
        guard let hotKeyListener else { return }
        applyHotkeyConfig()
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
        // If we're already in hands-free mode, this press is the
        // "exit" gesture. Stop the recording and let it transcribe
        // normally — same path as a manual hold-release.
        if handsFreeState == .on {
            exitHandsFree(reason: "Fn pressed")
            return
        }

        // Normal press path — start hold-record.
        guard !isRecording else { return }
        isRecording = true
        startRecording()
    }

    private func handleHotKeyUp() {
        // In hands-free mode, key-up events are no-ops. We exit only
        // on the next key-down or Escape, NOT on release.
        if handsFreeState == .on {
            return
        }

        guard isRecording else { return }
        isRecording = false
        stopRecording()
    }

    private func handleHandsFreeToggle() {
        if handsFreeState == .on {
            exitHandsFree(reason: "Fn+Control pressed")
            return
        }

        print("Fn+Control pressed → entering hands-free mode")
        DebugLog.log("handsFreeToggle: ENTER (isRecording=\(isRecording))")
        handsFreeState = .on
        activeFeedbackSurface()?.setHandsFree()
        AnalyticsClient.shared.track("hands_free_used")
        continuousDictation.start()

        // A push-to-talk capture may already be running: if Fn landed more than
        // the chord-debounce window before Control, push-to-talk started first
        // and left `isRecording == true`. The old `guard !isRecording` bailed
        // here — flipping the UI to hands-free but NEVER starting the continuous
        // engine, so no utterances were ever harvested. Instead, tear that stray
        // recording down (discarding its audio) and start fresh in continuous
        // mode, so entry works regardless of how the chord was pressed.
        if isRecording {
            DebugLog.log("handsFreeToggle: aborting in-flight push-to-talk before continuous start")
            audioRecorder?.abort()
            isRecording = false
        }
        isRecording = true
        startRecording(continuousHandsFree: true)
    }

    /// Escape — used to exit hands-free mode without requiring a second
    /// Fn press. No-op otherwise (the regular Escape key behavior
    /// in other apps is unaffected because HotKeyListener doesn't
    /// consume the event).
    private func handleEscapeKey() {
        guard handsFreeState == .on else { return }
        exitHandsFree(reason: "Escape pressed")
    }

    private func exitHandsFree(reason: String) {
        guard handsFreeState == .on else { return }
        print("\(reason) → exiting hands-free mode")
        handsFreeState = .off
        activeFeedbackSurface()?.setHandsFreeExitedAnimating()
        // Harvest the final in-flight utterance BEFORE tearing the engine down,
        // enqueue it, then drain the queue. The surface returns to idle when the
        // controller reports the queue fully drained (finishHandsFreeSession).
        if isRecording {
            if let wav = audioRecorder?.harvestSegment() {
                let context = ContextProvider.shared.snapshot(hotkey: .primary)
                continuousDictation.enqueue(wav: wav, context: context)
            }
            audioRecorder?.stopContinuous()
            isRecording = false
        }
        // Tear down the on-device live preview and stop feeding it buffers.
        liveSpeechPreview.stop()
        audioRecorder?.onLiveSpeechBuffer = nil
        continuousDictation.beginExit()
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
    
    func startRecording(continuousHandsFree: Bool = false) {
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
                // User previously denied. Give clear audible and visual
                // feedback, then open the privacy pane so they can fix it.
                print("Mic permission denied — opening Privacy pane")
                self.isRecording = false
                self.activeFeedbackSurface()?.setMissingPermissions(self.missingRequiredPermissionNames)
                self.activeFeedbackSurface()?.flashPermissionsWarning(durationSeconds: 5.0)
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
                self.activeFeedbackSurface()?.setMissingPermissions(self.missingRequiredPermissionNames)
                self.activeFeedbackSurface()?.flashPermissionsWarning(durationSeconds: 5.0)
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
            self.showRecordingFeedback()
            if continuousHandsFree {
                // Continuous hands-free transcribes each harvested segment via
                // the deterministic batch path — a single realtime websocket
                // can't commit per-utterance, so we don't open one (and clear
                // any PCM16 hook a prior session left set).
                self.realtimeStream?.close()
                self.realtimeStream = nil
                self.realtimeStreamFailed = false
                self.audioRecorder?.onPCM16Samples = nil
            } else {
                // Spin up realtime streaming BEFORE starting the tap so the
                // PCM16 callback is already set. If the flag is off, skip
                // entirely — we don't want to pay WebSocket connect cost for
                // users who haven't opted in.
                self.setupRealtimeStreamIfEnabled()
            }
            let didStart = self.audioRecorder?.startRecording(continuousHandsFree: continuousHandsFree) ?? false
            if didStart {
                self.permissionService.markMicrophoneOperational()
                self.scheduleContextCapture()
                // On-device live preview: if enabled + authorized for this
                // language, stream local partials into the notch. Works in both
                // push-to-talk and hands-free, on any provider — the pasted text
                // still comes from the API pipeline. Feed tap buffers on main so
                // the recognizer's task lifetime stays single-threaded.
                let previewLanguage = UserDefaults.standard.string(forKey: "language") ?? "hi"
                if UserDefaults.standard.bool(forKey: AppleSpeechLivePreview.enabledKey),
                   self.liveSpeechPreview.canRun(language: previewLanguage) {
                    self.liveSpeechPreview.start(language: previewLanguage)
                    self.audioRecorder?.onLiveSpeechBuffer = { [weak self] buffer in
                        DispatchQueue.main.async { self?.liveSpeechPreview.append(buffer) }
                    }
                } else {
                    self.audioRecorder?.onLiveSpeechBuffer = nil
                }
            } else {
                // Engine failed to start despite granted permission — usually
                // a device contention issue (another app holding the mic).
                // Bail cleanly; the pre-flight already covered the common
                // "no permission" case.
                print("Audio engine failed to start despite granted mic permission")
                self.isRecording = false
                self.hideRecordingFeedback()
                NSSound.beep()
            }
        }
    }

    /// Capture active-app context only after recording feedback and the audio
    /// tap are live. `ContextProvider.snapshot()` may synchronously capture and
    /// JPEG-encode a large window; keeping it ahead of `audioEngine.start()`
    /// caused the reported 0.5–1s dead period after pressing Fn.
    ///
    /// The short delay gives AppKit one render pass to present the recording
    /// state. The feedback surface is non-activating, so the user's source app
    /// and focused selection remain the snapshot target.
    private func scheduleContextCapture() {
        pendingContextSummaryTask?.cancel()
        pendingContextSummaryTask = nil
        pendingContext = nil

        let captureID = UUID()
        pendingContextCaptureID = captureID
        let scheduledAt = CFAbsoluteTimeGetCurrent()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, self.pendingContextCaptureID == captureID else { return }

            let capturedContext = ContextProvider.shared.snapshot(hotkey: .primary)
            guard self.pendingContextCaptureID == captureID else { return }
            self.pendingContext = capturedContext

            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - scheduledAt) * 1_000)
            DebugLog.log("ContextProvider: deferred snapshot READY latencyMs=\(latencyMs)")

            self.pendingContextSummaryTask = Task { [weak self, capturedContext] in
                guard let self, let whisper = self.whisperService else { return }
                let enrichedContext = await whisper.prepareContextSummaryAsync(capturedContext)
                guard !Task.isCancelled, let enrichedContext else { return }
                await MainActor.run { [weak self] in
                    guard
                        let self,
                        self.pendingContextCaptureID == captureID,
                        self.pendingContext?.capturedAt == capturedContext.capturedAt
                    else { return }
                    self.pendingContext = enrichedContext
                }
            }
        }
    }
    
    func stopRecording() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Tear down the on-device live preview (push-to-talk path) and stop
            // feeding it buffers before we tear the engine down.
            self.liveSpeechPreview.stop()
            self.audioRecorder?.onLiveSpeechBuffer = nil
            // Recording stopped, polish/transcription in flight → processing.
            // The floating chip stays in this state until handleResult
            // completes (success or failure), which calls hideRecordingFeedback
            // → setIdle.
            self.activeFeedbackSurface()?.setProcessing()

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

                        self.pendingContext = nil
                        self.pendingContextSummaryTask?.cancel()
                        self.pendingContextSummaryTask = nil
                        self.hideRecordingFeedback()
                        self.activeFeedbackSurface()?.flashNoAudioWarning(durationSeconds: 3.0)
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

                        self.hideRecordingFeedback()
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
                            let context = metadata.context ?? self.pendingContext ?? .empty()
                            session.attachContext(context)
                            self.pendingContext = nil
                            self.pendingContextSummaryTask?.cancel()
                            self.pendingContextSummaryTask = nil

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
                            // PROTOTYPE (Option B): no final text will land, so
                            // pull any live-typed preview back out of the field.
                            self.liveInjection.cancel()
                            // Attach context to failed runs too — these are
                            // where debugging value is highest. We need to
                            // know which app they were dictating to when
                            // it broke.
                            if let ctx = self.pendingContext {
                                session.attachContext(ctx)
                                self.pendingContext = nil
                            }
                            self.pendingContextSummaryTask?.cancel()
                            self.pendingContextSummaryTask = nil
                            print("Transcription error: \(error)")
                            session.fail(reason: Self.shortErrorDescription(error))
                            self.activeFeedbackSurface()?.flashNoOutputWarning(durationSeconds: 4.0)
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
                            // Empty streaming result → the stream gave us nothing
                            // usable. Don't silently drop the dictation: recover
                            // via the batch path on the WAV we already captured,
                            // mirroring the catch branch below.
                            if finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                print("Realtime stream returned empty final — falling back to batch")
                                AnalyticsClient.shared.track("stream_fallback", params: ["cause": "empty"])
                                self.realtimeStreamFailed = true
                                self.whisperService?.transcribeAndPolishWithMetadata(
                                    audioData: audioData,
                                    language: transcriptionLanguage,
                                    style: effectiveStyle,
                                    processingMode: processingMode,
                                    context: self.pendingContext,
                                    summarizeContextIfNeeded: false,
                                    completion: handleResult
                                )
                                return
                            }
                            self.whisperService?.polishOnlyWithMetadata(
                                rawTranscript: finalText,
                                providerLabel: "openai/gpt-4o-mini-transcribe/realtime",
                                transcriptionLatencyMs: streamLatency,
                                style: effectiveStyle,
                                processingMode: processingMode,
                                context: self.pendingContext,
                                summarizeContextIfNeeded: false,
                                completion: handleResult
                            )
                        } catch {
                            // Streaming failed — drop the socket and recover
                            // via the batch path using the WAV we already have.
                            print("Realtime stream failed, falling back to batch: \(error)")
                            AnalyticsClient.shared.track("stream_fallback", params: ["cause": "error"])
                            stream.close()
                            self.realtimeStream = nil
                            self.realtimeStreamFailed = true
                            self.whisperService?.transcribeAndPolishWithMetadata(
                                audioData: audioData,
                                language: transcriptionLanguage,
                                style: effectiveStyle,
                                processingMode: processingMode,
                                context: self.pendingContext,
                                summarizeContextIfNeeded: false,
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
                        context: self.pendingContext,
                        summarizeContextIfNeeded: false,
                        completion: handleResult
                    )
                }
            }
        }
    }

    // MARK: - Retry a stored run

    /// Re-run transcription + polish on a run's stored audio using the user's
    /// CURRENT settings, then copy the fresh transcript to the clipboard and
    /// log a new run. We don't auto-inject: a retry is triggered from the Run
    /// Log, so there's no valid target field to type into — clipboard + a
    /// "copied" flash is the predictable behaviour. Wired from the Run Log's
    /// "Retry transcript" action (previously a dead no-op notification).
    func handleRetryRun(runID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard let run = self.runStore.loadRun(id: runID),
                  let audioURL = self.runStore.audioURL(for: run),
                  let audioData = try? Data(contentsOf: audioURL) else {
                print("Retry: could not load stored audio for run \(runID)")
                self.activeFeedbackSurface()?.flashNoAudioWarning(durationSeconds: 3.0)
                return
            }

            self.activeFeedbackSurface()?.setProcessing()
            let session = self.runRecorder.beginRun()
            session.captureCompleted(audioData: audioData, voicedRange: nil)

            let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
            let outputModeRaw = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.verbatim.rawValue
            let style = TranscriptOutputStyle(rawValue: outputModeRaw) ?? .verbatim
            let processingModeRaw = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
            let processingMode = TranscriptProcessingMode(rawValue: processingModeRaw) ?? .dictation

            self.whisperService?.transcribeAndPolishWithMetadata(
                audioData: audioData,
                language: language,
                style: style,
                processingMode: processingMode,
                context: run.context,
                summarizeContextIfNeeded: false
            ) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.hideRecordingFeedback()
                    switch result {
                    case .success(let metadata):
                        session.transcriptionCompleted(
                            provider: metadata.provider,
                            rawText: metadata.rawText,
                            latencyMs: metadata.transcriptionLatencyMs
                        )
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
                        if let ctx = metadata.context ?? run.context {
                            session.attachContext(ctx)
                        }
                        session.finish()

                        let finalText = metadata.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
                        AnalyticsClient.shared.track("transcript_retried", params: [
                            "status": finalText.isEmpty ? "noSpeech" : "success"
                        ])
                        if finalText.isEmpty {
                            self.activeFeedbackSurface()?.flashNoOutputWarning(durationSeconds: 4.0)
                        } else {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(metadata.finalText, forType: .string)
                            self.activeFeedbackSurface()?.flashTranscriptCopied(durationSeconds: 4.0)
                        }
                    case .failure(let error):
                        // Coarse stage only — never the raw error string (it can
                        // carry endpoints/keys).
                        AnalyticsClient.shared.track("dictation_failed", params: ["stage": "retry"])
                        session.fail(reason: Self.shortErrorDescription(error))
                        self.activeFeedbackSurface()?.flashNoOutputWarning(durationSeconds: 4.0)
                    }
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
            self.persistAndInject(
                text: fallbackFinalText,
                session: session,
                targetBundleIdentifier: context.frontmostBundleID
            )
            return
        }

        // Empty raw transcript → nothing to route. Use polished output
        // (which may also be empty) so the existing hallucination guards
        // continue to work.
        let trimmedRaw = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRaw.isEmpty else {
            self.persistAndInject(
                text: fallbackFinalText,
                session: session,
                targetBundleIdentifier: context.frontmostBundleID
            )
            return
        }

        if mode == .promptEngineer {
            session.attachProfile(
                kind: .promptEngineer,
                trace: ["Transform mode: Prompt Engineer", "Handled by primary post-processing pass"]
            )
            self.persistAndInject(
                text: fallbackFinalText,
                session: session,
                targetBundleIdentifier: context.frontmostBundleID
            )
            return
        }

        let decision = router.route(transcript: trimmedRaw, context: context)
        session.attachProfile(kind: decision.profile.kind, trace: decision.trace)

        // Standard cleanup → use the polish path's output. We DON'T
        // call StandardCleanupProfile.transform() because that would be
        // a second polish round-trip on the same text.
        if decision.profile.kind == .standardCleanup {
            self.persistAndInject(
                text: fallbackFinalText,
                session: session,
                targetBundleIdentifier: context.frontmostBundleID
            )
            return
        }

        // Variable recognition WRAPS standard cleanup. The text was already
        // polished by the primary pass (fallbackFinalText) — running the
        // profile would re-invoke its inner StandardCleanupProfile and polish
        // a SECOND time (2× LLM latency + cost) on every IDE/terminal dictation.
        // Apply only the deterministic var-naming + filename transforms on the
        // already-polished text; no LLM round-trip.
        if decision.profile.kind == .variableRecognition {
            let (vars, _) = VariableRecognitionProfile.applyVariableTransforms(fallbackFinalText)
            let (withFiles, _) = VariableRecognitionProfile.applyFilenameTagging(vars, surface: context.surface)
            session.overrideFinalText(withFiles)
            self.persistAndInject(
                text: withFiles,
                session: session,
                targetBundleIdentifier: context.frontmostBundleID
            )
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
                    session.overrideFinalText(output.finalText)
                    if output.shouldInject {
                        self.persistAndInject(
                            text: output.finalText,
                            session: session,
                            targetBundleIdentifier: context.frontmostBundleID
                        )
                    } else {
                        self.persistWithoutInjection(session: session)
                    }
                case .failure(let err):
                    // Profile failed — fall back to polished text rather
                    // than dropping the dictation on the floor.
                    print("Profile \(decision.profile.kind.rawValue) failed: \(err.localizedDescription) — falling back to polished text")
                    self.persistAndInject(
                        text: fallbackFinalText,
                        session: session,
                        targetBundleIdentifier: context.frontmostBundleID
                    )
                }
            }
        }
    }

    /// Common tail: flush the run to disk + inject text into the focused
    /// app. Called from both the success and profile-failure paths.
    private func persistAndInject(
        text: String,
        session: RunSession,
        targetBundleIdentifier: String? = nil,
        handsFreeChunkOrdinal: Int? = nil,
        injectionResult: ((Bool) -> Void)? = nil
    ) {
        session.finish()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            print("Empty transcript (likely hallucination-filtered); nothing to inject.")
            // PROTOTYPE (Option B): the preview we live-typed has no final text
            // to become — yank it back out so we don't leave a stray fragment.
            liveInjection.cancel()
            // In a continuous hands-free session an empty chunk is normal (a
            // filtered utterance) — don't flash a warning that interrupts the
            // flow; just report "not injected" so spacing stays correct.
            if handsFreeChunkOrdinal == nil {
                activeFeedbackSurface()?.flashNoOutputWarning(durationSeconds: 4.0)
            }
            injectionResult?(false)
            return
        }
        if let ordinal = handsFreeChunkOrdinal {
            // Continuous hands-free chunk: keep the hands-free visual (no
            // setDone), inject with a leading space after the first injected
            // chunk, and bypass the trim/dedup of the normal path.
            self.textInjector?.injectHandsFreeChunk(
                trimmed,
                prependSpace: ordinal > 0,
                targetBundleIdentifier: targetBundleIdentifier
            )
            injectionResult?(true)
            return
        }
        self.activeFeedbackSurface()?.setDone()
        // PROTOTYPE (Option B): if we've been typing partials live into the
        // field, reconcile that preview to the final polished text instead of
        // pasting — a paste on top would duplicate it. finalize() returns false
        // when live-inject wasn't active, so the default paste path is unchanged.
        if !self.liveInjection.finalize(with: trimmed) {
            self.textInjector?.injectText(trimmed, targetBundleIdentifier: targetBundleIdentifier)
        }
        // Anonymous: word count only, never the transcript text itself.
        AnalyticsClient.shared.track("dictation_completed", params: [
            "word_count": trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        ])
        injectionResult?(true)
    }

    private func persistWithoutInjection(session: RunSession) {
        session.finish()
    }

    // MARK: - Continuous hands-free loop

    /// Fired (on main) by AudioRecorder when it detects a ~2s in-utterance pause.
    /// Cut the buffered audio into a segment and queue it for transcribe+inject;
    /// the engine keeps running for the next utterance.
    private func handleUtteranceSilence() {
        guard continuousDictation.isListening else { return }
        guard let wav = audioRecorder?.harvestSegment() else { return }
        // Snapshot context per segment — the user may have switched apps between
        // utterances, and each chunk should land where it was spoken.
        let context = ContextProvider.shared.snapshot(hotkey: .primary)
        continuousDictation.enqueue(wav: wav, context: context)
    }

    /// Transcribe one harvested segment via the batch path and inject it as a
    /// spaced chunk. Reports back whether non-empty text was injected so the
    /// controller can advance the queue and track chunk spacing. Mirrors the
    /// success/failure bookkeeping of the main `stopRecording` pipeline minus the
    /// router (Magic Words / dev-mode profiles don't apply mid-continuous-stream)
    /// and minus the idle-on-done transition (the hands-free visual must persist).
    private func transcribeAndInjectHandsFreeSegment(
        audioData: Data,
        context: ContextSnapshot,
        alreadyInjectedCount: Int,
        completion: @escaping (Bool) -> Void
    ) {
        guard let whisper = self.whisperService else { completion(false); return }
        let session = self.runRecorder.beginRun()
        session.captureCompleted(audioData: audioData, voicedRange: nil)

        let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
        let outputModeRaw = UserDefaults.standard.string(forKey: "output_mode") ?? TranscriptOutputStyle.verbatim.rawValue
        let style = TranscriptOutputStyle(rawValue: outputModeRaw) ?? .verbatim
        let processingModeRaw = UserDefaults.standard.string(forKey: "processing_mode") ?? TranscriptProcessingMode.dictation.rawValue
        let mode = TranscriptProcessingMode(rawValue: processingModeRaw) ?? .dictation

        whisper.transcribeAndPolishWithMetadata(
            audioData: audioData,
            language: language,
            style: style,
            processingMode: mode,
            context: context,
            summarizeContextIfNeeded: false
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { completion(false); return }
                switch result {
                case .success(let metadata):
                    session.transcriptionCompleted(
                        provider: metadata.provider,
                        rawText: metadata.rawText,
                        latencyMs: metadata.transcriptionLatencyMs
                    )
                    if let postMode = metadata.postProcessMode {
                        session.postProcessCompleted(
                            mode: postMode,
                            style: metadata.postProcessStyle ?? "unknown",
                            model: metadata.postProcessModel ?? "none",
                            prompt: metadata.postProcessPrompt ?? "",
                            finalText: metadata.finalText,
                            latencyMs: metadata.postProcessLatencyMs,
                            languageGuardTriggered: metadata.languageGuardTriggered
                        )
                    }
                    session.attachContext(context)

                    // Hands-free voice command: if the utterance is addressed to
                    // Verba ("Verba, open Claude"), carry out the action instead of
                    // typing the words. The wake phrase is what separates a command
                    // from ordinary dictation. We check the raw transcript (closest
                    // to what was spoken) and fall back to the polished text.
                    let commandSource = metadata.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? metadata.finalText
                        : metadata.rawText
                    switch VoiceCommandRouter.interpret(commandSource) {
                    case .executed(let confirmation):
                        session.finish()  // persist the run; we handled it, nothing to inject
                        print("🎙️ Voice command: \(confirmation)")
                        completion(false) // no text injected → keeps chunk spacing correct
                        return
                    case .failed(let reason):
                        session.finish()
                        print("🎙️ Voice command not run: \(reason)")
                        completion(false)
                        return
                    case .notACommand:
                        break  // fall through to normal dictation
                    }

                    self.persistAndInject(
                        text: metadata.finalText,
                        session: session,
                        targetBundleIdentifier: context.frontmostBundleID,
                        handsFreeChunkOrdinal: alreadyInjectedCount,
                        injectionResult: completion
                    )
                case .failure(let error):
                    session.attachContext(context)
                    print("Hands-free segment transcription error: \(error)")
                    session.fail(reason: Self.shortErrorDescription(error))
                    completion(false)
                }
            }
        }
    }

    /// Called once the queue has fully drained after the user exited hands-free.
    /// Return the recording surface to idle.
    private func finishHandsFreeSession() {
        hideRecordingFeedback()
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
        activeFeedbackSurface()?.setLiveTranscript("")

        guard UserDefaults.standard.bool(forKey: Self.realtimeStreamingKey) else { return }

        // Force the BATCH path for the Romanized style. The OpenAI Realtime
        // API is less consistent on multilingual audio than the batch endpoint
        // — for ambiguous Hindi/Urdu/Marathi speech it occasionally produces
        // non-Latin script output that breaks the bilingual normalizer.
        // The batch path with whisper-large-v3 auto-detect is more reliable.
        let outputModeRaw = UserDefaults.standard.string(forKey: "output_mode") ?? ""
        if outputModeRaw == TranscriptOutputStyle.cleanHinglish.rawValue {
            print("Realtime stream disabled for Romanized style — using batch path for multilingual reliability")
            return
        }

        // Realtime streaming is OPENAI-ONLY. Groq does NOT expose a realtime
        // transcription WebSocket — there is no wss://api.groq.com/.../realtime
        // endpoint, only the REST batch endpoint. The earlier code (and its
        // comments) wrongly claimed Groq spoke the same Realtime protocol, so
        // every Groq recording opened a dead socket and ran a useless PCM pump
        // before falling back to batch. Groq batch (whisper-large-v3-turbo) is
        // already sub-second, so for Groq we skip streaming and let the fast
        // batch path run.
        guard TranscriptionProvider.current == .openai else { return }
        let apiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        guard !apiKey.isEmpty else { return }

        let language = UserDefaults.standard.string(forKey: "language") ?? "hi"
        let normalizedLanguage = language == "auto" ? "" : language

        // Bias the streaming decoder with the SAME vocabulary + style prompt the
        // batch path uses, so streaming (the default-on path) no longer produces
        // lower-quality proper nouns than batch. `prompt` is supported on
        // gpt-4o-mini-transcribe (the OpenAI realtime model).
        let config: RealtimeTranscriptionService.Configuration = .openAI(
            apiKey: apiKey,
            language: normalizedLanguage,
            prompt: WhisperService.sttPromptForRealtime
        )
        let stream = RealtimeTranscriptionService(config: config)
        realtimeStream = stream
        realtimeStreamStart = CFAbsoluteTimeGetCurrent()

        // PROTOTYPE (Option B): if live-inject is on, start a live session so
        // partials type straight into the focused app (finalize/cancel happen on
        // the stop path). Default OFF — see LiveInjectionController.
        let liveInjectActive = liveInjection.isEnabled
        if liveInjectActive { liveInjection.begin() }

        stream.onPartial = { [weak self] text in
            DispatchQueue.main.async {
                self?.activeFeedbackSurface()?.setLiveTranscript(text)
                if liveInjectActive { self?.liveInjection.update(to: text) }
            }
        }

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

    /// Recording-state UI lives in the notch pill. Focus check happens
    /// upstream in `startRecording`; by the time this runs, we've already
    /// gated and confirmed a text input exists.
    let focusDetector = FocusDetector()

    private func showRecordingFeedback() {
        // Hands-free mode owns the chip state — `setHandsFree()` was
        // already called when entering the mode, and the recording-state
        // visual should persist until the user explicitly exits. The
        // standard "setRecording" call would overwrite that.
        if handsFreeState == .on {
            activeFeedbackSurface()?.setHandsFree()
        } else {
            activeFeedbackSurface()?.setRecording()
        }
        let surface = activeFeedbackSurface()
        audioRecorder?.onAmplitude = { [weak surface] level in
            surface?.updateAudioLevel(level)
        }
    }

    private func hideRecordingFeedback() {
        audioRecorder?.onAmplitude = nil
        activeFeedbackSurface()?.setLiveTranscript("")
        // Pipeline complete → back to idle. setProcessing() is called
        // separately at the moment fn is released (stopRecording).
        // If hands-free mode is still on we'd be ending it incorrectly
        // — but by the time hideRecordingFeedback runs, handsFreeState
        // has already been flipped to .off by handleHotKeyDown /
        // handleEscapeKey, so this is safe.
        activeFeedbackSurface()?.setIdle()
    }
}
