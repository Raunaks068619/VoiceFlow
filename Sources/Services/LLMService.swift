import Foundation

/// Generic LLM gateway. Profile code talks to this; the existing
/// WhisperService.runChatCompletion stays as the polish-pipeline
/// implementation but will be migrated onto this in a follow-up.
///
/// **Why a separate service from WhisperService.runChatCompletion**:
/// - Profiles need cost tracking (Insights tab tallies cumulative spend).
/// - Profiles need retry semantics on 5xx (polish path doesn't bother).
/// - Profiles need streaming partials in Phase 4 (agentic mode).
/// - Profiles need structured-output / tool-use, not just plain text.
///
/// **Design choice — class, not actor**: Swift 5.9 actors interop awkwardly
/// with completion-handler-style URLSession. We keep `class` + manual queue
/// dispatch where needed. Migrate when the rest of the app goes async/await.
final class LLMService {
    static let shared = LLMService()

    /// Cumulative spend across the running session (transient, resets on
    /// app restart). Persistent totals live in RunStore — query summed
    /// `llmCostUSD` per run for actual spend history.
    private(set) var sessionSpendUSD: Double = 0
    private let spendLock = NSLock()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public API

    /// Issue a chat completion against the user's chosen polish backend,
    /// or override to a specific backend (e.g. dev mode prefers
    /// gpt-4.1-mini even if the user picked llama for polish).
    ///
    /// `purpose` is just a tag for logging/cost-attribution — show up in
    /// the run trace as "LLMService.complete(purpose: \"dev_mode\")".
    func complete(
        request: LLMRequest,
        completion: @escaping (Result<LLMResponse, Error>) -> Void
    ) {
        let attempt = request.maxAttempts > 0 ? request.maxAttempts : 1
        runAttempt(request: request, remaining: attempt, completion: completion)
    }

