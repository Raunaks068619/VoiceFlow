import Foundation

enum TranscriptOutputStyle: String {
    case verbatim = "verbatim"
    case clean = "clean"
    case cleanHinglish = "clean_hinglish"
    /// Translate any spoken language to natural English.
    /// STT runs normally; the polish LLM does the actual translation step,
    /// so we keep our fast STT model and reuse the existing post-processing
    /// pipeline (no second STT path, no Whisper /translations endpoint).
    case translateEnglish = "translate_english"
}

enum TranscriptProcessingMode: String {
    case dictation = "dictation"
    case rewrite = "rewrite"
    case promptEngineer = "prompt_engineer"
}

enum VordiAIModels {
    static let transcriptionDefault = "gpt-4o-mini-transcribe"
    static let transcriptionBenchmark = "gpt-4o-transcribe"
    static let cleanup = "openai/gpt-oss-20b"
    static let screenshotSummary = "qwen/qwen3.6-27b"
}

enum PolishRule: String, CaseIterable, Identifiable {
    case makeConcise = "make_concise"
    case rewordForClarity = "reword_for_clarity"
    case reorderForReadability = "reorder_for_readability"
    case addStructureForReadability = "add_structure_for_readability"
    case maintainTone = "maintain_tone"

    var id: String { rawValue }

    private static let userDefaultsPrefix = "polish_rule_"

    var userDefaultsKey: String {
        Self.userDefaultsPrefix + rawValue
    }

    var title: String {
        switch self {
        case .makeConcise: return "Make more concise"
        case .rewordForClarity: return "Reword for clarity"
        case .reorderForReadability: return "Reorder for readability"
        case .addStructureForReadability: return "Add structure for readability"
        case .maintainTone: return "Maintain your tone"
        }
    }

    var description: String {
        switch self {
        case .makeConcise:
            return "Remove filler and repetition without cutting meaning."
        case .rewordForClarity:
            return "Fix grammar and make rough phrases easier to read."
        case .reorderForReadability:
            return "Move ideas into a clearer order when the intent is obvious."
        case .addStructureForReadability:
            return "Use line breaks, bullets, and numbered lists when helpful."
        case .maintainTone:
            return "Keep the output in your voice instead of sounding generic."
        }
    }

    var instruction: String {
        switch self {
        case .makeConcise:
            return "Make the transcript more concise by removing obvious filler, repetition, and false starts while preserving meaning."
        case .rewordForClarity:
            return "Reword awkward phrases for clarity, grammar, and natural punctuation without answering the transcript."
        case .reorderForReadability:
            return "When the speaker jumps between related ideas, reorder sentences only enough to make the note readable. Do not add new ideas."
        case .addStructureForReadability:
            return PolishFormattingPolicy.structureInstruction(isEnabled: true)
        case .maintainTone:
            return "Maintain the user's tone and domain vocabulary. Keep casual wording casual and technical wording technical."
        }
    }

    static func isEnabled(_ rule: PolishRule) -> Bool {
        guard UserDefaults.standard.object(forKey: rule.userDefaultsKey) != nil else {
            return true
        }
        return UserDefaults.standard.bool(forKey: rule.userDefaultsKey)
    }

    static func set(_ rule: PolishRule, isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: rule.userDefaultsKey)
    }

    static var enabledInstructions: [String] {
        allCases
            .filter { isEnabled($0) }
            .map(\.instruction)
    }
}

/// Transcription backend. Both providers support multilingual transcription
/// (Hindi, Marathi, English, and 100+ languages) via Whisper. OpenAI uses
/// gpt-4o-mini-transcribe for higher polish quality; Groq uses whisper-large-v3
/// on the multilingual path and is free with an embedded key.
enum TranscriptionProvider: String {
    case openai
    case groq

    static var current: TranscriptionProvider {
        let raw = UserDefaults.standard.string(forKey: "transcription_provider") ?? TranscriptionProvider.groq.rawValue
        return TranscriptionProvider(rawValue: raw) ?? .groq
    }
}

/// Polish backend — the LLM used for the post-STT cleanup step. This is a
/// separate axis from the transcription provider because:
///   - STT uses Whisper on both providers; both support multilingual.
///   - Polish is pure text → text. It can run on any OpenAI-compatible
///     endpoint (OpenAI cloud, LM Studio, Ollama).
///
/// Stored in UserDefaults as `polish_backend_id` using the format
/// "<kind>::<model>", e.g. "openai::gpt-4.1-mini", "lmstudio::qwen/qwen3.5-9b".
/// The "::" separator lets us pack both fields into a single picker selection
/// string in Settings — cleaner SwiftUI binding than two coupled defaults.
enum PolishBackend {
    case openai(model: String)
    case groq(model: String)
    case local(provider: LocalProvider, model: String)

    static let userDefaultsKey = "polish_backend_id"
    static let groqCleanupModel = VordiAIModels.cleanup
    static let groqScreenshotSummaryModel = VordiAIModels.screenshotSummary
    static let legacyGroqModelIds: Set<String> = [
        "groq::llama-3.3-70b-versatile",
        "groq::llama-3.1-8b-instant",
        "groq::meta-llama/llama-4-scout-17b-16e-instruct"
    ]
    /// Default polish for the bring-your-own-OpenAI-key path.
    static let defaultIdOpenAI = "openai::gpt-4.1-mini"
    /// Fast, low-cost cleanup model on Groq.
    static let defaultIdGroq = "groq::\(groqCleanupModel)"
    /// Convenience for "what's the right default given the user's key state."
    /// Settings UI also calls this when it detects key changes.
    static var defaultId: String {
        defaultIdGroq
    }

    static var current: PolishBackend {
        let id = UserDefaults.standard.string(forKey: userDefaultsKey) ?? defaultId
        return parse(id: id)
    }

    static func parse(id: String) -> PolishBackend {
        let parts = id.components(separatedBy: "::")
        guard parts.count == 2, !parts[1].isEmpty else {
            return .groq(model: groqCleanupModel)
        }
        let (kind, model) = (parts[0], parts[1])
        switch kind {
        case "lmstudio": return .local(provider: .lmstudio, model: model)
        case "ollama":   return .local(provider: .ollama,   model: model)
        case "groq":     return .groq(model: model)
        default:         return .openai(model: model)
        }
    }

    var id: String {
        switch self {
        case .openai(let m): return "openai::\(m)"
        case .groq(let m):   return "groq::\(m)"
        case .local(let p, let m): return "\(p.rawValue)::\(m)"
        }
    }

    var chatCompletionsURL: URL {
        switch self {
        case .openai:
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .groq:
            // OpenAI-compatible chat completions endpoint on Groq's host.
            return URL(string: "https://api.groq.com/openai/v1/chat/completions")!
        case .local(let provider, _):
            return provider.baseURL.appendingPathComponent("chat/completions")
        }
    }

    var modelName: String {
        switch self {
        case .openai(let m), .groq(let m), .local(_, let m): return m
        }
    }

    /// Display label for debug/logging purposes. Not used in UI (UI has its own).
    var displayLabel: String {
        switch self {
        case .openai(let m): return "openai/\(m)"
        case .groq(let m):   return "groq/\(m)"
        case .local(let p, let m): return "\(p.rawValue)/\(m)"
        }
    }

    /// API key lookup — cloud backends need one, local backends don't.
    /// Groq path falls back to the embedded beta key for users who haven't
    /// added their own; that's the whole point of the free tier.
    ///
    /// **Always trim the value before returning**. Pasting an API key is the
    /// #1 failure mode — copying from a dashboard often picks up trailing
    /// newlines or leading whitespace, which OpenAI rejects with "Incorrect
    /// API key" even though the key itself is valid. We trim defensively so
    /// the user doesn't have to know to do it.
    func apiKey() -> String {
        switch self {
        case .openai:
            let raw = UserDefaults.standard.string(forKey: "openai_api_key")
                ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
                ?? ""
            return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        case .groq:
            let userKey = (UserDefaults.standard.string(forKey: "groq_api_key") ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return userKey.isEmpty ? EmbeddedKeys.groq : userKey
        case .local:
            // LM Studio / Ollama accept any string (or none) for auth. Sending
            // a placeholder keeps the Authorization header shape consistent
            // with the cloud path.
            return "local"
        }
    }

    var requiresAPIKey: Bool {
        if case .local = self { return false }
        return true
    }
}

/// Embedded API keys for the free-tier beta. The Groq key ships with the
/// binary so users get fast English dictation out of the box.
///
/// SECURITY: this constant is REPLACED locally before building. Never
/// commit your real key. After editing the value below, run:
///
///     git update-index --skip-worktree Sources/Services/WhisperService.swift
///
/// to keep your local edit out of every diff. If the value is still the
/// placeholder, the app falls through to the user-provided key path.
enum EmbeddedKeys {
    /// Groq free-tier beta key. Replace with your real `gsk_...` key locally.
    /// Long-term plan: move this to a backend proxy so the key never ships
    /// with the binary.
    static let groq: String = "REPLACE_WITH_YOUR_GROQ_KEY"

    /// Whether an embedded Groq key is actually configured. Used by the
    /// UI to decide whether to show "free tier active" status or prompt
    /// the user to add their own key.
    static var hasGroq: Bool {
        !groq.isEmpty && groq != "REPLACE_WITH_YOUR_GROQ_KEY"
    }
}

class WhisperService {
    private typealias ContextSummaryCompletion = (ContextSnapshot?) -> Void
    private let contextSummaryLock = NSLock()
    private var contextSummaryWaiters: [Date: [ContextSummaryCompletion]] = [:]

    // OpenAI endpoints (default)
    private let openAIEndpoint = "https://api.openai.com/v1/audio/transcriptions"
    // Chat-completions endpoint is now resolved per-call via PolishBackend.current.chatCompletionsURL.
    //
    // STT model choice: `gpt-4o-mini-transcribe` is ~40% faster than
    // `gpt-4o-transcribe` with negligible quality loss on clean close-mic
    // audio (the typical dictation case). For noisy/long-form audio the
    // bigger model would win — revisit if accuracy complaints surface.
    // Fallback path stays on `whisper-1` (the classic model); it responds
    // fast and covers the rare case where the newer model route 404s.
    private let openAITranscriptionModel = VordiAIModels.transcriptionDefault

    // Groq free-tier — supports multilingual (Hindi, Marathi, English, etc.)
    private let groqEndpoint = "https://api.groq.com/openai/v1/audio/transcriptions"
    /// Faster model, good for English-only cleanup (verbatim path).
    private let groqTranscriptionModel = "whisper-large-v3-turbo"
    /// Full model, used for all multilingual paths (Romanized, Translate to English).
    /// Static so the routing function (which is also static) can reference it.
    static let groqMultilingualModel = "whisper-large-v3"

    /// Prompt sent as the Whisper multipart `prompt` field. Kept as a single
    /// source of truth so we can both (a) feed it to STT and (b) reject any
    /// output that echoes it verbatim — which happens on silent/corrupt audio
    /// where Whisper falls back to regurgitating its own prompt.
    ///
    /// Two parts:
    ///   1. Style/language hint (Hindi/Marathi → Latin script)
    ///   2. Custom vocabulary — biases the decoder toward unusual proper
    ///      nouns and brand spellings the user is likely to dictate.
    ///      OpenAI's docs: the model matches the prompt's STYLE including
    ///      capitalization and unusual spellings. So listing "Wispr Flow"
    ///      (vs. "Whisper Flow") teaches the decoder the correct form.
    ///
    /// Token budget: ~244 tokens max for the prompt field. Current ~120
    /// tokens leaves headroom for future user-defined vocabulary additions
    /// (the eventual Dictionary feature).
    /// Built-in vocabulary — product/tech proper nouns the user is likely
    /// to dictate. Stable list; user-added terms come in via `UserVocabulary`
    /// and get appended at prompt-build time.
    private static let baselineVocabulary = "Vordi, Vordi, Wispr Flow, ChatGPT, Codex, Cursor, Claude, Anthropic, OpenAI, Whisper, GitHub, Slack, Notion, Figma, Linear, TypeScript, JavaScript, Python, npm, GraphQL, MongoDB, Postgres, Docker, Kubernetes, Hinglish"

    /// One-line vocabulary hint for polish-LLM system prompts. Empty when
    /// the user hasn't added any vocabulary terms — callers should string-
    /// concatenate this directly into the prompt without surrounding
    /// formatting (the leading newline is included so empty doesn't add
    /// a blank line).
    private static var polishVocabularyHint: String {
        let userTerms = UserVocabulary.promptInjection
        guard !userTerms.isEmpty else { return "" }
        return "\n- The user dictates these proper nouns / project names. Preserve their exact capitalization and spelling whenever they appear (correct STT mis-spellings to these canonical forms): \(userTerms)."
    }

