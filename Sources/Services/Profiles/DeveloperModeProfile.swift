import Foundation

/// "voiceflow create" handler — turns "voiceflow create bash script that
/// does X" into an executable bash script (or SQL, or regex, or prompt)
/// pasted into the user's editor.
///
/// **Architecture choice**: ONE LLM call, not agentic. The agentic path
/// lives in `AgenticOrchestrator` and is gated behind a separate user
/// toggle (Phase 4 A/B). Single-call wins on latency by ~1.5s and is
/// the right default; agentic wins on quality for ambiguous prompts.
///
/// **Output discipline**: the system prompt is aggressive about "OUTPUT
/// THE ARTIFACT, NOTHING ELSE". LLMs love to wrap code in markdown fences
/// and add explanatory preambles — both ruin the paste. We post-process
/// to strip remaining ```fences``` defensively.
///
/// **Privacy posture**: when the user has a selection captured, that text
/// is sent to the LLM as context. Selection capture itself is opt-in
/// (ContextProvider.isClipboardSelectionEnabled), and we surface a
/// "Privacy" badge in the run-log row when selection was sent.
final class DeveloperModeProfile: TransformerProfile {
    let kind: ProfileKind = .developerMode
    let displayLabel = ProfileKind.developerMode.displayLabel

    private let llm: LLMService
    /// Hard-coded backend override for dev mode. Even if the user picked
    /// llama for polish, dev-mode wants the better instruction-follower
    /// for code generation. Falls back to user choice if no OpenAI key.
    private let preferredBackend: PolishBackend?

    init(llm: LLMService = .shared, preferredBackend: PolishBackend? = nil) {
        self.llm = llm
        self.preferredBackend = preferredBackend ?? Self.defaultBackend()
    }

    /// Pick the best backend automatically: OpenAI gpt-4.1-mini if the
    /// user has a key, else fall back to whatever they're using for polish.
    static func defaultBackend() -> PolishBackend? {
        let openAIKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        guard !openAIKey.isEmpty else { return nil }
        return .openai(model: "gpt-4.1-mini")
    }

