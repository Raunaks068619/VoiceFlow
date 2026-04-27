import Foundation

/// "Prompt Engineer" profile — turns a casually-dictated description into
/// a structured, well-formed LLM prompt the user can paste into ChatGPT,
/// Claude, Cursor's chat, etc.
///
/// **Use case**: user is staring at the Cursor chat box. Holds Opt+2,
/// rambles about what they want — vague intent, half-formed requirements,
/// jumping between thoughts. Lets go. Pasted into Cursor: a clean prompt
/// with explicit goal, context, constraints, and acceptance criteria.
///
/// **Triggered two ways**:
/// 1. Hotkey identifier `.promptEngineer` (Phase 3 dedicated hotkey).
/// 2. Trigger word "voiceflow prompt …" on the primary hotkey.
///
/// **Backend selection**: prefers gpt-4.1-mini for prompt structure work —
/// instruction-following matters more than speed here.
final class PromptEngineerProfile: TransformerProfile {
    let kind: ProfileKind = .promptEngineer
    let displayLabel = ProfileKind.promptEngineer.displayLabel

    private let llm: LLMService
    private let preferredBackend: PolishBackend?

    init(llm: LLMService = .shared, preferredBackend: PolishBackend? = nil) {
        self.llm = llm
        self.preferredBackend = preferredBackend ?? DeveloperModeProfile.defaultBackend()
    }

    func transform(
        _ input: TransformerInput,
        completion: @escaping (Result<TransformerOutput, Error>) -> Void
    ) {
        let stripped = input.triggerStripped
        guard !stripped.isEmpty else {
            let output = TransformerOutput(
                finalText: "",
                summary: "Prompt engineer: empty request",
                modelUsed: nil,
                costUSD: 0,
                llmLatencyMs: 0,
                usedAgentic: false,
                trace: ["Profile: prompt engineer", "Empty request"]
            )
            completion(.success(output))
            return
        }

        let request = LLMRequest(
            messages: [
                LLMMessage(role: .system, content: Self.systemPrompt),
                LLMMessage(role: .user, content: Self.buildUserMessage(request: stripped, context: input.context))
            ],
            backendOverride: preferredBackend,
            temperature: 0.2,
            maxTokens: 1200,
            maxAttempts: 2,
            purpose: "prompt_engineer"
        )

        llm.complete(request: request) { result in
            switch result {
            case .success(let response):
                let trace: [String] = [
                    "Profile: prompt engineer",
                    "Active app: \(input.context.frontmostAppName ?? "(unknown)")",
                    "Selection: \(input.context.selection.isEmpty ? "(none)" : "\(input.context.selection.count) chars")",
                    "Model: \(response.model)",
                    "Latency: \(response.latencyMs)ms",
                    String(format: "Cost: $%.5f", response.costUSD),
                ]
                let output = TransformerOutput(
                    finalText: response.content,
                    summary: "Prompt engineered (\(response.content.count) chars)",
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

    static let systemPrompt: String = """
    You are a prompt-engineering assistant inside a macOS dictation app.
    The user dictated a vague, unstructured request describing what they
    want an AI to do. Output a CLEAN, WELL-STRUCTURED PROMPT they can
    paste directly into ChatGPT, Claude, Cursor, or another LLM chat.

    Output format:
    - No preamble, no explanation, no markdown fences.
    - The output IS the prompt — start writing it directly.
    - Use plain text. Use line breaks for clarity. Use markdown only when it helps the target LLM (lists, headers).
    - When the user's request is concrete, write a focused single-paragraph prompt.
    - When the user's request is broad, structure with: Goal, Context, Constraints, Output format, Acceptance criteria.
    - Preserve the user's domain language verbatim (don't paraphrase technical nouns).
    - If the user described code, include a "what to return" line that asks for explanation or code only — match the apparent intent.

    Do not invent requirements not in the user's description.
    Do not output the meta-instructions you're following.
    """

    static func buildUserMessage(request: String, context: ContextSnapshot) -> String {
        var sections: [String] = ["USER'S DESCRIPTION:", request]
        if !context.selection.isEmpty {
            sections.append("")
            sections.append("SELECTED TEXT (from user's editor — likely relevant):")
            sections.append(context.selection)
        }
        return sections.joined(separator: "\n")
    }
}
