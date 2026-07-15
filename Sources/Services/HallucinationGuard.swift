import Foundation

/// The single, mandatory gate every transcript passes through before
/// becoming injected text. Pure functions, sub-millisecond, no I/O.
///
/// **Why this exists**: Whisper hallucinates on near-silent audio,
/// background noise, and unfamiliar accents. The hallucinations are
/// well-documented "training-set artifacts" — phrases pulled from
/// YouTube subtitle data that Whisper saw thousands of times next to
/// silence at the end of videos. Examples we hit in v0.4.1 logs:
///   • "Plain text only."
///   • "out of there."
///   • "All right."
///   • "Won't let go of your silverware Việt recon?"
/// All produced from <1s of microphone-on, no-actual-voice audio.
///
/// **Three layers of detection** (any one firing → drop):
///
///   1. PHANTOM PHRASES — exact / near-exact matches against a static
///      blocklist of known Whisper training artifacts. Sourced from
///      community corpora (sachaarbonel/whisper-hallucinations on
///      Hugging Face) + our own production logs.
///
///   2. CONFIDENCE SIGNALS — Whisper's own self-doubt scores from the
///      `verbose_json` response format. `no_speech_prob > 0.6` says
///      "this is probably silence even though I made up text for it";
///      `avg_logprob < -1.0` says "I'm guessing"; `compression_ratio
///      > 2.4` says "I'm looping ('the the the the')".
///
///   3. STRUCTURAL HEURISTICS — outputs that don't look like real
///      dictation: too few alphanumerics, single short OOV word,
///      heavy non-ASCII punctuation, exact-prompt-echo.
///
/// **Why hard-coded thresholds vs. ML classifier**: a classifier
/// would need training data we don't have. The thresholds below come
/// from OpenAI's own Whisper repo recommendations + Spheron's 2026
/// production guide. They're conservative; tuning lower means missing
/// real speech, tuning higher means leaking hallucinations. We bias
/// slightly toward "drop more" because the user-experience cost of a
/// dropped legit dictation (re-record) is far smaller than injecting
/// a phantom paragraph into someone's editor.
///
/// **Speed**: every call is O(N) over the transcript length where N
/// is at most a few hundred chars. Phantom-phrase scan is bounded by
/// the blocklist size (~150). Total runtime: well under 1ms even on
/// older Macs. No reason to skip it on any path, ever.
enum HallucinationGuard {

    // MARK: - Public API

    /// Confidence signals extracted from a Whisper `verbose_json`
    /// response. Average across all segments. nil values mean the
    /// signal wasn't available (e.g. older API or basic `json` format).
    struct Confidence {
        let noSpeechProb: Double?
        let avgLogprob: Double?
        let compressionRatio: Double?

        static let empty = Confidence(noSpeechProb: nil, avgLogprob: nil, compressionRatio: nil)
    }

    /// Decision returned to callers. `reason` is purely for logging /
    /// run-log diagnostics — it's never user-facing.
    struct Decision {
        let shouldDrop: Bool
        let reason: String?
    }