    func transform(
        _ input: TransformerInput,
        completion: @escaping (Result<TransformerOutput, Error>) -> Void
    ) {
        let stripped = input.triggerStripped
        guard !stripped.isEmpty else {
            // User said only "voiceflow create" with nothing after.
            // Return a deterministic stub — better than a useless API call.
            let output = TransformerOutput(
                finalText: "",
                summary: "Dev mode: empty request — nothing generated",
                modelUsed: nil,
                costUSD: 0,
                llmLatencyMs: 0,
                usedAgentic: false,
                trace: ["Profile: developer mode", "Empty request after trigger strip"]
            )
            completion(.success(output))
            return
        }

        let systemPrompt = Self.buildSystemPrompt(context: input.context)
        let userMessage = Self.buildUserMessage(request: stripped, context: input.context)

        let request = LLMRequest(
            messages: [
                LLMMessage(role: .system, content: systemPrompt),
                LLMMessage(role: .user, content: userMessage)
            ],
            backendOverride: preferredBackend,
            temperature: 0.1,                 // a hair above 0 — small flexibility for code that's "right but different"
            maxTokens: 1500,
            maxAttempts: 2,
            tools: [],
            purpose: "dev_mode_create"
        )

        llm.complete(request: request) { result in
            switch result {
            case .success(let response):
                let cleaned = Self.stripCodeFences(response.content)
                let trace: [String] = [
                    "Profile: developer mode",
                    "Active app: \(input.context.frontmostAppName ?? "(unknown)")",
                    "Surface: \(input.context.surface.rawValue)",
                    "Selection: \(input.context.selection.isEmpty ? "(none)" : "\(input.context.selection.count) chars from \(input.context.selectionSource.rawValue)")",
                    "Backend: \(self.preferredBackend?.displayLabel ?? PolishBackend.current.displayLabel)",
                    "Model: \(response.model)",
                    "Tokens: in \(response.inputTokens), out \(response.outputTokens)",
                    String(format: "Cost: $%.5f", response.costUSD),
                ]
                let output = TransformerOutput(
                    finalText: cleaned,
                    summary: "Dev mode: \"\(stripped.prefix(60))…\"",
                    modelUsed: response.model,
                    costUSD: response.costUSD,
                    llmLatencyMs: response.latencyMs,
                    usedAgentic: false,
                    trace: trace
                )
                completion(.success(output))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    // MARK: - Prompt construction

    /// Returns the system prompt. Stable across requests — only the
    /// surface-specific hint varies. We keep it terse to leave room for
    /// long selections.
    static func buildSystemPrompt(context: ContextSnapshot) -> String {
        let surfaceHint = surfaceSpecificHint(context.surface)
        return """
        You are a code generation assistant inside a macOS dictation app.
        The user dictates a request; you output ONLY the artifact requested.

        Output discipline:
        - No preamble, no explanation, no markdown fences (no ``` blocks).
        - No "Sure, here's…" or "Here is the…" prefixes.
        - No trailing comments unless the user asked for explanation.
        - The output is pasted directly into the user's active text field.

        Detect the artifact type from the request: bash command, shell script,
        regex, SQL query, prompt, code snippet, JSON, YAML, etc.

        \(surfaceHint)
        """
    }

    /// Surface hint nudges the model toward the dialect of the focused app.
    /// e.g. when the user is in BigQuery, prefer Standard SQL (not MySQL).
    static func surfaceSpecificHint(_ surface: AppSurface) -> String {
        switch surface {
        case .ide:
            return "The user is in an IDE — prefer code over prose. Use the language hinted by the selection if any."
        case .terminal:
            return "The user is in a terminal — prefer single-line shell commands when possible. Use bash unless the selection suggests zsh/fish."
        case .database:
            return "The user is in a database client — output SQL only. Detect dialect from selection (Postgres/MySQL/BigQuery/SQLite)."
        case .browser:
            return "The user is in a browser — they may be in a web-based IDE (BigQuery console, Supabase SQL editor, etc.) or a chat. Match the surrounding selection's language."
        case .chat, .mail:
            return "The user is in a chat/mail surface — prefer prose unless the request is explicitly for code."
        case .notes, .office:
            return "The user is in a document — prefer prose with code blocks where natural."
        case .design, .unknown:
            return "Best-guess the artifact from the request alone."
        }
    }

    static func buildUserMessage(request: String, context: ContextSnapshot) -> String {
        var sections: [String] = []
        sections.append("REQUEST:")
        sections.append(request)

        if !context.selection.isEmpty {
            sections.append("")
            sections.append("SELECTION (currently selected text in user's editor):")
            sections.append(context.selection)
        }

        if let bundleID = context.frontmostBundleID {
            sections.append("")
            sections.append("ACTIVE APP: \(context.frontmostAppName ?? bundleID) (\(bundleID))")
        }

        return sections.joined(separator: "\n")
    }

    /// LLMs sometimes wrap output in markdown despite explicit instructions.
    /// Strip if the entire output is a single ``` fenced block.
    static func stripCodeFences(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Match ``` or ```lang at start, ``` at end. Be careful not to
        // strip fences from inside legitimate multi-block output (rare for
        // dev-mode but happens — keep those intact).
        guard t.hasPrefix("```") && t.hasSuffix("```") else { return t }

        // Drop everything up to the first newline (the "```bash" header).
        if let newline = t.firstIndex(of: "\n") {
            t = String(t[t.index(after: newline)...])
        } else {
            // Single-line ```...``` — strip the back-ticks themselves.
            t = String(t.dropFirst(3).dropLast(3))
        }
        // Drop the trailing ```.
        if t.hasSuffix("```") {
            t = String(t.dropLast(3))
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
