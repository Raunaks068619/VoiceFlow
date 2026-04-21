import Foundation

/// Accumulates data from each pipeline stage during a single dictation run,
/// then flushes a completed `Run` to RunStore.
///
/// Usage from AppDelegate:
/// ```
/// let recorder = runRecorder.beginRun()
/// recorder.captureCompleted(audioData: data, voicedRange: "12...148 of 200")
/// recorder.transcriptionCompleted(provider: "groq/whisper-large-v3-turbo", rawText: text, latencyMs: 340)
/// recorder.postProcessCompleted(...)
/// recorder.finish()   // writes to RunStore
/// ```
///
/// If the pipeline fails at any stage, call `recorder.fail()` to persist
/// a partial run with error status — these are where debugging value is highest.
final class RunRecorder {
    private let store: RunStore

    init(store: RunStore = .shared) {
        self.store = store
    }

    func beginRun() -> RunSession {
        RunSession(store: store)
    }
}

final class RunSession {
    let id = UUID()
    private let startTime = Date()
    private let store: RunStore

    // Accumulated stage data
    private var audioData: Data?
    private var audioSizeBytes: Int = 0
    private var voicedRange: String?

    private var transcriptionProvider: String?
    private var rawText: String?
    private var transcriptionLatencyMs: Int = 0

    private var postProcessMode: String?
    private var postProcessStyle: String?
    private var postProcessModel: String?
    private var postProcessPrompt: String?
    private var finalText: String?
    private var postProcessLatencyMs: Int = 0
    private var languageGuardTriggered: Bool = false

    init(store: RunStore) {
        self.store = store
    }

    // MARK: - Stage callbacks

    func captureCompleted(audioData: Data, voicedRange: String?) {
        self.audioData = audioData
        self.audioSizeBytes = audioData.count
        self.voicedRange = voicedRange
    }

    func transcriptionCompleted(provider: String, rawText: String, latencyMs: Int) {
        self.transcriptionProvider = provider
        self.rawText = rawText
        self.transcriptionLatencyMs = latencyMs
    }

    func postProcessCompleted(
        mode: String,
        style: String,
        model: String,
        prompt: String,
        finalText: String,
        latencyMs: Int,
        languageGuardTriggered: Bool = false
    ) {
        self.postProcessMode = mode
        self.postProcessStyle = style
        self.postProcessModel = model
        self.postProcessPrompt = prompt
        self.finalText = finalText
        self.postProcessLatencyMs = latencyMs
        self.languageGuardTriggered = languageGuardTriggered
    }

    /// Flush a successful run to disk.
    func finish() {
        let duration = Date().timeIntervalSince(startTime)
        let hasFinal = !(finalText ?? rawText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let status: RunStatus = hasFinal ? .success : .noSpeech

        let capture = CaptureStage(
            audioFilename: "audio.wav",
            audioSizeBytes: audioSizeBytes,
            voicedBufferRange: voicedRange
        )

        let transcription: TranscriptionStage? = rawText.map {
            TranscriptionStage(
                provider: transcriptionProvider ?? "unknown",
                rawText: $0,
                latencyMs: transcriptionLatencyMs
            )
        }

        let postProcessing: PostProcessingStage? = postProcessMode.map {
            PostProcessingStage(
                mode: $0,
                style: postProcessStyle ?? "unknown",
                model: postProcessModel ?? "unknown",
                prompt: postProcessPrompt ?? "",
                finalText: finalText ?? "",
                latencyMs: postProcessLatencyMs,
                droppedLanguageGuardTriggered: languageGuardTriggered
            )
        }

        let run = Run(
            id: id,
            createdAt: startTime,
            durationSeconds: duration,
            status: status,
            capture: capture,
            transcription: transcription,
            postProcessing: postProcessing,
            errorMessage: nil
        )

        if let audioData = audioData {
            store.save(run: run, audioData: audioData)
        }
    }

    /// Flush a failed run (pipeline error at any stage).
    ///
    /// `reason` is shown in the Run Log row so a failed dictation tells the
    /// user *why* — "401 Unauthorized", "LM Studio unreachable" — instead of
    /// the misleading "(no transcript)". Keep it short; the detail view can
    /// show the full stack.
    func fail(reason: String? = nil) {
        let duration = Date().timeIntervalSince(startTime)

        let capture = CaptureStage(
            audioFilename: "audio.wav",
            audioSizeBytes: audioSizeBytes,
            voicedBufferRange: voicedRange
        )

        let transcription: TranscriptionStage? = rawText.map {
            TranscriptionStage(
                provider: transcriptionProvider ?? "unknown",
                rawText: $0,
                latencyMs: transcriptionLatencyMs
            )
        }

        let run = Run(
            id: id,
            createdAt: startTime,
            durationSeconds: duration,
            status: .failed,
            capture: capture,
            transcription: transcription,
            postProcessing: nil,
            errorMessage: reason
        )

        if let audioData = audioData {
            store.save(run: run, audioData: audioData)
        }
    }
}
