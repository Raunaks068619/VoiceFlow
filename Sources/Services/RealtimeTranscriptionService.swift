import Foundation

/// Streaming transcription over OpenAI's Realtime API.
///
/// Why this exists (alongside the file-based `WhisperService`):
///   - Perceived latency. Batch mode waits for Fn-release → upload → decode.
///     Streaming starts producing partial transcripts *while* the user is
///     still speaking, so the final commit after Fn-release only needs to
///     flush the last few hundred ms instead of the whole clip.
///   - Long dictations. File upload over cellular tethering for a 60s clip
///     is several seconds; streaming keeps the pipe warm and TX-bound.
///
/// Protocol shape (OpenAI Realtime, transcription intent):
///   - Connect wss://api.openai.com/v1/realtime?intent=transcription
///   - Send `transcription_session.update` with model + language + turn detection=null
///   - Stream `input_audio_buffer.append` events carrying base64 PCM16 @ 24 kHz
///   - On stop, send `input_audio_buffer.commit`
///   - Server emits `conversation.item.input_audio_transcription.delta` (partial)
///     and `...completed` (final).
///
/// Failure model: any error (connect fail, auth fail, mid-stream disconnect)
/// surfaces via the `onError` hook. Caller is expected to fall back to the
/// batch WhisperService path when streaming fails — we do NOT auto-retry,
/// because the caller has the raw WAV in hand and can just re-transcribe.
///
/// State machine: idle → connecting → streaming → committed → done/failed.
/// Any terminal transition invalidates the service; create a new instance
/// per recording session.
///
/// Concurrency: the class is NOT actor-isolated. All callers are expected
/// to drive it from the main thread (AppDelegate already dispatches onto
/// main before touching it). Internal receive-loop Tasks hop onto
/// MainActor explicitly before mutating state, so there's no data race in
/// practice even though Swift's type system doesn't enforce it.
final class RealtimeTranscriptionService: NSObject {

    // MARK: - Types

    struct Configuration {
        /// e.g. "wss://api.openai.com/v1/realtime"
        var baseURL: URL
        var apiKey: String
        /// Transcription model. Default matches our batch path.
        var model: String
        /// ISO 639-1 code or "auto". Whisper-style language hint.
        var language: String

        static func openAI(apiKey: String, language: String) -> Configuration {
            Configuration(
                baseURL: URL(string: "wss://api.openai.com/v1/realtime?intent=transcription")!,
                apiKey: apiKey,
                model: "gpt-4o-mini-transcribe",
                language: language
            )
        }
    }

    enum State: String {
        case idle
        case connecting
        case streaming
        case committed
        case done
        case failed
    }