    /// Async/await convenience for callers in modern code.
    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        try await withCheckedThrowingContinuation { cont in
            complete(request: request) { result in
                cont.resume(with: result)
            }
        }
    }

    // MARK: - Cost tracking

    /// Approximate cost in USD given input + output token counts. The
    /// numbers are intentionally conservative (rounded UP) — better to
    /// over-report than under-report on the Insights spend chart.
    ///
    /// Source: openai.com/api/pricing as of 2026-04. Update when prices move.
    static func estimateCost(model: String, inputTokens: Int, outputTokens: Int) -> Double {
        switch model {
        case "gpt-4.1-mini":   return Double(inputTokens) * 0.0000004 + Double(outputTokens) * 0.0000016
        case "gpt-4.1-nano":   return Double(inputTokens) * 0.0000001 + Double(outputTokens) * 0.0000004
        case "gpt-4.1":        return Double(inputTokens) * 0.0000020 + Double(outputTokens) * 0.0000080
        case "gpt-4o-mini":    return Double(inputTokens) * 0.00000015 + Double(outputTokens) * 0.0000006
        case "gpt-4o":         return Double(inputTokens) * 0.0000025 + Double(outputTokens) * 0.0000100
        // Groq's free-tier surface cost is effectively 0 under current
        // pricing for modest dictation traffic. We attribute 0 here so
        // the Insights tab honestly reports "Groq (free)".
        default:
            if model.contains("llama") || model.contains("groq") { return 0 }
            // Unknown model — approximate at gpt-4.1-mini rates so the
            // dashboard shows SOMETHING rather than $0.
            return Double(inputTokens) * 0.0000004 + Double(outputTokens) * 0.0000016
        }
    }

    private func recordSpend(_ amount: Double) {
        spendLock.lock()
        sessionSpendUSD += amount
        spendLock.unlock()
    }

    // MARK: - Internals

    private func runAttempt(
        request: LLMRequest,
        remaining: Int,
        completion: @escaping (Result<LLMResponse, Error>) -> Void
    ) {
        let backend = request.backendOverride ?? PolishBackend.current
        let apiKey = backend.apiKey()

        if backend.requiresAPIKey && apiKey.isEmpty {
            completion(.failure(LLMError.noAPIKey(backend: backend.displayLabel)))
            return
        }

        var urlRequest = URLRequest(url: backend.chatCompletionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = backend.requiresAPIKey ? 30 : 90

        // Build the messages array. We always send a system message even
        // if the profile didn't supply one (helps with consistency across
        // backends — Groq's llama gets noticeably worse without one).
        //
        // Tool-call protocol nuances:
        //   - Assistant messages that invoked tools must echo the tool_calls
        //     structure so the model sees the round-trip.
        //   - Tool messages must carry the matching tool_call_id, otherwise
        //     OpenAI returns 400 "tool messages must have tool_call_id".
        let messages: [[String: Any]] = request.messages.map { msg -> [String: Any] in
            var dict: [String: Any] = [
                "role": msg.role.rawValue,
                "content": msg.content,
            ]
            if msg.role == .tool, let callID = msg.toolCallID {
                dict["tool_call_id"] = callID
            }
            if msg.role == .assistant, !msg.toolCalls.isEmpty {
                dict["tool_calls"] = msg.toolCalls.map { call in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.argumentsJSON
                        ]
                    ]
                }
            }
            return dict
        }

        var payload: [String: Any] = [
            "model": backend.modelName,
            "temperature": request.temperature,
            "messages": messages,
        ]
        if let maxTokens = request.maxTokens {
            payload["max_tokens"] = maxTokens
        }

        // Tool-use payload for Phase 4 agentic mode. Only attached when
        // the request actually defines tools — keeps non-agentic calls
        // identical on the wire.
        if !request.tools.isEmpty {
            payload["tools"] = request.tools.map { $0.openAIRepresentation }
            payload["tool_choice"] = "auto"
        }

        let body: Data
        do {
            body = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(.failure(error))
            return
        }
        urlRequest.httpBody = body

        let started = CFAbsoluteTimeGetCurrent()

        session.dataTask(with: urlRequest) { [weak self] data, response, error in
            guard let self else { return }
            let latencyMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)

            // Network error path — retry on transport-layer failures.
            if let error = error {
                if remaining > 1 {
                    print("LLMService: transport error, retrying (\(remaining - 1) left): \(error.localizedDescription)")
                    let delay = Self.backoff(attemptNumber: request.maxAttempts - remaining + 1)
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.runAttempt(request: request, remaining: remaining - 1, completion: completion)
                    }
                    return
                }
                completion(.failure(LLMError.transport(error)))
                return
            }

            // Status-based retry path — 429 / 5xx are retryable, 4xx not.
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 429 || (500...599).contains(status) {
                if remaining > 1 {
                    let delay = Self.backoff(attemptNumber: request.maxAttempts - remaining + 1)
                    print("LLMService: \(status) from \(backend.displayLabel), retrying after \(delay)s (\(remaining - 1) left)")
                    DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                        self.runAttempt(request: request, remaining: remaining - 1, completion: completion)
                    }
                    return
                }
            }

            guard let data = data else {
                completion(.failure(LLMError.noData))
                return
            }

            do {
                let parsed = try Self.parseChatResponse(data: data, model: backend.modelName, latencyMs: latencyMs)
                self.recordSpend(parsed.costUSD)
                completion(.success(parsed))
            } catch {
                if let llmErr = error as? LLMError {
                    completion(.failure(llmErr))
                } else {
                    completion(.failure(LLMError.parseError(error.localizedDescription)))
                }
            }
        }.resume()
    }

    /// Exponential backoff with full jitter — caps at ~4s.
    private static func backoff(attemptNumber: Int) -> TimeInterval {
        let base = min(4.0, pow(2.0, Double(attemptNumber - 1)) * 0.4)
        return base * Double.random(in: 0.5...1.0)
    }

    private static func parseChatResponse(data: Data, model: String, latencyMs: Int) throws -> LLMResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.parseError("non-json response body")
        }

        // API error shape — surface the message verbatim. Profiles
        // sometimes fall back to deterministic behavior on these.
        if let errorObj = json["error"] as? [String: Any],
           let message = errorObj["message"] as? String {
            let type = (errorObj["type"] as? String) ?? "api_error"
            throw LLMError.apiError(type: type, message: message)
        }

        guard let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any] else {
            throw LLMError.parseError("missing choices/message")
        }

        let content = (message["content"] as? String) ?? ""
        let toolCalls = (message["tool_calls"] as? [[String: Any]]) ?? []

        // Token usage — both OpenAI & Groq emit `usage`. Defaults to 0
        // when missing so cost estimation degrades gracefully.
        let usage = (json["usage"] as? [String: Any]) ?? [:]
        let inputTokens = (usage["prompt_tokens"] as? Int) ?? 0
        let outputTokens = (usage["completion_tokens"] as? Int) ?? 0

        let cost = LLMService.estimateCost(
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )

        let parsedToolCalls: [LLMResponse.ToolCall] = toolCalls.compactMap { tc in
            guard
                let id = tc["id"] as? String,
                let function = tc["function"] as? [String: Any],
                let name = function["name"] as? String
            else { return nil }
            let arguments = (function["arguments"] as? String) ?? "{}"
            return LLMResponse.ToolCall(id: id, name: name, argumentsJSON: arguments)
        }

        return LLMResponse(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            toolCalls: parsedToolCalls,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: cost,
            latencyMs: latencyMs
        )
    }
}

