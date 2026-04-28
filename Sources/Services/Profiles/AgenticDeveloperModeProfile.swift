import Foundation

/// Agentic version of DeveloperModeProfile — gives the LLM tools it can
/// call to build a more deliberate response.
///
/// **Tool surface** (intentionally tiny):
/// - `get_selection()`           → returns the currently-selected text
/// - `get_active_app()`          → returns bundle ID + app name + surface
/// - `detect_artifact_type(req)` → asks the model to commit to a type
/// - `inspect_for_dialect(text)` → returns SQL/lang dialect heuristics
///
/// We pass the selection + app already-resolved in the system prompt, so
/// in practice the model rarely needs to call them. They exist primarily
/// as an A/B baseline against the single-call profile — does giving the
/// model the OPTION to call them improve quality, even if it usually
/// doesn't?
///
/// **Loop bounds**: max 4 tool-use turns. Past that we force a final
/// answer with a synthetic "now produce the artifact" message.
final class AgenticDeveloperModeProfile: TransformerProfile {
    let kind: ProfileKind = .agentic
    let displayLabel = ProfileKind.agentic.displayLabel

    private let llm: LLMService
    private let preferredBackend: PolishBackend?
    static let maxToolTurns = 4

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
            completion(.success(TransformerOutput(
                finalText: "",
                summary: "Agentic dev mode: empty request",
                modelUsed: nil,
                costUSD: 0,
                llmLatencyMs: 0,
                usedAgentic: true,
                trace: ["Profile: agentic dev mode", "Empty request"]
            )))
            return
        }

        let messages: [LLMMessage] = [
            LLMMessage(role: .system, content: Self.systemPrompt(context: input.context)),
            LLMMessage(role: .user, content: DeveloperModeProfile.buildUserMessage(
                request: stripped,
                context: input.context
            ))
        ]

        runLoop(
            messages: messages,
            context: input.context,
            stripped: stripped,
            turnsRemaining: Self.maxToolTurns,
            cumulativeCost: 0,
            cumulativeLatency: 0,
            trace: ["Profile: agentic dev mode"],
            completion: completion
        )
    }

    // MARK: - Loop

    private func runLoop(
        messages: [LLMMessage],
        context: ContextSnapshot,
        stripped: String,
        turnsRemaining: Int,
        cumulativeCost: Double,
        cumulativeLatency: Int,
        trace: [String],
        completion: @escaping (Result<TransformerOutput, Error>) -> Void
    ) {
        // Out of turns — force a final answer. This is a safety belt so
        // the loop can't run forever on a tool-happy model.
        let forceFinal = turnsRemaining <= 0
        var convo = messages
        if forceFinal {
            convo.append(LLMMessage(
                role: .user,
                content: "Stop calling tools. Output the artifact now, no preamble, no fences."
            ))
        }

        let request = LLMRequest(
            messages: convo,
            backendOverride: preferredBackend,
            temperature: 0.1,
            maxTokens: 2000,
            maxAttempts: 2,
            tools: forceFinal ? [] : Self.tools,
            purpose: "agentic_dev_mode"
        )

        llm.complete(request: request) { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let err):
                completion(.failure(err))

            case .success(let response):
                let cost = cumulativeCost + response.costUSD
                let latency = cumulativeLatency + response.latencyMs

                // Final answer — no tool calls. Done.
                if response.toolCalls.isEmpty {
                    let cleaned = DeveloperModeProfile.stripCodeFences(response.content)
                    var finalTrace = trace
                    finalTrace.append("Final answer (\(cleaned.count) chars)")
                    finalTrace.append("Tokens used (last call): in \(response.inputTokens), out \(response.outputTokens)")
                    finalTrace.append(String(format: "Total cost: $%.5f", cost))
                    finalTrace.append("Total latency: \(latency)ms")
                    let output = TransformerOutput(
                        finalText: cleaned,
                        summary: "Agentic dev mode: \"\(stripped.prefix(60))…\"",
                        modelUsed: response.model,
                        costUSD: cost,
                        llmLatencyMs: latency,
                        usedAgentic: true,
                        trace: finalTrace
                    )
                    completion(.success(output))
                    return
                }

                // Tool calls — execute each, append the assistant message
                // that requested them + a tool message per result, recurse.
                var nextTrace = trace
                var nextMessages = messages
                // The assistant message that invoked the tools must echo
                // the tool_calls structure — OpenAI's protocol rejects
                // a bare assistant turn followed by tool messages otherwise.
                nextMessages.append(LLMMessage(
                    role: .assistant,
                    content: response.content,
                    toolCalls: response.toolCalls
                ))

                for call in response.toolCalls {
                    let result = Self.dispatchTool(
                        name: call.name,
                        argumentsJSON: call.argumentsJSON,
                        context: context
                    )
                    nextTrace.append("Tool call: \(call.name) → \(result.prefix(80))")
                    nextMessages.append(LLMMessage(
                        role: .tool,
                        content: result,
                        toolCallID: call.id
                    ))
                }

                self.runLoop(
                    messages: nextMessages,
                    context: context,
                    stripped: stripped,
                    turnsRemaining: turnsRemaining - 1,
                    cumulativeCost: cost,
                    cumulativeLatency: latency,
                    trace: nextTrace,
                    completion: completion
                )
            }
        }
    }

    // MARK: - Tool definitions

    static let tools: [LLMTool] = [
        LLMTool(
            name: "get_selection",
            description: "Return the text the user has currently selected in their editor. May be empty.",
            parametersSchema: ["type": "object", "properties": [:]]
        ),
        LLMTool(
            name: "get_active_app",
            description: "Return the bundle ID, name, and inferred surface category of the currently-focused app.",
            parametersSchema: ["type": "object", "properties": [:]]
        ),
        LLMTool(
            name: "detect_artifact_type",
            description: "Classify the user's dictated request into one of: bash, sql, regex, prompt, code, json, yaml, prose. The classification is opinionated — return ONE word.",
            parametersSchema: [
                "type": "object",
                "properties": [
                    "request": ["type": "string", "description": "The user's stripped request text"]
                ],
                "required": ["request"]
            ]
        ),
        LLMTool(
            name: "inspect_for_dialect",
            description: "Inspect text for code-language or SQL-dialect markers (e.g. SELECT-only → SQL, function () { → JS). Returns one of: postgres, mysql, bigquery, sqlite, javascript, typescript, python, swift, bash, unknown.",
            parametersSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string"]
                ],
                "required": ["text"]
            ]
        )
    ]

    /// Local deterministic implementations of the tool surface. The model
    /// asks; we answer locally rather than another LLM call. Keeps cost &
    /// latency bounded.
    static func dispatchTool(
        name: String,
        argumentsJSON: String,
        context: ContextSnapshot
    ) -> String {
        switch name {
        case "get_selection":
            return context.selection.isEmpty
                ? "(no selection)"
                : context.selection

        case "get_active_app":
            return """
            bundle_id: \(context.frontmostBundleID ?? "(unknown)")
            name: \(context.frontmostAppName ?? "(unknown)")
            surface: \(context.surface.rawValue)
            """

        case "detect_artifact_type":
            guard
                let data = argumentsJSON.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let request = parsed["request"] as? String
            else { return "prose" }
            return classifyArtifact(request: request)

        case "inspect_for_dialect":
            guard
                let data = argumentsJSON.data(using: .utf8),
                let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let text = parsed["text"] as? String
            else { return "unknown" }
            return inspectDialect(text: text)

        default:
            return "(unknown tool: \(name))"
        }
    }

    private static func classifyArtifact(request: String) -> String {
        let r = request.lowercased()
        if r.contains("bash") || r.contains("shell") || r.contains("script") { return "bash" }
        if r.contains("sql") || r.contains("query") || r.contains("select") { return "sql" }
        if r.contains("regex") || r.contains("regular expression") { return "regex" }
        if r.contains("prompt") { return "prompt" }
        if r.contains("yaml") { return "yaml" }
        if r.contains("json") { return "json" }
        if r.contains("function") || r.contains("class") || r.contains("component") { return "code" }
        return "prose"
    }

    private static func inspectDialect(text: String) -> String {
        let t = text.lowercased()
        if t.contains("create or replace") { return "postgres" }
        if t.contains("auto_increment") { return "mysql" }
        if t.contains("partition by date_trunc") || t.contains("`bigquery`") { return "bigquery" }
        if t.contains("pragma ") { return "sqlite" }
        if t.contains("interface ") || t.contains(": string;") || t.contains("import {") { return "typescript" }
        if t.contains("function(") || t.contains("=>") { return "javascript" }
        if t.contains("def ") || t.contains("import ") { return "python" }
        if t.contains("import swiftui") || t.contains("var body: some view") { return "swift" }
        if t.hasPrefix("#!/bin/bash") || t.contains("set -euo pipefail") { return "bash" }
        return "unknown"
    }

    static func systemPrompt(context: ContextSnapshot) -> String {
        let baseSystem = DeveloperModeProfile.buildSystemPrompt(context: context)
        return baseSystem + """


        You have access to tools that return facts about the user's environment.
        - Call them when the request is ambiguous or selection-dependent.
        - Skip them when the user's request is self-contained.
        - Stop calling tools after at most 3 turns; then output the artifact.
        - Never paraphrase a tool result — read it, then act.
        """
    }
}