    enum StreamError: Error, LocalizedError {
        case notConnected
        case server(String)
        case decoding(String)
        case transport(Error)
        case missingFinal

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Realtime session is not connected."
            case .server(let m): return "OpenAI Realtime error: \(m)"
            case .decoding(let m): return "Could not decode event: \(m)"
            case .transport(let e): return "Transport error: \(e.localizedDescription)"
            case .missingFinal: return "Stream closed without a final transcript."
            }
        }
    }

    // MARK: - Public API

    /// Partial-transcript callback. Fires on every delta. String is cumulative
    /// — caller should replace-not-append. Empty string means "reset".
    var onPartial: ((String) -> Void)?
    /// Terminal error callback. Called at most once.
    var onError: ((StreamError) -> Void)?
    /// State-change notification, purely for UI (e.g. "Connecting…" indicator).
    var onStateChange: ((State) -> Void)?

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }

    // MARK: - Internal

    private let config: Configuration
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?

    /// Accumulated transcript as the server sends us deltas. We also surface
    /// the `...completed` event which carries the final (possibly cleaned-up)
    /// text — use that for the commit result and ignore trailing deltas.
    private var accumulatedTranscript: String = ""
    private var finalTranscript: String?
    private var commitContinuation: CheckedContinuation<String, Error>?

    init(config: Configuration) {
        self.config = config
        super.init()
    }

    /// Open the WebSocket and send the session-configure event. Returns when
    /// the server acks `transcription_session.updated`.
    func connect() async throws {
        guard state == .idle else { return }
        state = .connecting

        var req = URLRequest(url: config.baseURL)
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        // Realtime beta header — required as of 2024-2026 window.
        req.setValue("realtime=v1", forHTTPHeaderField: "OpenAI-Beta")

        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 15
        let s = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
        self.session = s

        let t = s.webSocketTask(with: req)
        self.task = t
        t.resume()

        // Kick receive loop before sending anything; otherwise early
        // server errors can race the send and get dropped.
        startReceiveLoop()

        try await sendSessionUpdate()
        state = .streaming
    }

    /// Stream a chunk of 16-bit PCM mono audio at 24 kHz.
    /// Chunk size is flexible (recommended 40-100ms ≈ 1920-4800 samples).
    func appendPCM16(_ data: Data) {
        guard state == .streaming, let task else { return }
        let base64 = data.base64EncodedString()
        let payload: [String: Any] = [
            "type": "input_audio_buffer.append",
            "audio": base64
        ]
        sendJSON(payload, via: task)
    }

    /// Flush audio buffer, tell server to finalize, and await the `...completed`
    /// event. Returns the final transcript string.
    func commitAndAwaitFinal() async throws -> String {
        guard state == .streaming, let task else {
            throw StreamError.notConnected
        }
        let commit: [String: Any] = ["type": "input_audio_buffer.commit"]
        sendJSON(commit, via: task)
        state = .committed

        return try await withCheckedThrowingContinuation { cont in
            self.commitContinuation = cont
        }
    }

    /// Close the socket and mark the session terminal. Idempotent.
    func close() {
        guard state != .done && state != .failed else { return }
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
        // If a commit was pending, fail it now.
        if let cont = commitContinuation {
            commitContinuation = nil
            cont.resume(throwing: StreamError.missingFinal)
        }
        state = .done
    }

    // MARK: - Session setup

    private func sendSessionUpdate() async throws {
        guard let task else { throw StreamError.notConnected }
        // turn_detection: null → we control commit boundaries explicitly.
        let session: [String: Any] = [
            "type": "transcription_session.update",
            "session": [
                "input_audio_format": "pcm16",
                "input_audio_transcription": [
                    "model": config.model,
                    "language": config.language
                ],
                "turn_detection": NSNull()
            ]
        ]
        sendJSON(session, via: task)
    }

    // MARK: - Transport helpers

    private func sendJSON(_ dict: [String: Any], via task: URLSessionWebSocketTask) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return
        }
        task.send(.string(str)) { [weak self] err in
            if let err {
                Task { @MainActor [weak self] in
                    self?.fail(with: .transport(err))
                }
            }
        }
    }

    private func startReceiveLoop() {
        guard let task else { return }
        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handle(message: message)
                    // Continue looping unless we've gone terminal.
                    if self.state != .done && self.state != .failed {
                        self.startReceiveLoop()
                    }
                case .failure(let error):
                    self.fail(with: .transport(error))
                }
            }
        }
    }

    private func handle(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            handleTextEvent(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                handleTextEvent(text)
            }
        @unknown default:
            break
        }
    }

    private func handleTextEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        switch type {
        case "conversation.item.input_audio_transcription.delta":
            if let delta = json["delta"] as? String {
                accumulatedTranscript += delta
                onPartial?(accumulatedTranscript)
            }

        case "conversation.item.input_audio_transcription.completed":
            // Final transcript. Server sends the cleaned version here, not
            // necessarily the delta accumulation — prefer it.
            let transcript = (json["transcript"] as? String) ?? accumulatedTranscript
            finalTranscript = transcript
            if let cont = commitContinuation {
                commitContinuation = nil
                cont.resume(returning: transcript)
            }

        case "error":
            let msg: String = {
                if let err = json["error"] as? [String: Any],
                   let m = err["message"] as? String { return m }
                return "Unknown error"
            }()
            fail(with: .server(msg))

        case "transcription_session.updated":
            // Session ack — nothing to do, session is live.
            break

        case "input_audio_buffer.committed":
            // Commit ack — server has accepted the flush. Now waiting for completed.
            break

        default:
            // Ignore unrelated events (rate_limits.updated, etc).
            break
        }
    }

    private func fail(with error: StreamError) {
        guard state != .failed && state != .done else { return }
        state = .failed
        onError?(error)
        if let cont = commitContinuation {
            commitContinuation = nil
            cont.resume(throwing: error)
        }
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }
}
