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
        // durationSeconds == AUDIO duration (how long the user spoke), not
        // pipeline wall-clock. Previously this was `Date() - beginRun()`,
        // which measured "time from Fn-release to polish-complete" — a
        // tiny number (~1s) that has nothing to do with how much audio
        // was captured. Users opening the run log saw the header showing
        // 0:01 next to a 26-second recording and thought their audio was
        // truncated.
        //
        // We derive duration from the WAV header bytes rather than tracking
        // it in AudioRecorder so that any path that produces a WAV (current
        // batch path, future re-import / replay flows) gets correct duration
        // for free. Per-stage latencies live in their own fields already
        // (transcription.latencyMs, postProcessing.latencyMs) — that's where
        // pipeline timing belongs.
        let duration = Self.audioDuration(fromWAV: audioData) ?? Date().timeIntervalSince(startTime)
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

    /// Parse the audio duration from a PCM WAV blob in seconds.
    ///
    /// Returns nil for malformed input — caller falls back to wall-clock.
    /// We tolerate non-canonical layouts (e.g. extra chunks before "data")
    /// by scanning for the "data" chunk marker rather than assuming offset 36.
    ///
    /// Why parse instead of using AVAudioFile: AVAudioFile would force us to
    /// write the bytes to a temp file just to read its duration, which costs
    /// disk I/O on every run. The WAV header is 44 bytes — parsing it is
    /// cheaper than the syscall to write the temp.
    static func audioDuration(fromWAV data: Data?) -> TimeInterval? {
        guard let data, data.count >= 44 else { return nil }
        // Verify "RIFF" + "WAVE" magic so we don't misread an unrelated blob.
        guard data.starts(with: Data([0x52, 0x49, 0x46, 0x46])) else { return nil }
        let waveMarker = data.subdata(in: 8..<12)
        guard waveMarker == Data([0x57, 0x41, 0x56, 0x45]) else { return nil }

        // fmt chunk: bytes 22-23 channels, 24-27 sample rate, 34-35 bits/sample.
        let channels = data.readUInt16LE(at: 22)
        let sampleRate = data.readUInt32LE(at: 24)
        let bitsPerSample = data.readUInt16LE(at: 34)
        guard channels > 0, sampleRate > 0, bitsPerSample > 0 else { return nil }

        // Find the "data" chunk — usually at offset 36 but we scan to be safe.
        let dataMarker: [UInt8] = [0x64, 0x61, 0x74, 0x61] // "data"
        var idx = 36
        while idx + 8 <= data.count {
            let chunkID = Array(data.subdata(in: idx..<idx+4))
            let chunkSize = data.readUInt32LE(at: idx + 4)
            if chunkID == dataMarker {
                let bytesPerSample = Int(bitsPerSample) / 8
                let totalSamples = Int(chunkSize) / (Int(channels) * bytesPerSample)
                return TimeInterval(totalSamples) / TimeInterval(sampleRate)
            }
            idx += 8 + Int(chunkSize)
        }
        return nil
    }
}

private extension Data {
    func readUInt16LE(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