    private static var polishRuleInstruction: String {
        let enabledInstructions = PolishRule.enabledInstructions
        guard !enabledInstructions.isEmpty else {
            // Every Polish rule is disabled — the user is explicitly asking for a
            // near-verbatim result. Pin the model to the most faithful transform
            // possible so "all attributes off" actually means "don't rewrite me".
            return """
            - The user has disabled all rewriting. Output the transcript essentially verbatim.
            - Only fix capitalization, punctuation, and obvious speech-to-text spelling errors.
            - Do NOT reword, reorder, condense, summarize, or add structure (headings, lists, line breaks). Preserve the speaker's exact wording and order.
            """
        }
        var instructions = enabledInstructions
        if !PolishRule.isEnabled(.addStructureForReadability) {
            instructions.append(PolishFormattingPolicy.structureInstruction(isEnabled: false))
        }
        return instructions.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func allowsStructuredLists(for processingMode: TranscriptProcessingMode) -> Bool {
        PolishFormattingPolicy.allowsStructuredLists(
            processingModeRawValue: processingMode.rawValue,
            structureRuleEnabled: PolishRule.isEnabled(.addStructureForReadability)
        )
    }

    /// Whisper STT prompt. Computed (NOT a `static let`) so user-added
    /// vocabulary takes effect immediately when the user edits it in
    /// Settings — no app restart required.
    ///
    /// The Whisper prompt field is bounded at ~244 tokens (~1000 chars);
    /// `UserVocabulary.promptInjection` is already capped at 800 chars so
    /// the combined prompt stays well within the limit even with the
    /// baseline vocabulary added.
    static func sttPrompt(for style: TranscriptOutputStyle) -> String {
        let userTerms = UserVocabulary.promptInjection
        let vocabulary: String = {
            if userTerms.isEmpty { return baselineVocabulary }
            return baselineVocabulary + ", " + userTerms
        }()
        let styleInstruction: String
        switch style {
        case .verbatim:
            styleInstruction = "Transcribe exactly in the spoken language and script. Preserve wording, names, and technical terms."
        case .clean:
            styleInstruction = "Transcribe in the spoken language and script. Preserve the speaker's meaning and terminology."
        case .cleanHinglish:
            styleInstruction = "Keep the spoken language. Write Hindi, Marathi, and other Indic speech in natural Latin letters. Never use Devanagari."
        case .translateEnglish:
            styleInstruction = "Transcribe the original speech faithfully. Preserve names and technical terms; translation happens after transcription."
        }
        return "\(styleInstruction) Plain text only.\nCommon terms that may appear: \(vocabulary)."
    }

    /// Minimum plausible WAV size. Our recorder produces ~16kHz mono PCM with
    /// a 44-byte header → ~32KB/sec. 4KB ≈ 125ms of audio, which is below the
    /// shortest utterance Whisper can resolve. Anything smaller is guaranteed
    /// to either return empty or hallucinate — drop it at the gate.
    private static let minimumWAVBytes = 4_096

    /// Sentinel value passed back as the "prompt" when the fast-path elected
    /// to skip the polish LLM entirely. Surfaced in the run log so users can
    /// distinguish "polish ran with this prompt" from "polish was a no-op."
    /// We embed the actual reason rather than just a flag so the run-log
    /// disclosure is informative without needing extra UI plumbing.
    static let fastPathSkipMarker = "(skipped — transcript was already clean Latin script with no fillers, so it was injected verbatim. No LLM call was made.)"

    // Known Whisper hallucinations. When the raw transcript matches one of these
    // (case-insensitive, whitespace-trimmed), we drop it without invoking the
    // polish LLM. Sourced from Carnegie Mellon "Careless Whisper" (2024) +
    // community reports. Expand as you encounter more.
    private let hallucinationBlocklist: [String] = [
        "thank you for watching",
        "thanks for watching",
        "please subscribe",
        "subscribe to my channel",
        "don't forget to subscribe",
        "like and subscribe",
        "subtitles by the amara.org community",
        "transcribed by",
        "you",
        "bye",
        "thank you",
        "thanks",
        "okay",
        "ok",
        "hmm",
        "uh",
        "um",
        "ah",
        "mm",
        "♪",
        "[music]",
        "(music)",
        "[applause]",
        "so",
        "how are you",
        "more than me",
        "we are aware",
        "we are all here",
        "come now",
        "related",
        "जानेमन",
        "prasad",
        "dharam",
        "samajh gaya",
        "samajh gaya. aapka agla text bhejiye",
        "aapka agla text bhejiye",
        "namaste",
        "aapka swagat hai",
        "swagat hai",
        "muje pata hai",
        "mujhe pata hai",
        "aapka agla text bhejiye",
        "dhanyawad",
        "dhanyavaad",
        "shukriya",
        "theek hai",
        "thik hai",
        "acha",
        "accha",
        "haan ji",
        "ji haan",
        "kya haal hai",
        "kaise ho",
        "main theek hoon",
        "bahut accha",
        "bahut achha",
        "aap kaise hain",
        "sab theek hai",
        "chaliye",
        "chalo",
        "dekhte hain",
        "pata nahi",
        "koi baat nahi",
        "maaf kijiye",
        "suniye",
        "batayiye",
        "zaroor",
        "bilkul"
    ]
    
    func transcribeAndPolish(
        audioData: Data,
        language: String = "hi",
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode,
        context: ContextSnapshot? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        transcribeAndPolishWithMetadata(
            audioData: audioData,
            language: language,
            style: style,
            processingMode: processingMode,
            context: context
        ) { result in
            switch result {
            case .success(let metadata):
                completion(.success(metadata.finalText))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Full pipeline with metadata capture for RunLog observability.
    func transcribeAndPolishWithMetadata(
        audioData: Data,
        language: String = "hi",
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode,
        context: ContextSnapshot? = nil,
        summarizeContextIfNeeded: Bool = true,
        completion: @escaping (Result<TranscriptionMetadata, Error>) -> Void
    ) {
        // Entry guard: reject audio that's obviously too small to transcribe.
        // Without this, silent audio (e.g. recording with denied mic access
        // that still produced a zero-byte buffer) flows into Whisper, which
        // falls back to emitting its own multipart prompt as the "transcript"
        // on some edge cases. That later leaks into the polish LLM and can
        // surface as the system prompt being injected into the user's editor.
        // Resolve route ONCE per call. Layer 1 (provider), Layer 3 (language),
        // Layer 4 (polish backend co-location) all flow from this decision.
        let route = Self.route(forStyle: style, userLanguage: language)

        guard audioData.count >= Self.minimumWAVBytes else {
            print("WhisperService: rejecting tiny audio (\(audioData.count) bytes) — aborting pipeline before STT")
            let providerString: String = {
                switch route.provider {
                case .groq: return "groq/\(self.groqTranscriptionModel)"
                case .openai: return "openai/\(self.openAITranscriptionModel)"
                }
            }()
            completion(.success(TranscriptionMetadata(
                provider: providerString,
                rawText: "",
                transcriptionLatencyMs: 0,
                postProcessMode: processingMode.rawValue,
                postProcessStyle: style.rawValue,
                postProcessModel: nil,
                postProcessPrompt: nil,
                finalText: "",
                postProcessLatencyMs: 0,
                languageGuardTriggered: false,
                context: context
            )))
            return
        }

        let transcribeStart = CFAbsoluteTimeGetCurrent()

        transcribeWithProvider(
            audioData: audioData,
            language: route.language,
            provider: route.provider,
            groqModelOverride: route.groqModel,
            prompt: Self.sttPrompt(for: style)
        ) { [weak self] result in
            guard let self else { return }
            let transcribeLatency = Int((CFAbsoluteTimeGetCurrent() - transcribeStart) * 1000)

            let providerString: String
            switch route.provider {
            case .groq:
                providerString = "groq/\(route.groqModel ?? self.groqTranscriptionModel)"
            case .openai:
                providerString = "openai/\(self.openAITranscriptionModel)"
            }

            switch result {
            case .success(let stt):
                // Whether the polish LLM will run — it romanizes/translates any
                // non-Latin output downstream, so for those styles we must NOT
                // pre-transliterate here.
                let polishWillRun = (style != .verbatim)

                // Latin handling for the RAW transcript:
                //   - Verbatim (no polish): apply the deterministic Latin gate
                //     now, since nothing downstream will romanize it.
                //   - Polished styles: keep Whisper's output AS-IS (Devanagari
                //     included) so the polish LLM can romanize it *with meaning*.
                //     The old code ran Apple's `.toLatin` transform here first,
                //     which letter-by-letter mangled Devanagari — including
                //     English loanwords (रेस्टोरेंट → "restorenta", बुक → "buka")
                //     — and fed that garbage to the LLM instead of the clean
                //     script. The final Latin backstop still runs post-polish,
                //     so a leaked/failed romanization can't reach the editor.
                let transcript = polishWillRun
                    ? stt.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    : self.ensureLatinScript(stt.text)

                // HALLUCINATION GATE — runs BEFORE everything else, on
                // every style. Phantom phrases ("Thanks for watching"),
                // Whisper's confidence signals (no_speech_prob,
                // avg_logprob, compression_ratio AND-ed correctly), and
                // structural checks (alphanumeric count, repetition,
                // unsupported scripts). If any layer fires, drop the
                // transcript entirely — no run-log entry text, no
                // injection, no polish call.
                //
                // `polishWillRun` tells the structural-script check to
                // skip the "non-Latin output" rejection — for Hinglish /
                // English styles the polish LLM transliterates anything
                // Whisper outputs in Arabic / Devanagari / etc. We only
                // hard-block non-Latin on the verbatim path.
                let guardDecision = HallucinationGuard.evaluate(
                    text: transcript,
                    confidence: stt.confidence,
                    hadVoicedAudio: true,  // we already passed the AudioRecorder gate
                    polishWillRun: polishWillRun
                )
                if guardDecision.shouldDrop {
                    print("HallucinationGuard: dropping — \(guardDecision.reason ?? "unknown")")
                    let metadata = TranscriptionMetadata(
                        provider: providerString,
                        rawText: transcript,
                        transcriptionLatencyMs: transcribeLatency,
                        postProcessMode: processingMode.rawValue,
                        postProcessStyle: style.rawValue,
                        postProcessModel: "dropped: \(guardDecision.reason ?? "hallucination")",
                        postProcessPrompt: nil,
                        finalText: "",
                        postProcessLatencyMs: 0,
                        languageGuardTriggered: false,
                        context: context
                    )
                    completion(.success(metadata))
                    return
                }

                // Whisper prompt echo guard: silent audio sometimes makes
                // Whisper return our own multipart `prompt` verbatim (or a
                // light variation of it). Drop those before the polish LLM
                // turns them into plausible-looking sentences and we inject
                // them into the user's editor.
                if Self.isWhisperPromptEcho(transcript) {
                    print("WhisperService: STT returned a prompt-echo — dropping, nothing to polish")
                    let metadata = TranscriptionMetadata(
                        provider: providerString,
                        rawText: transcript,
                        transcriptionLatencyMs: transcribeLatency,
                        postProcessMode: processingMode.rawValue,
                        postProcessStyle: style.rawValue,
                        postProcessModel: nil,
                        postProcessPrompt: nil,
                        finalText: "",
                        postProcessLatencyMs: 0,
                        languageGuardTriggered: false,
                        context: context
                    )
                    completion(.success(metadata))
                    return
                }

                let continueWithContext: (ContextSnapshot?) -> Void = { enrichedContext in
                    let postStart = CFAbsoluteTimeGetCurrent()
                    self.postProcessWithPrompt(
                        text: transcript,
                        style: style,
                        processingMode: processingMode,
                        context: enrichedContext,
                        polishBackendOverride: route.polishBackendOverride
                    ) { postResult in
                        let postLatency = Int((CFAbsoluteTimeGetCurrent() - postStart) * 1000)

                        switch postResult {
                        case .success(let (finalText, prompt, guardTriggered)):
                            // Fast-path skip: prompt carries our sentinel marker.
                            // Show "skipped" as the model so the run log doesn't
                            // misleadingly imply the LLM ran with 0ms latency.
                            let polishRan = !(prompt == Self.fastPathSkipMarker)
                            let modelLabel: String? = {
                                if style == .verbatim { return nil }
                                if !polishRan { return "skipped (fast path)" }
                                return (route.polishBackendOverride ?? PolishBackend.current).displayLabel
                            }()
                            // LATIN GATE — last moment, every successful exit.
                            // VOCAB GATE — local find-and-replace for proper nouns.
                            // Runs AFTER Latin gate so we don't try to fuzzy-match
                            // against half-transliterated Devanagari, and AFTER
                            // polish so the LLM's output gets the same canonical-
                            // spelling treatment as raw STT does on the verbatim
                            // path. Local + sub-millisecond.
                            let latinFinal = self.ensureLatinScript(finalText)
                            let safeFinal = UserVocabulary.applyTo(latinFinal)
                            let metadata = TranscriptionMetadata(
                                provider: providerString,
                                rawText: transcript,
                                transcriptionLatencyMs: transcribeLatency,
                                postProcessMode: processingMode.rawValue,
                                postProcessStyle: style.rawValue,
                                postProcessModel: modelLabel,
                                postProcessPrompt: prompt,
                                finalText: safeFinal,
                                postProcessLatencyMs: postLatency,
                                languageGuardTriggered: guardTriggered,
                                context: enrichedContext
                            )
                            completion(.success(metadata))
                        case .failure(let error):
                            // Post-processing failed — return raw transcript as
                            // finalText fallback. Apply Latin + vocab gates
                            // before metadata so the user gets clean script
                            // and canonical proper nouns even on the error path.
                            print("Post-processing failed, using raw transcript: \(error)")
                            let latinFinal = self.ensureLatinScript(transcript)
                            let safeFinal = UserVocabulary.applyTo(latinFinal)
                            let metadata = TranscriptionMetadata(
                                provider: providerString,
                                rawText: transcript,
                                transcriptionLatencyMs: transcribeLatency,
                                postProcessMode: processingMode.rawValue,
                                postProcessStyle: style.rawValue,
                                postProcessModel: nil,
                                postProcessPrompt: nil,
                                finalText: safeFinal,
                                postProcessLatencyMs: postLatency,
                                languageGuardTriggered: false,
                                context: enrichedContext
                            )
                            completion(.success(metadata))
                        }
                    }
                }
                if summarizeContextIfNeeded {
                    self.prepareContextSummary(context, completion: continueWithContext)
                } else {
                    continueWithContext(context)
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Streaming-friendly entry point: caller already has a transcript (from
    /// the Realtime API) and just needs the post-processing pipeline.
    /// Shapes the same `TranscriptionMetadata` so RunLog rows look identical
    /// whether the transcript came from batch or stream.
    ///
    /// `providerLabel` lets the caller identify the origin (e.g.
    /// "openai/gpt-4o-mini-transcribe/realtime") so we can slice latency by
    /// path in the Run Log.
    func polishOnlyWithMetadata(
        rawTranscript: String,
        providerLabel: String,
        transcriptionLatencyMs: Int,
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode,
        context: ContextSnapshot? = nil,
        summarizeContextIfNeeded: Bool = true,
        completion: @escaping (Result<TranscriptionMetadata, Error>) -> Void
    ) {
        // Entry guard: empty/whitespace transcript → short-circuit without
        // ever hitting the polish LLM. The LLM has been observed to invent
        // a chat-reply ("Samajh gaya. Aapka agla text bhejiye.") or echo
        // its own system prompt on empty input despite the EMPTY-sentinel
        // contract. Belt-and-suspenders: the downstream `postProcess` has
        // the same guard, but we'd rather not even dispatch the request.
        let trimmedEntry = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEntry.isEmpty else {
            print("polishOnlyWithMetadata: empty transcript — skipping polish entirely")
            completion(.success(TranscriptionMetadata(
                provider: providerLabel,
                rawText: rawTranscript,
                transcriptionLatencyMs: transcriptionLatencyMs,
                postProcessMode: processingMode.rawValue,
                postProcessStyle: style.rawValue,
                postProcessModel: nil,
                postProcessPrompt: nil,
                finalText: "",
                postProcessLatencyMs: 0,
                languageGuardTriggered: false,
                context: context
            )))
            return
        }
        // Also drop raw transcripts that exactly echo the Whisper prompt —
        // this happens on silent audio where Whisper regurgitates the prompt
        // back as the "transcript". Catching it here prevents the echo from
        // reaching the polish LLM (which could then "clean it up" into real-
        // looking English that then gets injected into the user's editor).
        if Self.isWhisperPromptEcho(trimmedEntry) {
            print("polishOnlyWithMetadata: Whisper prompt echo detected — dropping")
            completion(.success(TranscriptionMetadata(
                provider: providerLabel,
                rawText: rawTranscript,
                transcriptionLatencyMs: transcriptionLatencyMs,
                postProcessMode: processingMode.rawValue,
                postProcessStyle: style.rawValue,
                postProcessModel: nil,
                postProcessPrompt: nil,
                finalText: "",
                postProcessLatencyMs: 0,
                languageGuardTriggered: false,
                context: context
            )))
            return
        }

        // HALLUCINATION GATE for the streaming path. The Realtime API
        // doesn't return per-segment confidence scores, so the
        // confidence layer is no-op here — but the phantom-phrase and
        // structural-heuristics layers still catch silence-induced
        // hallucinations the same way they do on the batch path.
        // `polishWillRun` matches the batch-path semantics: any non-
        // verbatim style allows non-Latin output through to polish.
        let streamingPolishWillRun = (style != .verbatim)
        let streamingDecision = HallucinationGuard.evaluate(
            text: trimmedEntry,
            confidence: .empty,
            hadVoicedAudio: true,
            polishWillRun: streamingPolishWillRun
        )
        if streamingDecision.shouldDrop {
            print("HallucinationGuard (streaming): dropping — \(streamingDecision.reason ?? "unknown")")
            completion(.success(TranscriptionMetadata(
                provider: providerLabel,
                rawText: rawTranscript,
                transcriptionLatencyMs: transcriptionLatencyMs,
                postProcessMode: processingMode.rawValue,
                postProcessStyle: style.rawValue,
                postProcessModel: "dropped: \(streamingDecision.reason ?? "hallucination")",
                postProcessPrompt: nil,
                finalText: "",
                postProcessLatencyMs: 0,
                languageGuardTriggered: false,
                context: context
            )))
            return
        }

        // Streaming path uses the same style → polish-backend co-location
        // logic as the batch path. The streaming provider was decided
        // upstream by setupRealtimeStreamIfEnabled, but the POLISH backend
        // for the result is still our call.
        let route = Self.route(forStyle: style, userLanguage: "")

        let continueWithContext: (ContextSnapshot?) -> Void = { [weak self] enrichedContext in
            guard let self else { return }
            let postStart = CFAbsoluteTimeGetCurrent()
            self.postProcessWithPrompt(
                text: rawTranscript,
                style: style,
                processingMode: processingMode,
                context: enrichedContext,
                polishBackendOverride: route.polishBackendOverride
            ) { [weak self] postResult in
                let postLatency = Int((CFAbsoluteTimeGetCurrent() - postStart) * 1000)
                switch postResult {
                case .success(let (finalText, prompt, guardTriggered)):
                    // Fast-path skip detection — see the matching block in
                    // transcribeAndPolishWithMetadata for the full rationale.
                    let polishRan = !(prompt == Self.fastPathSkipMarker)
                    let modelLabel: String? = {
                        if style == .verbatim { return nil }
                        if !polishRan { return "skipped (fast path)" }
                        return (route.polishBackendOverride ?? PolishBackend.current).displayLabel
                    }()
                    // LATIN + VOCAB GATES — last moment, every successful
                    // streaming exit. Same treatment as the batch path so
                    // the user gets canonical proper nouns regardless of
                    // which pipeline produced the text.
                    let latinFinal = self?.ensureLatinScript(finalText) ?? finalText
                    let safeFinal = UserVocabulary.applyTo(latinFinal)
                    let metadata = TranscriptionMetadata(
                        provider: providerLabel,
                        rawText: rawTranscript,
                        transcriptionLatencyMs: transcriptionLatencyMs,
                        postProcessMode: processingMode.rawValue,
                        postProcessStyle: style.rawValue,
                        postProcessModel: modelLabel,
                        postProcessPrompt: prompt,
                        finalText: safeFinal,
                        postProcessLatencyMs: postLatency,
                        languageGuardTriggered: guardTriggered,
                        context: enrichedContext
                    )
                    completion(.success(metadata))
                case .failure(let error):
                    // Same graceful fallback shape as the batch path.
                    print("Post-processing failed (streaming), using raw transcript: \(error)")
                    let latinFinalErr = self?.ensureLatinScript(rawTranscript) ?? rawTranscript
                    let safeFinal = UserVocabulary.applyTo(latinFinalErr)
                    let metadata = TranscriptionMetadata(
                        provider: providerLabel,
                        rawText: rawTranscript,
                        transcriptionLatencyMs: transcriptionLatencyMs,
                        postProcessMode: processingMode.rawValue,
                        postProcessStyle: style.rawValue,
                        postProcessModel: nil,
                        postProcessPrompt: nil,
                        finalText: safeFinal,
                        postProcessLatencyMs: postLatency,
                        languageGuardTriggered: false,
                        context: enrichedContext
                    )
                    completion(.success(metadata))
                }
            }
        }
        if summarizeContextIfNeeded {
            self.prepareContextSummary(context, completion: continueWithContext)
        } else {
            continueWithContext(context)
        }
    }

    /// Public entry — preserves the original `Result<String, Error>`
    /// signature for any caller that doesn't have style context. The
    /// internal pipeline now passes around `STTResult` (text +
    /// confidence) but external callers can stay string-based.
    func transcribe(audioData: Data, language: String = "hi", completion: @escaping (Result<String, Error>) -> Void) {
        transcribeWithProvider(
            audioData: audioData,
            language: language,
            provider: TranscriptionProvider.current,
            prompt: Self.sttPrompt(for: .verbatim)
        ) { result in
            switch result {
            case .success(let stt):
                completion(.success(stt.text))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    /// Rich STT result — text plus Whisper's self-reported confidence
    /// signals from the `verbose_json` response format. Confidence is
    /// `.empty` when the response body didn't include segments (older
    /// API tier or unsupported format) — downstream guards still run on
    /// phantom-phrase + structural signals in that case.
    struct STTResult {
        let text: String
        let confidence: HallucinationGuard.Confidence
    }

    /// Provider-explicit entry — used by `transcribeAndPolishWithMetadata`
    /// after `STTRoute` resolves the right backend for the user's style.
    ///
    /// Empty `language` string omits the param → Whisper auto-detects.
    /// Pass `groqModelOverride` to use `whisper-large-v3` on the multilingual
    /// path instead of the default turbo model.
    private func transcribeWithProvider(
        audioData: Data,
        language: String,
        provider: TranscriptionProvider,
        groqModelOverride: String? = nil,
        prompt: String,
        completion: @escaping (Result<STTResult, Error>) -> Void
    ) {
        switch provider {
        case .groq:
            transcribeWithModel(
                audioData: audioData,
                language: language,
                model: groqModelOverride ?? groqTranscriptionModel,
                endpoint: groqEndpoint,
                apiKey: groqAPIKey(),
                prompt: prompt,
                completion: completion
            )
        case .openai:
            transcribeWithModel(
                audioData: audioData,
                language: language,
                model: openAITranscriptionModel,
                endpoint: openAIEndpoint,
                apiKey: openAIAPIKey(),
                prompt: prompt,
                completion: completion
            )
        }
    }

    private func openAIAPIKey() -> String {
        let raw = UserDefaults.standard.string(forKey: "openai_api_key")
            ?? ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
            ?? ""
        // Trim whitespace/newlines defensively. Pasting from the OpenAI
        // dashboard often picks up trailing newlines that the OpenAI API
        // rejects with "Incorrect API key" even when the key itself is valid.
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// User-provided key wins. Falls back to env var, then to the embedded
    /// beta key. So a user with an empty Groq field still gets transcription
    /// for free during the beta.
    private func groqAPIKey() -> String {
        // Same trim discipline as openAIAPIKey() — trailing newlines from
        // the dashboard copy paste are the silent killer for cloud keys.
        let userKey = (UserDefaults.standard.string(forKey: "groq_api_key") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !userKey.isEmpty { return userKey }
        let envKey = (ProcessInfo.processInfo.environment["GROQ_API_KEY"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !envKey.isEmpty { return envKey }
        return EmbeddedKeys.groq
    }

    private func transcribeWithModel(
        audioData: Data,
        language: String,
        model: String,
        endpoint: String,
        apiKey: String,
        prompt: String,
        completion: @escaping (Result<STTResult, Error>) -> Void
    ) {
        guard !apiKey.isEmpty else {
            completion(.failure(WhisperError.noAPIKey))
            return
        }

        guard let url = URL(string: endpoint) else {
            completion(.failure(WhisperError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add file data
        body.append("--\(boundary)\r\n".data(using: .ascii)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .ascii)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .ascii)!)
        body.append(audioData)
        body.append("\r\n".data(using: .ascii)!)

        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .ascii)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .ascii)!)
        body.append("\(model)\r\n".data(using: .ascii)!)

        // Encourage same-language transcript with Latin script for Hindi content.
        body.append("--\(boundary)\r\n".data(using: .ascii)!)
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n".data(using: .ascii)!)
        body.append("\(prompt)\r\n".data(using: .utf8)!)

        // Send the language form-field unless caller asked for auto-detect.
        // BOTH "auto" (legacy sentinel) and "" (new empty-string sentinel from
        // STTRoute) suppress the field. Whisper auto-detects when no language
        // is supplied, which is what we want for translation paths.
        if language != "auto" && !language.isEmpty {
            body.append("--\(boundary)\r\n".data(using: .ascii)!)
            body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .ascii)!)
            body.append("\(language)\r\n".data(using: .ascii)!)
        }

        // Force deterministic decoding. Whisper's default temperature includes
        // a fallback ladder (0 → 0.2 → 0.4 → ...) that dramatically increases
        // hallucinations on quiet/noisy audio. Pinning to 0 trades robustness
        // for predictability — exactly what we want for dictation.
        body.append("--\(boundary)\r\n".data(using: .ascii)!)
        body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .ascii)!)
        body.append("0\r\n".data(using: .ascii)!)

        // Confidence-signal format depends on the model — this MUST branch, or
        // HallucinationGuard's confidence layer goes silently dead:
        //
        //   • whisper-1 and Groq whisper-large-v3* support `verbose_json`, which
        //     carries per-SEGMENT no_speech_prob / avg_logprob / compression_ratio
        //     — Whisper's own self-doubt signals (no_speech_prob spikes >~0.6 and
        //     avg_logprob drops <~-1.0 when it hallucinates on silence).
        //
        //   • gpt-4o-transcribe / gpt-4o-mini-transcribe (our DEFAULT OpenAI
        //     model) do NOT support verbose_json — only json|text. Sending
        //     verbose_json returns no segments (or 400s), which blinded the
        //     confidence guard on the primary path. For those we ask for
        //     `json` + `include[]=logprobs` and derive a synthetic avg_logprob
        //     from the per-token logprobs in the response parser below.
        let isGPT4oModel = model.lowercased().hasPrefix("gpt-4o")
        if isGPT4oModel {
            body.append("--\(boundary)\r\n".data(using: .ascii)!)
            body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .ascii)!)
            body.append("json\r\n".data(using: .ascii)!)

            body.append("--\(boundary)\r\n".data(using: .ascii)!)
            body.append("Content-Disposition: form-data; name=\"include[]\"\r\n\r\n".data(using: .ascii)!)
            body.append("logprobs\r\n".data(using: .ascii)!)
        } else {
            body.append("--\(boundary)\r\n".data(using: .ascii)!)
            body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .ascii)!)
            body.append("verbose_json\r\n".data(using: .ascii)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .ascii)!)

        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(WhisperError.noData))
                return
            }

            // Parse JSON response — `verbose_json` shape:
            //   {
            //     "text": "...",
            //     "language": "en",
            //     "duration": 1.23,
            //     "segments": [
            //       {
            //         "id": 0, "seek": 0, "start": 0.0, "end": 1.23,
            //         "text": "...",
            //         "tokens": [...],
            //         "temperature": 0.0,
            //         "avg_logprob": -0.42,
            //         "compression_ratio": 1.12,
            //         "no_speech_prob": 0.03
            //       },
            //       ...
            //     ]
            //   }
            //
            // We aggregate the per-segment scores by mean — gives a
            // single Confidence struct that downstream guards can act on.
            // The basic `json` fallback path (no segments) returns
            // `Confidence.empty` and downstream guards still fire on
            // phantom-phrase + structural signals.
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(WhisperError.parseError))
                    return
                }

                // API error shape — bubble up first.
                if let errorObj = json["error"] as? [String: Any],
                   let message = errorObj["message"] as? String {
                    completion(.failure(WhisperError.apiError(message)))
                    return
                }

                guard let text = json["text"] as? String else {
                    completion(.failure(WhisperError.parseError))
                    return
                }

                // Aggregate confidence. The signal source depends on the model:
                //   • verbose_json (whisper-1 / Groq v3*) → per-segment scores.
                //   • json + logprobs (gpt-4o family) → per-token logprobs, from
                //     which we derive a synthetic avg_logprob.
                // Anything else → empty confidence, and downstream guards still
                // fire on phantom-phrase + structural signals.
                let segments = (json["segments"] as? [[String: Any]]) ?? []
                let confidence: HallucinationGuard.Confidence
                if !segments.isEmpty {
                    // We use simple mean rather than weighted-by-duration
                    // because for dictation-length audio (<30s) all segments are
                    // similar size.
                    confidence = Self.aggregateConfidence(segments: segments)
                } else if let logprobs = json["logprobs"] as? [[String: Any]] {
                    confidence = Self.aggregateLogprobs(logprobs)
                } else {
                    confidence = .empty
                }

                completion(.success(STTResult(text: text, confidence: confidence)))
            } catch {
                completion(.failure(error))
            }
        }

        task.resume()
    }

