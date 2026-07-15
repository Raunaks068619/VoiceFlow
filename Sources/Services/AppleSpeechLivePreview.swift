import Foundation
import Speech
import AVFoundation

/// On-device live preview via Apple's `SFSpeechRecognizer`.
///
/// Purpose: drive the **notch live-transcript UI** with instant, provider-independent
/// partial results, while the *authoritative* transcript still comes from our
/// pipeline (Groq/OpenAI) and pastes into the focused app. This is the
/// "show me words as I speak, like macOS dictation" experience, decoupled from
/// the cloud pipeline:
///   - Apple STT → live preview in the notch (fast, offline, works on any provider).
///   - Our API   → final text pasted into the field (accurate, multilingual).
///
/// Why this exists (vs. the OpenAI realtime stream): realtime streaming only works
/// on OpenAI. On the free Groq tier there is no realtime endpoint, so there were no
/// live partials at all. Apple's recognizer runs locally and needs no provider, so
/// the live preview works everywhere — including hands-free, where we deliberately
/// don't open a realtime socket.
///
/// Privacy: prefers on-device recognition (`requiresOnDeviceRecognition` is set to
/// whatever the locale supports). For locales with on-device models, audio never
/// leaves the Mac — matching Vordi's local-first stance. Locales without an
/// on-device model fall back to Apple's server recognition for the *preview only*;
/// the authoritative transcript path is unaffected.
///
/// Threading: everything below runs on the main thread. The recognition callback
/// hops to main before mutating state or firing `onPartial`, and `append(_:)` is
/// expected to be called on main too (the wiring dispatches tap buffers onto main),
/// so task/request lifetime is race-free without locking on the audio thread.
final class AppleSpeechLivePreview {

    /// UserDefaults flag. Default OFF — opt-in, and enabling it triggers the
    /// Speech Recognition permission prompt.
    static let enabledKey = "on_device_preview_enabled"

    /// Fires with the cumulative best transcript as recognition progresses.
    var onPartial: ((String) -> Void)?

    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private(set) var isRunning = false

    // MARK: - Authorization

    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
    }

    /// Request Speech Recognition access (a TCC permission distinct from mic).
    /// Completion is delivered on the main thread.
    static func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async { completion(status == .authorized) }
        }
    }

    // MARK: - Lifecycle

    /// Whether a preview could run right now for the given dictation language.
    func canRun(language: String?) -> Bool {
        guard Self.isAuthorized else { return false }
        guard let rec = Self.makeRecognizer(language: language), rec.isAvailable else { return false }
        return true
    }

    /// Begin a live session for the given dictation language (e.g. "hi", "en",
    /// "auto"). No-op if unauthorized or the locale has no recognizer.
    func start(language: String?) {
        guard !isRunning, Self.isAuthorized else { return }
        guard let rec = Self.makeRecognizer(language: language), rec.isAvailable else { return }
        recognizer = rec
        isRunning = true
        startTask()
    }

    /// Feed one captured audio buffer. Call on the main thread. Cheap no-op when
    /// not running.
    func append(_ buffer: AVAudioPCMBuffer) {
        guard isRunning else { return }
        request?.append(buffer)
    }

    /// Stop the live session and tear everything down. Idempotent.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        recognizer = nil
    }

    // MARK: - Internal

    private func startTask() {
        guard isRunning, let recognizer else { return }
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        // Prefer on-device when the locale supports it (private, offline); allow
        // Apple's server recognition otherwise so the preview still works.
        req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request = req

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // Callback lands on an arbitrary queue — hop to main so all
            // task/request mutation happens on one thread.
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                if let result {
                    self.onPartial?(result.bestTranscription.formattedString)
                }
                // A single SFSpeech task is capped (~1 min) and finalizes on a
                // long silence. For long hands-free sessions, transparently spin
                // up a fresh task so the preview keeps flowing. The transcript
                // resets per task, which is fine for a rolling preview.
                if (result?.isFinal ?? false) || error != nil {
                    self.request?.endAudio()
                    self.task = nil
                    self.request = nil
                    self.startTask()
                }
            }
        }
    }

    /// Build a recognizer for the dictation language. Maps our short codes to full
    /// locales; falls back to the system-locale recognizer.
    private static func makeRecognizer(language: String?) -> SFSpeechRecognizer? {
        guard let language, !language.isEmpty, language.lowercased() != "auto" else {
            return SFSpeechRecognizer()
        }
        let mapped = localeIdentifier(for: language)
        return SFSpeechRecognizer(locale: Locale(identifier: mapped)) ?? SFSpeechRecognizer()
    }

    private static func localeIdentifier(for language: String) -> String {
        // If a region is already present ("en-US", "hi_IN"), normalize and use it.
        if language.contains("-") || language.contains("_") {
            return language.replacingOccurrences(of: "_", with: "-")
        }
        switch language.lowercased() {
        case "en": return "en-US"
        case "hi": return "hi-IN"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "pt": return "pt-BR"
        case "it": return "it-IT"
        case "ja": return "ja-JP"
        case "zh": return "zh-CN"
        default:   return language
        }
    }
}
