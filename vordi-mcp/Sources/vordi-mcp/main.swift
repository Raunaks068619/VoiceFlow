import Foundation

// vordi-mcp — a minimal, dependency-free MCP server (JSON-RPC 2.0 over stdio)
// that exposes the user's local Vordi dictation history to AI agents
// (Claude Code, Codex, Cursor). Read-only. The protocol channel is stdout;
// all diagnostics go to stderr so they never corrupt a message.

let serverName = "vordi-mcp"
let serverVersion = "0.1.0"
let protocolVersion = "2025-06-18"

let store = VordiStore()

// MARK: - I/O

func logErr(_ s: String) {
    FileHandle.standardError.write(("[\(serverName)] " + s + "\n").data(using: .utf8)!)
}

func writeMessage(_ obj: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return }
    var out = data
    out.append(0x0A) // newline-delimited per MCP stdio transport
    FileHandle.standardOutput.write(out)
}

func respond(id: Any, result: Any) {
    writeMessage(["jsonrpc": "2.0", "id": id, "result": result])
}

func respondError(id: Any, code: Int, message: String) {
    writeMessage(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
}

// MARK: - Tool catalog

let tools: [[String: Any]] = [
    [
        "name": "vordi_list_runs",
        "description": "List the user's most recent Vordi dictation runs (newest first). Returns id, date, app, status, word count and the transcript text. Use this to see what the user recently dictated.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "limit": ["type": "integer", "description": "Max runs to return (default 20)."]
            ],
            "additionalProperties": false,
        ],
    ],
    [
        "name": "vordi_get_run",
        "description": "Get the full detail of one dictation run by id: raw transcript, cleaned/polished transcript, STT provider, polish model, app context and timing.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "id": ["type": "string", "description": "Run id (UUID) from vordi_list_runs or vordi_search_transcripts."]
            ],
            "required": ["id"],
            "additionalProperties": false,
        ],
    ],
    [
        "name": "vordi_search_transcripts",
        "description": "Search the user's dictation history for a keyword or phrase. Returns matching runs (id, date, app, transcript). Use this to recall what the user said about a topic.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "query": ["type": "string", "description": "Keyword or phrase to search for."],
                "limit": ["type": "integer", "description": "Max results (default 20)."],
            ],
            "required": ["query"],
            "additionalProperties": false,
        ],
    ],
]

enum ToolError: Error { case badArgs(String), notFound(String) }

func callTool(name: String, args: [String: Any]) throws -> String {
    switch name {
    case "vordi_list_runs":
        let limit = (args["limit"] as? Int) ?? 20
        return store.jsonText(store.listRuns(limit: limit))
    case "vordi_get_run":
        guard let id = args["id"] as? String, !id.isEmpty else { throw ToolError.badArgs("missing 'id'") }
        guard let run = store.getRun(id: id) else { throw ToolError.notFound("no run found for id \(id)") }
        return store.jsonText(run)
    case "vordi_search_transcripts":
        guard let q = args["query"] as? String, !q.isEmpty else { throw ToolError.badArgs("missing 'query'") }
        let limit = (args["limit"] as? Int) ?? 20
        return store.jsonText(store.search(query: q, limit: limit))
    default:
        throw ToolError.notFound("unknown tool \(name)")
    }
}

// MARK: - Dispatch

func handle(_ msg: [String: Any]) {
    let method = msg["method"] as? String ?? ""
    let id = msg["id"]

    switch method {
    case "initialize":
        guard let id = id else { return }
        respond(id: id, result: [
            "protocolVersion": protocolVersion,
            "capabilities": ["tools": [String: Any]()],
            "serverInfo": ["name": serverName, "version": serverVersion],
        ])

    case "ping":
        guard let id = id else { return }
        respond(id: id, result: [String: Any]())

    case "tools/list":
        guard let id = id else { return }
        respond(id: id, result: ["tools": tools])

    case "tools/call":
        guard let id = id else { return }
        let params = msg["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]
        do {
            let text = try callTool(name: name, args: args)
            respond(id: id, result: ["content": [["type": "text", "text": text]]])
        } catch {
            let reason = (error as? ToolError).map { "\($0)" } ?? error.localizedDescription
            respond(id: id, result: [
                "content": [["type": "text", "text": "Error: \(reason)"]],
                "isError": true,
            ])
        }

    case let m where m.hasPrefix("notifications/"):
        break // fire-and-forget, no response

    default:
        if let id = id { respondError(id: id, code: -32601, message: "Method not found: \(method)") }
    }
}

// MARK: - Run loop (newline-delimited JSON-RPC on stdin until EOF)

logErr("ready — read-only Vordi history server v\(serverVersion)")
while let line = readLine(strippingNewline: true) {
    if line.isEmpty { continue }
    guard let data = line.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data),
          let msg = obj as? [String: Any] else {
        logErr("skipped unparseable line")
        continue
    }
    handle(msg)
}