    /// Mean of each confidence signal across segments. Missing values
    /// in a segment skip that signal for that segment (still averaged
    /// over the segments that DID provide it).
    private static func aggregateConfidence(segments: [[String: Any]]) -> HallucinationGuard.Confidence {
        guard !segments.isEmpty else { return .empty }

        var noSpeechSum = 0.0; var noSpeechCount = 0
        var logprobSum = 0.0; var logprobCount = 0
        var compRatioSum = 0.0; var compRatioCount = 0

        for seg in segments {
            if let v = seg["no_speech_prob"] as? Double {
                noSpeechSum += v; noSpeechCount += 1
            }
            if let v = seg["avg_logprob"] as? Double {
                logprobSum += v; logprobCount += 1
            }
            if let v = seg["compression_ratio"] as? Double {
                compRatioSum += v; compRatioCount += 1
            }
        }

        // For no_speech_prob we use MAX rather than mean — even one
        // segment scoring high means part of the audio is silent and
        // Whisper is filling in. Mean would dilute the signal across
        // legitimate-speech segments.
        var noSpeechMax: Double? = nil
        for seg in segments {
            if let v = seg["no_speech_prob"] as? Double {
                noSpeechMax = max(noSpeechMax ?? 0, v)
            }
        }

        return HallucinationGuard.Confidence(
            noSpeechProb: noSpeechMax,
            avgLogprob: logprobCount > 0 ? logprobSum / Double(logprobCount) : nil,
            compressionRatio: compRatioCount > 0 ? compRatioSum / Double(compRatioCount) : nil
        )
    }