    /// Run all three layers of detection.
    ///
    /// - Parameters:
    ///   - text: the transcript candidate (post-STT, pre-injection).
    ///   - confidence: Whisper's self-reported confidence signals from
    ///     `verbose_json`. Pass `.empty` if unavailable — the phantom
    ///     phrase + structural layers still run.
    ///   - hadVoicedAudio: whether the upstream RMS gate detected any
    ///     voiced buffers. When false, ANY non-empty output is by
    ///     definition a hallucination — kill it.
    ///   - polishWillRun: when true, the polish LLM will transliterate
    ///     non-Latin output downstream — so we shouldn't drop on the
    ///     "unsupported script" signal here. Used by `.cleanHinglish`
    ///     and `.clean` paths where the bilingual normalizer / translator
    ///     can repair Arabic-script Hindi or other STT mis-script output.
    /// - Returns: a Decision; if `shouldDrop`, the caller MUST replace
    ///   the transcript with empty before any injection or display.
    static func evaluate(
        text: String,
        confidence: Confidence = .empty,
        hadVoicedAudio: Bool = true,
        polishWillRun: Bool = false
    ) -> Decision {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // An already-empty transcript is the trivial "good" case — we
        // simply don't have anything to inject. Don't flag it as a
        // drop; that wording is reserved for "we had something but
        // we're killing it."
        if trimmed.isEmpty {
            return Decision(shouldDrop: false, reason: nil)
        }

        // No voiced audio + non-empty output = guaranteed hallucination.
        // The upstream noise gate said the user didn't speak; STT
        // produced text anyway → it's invented.
        if !hadVoicedAudio {
            return Decision(shouldDrop: true, reason: "no voiced audio reached STT")
        }

        // Layer 1: phantom phrase blocklist. These are exact matches
        // against known training-set artifacts — high-confidence drops.
        if let phrase = phantomMatch(trimmed) {
            return Decision(shouldDrop: true, reason: "phantom phrase: \(phrase)")
        }

        // Layer 2: Whisper confidence signals.
        //
        // CRITICAL: drop only when MULTIPLE signals agree. Earlier
        // versions dropped on any single signal — that killed legitimate
        // short utterances (e.g. "hello mic check" sometimes scores
        // no_speech_prob=0.77 because Whisper is uncertain about a 1-2s
        // clip even when the words are perfectly recognized). OpenAI's
        // own decoder algorithm uses AND between no_speech_prob and
        // avg_logprob — neither alone is enough.
        //
        // Compression ratio (looping detection) IS standalone-actionable
        // because Whisper looping ("the the the the") is unambiguous.
        let highNoSpeech = (confidence.noSpeechProb ?? 0) > Thresholds.noSpeechProb
        let lowLogprob = (confidence.avgLogprob ?? 0) < Thresholds.avgLogprob
        if highNoSpeech && lowLogprob {
            return Decision(
                shouldDrop: true,
                reason: "no_speech_prob=\(String(format: "%.2f", confidence.noSpeechProb ?? 0)) AND avg_logprob=\(String(format: "%.2f", confidence.avgLogprob ?? 0)) (both bad)"
            )
        }
        if let cr = confidence.compressionRatio, cr > Thresholds.compressionRatio {
            return Decision(
                shouldDrop: true,
                reason: "compression_ratio=\(String(format: "%.2f", cr)) > \(Thresholds.compressionRatio) (likely looping)"
            )
        }

        // gpt-4o transcribe path: confidence is per-token logprobs only, so the
        // no_speech AND-gate above can NEVER fire (no_speech_prob is nil). Apply
        // a conservative standalone logprob floor instead. Keyed on
        // `noSpeechProb == nil` so the whisper / Groq verbose_json path (which
        // always carries a no_speech_prob) is completely unaffected. The
        // threshold is deliberately stricter than the whisper avg_logprob
        // (-1.0) because per-token logprobs sit much closer to 0 for confident
        // output — this only catches egregiously uncertain transcription.
        if confidence.noSpeechProb == nil,
           let lp = confidence.avgLogprob,
           lp < Thresholds.gpt4oAvgLogprob {
            return Decision(
                shouldDrop: true,
                reason: "gpt-4o avg per-token logprob=\(String(format: "%.2f", lp)) < \(Thresholds.gpt4oAvgLogprob) (low confidence)"
            )
        }

        // Layer 3: structural heuristics. Skip the "unsupported script"
        // sub-check when the polish step will run — for `.cleanHinglish`
        // and `.clean` paths, the LLM can transliterate any script to
        // Latin / English. We only catch raw-non-Latin output as a
        // hallucination signal on the verbatim path where there's no
        // polish to repair it.
        if let reason = structuralIssue(trimmed, allowNonLatin: polishWillRun) {
            return Decision(shouldDrop: true, reason: "structural: \(reason)")
        }

        return Decision(shouldDrop: false, reason: nil)
    }

    // MARK: - Thresholds