// MARK: - Request / Response types

struct LLMRequest {
    var messages: [LLMMessage]
    /// Override which backend handles this request. nil → use whatever
    /// the user picked in Settings (PolishBackend.current).
    var backendOverride: PolishBackend?
    var temperature: Double
    var maxTokens: Int?
    var maxAttempts: Int
    /// Tools available to the model. Empty for non-agentic calls.
    var tools: [LLMTool]
    /// Free-form purpose tag for log attribution. Doesn't go to the API.
    var purpose: String

    init(
        messages: [LLMMessage],
        backendOverride: PolishBackend? = nil,
        temperature: Double = 0.0,
        maxTokens: Int? = nil,
        maxAttempts: Int = 2,
        tools: [LLMTool] = [],
        purpose: String = "uncategorized"
    ) {
        self.messages = messages
        self.backendOverride = backendOverride
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.maxAttempts = maxAttempts
        self.tools = tools
        self.purpose = purpose
    }
}

struct LLMMessage {
    enum Role: String { case system, user, assistant, tool }
    let role: Role
    let content: String
    /// Required when role == .tool — OpenAI rejects tool messages
    /// without a matching tool_call_id linking back to the assistant's
    /// tool_calls request. Ignored for other roles.
    let toolCallID: String?
    /// Set on assistant messages that themselves invoked tools, so the
    /// next turn's payload can reflect the tool_calls structure.
    let toolCalls: [LLMResponse.ToolCall]

    init(role: Role, content: String, toolCallID: String? = nil, toolCalls: [LLMResponse.ToolCall] = []) {
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }
}

/// OpenAI tool-calling shape. Translated to the wire format inside LLMService.
struct LLMTool {
    let name: String
    let description: String
    /// JSON-Schema-shaped parameter definition.
    let parametersSchema: [String: Any]

    var openAIRepresentation: [String: Any] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": parametersSchema
            ]
        ]
    }
}

struct LLMResponse {
    /// Plain-text content from the model. Empty when only tool calls were
    /// emitted in this turn.
    let content: String
    /// Structured tool calls — populated when the model invoked a tool.
    let toolCalls: [ToolCall]
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
    let latencyMs: Int

    struct ToolCall {
        let id: String
        let name: String
        /// Raw JSON string. Profiles deserialize per-tool.
        let argumentsJSON: String
    }
}

enum LLMError: LocalizedError {
    case noAPIKey(backend: String)
    case transport(Error)
    case noData
    case parseError(String)
    case apiError(type: String, message: String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey(let backend): return "No API key for \(backend)"
        case .transport(let err):    return "Transport error: \(err.localizedDescription)"
        case .noData:                return "No data from LLM"
        case .parseError(let m):     return "LLM parse error: \(m)"
        case .apiError(let t, let m): return "LLM API \(t): \(m)"
        }
    }
}