    /// Build a Confidence from the gpt-4o `logprobs` array (per-token). Only
    /// avg_logprob is available on this path — gpt-4o has no no_speech_prob or
    /// compression_ratio equivalent, so those stay nil. The nil no_speech_prob
    /// is intentional and load-bearing: it lets HallucinationGuard tell a
    /// gpt-4o per-token signal apart from a whisper per-segment signal and apply
    /// the correct (stricter, standalone) logprob threshold instead of the
    /// no_speech AND-gate, which can never fire without a no_speech_prob.
    private static func aggregateLogprobs(_ logprobs: [[String: Any]]) -> HallucinationGuard.Confidence {
        var sum = 0.0
        var count = 0
        for token in logprobs {
            if let lp = token["logprob"] as? Double {
                sum += lp
                count += 1
            }
        }
        guard count > 0 else { return .empty }
        return HallucinationGuard.Confidence(
            noSpeechProb: nil,
            avgLogprob: sum / Double(count),
            compressionRatio: nil
        )
    }

    /// Returns (finalText, systemPrompt, languageGuardTriggered).
    ///
    /// `polishBackendOverride` lets callers force a specific polish backend
    /// (e.g. STT routing wants to keep polish on Groq when STT is Groq).
    /// nil → respect user's PolishBackend.current setting.
    private func postProcessWithPrompt(
        text: String,
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode,
        context: ContextSnapshot? = nil,
        polishBackendOverride: PolishBackend? = nil,
        completion: @escaping (Result<(String, String?, Bool), Error>) -> Void
    ) {
        postProcess(
            text: text,
            style: style,
            processingMode: processingMode,
            context: context,
            capturePrompt: true,
            polishBackendOverride: polishBackendOverride
        ) { result in
            completion(result)
        }
    }

    private func postProcess(
        text: String,
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode,
        context: ContextSnapshot? = nil,
        capturePrompt: Bool = false,
        polishBackendOverride: PolishBackend? = nil,
        completion: @escaping (Result<(String, String?, Bool), Error>) -> Void
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.success(("", nil, false)))
            return
        }
        guard hasMeaningfulTranscriptText(trimmed) else {
            completion(.success(("", nil, false)))
            return
        }

        // Hallucination guard #1 (pre-polish): drop known Whisper phantom
        // phrases before they reach the polish LLM.
        if isLikelyHallucination(trimmed) {
            print("Dropped suspected Whisper hallucination (pre-polish): \(trimmed)")
            completion(.success(("", nil, false)))
            return
        }

        // Guard against GPT polish-step hallucinations: if the raw transcript
        // is suspiciously short (< 4 real alphanumeric chars), the LLM is
        // likely to invent a chat reply like "Samajh gaya. Aapka agla text bhejiye."
        // Skip polish entirely and return the raw transcript.
        let alphaNumCount = trimmed.unicodeScalars.filter { s in
            let v = s.value
            return (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) ||
                   (0x61...0x7A).contains(v) || (0x0900...0x097F).contains(v)
        }.count
        if alphaNumCount < 4 {
            print("Skipping polish on tiny transcript (\(alphaNumCount) chars) to prevent LLM improvisation")
            completion(.success(("", nil, false)))
            return
        }

        // Fast path — Original + Dictation is intentionally raw STT. Rewrite,
        // Prompt Engineer, and every polished output style still run the LLM.
        if Self.shouldSkipPolish(transcript: trimmed, style: style, processingMode: processingMode) {
            print("Polish skipped (fast path): transcript is clean Latin with no fillers")
            // Annotate the skip so the run log can show users WHY their
            // post-process card has 0ms latency and no model invocation.
            // Without this, users see "Latency 0ms" and think the LLM ran but
            // did nothing — when in fact we never made the API call.
            completion(.success((trimmed, Self.fastPathSkipMarker, false)))
            return
        }

        if processingMode == .promptEngineer {
            promptEngineerTransform(
                text: trimmed,
                style: style,
                context: context,
                polishBackendOverride: polishBackendOverride,
                completion: completion
            )
            return
        }

        if style == .cleanHinglish {
            normalizeBilingualSegments(
                text: trimmed,
                processingMode: processingMode,
                context: context,
                polishBackendOverride: polishBackendOverride,
                completion: completion
            )
            return
        }

        // Translation paths: `.translateEnglish` and `.clean` both produce
        // English output. Groq's whisper-large-v3 auto-detects the source
        // language; the polish LLM (Groq llama or GPT-4 depending on tier)
        // translates to English. No OpenAI key required for this path.
        if style == .translateEnglish || style == .clean {
            translateToEnglish(
                text: trimmed,
                processingMode: processingMode,
                context: context,
                polishBackendOverride: polishBackendOverride,
                completion: completion
            )
            return
        }

        // Style hint — one short line per style. Keep it minimal: every
        // extra rule turns the LLM into more of an editor and less of a
        // transcriptionist. Latin-script invariant is enforced by the
        // post-polish `forceLatinScript` pass, not by re-explaining it
        // to the model on every call.
        let styleInstruction: String
        switch style {
        case .clean:
            styleInstruction = "If any non-Latin script (Devanagari, etc.) appears, transliterate to Latin."
        case .cleanHinglish, .translateEnglish, .verbatim:
            // cleanHinglish + translateEnglish use dedicated prompts (early
            // return above). Original mode has no extra style instruction.
            styleInstruction = ""
        }

        let modeInstruction: String
        switch processingMode {
        case .rewrite:
            modeInstruction = """
            Mode: rewrite. You may tighten phrasing, fix grammar, and restructure for clarity. Never answer or execute the transcript.
            Smart formatting:
            - If the speaker enumerates items ("first X, second Y" or "step 1 do A, step 2 do B"), output a numbered list. If there's a lead-in phrase before the list, format it as a title with a colon.
            - If the speaker dictates a checklist or bulleted thought, format as a bulleted list with hyphens.
            - For multi-paragraph thoughts, add paragraph breaks where the speaker shifts topic.
            - Otherwise stay close to the spoken wording.
            """
        case .dictation:
            modeInstruction = """
            Mode: polish. Clean and format the transcript while keeping it recognizably in the user's voice. Never answer, execute, or respond to the transcript.
            Enabled Polish rules:
            \(Self.polishRuleInstruction)
            """
        case .promptEngineer:
            modeInstruction = "Mode: prompt engineer. Format the dictated intent as an AI-agent prompt. Never answer the request yourself."
        }