    /// Tuned per OpenAI Whisper repo guidance + production reports.
    /// Bias is slightly aggressive (drop more) because injecting a
    /// hallucinated sentence into the user's editor is materially
    /// worse than asking them to re-dictate.
    enum Thresholds {
        /// Drop when Whisper says "this segment is probably silence."
        /// Whisper itself defaults to 0.6 — we match.
        static let noSpeechProb: Double = 0.6
        /// Drop when Whisper's own per-token confidence average is
        /// below this. -1.0 catches most hallucinations; -0.5 would
        /// catch more but also drops some legit accented speech.
        static let avgLogprob: Double = -1.0
        /// Compression ratio of input → token output. >2.4 means the
        /// model is repeating itself ("the the the the").
        static let compressionRatio: Double = 2.4
        /// Standalone avg-logprob floor for the gpt-4o transcribe path, whose
        /// confidence comes from per-token logprobs (not whisper segments) and
        /// so can't use the no_speech AND-gate. Per-token logprobs sit close to
        /// 0 for confident output, so this is stricter than `avgLogprob` (-1.0)
        /// and only fires on egregiously uncertain output. Conservative on
        /// purpose — TUNE against real gpt-4o run-logs before tightening.
        static let gpt4oAvgLogprob: Double = -1.6
        /// Minimum alphanumeric character count. Below this we treat
        /// the output as junk regardless of other signals — Whisper
        /// often emits a single OOV token on noise.
        static let minAlphaNumChars: Int = 3
    }

    // MARK: - Layer 1: phantom phrases
    //
    // Sourced from the public Whisper-hallucinations dataset on Hugging
    // Face + our own logs. Strings are matched case-insensitively after
    // trim. Shorter generic phrases ("you", "okay") are intentionally
    // EXCLUDED from this list — they'd false-positive on real one-word
    // dictations. We instead rely on the structural-heuristics layer
    // for those.
    //
    // Add new phantoms here as you spot them in run-logs.

    private static let phantomPhrases: [String] = [
        // YouTube subtitle artifacts
        "thanks for watching",
        "thanks for watching!",
        "thank you for watching",
        "thank you for watching.",
        "thanks for watching this video",
        "subscribe and like",
        "please like and subscribe",
        "don't forget to subscribe",
        "if you enjoyed this video",
        "see you in the next video",
        "see you next time",

        // Subtitle-credit phantoms
        "subtitles by the amara org community",
        "subtitles by the amara.org community",
        "subtitle by ai-media",
        "subtitled by ai-media",
        "transcription by",
        "transcript emily beynon",
        "captions by",
        "subs by",
        "subtitle by",

        // Filler / closing phantoms
        "i'll see you in the next one",
        "see you guys later",
        "alright guys",
        "all right guys",
        "let's get started",

        // Real production-log phantoms (your scratchpad)
        "won't let go of your silverware",
        "plain text only.",
        "plain text only",
        "out of there.",
        "out of there",
        "transュwoc",                  // garbled non-Latin-Latin mash
        "transュwoc,",
        "st studio to mention",      // first words of a long phantom paragraph

        // Generic non-speech filler tokens
        "...",
        "[music]",
        "[silence]",
        "[noise]",
        "[applause]",
        "(music)",
        "(silence)",
        "(noise)",
    ]

    /// Normalize-and-match against the phantom phrase list. Returns
    /// the matched phrase for logging, or nil if no match.
    private static func phantomMatch(_ trimmed: String) -> String? {
        let lower = trimmed.lowercased()
        // Exact + prefix match — phantoms are usually the entire
        // utterance OR appended after real speech. We catch both with
        // a hasPrefix check, which is also cheaper than substring scan.
        for phrase in phantomPhrases {
            if lower == phrase { return phrase }
            if lower.hasPrefix(phrase + " ") || lower.hasPrefix(phrase + ".") || lower.hasPrefix(phrase + ",") {
                return phrase
            }
        }
        // Special case: phantoms appearing ANYWHERE in the text (real speech
        // with a subtitle artifact appended). This pass runs ONLY over
        // `substringSafePhantoms` — unambiguous training artifacts no one
        // dictates. We deliberately do NOT substring-match conversational
        // phantoms like "let's get started" or "all right guys": users say
        // those mid-sentence, and matching them anywhere was discarding real
        // transcripts wholesale.
        for phrase in substringSafePhantoms {
            if lower.contains(" " + phrase) || lower.contains(phrase + " ") {
                return phrase
            }
        }
        return nil
    }