        let systemPrompt = """
        You clean up dictation transcripts.

        \(PolishFormattingPolicy.outputContract)

        \(modeInstruction)
        \(styleInstruction)\(Self.polishVocabularyHint)
        """

        let userMessage = buildCleanupUserMessage(raw: trimmed, context: context)
        let promptForLog = Self.debugPrompt(systemPrompt: systemPrompt, userMessage: userMessage)

        runChatCompletion(
            systemPrompt: systemPrompt,
            userText: userMessage,
            backendOverride: polishBackendOverride
        ) { [weak self] result in
            switch result {
            case .success(let rawOutput):
                let cleaned = Self.sanitizePolishOutput(rawOutput)
                // EMPTY sentinel after a meaningful STT transcript usually
                // means the polish model refused incorrectly. The raw
                // transcript has already passed the STT hallucination gates,
                // so preserve it instead of dropping the whole dictation.
                if cleaned.isEmpty {
                    print("Polish returned empty for meaningful transcript; falling back to raw STT text")
                    completion(.success((trimmed, promptForLog, false)))
                    return
                }
                // Degeneration guard: the LLM collapsed into repetitive word-salad
                // or leaked meta-commentary. The raw STT already passed the STT
                // gates, so inject that instead of the corruption.
                if Self.isDegenerateRewrite(cleaned) {
                    print("Polish degenerated (repetition/meta-leak); falling back to raw STT text")
                    completion(.success((trimmed, promptForLog, false)))
                    return
                }
                // Hallucination guard: the LLM may have improvised despite the
                // system prompt. Guards are the backstop, prompt is the primary
                // defense.
                if self?.isLikelyPolishHallucination(
                    output: cleaned,
                    input: trimmed,
                    allowStructuredLists: Self.allowsStructuredLists(for: processingMode)
                ) == true {
                    print("Dropped GPT polish hallucination: \(cleaned)")
                    completion(.success(("", promptForLog, false)))
                    return
                }
                if style == .cleanHinglish, self?.containsDevanagari(cleaned) == true {
                    self?.forceLatinScript(input: cleaned, polishBackendOverride: polishBackendOverride) { latinResult in
                        switch latinResult {
                        case .success(let latinText):
                            completion(.success((latinText, promptForLog, false)))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    completion(.success((cleaned, promptForLog, false)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Wraps a raw transcript in a labeled field so the LLM sees it as data
    /// to transform, not a conversational message to reply to. This framing
    /// alone materially reduces instruction-following drift on imperatives
    /// like "create a query...".
    private func buildCleanupUserMessage(raw: String, context: ContextSnapshot? = nil) -> String {
        // Escape internal double-quotes so the field boundary stays unambiguous.
        let escaped = raw.replacingOccurrences(of: "\"", with: "\\\"")
        let contextBlock = Self.postProcessingContextBlock(for: context)
        let contextInstruction = contextBlock.isEmpty
            ? ""
            : """

        CONTEXT: "\(contextBlock)"
        Use CONTEXT only to correct spelling, casing, or punctuation for words already present in RAW_TRANSCRIPTION. Never add people, apps, topics, commands, or facts from CONTEXT if they were not spoken.
        """
        return """
        Clean up RAW_TRANSCRIPTION and return only the cleaned transcript text — no surrounding quotes, no explanations.
        Return exactly EMPTY if there is nothing meaningful to clean.
        \(contextInstruction)

        RAW_TRANSCRIPTION: "\(escaped)"
        """
    }

    private static func postProcessingContextBlock(for context: ContextSnapshot?) -> String {
        guard let context else { return "" }
        var parts: [String] = []
        if let summary = context.summary?.text.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            parts.append(summary)
        }
        if let app = context.frontmostAppName, !app.isEmpty {
            parts.append("App: \(app)")
        }
        if let title = context.windowTitle, !title.isEmpty {
            parts.append("Window: \(title)")
        }
        if !context.selection.isEmpty {
            let capped = context.selection.count > 500
                ? String(context.selection.prefix(500)) + "…"
                : context.selection
            parts.append("Selected text: \(capped)")
        }
        return parts.joined(separator: " | ")
    }

    private static func debugPrompt(systemPrompt: String, userMessage: String) -> String {
        """
        [System]
        \(systemPrompt)

        [User]
        \(userMessage)
        """
    }

    /// Normalizes the LLM's raw completion: trims whitespace, strips outer
    /// quotes if the model wrapped the whole response in them, and converts
    /// the EMPTY sentinel to an empty string. The sentinel is how we let the
    /// model refuse cleanly without hallucinating a filler reply.
    private static func sanitizePolishOutput(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }

        // Strip a single layer of surrounding quotes if the model wrapped its
        // entire response. Only strip when BOTH ends are quoted — mid-sentence
        // quotes should survive.
        if result.count >= 2,
           (result.hasPrefix("\"") && result.hasSuffix("\"")) ||
           (result.hasPrefix("'") && result.hasSuffix("'")) {
            result.removeFirst()
            result.removeLast()
            result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // The EMPTY sentinel (including common variations the model might emit)
        // maps to an empty output. Callers decide whether that means "drop" or
        // "fallback to raw STT", depending on whether the raw transcript already
        // passed their validity guards.
        let upper = result.uppercased()
        if upper == "EMPTY" || upper == "[EMPTY]" || upper == "EMPTY." {
            return ""
        }

        return result
    }

    /// Detect a *degenerate* rewrite — the polish LLM collapsing into broken,
    /// repetitive word-salad or leaking meta-commentary instead of cleaning the
    /// transcript. Distinct from `isLikelyPolishHallucination`, whose checks key
    /// off output that is *longer* than the input or starts with a chatbot
    /// prefix. Degeneration is usually the SAME length or SHORTER and is built
    /// from scattered token repeats, so it slips past every length- and
    /// prefix-based guard. On a hit, callers fall back to the raw STT transcript
    /// (known-good — it already passed the STT gates) instead of injecting the
    /// corruption.
    ///
    /// Two independent signals; either one fires:
    ///   1. Scattered adjacent word-doublings ("going going", "cart cart") — the
    ///      signature of greedy-decoding repetition collapse. A faithful cleanup
    ///      effectively never emits 3+ exact adjacent repeats across one output.
    ///   2. Meta-commentary in the leading window ("Here is a clean version",
    ///      "To provide a clean transcript…") — the model narrating its task
    ///      instead of doing it.
    static func isDegenerateRewrite(_ output: String) -> Bool {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        // Signal 1 — adjacent duplicate words.
        let words = trimmed
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        if words.count >= 4 {
            var doubledPairs = 0
            for i in 1..<words.count where words[i] == words[i - 1] && words[i].count >= 2 {
                doubledPairs += 1
            }
            // 3+ exact adjacent repeats across one output is a decode loop, not
            // real speech — a faithful cleanup removes stutters, so even a single
            // surviving "that that" is rare and three is decisive. (Threshold
            // kept conservative; the fallback is the raw STT, so over-triggering
            // is non-destructive.)
            if doubledPairs >= 3 { return true }
        }

        // Signal 2 — meta-commentary leak near the start. Collapse whitespace
        // first so the match survives the irregular spacing degeneration emits.
        let collapsed = trimmed
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let head = String(collapsed.prefix(120))
        let metaLeaks = [
            "here is a clean", "here's a clean", "here is the clean",
            "a clean version", "clean version of", "cleaned transcript",
            "to provide a clean", "to provide clean",
            "adhere strictly", "follow guidelines", "follow the guidelines",
            "the cleaned version"
        ]
        for phrase in metaLeaks where head.contains(phrase) {
            return true
        }

        return false
    }

    private func normalizeBilingualSegments(
        text: String,
        processingMode: TranscriptProcessingMode,
        context: ContextSnapshot? = nil,
        polishBackendOverride: PolishBackend? = nil,
        completion: @escaping (Result<(String, String?, Bool), Error>) -> Void
    ) {
        let modeHint: String
        switch processingMode {
        case .rewrite:
            modeHint = """
            You may tighten phrasing within a single language. Never merge sentences across languages.
            If the speaker enumerates items ("first X, second Y" or "step 1, step 2"), output a numbered list with the lead-in as a colon-terminated title.
            For checklist-style content, format as a bulleted list with hyphens.
            """
        case .dictation:
            modeHint = """
            Apply the enabled Polish rules without translating between languages:
            \(Self.polishRuleInstruction)
            """
        case .promptEngineer:
            modeHint = "Format the dictated intent as an AI-agent prompt without answering it."
        }

        // Slim bilingual contract — the v1.1.3 prompt was a single sentence
        // and produced more faithful output than the 9-rule version that
        // followed. Restoring that brevity, with three non-negotiables
        // (Latin script, no translation, preserve every utterance) called
        // out as bullets.
        let prompt = """
        You clean up multilingual dictation transcripts and write them in Latin (Roman) script.
        The speaker may use any combination of Hindi, Marathi, English, or other languages in a single recording.

        \(PolishFormattingPolicy.outputContract)

        - All non-Latin words must be written in Latin/Roman script (e.g. "mera naam Raunak hai", "me tula bhetnar"). Never output Devanagari, Telugu, or any non-Latin script.
        - If the input is Hindi written in Arabic / Urdu script (e.g. "میرا نام رونق ہے"), TRANSLITERATE it to Latin Hinglish ("mera naam Raunak hai"). Treat Urdu-script and Devanagari-script Hindi as the same language; only the script changes — meaning is preserved, only romanize the spelling.
        - Never output Arabic / Persian / Urdu script in the result, even if the input was in that script.
        - Never translate English ↔ Hindi. Each segment stays in its original language.
        - English words the speaker used must be spelled in standard English — NOT phonetically romanized — even when the STT wrote them in Devanagari or garbled them. The speaker code-switches into English constantly (tech, food, everyday loanwords), and those words should read as normal English. Examples: रेस्टोरेंट / "restorenta" / "restorent" → "restaurant"; बुक / "buka" → "book"; मीटिंग / "meetinga" → "meeting"; ऑफिस / "ofisa" → "office"; फ़ोन → "phone"; डिनर / "dinara" → "dinner"; ऑर्डर / "ardara" → "order". Keep the surrounding Hindi romanized as Hinglish.
        - Preserve every distinct utterance in order. Don't merge or drop sentences even if two languages express the same meaning.
        - Fix Hindi spelling drift introduced by speech-to-text. The STT writes Hindi phonetically with predictable errors; correct them to canonical Hinglish romanization. Examples: "nama" → "naam", "hum" (when meaning "I am") → "hoon", "kara raha" → "kar raha", "aura" → "aur", "maim" → "main", "ka" sometimes → "kar", "thaan" → "tha".
        - Fix proper-noun mangling using the spoken context. Examples: "ronaka" / "ronak" → "Raunak", "wordy" / "vordi" → "Vordi", "vo'isalopa" / "voisalop" / "wide flow" / "wispr flow" → "Vordi", "shopsense" stays "Shopsense", "fynd" stays "Fynd", "chatgpt" → "ChatGPT", "openai" → "OpenAI". Capitalize known product / person names.
        - Where the speaker's intent is unambiguous from context, fix obvious word errors that aren't proper nouns (e.g. "kama" → "kaam" when the sentence is about work). Don't invent words; when ambiguous, leave the closest plausible spelling.
        - \(modeHint)\(Self.polishVocabularyHint)
        """

        let userMessage = buildCleanupUserMessage(raw: text, context: context)
        let promptForLog = Self.debugPrompt(systemPrompt: prompt, userMessage: userMessage)

        runChatCompletion(
            systemPrompt: prompt,
            userText: userMessage,
            backendOverride: polishBackendOverride
        ) { [weak self] result in
            switch result {
            case .success(let rawOutput):
                let normalized = Self.sanitizePolishOutput(rawOutput)
                if normalized.isEmpty {
                    print("Normalizer returned empty for meaningful transcript; falling back to raw STT text")
                    completion(.success((text, promptForLog, false)))
                    return
                }
                if Self.isDegenerateRewrite(normalized) {
                    print("Normalizer degenerated (repetition/meta-leak); falling back to raw STT text")
                    completion(.success((text, promptForLog, false)))
                    return
                }
                if self?.isLikelyPolishHallucination(
                    output: normalized,
                    input: text,
                    allowStructuredLists: Self.allowsStructuredLists(for: processingMode)
                ) == true {
                    print("Dropped GPT normalizer hallucination: \(normalized)")
                    completion(.success(("", promptForLog, false)))
                    return
                }
                if self?.didDropLanguage(original: text, cleaned: normalized) == true {
                    print("Normalizer dropped a language; returning raw transcript")
                    completion(.success((text, promptForLog, true)))
                    return
                }
                if self?.containsDevanagari(normalized) == true {
                    self?.forceLatinScript(input: normalized, polishBackendOverride: polishBackendOverride) { latinResult in
                        switch latinResult {
                        case .success(let latinText):
                            completion(.success((latinText, promptForLog, false)))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    completion(.success((normalized, promptForLog, false)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Translate any spoken language to natural English using the polish LLM.
    ///
    /// Why not the Whisper `/translations` endpoint?
    ///   - That endpoint forces `whisper-1`, losing the ~500ms speed gain we
    ///     get from `gpt-4o-mini-transcribe`.
    ///   - It has no prompt surface, so we can't enforce "no chatbot answers".
    ///   - Splits the pipeline into two STT paths for one feature.
    ///
    /// Instead: STT stays on the fast path, we run a dedicated translation
    /// system prompt through the existing polish backend. Works with local
    /// models (LM Studio / Ollama) too, since it's just text-to-text.
    private func translateToEnglish(
        text: String,
        processingMode: TranscriptProcessingMode,
        context: ContextSnapshot? = nil,
        polishBackendOverride: PolishBackend? = nil,
        completion: @escaping (Result<(String, String?, Bool), Error>) -> Void
    ) {
        let modeHint: String
        switch processingMode {
        case .rewrite:
            modeHint = """
            You may tighten phrasing while translating. Don't add information.
            If the speaker enumerates items, output as a numbered list. Lead-in becomes a colon-terminated title.
            For checklist-style content, format as a bulleted list with hyphens.
            """
        case .dictation:
            modeHint = """
            Translate faithfully, then apply the enabled Polish rules:
            \(Self.polishRuleInstruction)
            """
        case .promptEngineer:
            modeHint = "Translate the dictated request to English, then format it as an AI-agent prompt without answering it."
        }

        // Slim translator contract. Most of the verbose rules in the
        // previous 9-point version were edge-case worried — the model
        // already does the right thing on the common path. Kept the two
        // non-obvious things (already-English passthrough, proper-noun
        // preservation) as bullets.
        let prompt = """
        You translate dictation to natural English.

        \(PolishFormattingPolicy.outputContract)

        - Output is English in Latin script only.
        - If the input is already English, just clean it (fillers + grammar). Don't paraphrase.
        - Preserve proper nouns and technical terms exactly as spoken (e.g. "Raunak" stays "Raunak", "API key save kar do" → "Save the API key").
        - \(modeHint)\(Self.polishVocabularyHint)
        """

        let userMessage = buildCleanupUserMessage(raw: text, context: context)
        let promptForLog = Self.debugPrompt(systemPrompt: prompt, userMessage: userMessage)

        runChatCompletion(
            systemPrompt: prompt,
            userText: userMessage,
            backendOverride: polishBackendOverride
        ) { [weak self] result in
            switch result {
            case .success(let rawOutput):
                let translated = Self.sanitizePolishOutput(rawOutput)
                if translated.isEmpty {
                    print("Translator returned empty for meaningful transcript; falling back to raw STT text")
                    completion(.success((text, promptForLog, false)))
                    return
                }
                if Self.isDegenerateRewrite(translated) {
                    print("Translator degenerated (repetition/meta-leak); falling back to raw STT text")
                    completion(.success((text, promptForLog, false)))
                    return
                }
                if self?.isLikelyPolishHallucination(
                    output: translated,
                    input: text,
                    allowStructuredLists: Self.allowsStructuredLists(for: processingMode)
                ) == true {
                    print("Dropped GPT translator hallucination: \(translated)")
                    completion(.success(("", promptForLog, false)))
                    return
                }
                // Hard guard: if Devanagari leaked through, force a Latin-only
                // second pass using the same machinery that backstops Hinglish.
                if self?.containsDevanagari(translated) == true {
                    self?.forceLatinScript(input: translated, polishBackendOverride: polishBackendOverride) { latinResult in
                        switch latinResult {
                        case .success(let latinText):
                            completion(.success((latinText, promptForLog, true)))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    completion(.success((translated, promptForLog, false)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    /// Turn dictated intent into a reusable AI prompt in the same single
    /// post-processing call that would otherwise polish/rewrite the transcript.
    private func promptEngineerTransform(
        text: String,
        style: TranscriptOutputStyle,
        context: ContextSnapshot? = nil,
        polishBackendOverride: PolishBackend? = nil,
        completion: @escaping (Result<(String, String?, Bool), Error>) -> Void
    ) {
        let languageInstruction = Self.promptEngineerLanguageInstruction(for: style)
        let prompt = """
        \(PromptEngineerProfile.systemPrompt)

        Language output:
        \(languageInstruction)
        """

        let userMessage = PromptEngineerProfile.buildUserMessage(
            request: text,
            context: context ?? .empty()
        )
        let promptForLog = Self.debugPrompt(systemPrompt: prompt, userMessage: userMessage)

        runChatCompletion(
            systemPrompt: prompt,
            userText: userMessage,
            backendOverride: polishBackendOverride
        ) { [weak self] result in
            switch result {
            case .success(let rawOutput):
                let engineered = Self.sanitizePolishOutput(rawOutput)
                if engineered.isEmpty {
                    print("Prompt Engineer returned empty for meaningful transcript; falling back to raw STT text")
                    completion(.success((text, promptForLog, false)))
                    return
                }
                if self?.isLikelyHallucination(engineered) == true
                    || self?.isLikelyPolishSystemPromptEcho(engineered) == true
                    || Self.isWhisperPromptEcho(engineered) {
                    print("Dropped Prompt Engineer hallucination or prompt echo: \(engineered)")
                    completion(.success(("", promptForLog, false)))
                    return
                }
                if self?.containsDevanagari(engineered) == true {
                    self?.forceLatinScript(input: engineered, polishBackendOverride: polishBackendOverride) { latinResult in
                        switch latinResult {
                        case .success(let latinText):
                            completion(.success((latinText, promptForLog, true)))
                        case .failure(let error):
                            completion(.failure(error))
                        }
                    }
                } else {
                    completion(.success((engineered, promptForLog, false)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private static func promptEngineerLanguageInstruction(for style: TranscriptOutputStyle) -> String {
        PromptEngineerProfile.languageInstruction(for: style)
    }

    /// Heuristic: did the LLM silently drop one of the two languages?
    /// Uses common English function words + Hindi-in-Latin function words as
    /// markers. If the original text has both sets but the cleaned text only
    /// has one, the LLM deduplicated cross-language content — which is a bug
    /// specific to bilingual dictation (user says the same thing in two
    /// languages intentionally, LLM treats as redundancy).
    private func didDropLanguage(original: String, cleaned: String) -> Bool {
        let engMarkers: Set<String> = [
            "my", "the", "is", "are", "was", "were", "i", "name", "hello",
            "what", "when", "where", "how", "this", "that", "a", "an", "of",
            "to", "in", "on", "for", "and", "or", "you", "your", "it", "its"
        ]
        let hinMarkers: Set<String> = [
            "mera", "meri", "tera", "aap", "hai", "hain", "kya", "kyun",
            "kaise", "naam", "nam", "namaste", "haan", "nahi", "nahin",
            "ki", "ka", "ke", "mein", "se", "ko", "bhi", "toh", "par",
            "wala", "waali", "acha", "achha", "theek", "thik"
        ]

        func markerHits(_ text: String, markers: Set<String>) -> Int {
            let words = text
                .lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
            return words.reduce(0) { $0 + (markers.contains($1) ? 1 : 0) }
        }

        let origEng = markerHits(original, markers: engMarkers)
        let origHin = markerHits(original, markers: hinMarkers)
        let cleanEng = markerHits(cleaned, markers: engMarkers)
        let cleanHin = markerHits(cleaned, markers: hinMarkers)

        // Both languages present in input (≥1 marker each) but at least one
        // language completely disappeared in output.
        let origHadBoth = origEng >= 1 && origHin >= 1
        let cleanHasBoth = cleanEng >= 1 && cleanHin >= 1
        return origHadBoth && !cleanHasBoth
    }

    private func forceLatinScript(
        input: String,
        polishBackendOverride: PolishBackend? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let locallyTransliterated = transliterateToLatin(input)
        if !containsDevanagari(locallyTransliterated) {
            completion(.success(locallyTransliterated))
            return
        }

        let prompt = """
        \(PolishFormattingPolicy.outputContract)
        Convert only non-Latin script portions to Latin script.
        Never output Devanagari or any non-Latin script.
        Preserve original wording and language choice.
        Keep English text in English.
        Keep Hindi text in Hindi wording but Latin letters.
        Output plain text only.
        """

        runChatCompletion(
            systemPrompt: prompt,
            userText: input,
            backendOverride: polishBackendOverride,
            completion: completion
        )
    }

    private func transliterateToLatin(_ text: String) -> String {
        let transformed = text.applyingTransform(.toLatin, reverse: false) ?? text
        let asciiLike = transformed.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        let squashedSpaces = asciiLike.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return squashedSpaces.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Hard Latin-script backstop (Layer 2)
    //
    // Local, deterministic, sub-millisecond. Apply at every TranscriptionMetadata
    // construction site so no exit path — success, fast-path, polish-failed,
    // prompt-echo, hallucination-dropped, error-fallback — can leak Devanagari
    // into the user's editor.
    //
    // The function does THREE passes in escalating aggression:
    //   1. No-op when input is already pure Latin (zero cost).
    //   2. Apple's StringTransform `.toLatin` for clean transliteration.
    //   3. Final scrub: forcibly strip remaining Devanagari codepoints.
    //
    // Step 3 is the "nuclear option" — if step 2 somehow left Devanagari (rare,
    // happens for codepoints StringTransform doesn't know), we drop them. Losing
    // content is preferable to leaking script: the user can simply re-dictate.
    //
    // Why apply at the END instead of inside `forceLatinScript`: forceLatinScript
    // runs ONLY on the success path of certain styles. The leak paths (Whisper
    // prompt echo, polish failure → raw fallback, fast-path skip) all bypass it.
    // This gate sits outside the conditional logic — architecturally impossible
    // to skip.
    private func ensureLatinScript(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        guard containsDevanagari(text) else { return text }

        let transliterated = transliterateToLatin(text)
        if !containsDevanagari(transliterated) {
            return transliterated
        }

        // Step 3: forcibly strip any remaining Devanagari. Replace each
        // dropped scalar with empty so we don't end up with double-spaces;
        // the trim/squash at the end normalizes whitespace.
        var scrubbed = ""
        scrubbed.reserveCapacity(transliterated.count)
        for scalar in transliterated.unicodeScalars {
            if (0x0900...0x097F).contains(scalar.value) { continue }
            scrubbed.unicodeScalars.append(scalar)
        }
        let collapsed = scrubbed.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - STT routing (Layer 1 + 3 + 4)

    /// Resolved routing decision for a single transcribe+polish call.
    /// Built from the user's chosen output style — NOT from the
    /// transcription_provider UserDefault, which is a coarse override.
    private struct STTRoute {
        /// Which transcription backend to hit.
        let provider: TranscriptionProvider
        /// Whisper `language` form-field. Empty string means "omit the
        /// param entirely" — letting Whisper auto-detect.
        let language: String
        /// Groq model override. nil = use turbo (English verbatim);
        /// set to `whisper-large-v3` on all multilingual paths.
        let groqModel: String?
        /// Optional polish backend override. nil → respect the user's
        /// PolishBackend.current selection. Set when we want to co-locate
        /// polish on the same provider as STT (e.g. Groq STT + Groq llama
        /// polish saves ~150-300ms cross-provider TLS handshake).
        let polishBackendOverride: PolishBackend?
    }

    /// Decide STT provider + language + polish co-location from the
    /// caller's output style. The ONE place these decisions are made.
    ///
    /// Both Groq and OpenAI support multilingual via Whisper. Groq uses
    /// `whisper-large-v3` on the multilingual paths; turbo stays for the
    /// verbatim path where English is the expected input.
    ///
    /// Style → Route table:
    ///   .clean / .translateEnglish (OpenAI key)  → OpenAI STT, lang=auto, translation polish
    ///   .clean / .translateEnglish (Groq tier)   → Groq large-v3, lang=auto, Groq llama polish (translation)
    ///   .cleanHinglish "Romanized" (OpenAI key)  → OpenAI STT, lang=auto, bilingual → Latin prompt
    ///   .cleanHinglish "Romanized" (Groq tier)   → Groq large-v3, lang=auto, Groq llama polish
    ///   .verbatim "Original"                     → user's provider, user's lang, no polish
    private static func route(
        forStyle style: TranscriptOutputStyle,
        userLanguage: String
    ) -> STTRoute {
        let requestedProvider = TranscriptionProvider.current
        let openAIKey = (UserDefaults.standard.string(forKey: "openai_api_key") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // OpenAI is opt-in. If its key is unavailable, preserve the zero-setup
        // Groq path instead of letting a first transcription fail.
        let provider: TranscriptionProvider =
            requestedProvider == .openai && !openAIKey.isEmpty ? .openai : .groq

        switch style {
        case .clean, .translateEnglish:
            return STTRoute(
                provider: provider,
                language: "",
                groqModel: provider == .groq ? WhisperService.groqMultilingualModel : nil,
                polishBackendOverride: .groq(model: PolishBackend.groqCleanupModel)
            )
        case .cleanHinglish:
            // "Romanized" — any language (Hindi, Marathi, etc.) → Latin script.
            // Whisper auto-detects the source language; polish writes it in
            // English letters without translating meaning.
            return STTRoute(
                provider: provider,
                language: "",
                groqModel: provider == .groq ? WhisperService.groqMultilingualModel : nil,
                polishBackendOverride: .groq(model: PolishBackend.groqCleanupModel)
            )
        case .verbatim:
            return STTRoute(
                provider: provider,
                language: userLanguage,
                groqModel: nil,
                polishBackendOverride: .groq(model: PolishBackend.groqCleanupModel)
            )
        }
    }

    func prepareContextSummaryAsync(_ context: ContextSnapshot?) async -> ContextSnapshot? {
        await withCheckedContinuation { continuation in
            prepareContextSummary(context) { enrichedContext in
                continuation.resume(returning: enrichedContext)
            }
        }
    }

    private func prepareContextSummary(
        _ context: ContextSnapshot?,
        completion: @escaping (ContextSnapshot?) -> Void
    ) {
        guard let context else {
            completion(nil)
            return
        }
        guard context.summary == nil else {
            completion(context)
            return
        }
        guard
            let screenshot = context.screenshot,
            screenshot.status == .captured,
            let imageData = screenshot.imageData
        else {
            completion(context)
            return
        }

        // Context capture starts while the user is speaking, and the
        // transcription pipeline asks for the same summary again on release.
        // Coalesce both callers so one vision request runs and the pipeline
        // waits for its result instead of racing a stale snapshot into Run Log.
        contextSummaryLock.lock()
        if contextSummaryWaiters[context.capturedAt] != nil {
            contextSummaryWaiters[context.capturedAt]?.append(completion)
            contextSummaryLock.unlock()
            return
        }
        contextSummaryWaiters[context.capturedAt] = [completion]
        contextSummaryLock.unlock()

        let finish: ContextSummaryCompletion = { [weak self] enrichedContext in
            guard let self else {
                completion(enrichedContext)
                return
            }
            self.contextSummaryLock.lock()
            let waiters = self.contextSummaryWaiters.removeValue(forKey: context.capturedAt) ?? [completion]
            self.contextSummaryLock.unlock()
            waiters.forEach { $0(enrichedContext) }
        }

        let systemPrompt = """
        You are a context synthesis assistant for a speech-to-text pipeline.
        Given app/window metadata and an optional screenshot, output exactly two sentences that describe what the user is doing right now and the likely writing intent in the current window.
        Prioritize concrete details only from the context: app name, window title, visible recipients, subject/thread cues, document title, terminal/code/text work, active command, file, or topic.
        If details are missing, state uncertainty instead of inventing facts.
        Return only two sentences, no labels, no markdown, no extra commentary.
        """

        let userMessage = """
        [screenshot attached]
        Analyze the screenshot plus metadata to infer current activity.
        App: \(context.frontmostAppName ?? "Unknown")
        Bundle ID: \(context.frontmostBundleID ?? "Unknown")
        Window: \(context.windowTitle ?? "Unknown")
        Surface: \(context.surface.rawValue)
        Selected text: \(context.selection.isEmpty ? "None" : context.selection)
        """
        let promptForLog = Self.debugPrompt(systemPrompt: systemPrompt, userMessage: userMessage)
        let start = CFAbsoluteTimeGetCurrent()

        runVisionChatCompletion(
            systemPrompt: systemPrompt,
            userText: userMessage,
            imageData: imageData
        ) { result in
            let latency = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
            switch result {
            case .success(let summaryText):
                let summary = ContextSummary(
                    model: "groq/\(PolishBackend.groqScreenshotSummaryModel)",
                    prompt: promptForLog,
                    text: summaryText,
                    latencyMs: latency
                )
                finish(context.withSummary(summary))
            case .failure(let error):
                print("Context summary failed, continuing without screenshot summary: \(error.localizedDescription)")
                finish(context)
            }
        }
    }

    private func runVisionChatCompletion(
        systemPrompt: String,
        userText: String,
        imageData: Data,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let backend = PolishBackend.groq(model: PolishBackend.groqScreenshotSummaryModel)
        let apiKey = backend.apiKey()
        guard !apiKey.isEmpty else {
            completion(.failure(WhisperError.noAPIKey))
            return
        }

        var request = URLRequest(url: backend.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let imageURL = "data:image/jpeg;base64,\(imageData.base64EncodedString())"
        let payload: [String: Any] = [
            "model": backend.modelName,
            "temperature": 0.0,
            "reasoning_effort": "none",
            "reasoning_format": "hidden",
            "max_completion_tokens": 180,
            "messages": [
                ["role": "system", "content": systemPrompt],
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": userText],
                        ["type": "image_url", "image_url": ["url": imageURL]]
                    ]
                ]
            ]
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(WhisperError.noData))
                return
            }

            do {
                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let choices = json["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let message = firstChoice["message"] as? [String: Any],
                    let content = message["content"] as? String
                else {
                    if let errorJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorJson["error"] as? [String: Any],
                       let message = errorMessage["message"] as? String {
                        completion(.failure(WhisperError.apiError(message)))
                    } else {
                        completion(.failure(WhisperError.parseError))
                    }
                    return
                }

                completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func runChatCompletion(
        systemPrompt: String,
        userText: String,
        backendOverride: PolishBackend? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // The polish backend is chosen at call-time (not init-time) so users
        // can switch in Settings without restarting the app.
        //
        // `backendOverride` lets the STT routing layer co-locate polish on
        // the same provider as STT (e.g. Groq STT → Groq llama polish saves
        // ~150-300ms of cross-provider TLS handshake). nil = respect user's
        // PolishBackend.current selection.
        let backend = backendOverride ?? PolishBackend.current
        let apiKey = backend.apiKey()
        if backend.requiresAPIKey && apiKey.isEmpty {
            completion(.failure(WhisperError.noAPIKey))
            return
        }

        var request = URLRequest(url: backend.chatCompletionsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Local model inference can be slow on first cold-load; give it headroom.
        request.timeoutInterval = backend.requiresAPIKey ? 30 : 90

        // temperature 0.0: FreeFlow pattern. Cuts drift materially on the
        // polish step where we want the most deterministic transform possible.
        var payload: [String: Any] = [
            "model": backend.modelName,
            "temperature": 0.0,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userText]
            ]
        ]
        if case .groq(let model) = backend, model == PolishBackend.groqCleanupModel {
            payload["reasoning_effort"] = "low"
            payload["reasoning_format"] = "hidden"
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(WhisperError.noData))
                return
            }

            do {
                guard
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let choices = json["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let message = firstChoice["message"] as? [String: Any],
                    let content = message["content"] as? String
                else {
                    if let errorJson = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let errorMessage = errorJson["error"] as? [String: Any],
                       let message = errorMessage["message"] as? String {
                        completion(.failure(WhisperError.apiError(message)))
                    } else {
                        completion(.failure(WhisperError.parseError))
                    }
                    return
                }

                completion(.success(content.trimmingCharacters(in: .whitespacesAndNewlines)))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private func containsDevanagari(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if (0x0900...0x097F).contains(scalar.value) {
                return true
            }
        }
        return false
    }

    /// Detect hallucinations generated by the GPT polish step. Runs on the
    /// LLM's output and cross-references the original Whisper transcript.
    /// Catches three classes of failure:
    ///   1. Output is (or starts with) a known chat-acknowledgment phrase
    ///   2. Output is dramatically longer than input (invention)
    ///   3. Output matches the raw hallucination blocklist (escaped from guard #1)
    private func isLikelyPolishHallucination(
        output: String,
        input: String,
        allowStructuredLists: Bool
    ) -> Bool {
        let out = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return false } // empty is fine — it's what we want

        // Known LLM chat-reply openings. These should NEVER appear in a
        // dictation-cleanup result — they only appear when the model breaks
        // character and responds as an assistant.
        let chatReplyPrefixes = [
            "samajh gaya",
            "samjh gaya",
            "got it",
            "understood",
            "sure,",
            "okay,",
            "ok,",
            "noted",
            "aapka agla",
            "apka agla",
            "send your next",
            "please provide",
            "please share",
            "i understand",
            "i see",
            "kya aap",
            "kripya",
            "i'm sorry",
            "sorry, i"
        ]
        let outLower = out.lowercased()
        for prefix in chatReplyPrefixes {
            if outLower.hasPrefix(prefix),
               !Self.inputAlreadyStartedWithChatPrefix(input, prefix: prefix) {
                return true
            }
        }

        // Pre-polish blocklist still applies to post-polish output.
        if isLikelyHallucination(out) { return true }

        // System-prompt echo — the LLM broke character and regurgitated its
        // own instructions into the completion. Catastrophic if injected.
        if isLikelyPolishSystemPromptEcho(out) { return true }

        // Whisper-prompt echo — the raw Whisper prompt leaking all the way
        // through the polish stage. Shouldn't happen (we also guard upstream)
        // but cheap to double-check at the final gate.
        if Self.isWhisperPromptEcho(out) { return true }

        // Structural chatbot-answer detection (markdown, code fences, answer
        // scaffolding). Runs before length check — these patterns are a
        // hard-fail signal regardless of how short the answer is.
        if looksLikeChatbotAnswer(
            output: out,
            input: input,
            allowStructuredLists: allowStructuredLists
        ) {
            return true
        }

        // Length-divergence heuristic: a proper cleanup should stay close to
        // the input size. Structured output gets extra room for list markers,
        // punctuation, and line breaks without weakening the default guard.
        let inLen = input.trimmingCharacters(in: .whitespacesAndNewlines).count
        let maxFactor = allowStructuredLists ? 3 : 2
        if inLen >= 2 && out.count > max(inLen * maxFactor, inLen + 30) {
            return true
        }

        return false
    }

    /// Prefixes like "I see" and "I understand" can be chatbot tells, but
    /// they are also normal dictated speech. Only treat them as hallucinated
    /// assistant acknowledgments when the speaker did not say that leading
    /// phrase themselves.
    private static func inputAlreadyStartedWithChatPrefix(_ input: String, prefix: String) -> Bool {
        var normalized = input
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        let leadingFillers = ["and ", "so ", "well ", "okay ", "ok ", "like ", "actually ", "basically "]
        var changed = true
        while changed {
            changed = false
            for filler in leadingFillers where normalized.hasPrefix(filler) {
                normalized = String(normalized.dropFirst(filler.count))
                    .trimmingCharacters(in: .whitespaces)
                changed = true
            }
        }

        return normalized.hasPrefix(prefix)
    }

    /// Detect structural tells of an LLM chatbot response: code fences,
    /// headings, answer scaffolding, and lists forbidden by the active Polish
    /// policy. Fail closed on assistant-shaped output while preserving lists
    /// that the user explicitly enabled.
    private func looksLikeChatbotAnswer(
        output: String,
        input: String,
        allowStructuredLists: Bool
    ) -> Bool {
        let outLower = output.lowercased()
        let inLower = input.lowercased()

        // 1. Code fences in output. Allow only if the user explicitly said
        //    something like "triple backtick" or "code fence" in dictation.
        if outLower.contains("```")
            && !inLower.contains("triple backtick")
            && !inLower.contains("code fence")
            && !inLower.contains("backticks") {
            return true
        }

        // 2. Markdown headers (e.g. "# Summary", "## Steps").
        if output.range(of: #"(?m)^#{1,6}\s"#, options: .regularExpression) != nil {
            return true
        }

        // Lists are valid transcript structure only when the active formatting
        // policy permits them. This keeps the safety guard aligned with the UI
        // toggle instead of rejecting output the prompt explicitly requested.
        if PolishFormattingPolicy.rejectsStructuredList(
            output,
            allowStructuredLists: allowStructuredLists
        ) {
            return true
        }

        // 5. Answer-scaffolding prefixes. These phrases are how LLMs introduce
        //    answers — they should never lead a dictation cleanup.
        let answerScaffolds = [
            "here is ", "here's ", "here are ",
            "to do this", "as follows",
            "example:", "example usage",
            "you can use ", "you should "
        ]
        for scaffold in answerScaffolds {
            if outLower.hasPrefix(scaffold) { return true }
        }

        // 6. "Replace X with Y" instructional pattern — common in code answers.
        if outLower.contains("replace ") && outLower.contains(" with ") && outLower.contains("`") {
            return true
        }

        return false
    }

    private func isLikelyHallucination(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet.punctuationCharacters)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if normalized.isEmpty { return true }

        // Exact match against blocklist.
        if hallucinationBlocklist.contains(normalized) { return true }

        // If the entire transcript is just a single short blocklisted phrase
        // (with trailing punctuation variations), drop it.
        for phrase in hallucinationBlocklist where phrase.count >= 3 {
            if normalized == phrase { return true }
            // Transcript is very short AND the blocklisted phrase dominates it.
            if normalized.count <= phrase.count + 5 && normalized.contains(phrase) {
                return true
            }
        }

        // Repetition detector — Whisper can loop on near-silent audio, but
        // real dictation also contains thinking placeholders ("this, this,
        // this") and stutters. Repetition is only a drop signal when the whole
        // transcript is short or low-content; cleanup handles repetition
        // inside otherwise meaningful dictations.
        let words = normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { String($0) }
            .filter { !$0.isEmpty }
        let uniqueWordCount = Set(words).count
        let isVeryLowContent = uniqueWordCount <= 2

        if words.count >= 3 {
            var longestRunWord = words[0]
            var longestRunLength = 1
            var currentRunWord = words[0]
            var currentRunLength = 1

            for word in words.dropFirst() {
                if word == currentRunWord {
                    currentRunLength += 1
                } else {
                    if currentRunLength > longestRunLength {
                        longestRunWord = currentRunWord
                        longestRunLength = currentRunLength
                    }
                    currentRunWord = word
                    currentRunLength = 1
                }
            }
            if currentRunLength > longestRunLength {
                longestRunWord = currentRunWord
                longestRunLength = currentRunLength
            }

            let runRatio = Double(longestRunLength) / Double(words.count)
            if longestRunLength >= 3 && (isVeryLowContent || runRatio >= 0.75) {
                print("Hallucination repetition detected: '\(longestRunWord)' x\(longestRunLength) in short/low-content transcript")
                return true
            }
            if longestRunLength >= 8 && runRatio >= 0.45 {
                print("Hallucination repetition detected: '\(longestRunWord)' x\(longestRunLength) dominates transcript")
                return true
            }
        }

        if words.count >= 5 {
            // Dominance check — same word makes up most of a short/low-content
            // transcript. Long meaningful dictations can contain repeated
            // filler words; those should be cleaned, not dropped.
            var counts: [String: Int] = [:]
            for w in words { counts[w, default: 0] += 1 }
            if let topCount = counts.values.max() {
                let topRatio = Double(topCount) / Double(words.count)
                let topWord = counts.first(where: { $0.value == topCount })?.key ?? "?"
                if words.count <= 12 && isVeryLowContent && topRatio >= 0.5 {
                    print("Hallucination dominance detected: '\(topWord)' = \(topCount)/\(words.count) tokens in short/low-content transcript")
                    return true
                }
            }
        }

        return false
    }

    /// Fast-path predicate — should we skip the polish step entirely?
    ///
    /// Current contract is dead simple: only `.verbatim + dictation` skips
    /// polish. Every other style or mode has an LLM contract that running
    /// raw Whisper output through would violate:
    ///   - `.clean` / `.translateEnglish` — must translate non-English
    ///     input to English. Skipping leaks raw Hindi to the editor.
    ///   - `.cleanHinglish` — must normalize STT's phonetic mis-spellings
    ///     ("nama" → "naam"). Skipping ships drift the user can't undo.
    ///   - `rewrite` / `promptEngineer` — transformation IS the job, even
    ///     for Original.
    ///
    /// Earlier versions had a heuristic-driven "Latin-only + no fillers =
    /// ship verbatim" fast path. That made sense when `.clean` was a pure
    /// English cleanup style; it broke once `.clean` became translation.
    /// We deleted the heuristic rather than maintain it for a path that
    /// no longer exists. If a future style wants it back, restore from
    /// git history — the rationale is preserved there.
    private static func shouldSkipPolish(
        transcript: String,
        style: TranscriptOutputStyle,
        processingMode: TranscriptProcessingMode
    ) -> Bool {
        return style == .verbatim && processingMode == .dictation
    }

    /// Detect the case where Whisper (or the polish LLM) returned our own
    /// prompt text back. Uses a token-overlap heuristic — Whisper sometimes
    /// paraphrases slightly on silent audio rather than echoing verbatim, so
    /// exact-match alone would miss real failures.
    ///
    /// Fires when the output contains a cluster of distinctive phrases from
    /// the prompt. Kept static + deterministic so it's trivial to unit test.
    static func isWhisperPromptEcho(_ text: String) -> Bool {
        let out = text
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty else { return false }

        // Exact / near-exact echo of the Whisper prompt.
        for style in [TranscriptOutputStyle.verbatim, .clean, .cleanHinglish, .translateEnglish] {
            let promptLower = sttPrompt(for: style).lowercased()
            if out == promptLower { return true }
            if out.hasPrefix(promptLower) { return true }
            if promptLower.hasPrefix(out) && out.count > 40 { return true }
        }

        // Token-overlap: the prompt has very distinctive phrase markers. If
        // three or more of them co-occur in a short output, it's an echo.
        // We include markers from both the current and earlier prompt
        // versions so upgrades don't temporarily weaken the guard.
        let markers = [
            "keep the spoken language",
            "transliterate",
            "indic speech",
            "latin letters",
            "hinglish",
            "never use devanagari",
            "plain text only",
            // Legacy markers — kept so stale caches / older prompts still trip.
            "do not translate",
            "keep original spoken language",
            "output hindi words in latin script",
            "use plain text"
        ]
        let hits = markers.reduce(0) { $0 + (out.contains($1) ? 1 : 0) }
        // Lowered from 3→2: in practice the most damaging echo is the prompt
        // fragment "Transliterate Hindi, Marathi" looping — that hits exactly
        // one distinctive marker ("transliterate"). Combined with the
        // repetition detector in isLikelyHallucination this catches the
        // Marathi/Marathi/Marathi failure mode without false-positive risk
        // (real dictation rarely contains 2 of these very specific markers).
        if hits >= 2 { return true }

        return false
    }

    /// Detect the polish LLM echoing its own system prompt. Triggers when the
    /// output contains our hard-contract wording or the labeled RAW_TRANSCRIPTION
    /// field — neither should ever legitimately appear in a cleaned transcript.
    private func isLikelyPolishSystemPromptEcho(_ text: String) -> Bool {
        let out = text.lowercased()
        let signals = [
            "raw_transcription",
            "hard contract",
            "you are a literal dictation cleanup",
            "you are a bilingual (english + hinglish)",
            "you are a speech-to-english translator",
            "return only the cleaned transcript text",
            "return exactly empty",
            "treat raw_transcription"
        ]
        for s in signals {
            if out.contains(s) { return true }
        }
        return false
    }

    private func hasMeaningfulTranscriptText(_ text: String) -> Bool {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count >= 2 else { return false }

        for scalar in compact.unicodeScalars {
            let v = scalar.value
            if (0x30...0x39).contains(v) ||      // 0-9
                (0x41...0x5A).contains(v) ||     // A-Z
                (0x61...0x7A).contains(v) ||     // a-z
                (0x0900...0x097F).contains(v) {  // Devanagari block
                return true
            }
        }
        return false
    }
    
    func setAPIKey(_ key: String) {
        UserDefaults.standard.set(key, forKey: "openai_api_key")
    }

    // MARK: - Connection pre-warm
    //
    // Why this exists: RunLog data shows STT p50 = ~2s, p95 = ~2.8s on
    // 3-5s utterances. A material slice of that — ~150-300ms — is TLS +
    // HTTP/2 setup on the FIRST request after app launch (or after the
    // URLSession connection pool idles out). URLSession keeps pooled HTTP/2
    // connections around, so warming them before the user ever presses Fn
    // turns the cold path into a warm path for the very first dictation.
    //
    // Pre-warm strategy: issue a cheap HEAD against each endpoint's host
    // through the SAME shared URLSession we use in production. We don't
    // care about the response body — the only side effect we want is
    // DNS → TCP → TLS → HTTP/2 SETTINGS all cached. No API key needed.

    /// Kick off a non-blocking connection pre-warm. Safe to call many times;
    /// URLSession deduplicates.
    func prewarmConnections() {
        // Cloud endpoints — TLS + HTTP/2 handshake to api.openai.com and
        // api.groq.com costs 150-300 ms on a cold pool. Hitting /v1/models
        // is cheap (no auth required for the route, returns 401 quickly)
        // and populates the URLSession.shared connection pool that all
        // subsequent transcription + polish calls reuse.
        //
        // We hit BOTH /v1/models (transcription endpoint family) and
        // /v1/chat/completions (polish endpoint family) because some
        // edge-routing setups segregate connections per route prefix.
        // Hit both /models (warms STT + TLS) and /chat/completions
        // (warms polish endpoint pool — separate route family that
        // some edge proxies don't share with /models). For Groq we
        // also explicitly include /chat/completions because that's
        // where Groq Llama polish calls land.
        let cloudHosts = [
            "https://api.openai.com/v1/models",
            "https://api.openai.com/v1/chat/completions",
            "https://api.groq.com/openai/v1/models",
            "https://api.groq.com/openai/v1/chat/completions"
        ]
        for host in cloudHosts {
            guard let url = URL(string: host) else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 5
            URLSession.shared.dataTask(with: req) { _, _, _ in
                // Intentional empty handler — we only want the side effect
                // of populating the connection pool.
            }.resume()
        }

        // Local backends — only prewarm if the user is actually configured
        // to use one. LM Studio + Ollama don't need TLS handshake (HTTP) but
        // the FIRST request loads the model into memory, which on cold-start
        // takes 5-30s. A prewarm GET against /v1/models forces the load
        // ahead of the user's first dictation, so the actual polish call
        // hits a hot model.
        let backendId = PolishBackend.current.id
        if backendId.hasPrefix("lmstudio::") {
            prewarmLocalEndpoint("http://127.0.0.1:1234/v1/models")
        } else if backendId.hasPrefix("ollama::") {
            prewarmLocalEndpoint("http://127.0.0.1:11434/api/tags")
        }
    }

    private func prewarmLocalEndpoint(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = 3
        URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
    }
}

/// Metadata captured during a transcription pipeline run, for RunLog observability.
struct TranscriptionMetadata {
    let provider: String              // e.g. "openai/gpt-4o-transcribe"
    let rawText: String
    let transcriptionLatencyMs: Int
    let postProcessMode: String?      // "dictation" / "rewrite"
    let postProcessStyle: String?     // "verbatim" / "clean" / "clean_hinglish"
    let postProcessModel: String?     // "gpt-4.1-mini"
    let postProcessPrompt: String?    // full system prompt
    let finalText: String
    let postProcessLatencyMs: Int
    let languageGuardTriggered: Bool
    let context: ContextSnapshot?

    init(
        provider: String,
        rawText: String,
        transcriptionLatencyMs: Int,
        postProcessMode: String?,
        postProcessStyle: String?,
        postProcessModel: String?,
        postProcessPrompt: String?,
        finalText: String,
        postProcessLatencyMs: Int,
        languageGuardTriggered: Bool,
        context: ContextSnapshot? = nil
    ) {
        self.provider = provider
        self.rawText = rawText
        self.transcriptionLatencyMs = transcriptionLatencyMs
        self.postProcessMode = postProcessMode
        self.postProcessStyle = postProcessStyle
        self.postProcessModel = postProcessModel
        self.postProcessPrompt = postProcessPrompt
        self.finalText = finalText
        self.postProcessLatencyMs = postProcessLatencyMs
        self.languageGuardTriggered = languageGuardTriggered
        self.context = context
    }
}

enum WhisperError: LocalizedError {
    case noAPIKey
    case invalidURL
    case noData
    case parseError
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No OpenAI API key configured"
        case .invalidURL:
            return "Invalid API URL"
        case .noData:
            return "No data received from API"
        case .parseError:
            return "Failed to parse response"
        case .apiError(let message):
            return "API Error: \(message)"
        }
    }
}