    /// Subset of `phantomPhrases` safe to match anywhere in the transcript.
    /// These are YouTube/subtitle credits and known garbled artifacts that
    /// never occur inside genuine dictation — so an interior match is always
    /// a hallucination, not a false positive on real speech.
    private static let substringSafePhantoms: [String] = [
        "thanks for watching",
        "thank you for watching",
        "thanks for watching this video",
        "please like and subscribe",
        "don't forget to subscribe",
        "subtitles by the amara org community",
        "subtitles by the amara.org community",
        "subtitle by ai-media",
        "subtitled by ai-media",
        "transcript emily beynon",
        "won't let go of your silverware",
        "st studio to mention",
    ]

    // MARK: - Layer 3: structural heuristics

    /// Returns a non-nil reason string when the output looks structurally
    /// broken. nil = passes the structural gate.
    ///
    /// `allowNonLatin` skips the unsupported-script check when the polish
    /// step downstream can transliterate (e.g. on .cleanHinglish path,
    /// the bilingual normalizer LLM transliterates Arabic-script Hindi
    /// → Latin Hinglish). Verbatim path passes false — there's no polish
    /// to repair non-Latin output.
    private static func structuralIssue(_ trimmed: String, allowNonLatin: Bool) -> String? {
        // Count letter/digit characters from any Unicode script — earlier
        // versions only counted Latin + Devanagari, which dropped Arabic-
        // script Hindi (Whisper sometimes outputs Urdu script for
        // ambiguous Hindi audio) as "0 alphanumeric chars" even though
        // it's perfectly valid speech the polish step can transliterate.
        let alphaNumCount = trimmed.unicodeScalars.filter { scalar in
            // Unicode general categories: L (any letter) + N (any number).
            switch scalar.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter,
                 .modifierLetter, .otherLetter,
                 .decimalNumber, .letterNumber, .otherNumber:
                return true
            default:
                return false
            }
        }.count
        if alphaNumCount < Thresholds.minAlphaNumChars {
            return "only \(alphaNumCount) alphanumeric chars"
        }

        // Repetition detector: if a single 3-gram appears more than 4
        // times, Whisper is looping. Cheap n-gram scan.
        if isLooping(trimmed) {
            return "n-gram looping detected"
        }

        // Heavy non-Latin script. Skip when polish can transliterate.
        if !allowNonLatin && hasUnsupportedScript(trimmed) {
            return "non-supported script in output"
        }

        return nil
    }

    /// Detect Whisper's classic looping pattern (e.g. "the the the the").
    /// Splits on whitespace, walks 3-grams, drops if any 3-gram appears
    /// more than `maxRepeats` times.
    private static func isLooping(_ text: String, maxRepeats: Int = 4) -> Bool {
        let words = text.lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0.isPunctuation })
            .map(String.init)
        guard words.count >= maxRepeats * 3 else { return false }

        var trigramCount: [String: Int] = [:]
        for i in 0..<(words.count - 2) {
            let key = "\(words[i])|\(words[i+1])|\(words[i+2])"
            trigramCount[key, default: 0] += 1
            if trigramCount[key]! > maxRepeats {
                return true
            }
        }
        return false
    }

    /// True when text contains scalar values from scripts we don't
    /// support in the dictation pipeline. Vietnamese (Latin Extended +
    /// combining marks above 0x1EA0) IS technically Latin, but Whisper
    /// only emits it when hallucinating (we never speak Vietnamese
    /// here), so we treat it as a hallucination signal.
    ///
    /// Specifically blocks: CJK (0x4E00–0x9FFF), Arabic (0x0600–0x06FF),
    /// Hebrew (0x0590–0x05FF), Cyrillic (0x0400–0x04FF), Greek (0x0370–0x03FF),
    /// Vietnamese diacritics (0x1EA0–0x1EFF — Latin Extended Additional).
    private static func hasUnsupportedScript(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x0370...0x03FF).contains(v) { return true } // Greek
            if (0x0400...0x04FF).contains(v) { return true } // Cyrillic
            if (0x0590...0x05FF).contains(v) { return true } // Hebrew
            if (0x0600...0x06FF).contains(v) { return true } // Arabic
            if (0x1EA0...0x1EFF).contains(v) { return true } // Vietnamese diacritics
            if (0x4E00...0x9FFF).contains(v) { return true } // CJK Unified
            if (0x3040...0x309F).contains(v) { return true } // Hiragana
            if (0x30A0...0x30FF).contains(v) { return true } // Katakana
        }
        return false
    }
}
