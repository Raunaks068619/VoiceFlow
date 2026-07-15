import Foundation
import SwiftUI

/// One-click wiring of the bundled `vordi-mcp` helper into local AI agents
/// (Claude Code, Cursor, Codex). Writes each client's MCP config directly so
/// the user never touches a terminal or JSON file.
///
/// **Read-only by design.** The helper exposes only read tools — no writes, no
/// audio, no screenshots. Connecting an agent lets it *read* dictation history;
/// it can never modify or delete anything.
@MainActor
final class MCPConnectionManager: ObservableObject {
    static let shared = MCPConnectionManager()

    /// The MCP server key written into each client's config.
    static let serverKey = "vordi"

    enum Client: String, CaseIterable, Identifiable {
        case claude, claudeDesktop, cursor, codex
        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claude:        return "Claude Code"
            case .claudeDesktop: return "Claude Desktop"
            case .cursor:        return "Cursor"
            case .codex:         return "Codex"
            }
        }

        var icon: String {
            switch self {
            case .claude:        return "terminal"
            case .claudeDesktop: return "bubble.left.and.bubble.right"
            case .cursor:        return "cursorarrow.rays"
            case .codex:         return "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    @Published private(set) var installed: [Client: Bool] = [:]
    @Published private(set) var connected: [Client: Bool] = [:]
    @Published var lastError: String?

    private let fm = FileManager.default

    private init() {}

    // MARK: - Bundled helper path

    /// Absolute path to the bundled helper. In a normal install this resolves to
    /// `Vordi.app/Contents/MacOS/vordi-mcp`. Returns nil if the helper isn't
    /// bundled (e.g. running from Xcode without the install script) — the UI
    /// then shows the copy-paste fallback with the expected install path.
    var binaryURL: URL? {
        if let url = Bundle.main.url(forAuxiliaryExecutable: "vordi-mcp") { return url }
        if let macos = Bundle.main.executableURL?.deletingLastPathComponent() {
            let candidate = macos.appendingPathComponent("vordi-mcp")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    var binaryPath: String { binaryURL?.path ?? "/Applications/\(AppBrand.name).app/Contents/MacOS/vordi-mcp" }

    var isBundled: Bool { binaryURL != nil }

    // MARK: - Detection

    func refresh() {
        for client in Client.allCases {
            installed[client] = detectInstalled(client)
            connected[client] = detectConnected(client)
        }
    }

    private func detectInstalled(_ client: Client) -> Bool {
        switch client {
        case .claude:        return fm.fileExists(atPath: home(".claude.json")) || claudeCLIPath() != nil
        case .claudeDesktop: return fm.fileExists(atPath: "/Applications/Claude.app") || fm.fileExists(atPath: claudeDesktopConfig)
        case .cursor:        return fm.fileExists(atPath: home(".cursor"))
        case .codex:         return fm.fileExists(atPath: home(".codex"))
        }
    }

    private func detectConnected(_ client: Client) -> Bool {
        switch client {
        case .claude:
            return (readJSON(home(".claude.json"))?["mcpServers"] as? [String: Any])?[Self.serverKey] != nil
        case .claudeDesktop:
            return (readJSON(claudeDesktopConfig)?["mcpServers"] as? [String: Any])?[Self.serverKey] != nil
        case .cursor:
            return (readJSON(home(".cursor/mcp.json"))?["mcpServers"] as? [String: Any])?[Self.serverKey] != nil
        case .codex:
            let toml = (try? String(contentsOfFile: home(".codex/config.toml"), encoding: .utf8)) ?? ""
            return toml.contains("[mcp_servers.\(Self.serverKey)]")
        }
    }

    // MARK: - Connect / disconnect

    func connect(_ client: Client) {
        lastError = nil
        do {
            switch client {
            case .claude:        try writeJSONServer(path: home(".claude.json"), extraKeys: ["type": "stdio"])
            case .claudeDesktop: try writeJSONServer(path: claudeDesktopConfig, extraKeys: [:])
            case .cursor:        try writeJSONServer(path: home(".cursor/mcp.json"), extraKeys: [:])
            case .codex:         try connectCodex()
            }
            connected[client] = true
        } catch {
            lastError = "Couldn't connect \(client.displayName): \(error.localizedDescription)"
        }
    }

    func disconnect(_ client: Client) {
        lastError = nil
        do {
            switch client {
            case .claude:        try removeJSONServer(path: home(".claude.json"))
            case .claudeDesktop: try removeJSONServer(path: claudeDesktopConfig)
            case .cursor:        try removeJSONServer(path: home(".cursor/mcp.json"))
            case .codex:         try disconnectCodex()
            }
            connected[client] = false
        } catch {
            lastError = "Couldn't disconnect \(client.displayName): \(error.localizedDescription)"
        }
    }

    // MARK: - JSON clients (Claude, Cursor)

    /// Read-modify-write the client's JSON config, adding our server under
    /// `mcpServers` while preserving every other key. Creates the file if absent.
    private func writeJSONServer(path: String, extraKeys: [String: Any]) throws {
        var root = readJSON(path) ?? [:]
        var servers = root["mcpServers"] as? [String: Any] ?? [:]

        var entry: [String: Any] = ["command": binaryPath, "args": [String]()]
        for (k, v) in extraKeys { entry[k] = v }
        servers[Self.serverKey] = entry
        root["mcpServers"] = servers

        try ensureParentDir(path)
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func removeJSONServer(path: String) throws {
        guard var root = readJSON(path),
              var servers = root["mcpServers"] as? [String: Any] else { return }
        servers.removeValue(forKey: Self.serverKey)
        root["mcpServers"] = servers
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    // MARK: - Codex (TOML)

    /// Append a `[mcp_servers.vordi]` table to config.toml. TOML tables are
    /// order-independent, so appending at EOF is safe and non-destructive.
    private func connectCodex() throws {
        let path = home(".codex/config.toml")
        var toml = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        guard !toml.contains("[mcp_servers.\(Self.serverKey)]") else { return }
        let block = """

        [mcp_servers.\(Self.serverKey)]
        command = "\(binaryPath)"
        args = []
        """
        if !toml.hasSuffix("\n") && !toml.isEmpty { toml += "\n" }
        toml += block + "\n"
        try ensureParentDir(path)
        try toml.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// Strip the `[mcp_servers.vordi]` block: from its header to the next
    /// top-level `[` table or EOF.
    private func disconnectCodex() throws {
        let path = home(".codex/config.toml")
        guard let toml = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        let lines = toml.components(separatedBy: "\n")
        var out: [String] = []
        var skipping = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "[mcp_servers.\(Self.serverKey)]" { skipping = true; continue }
            if skipping {
                // Stop skipping at the next table header.
                if trimmed.hasPrefix("[") { skipping = false } else { continue }
            }
            out.append(line)
        }
        try out.joined(separator: "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    // MARK: - Copy-paste fallback

    /// The config snippet to paste manually — proof it's real, and an escape
    /// hatch for clients we don't write directly.
    func configSnippet(for client: Client) -> String {
        switch client {
        case .claude:
            return "claude mcp add \(Self.serverKey) -- \"\(binaryPath)\""
        case .claudeDesktop:
            return """
            // ~/Library/Application Support/Claude/claude_desktop_config.json
            { "mcpServers": { "\(Self.serverKey)": { "command": "\(binaryPath)" } } }
            """
        case .cursor:
            return """
            // ~/.cursor/mcp.json
            { "mcpServers": { "\(Self.serverKey)": { "command": "\(binaryPath)" } } }
            """
        case .codex:
            return """
            # ~/.codex/config.toml
            [mcp_servers.\(Self.serverKey)]
            command = "\(binaryPath)"
            """
        }
    }

    // MARK: - Helpers

    private func home(_ rel: String) -> String {
        fm.homeDirectoryForCurrentUser.appendingPathComponent(rel).path
    }

    /// Claude Desktop's MCP config file (distinct from Claude Code's ~/.claude.json).
    private var claudeDesktopConfig: String {
        home("Library/Application Support/Claude/claude_desktop_config.json")
    }

    private func readJSON(_ path: String) -> [String: Any]? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private func ensureParentDir(_ path: String) throws {
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func claudeCLIPath() -> String? {
        let candidates = [".local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        for c in candidates {
            let p = c.hasPrefix("/") ? c : home(c)
            if fm.isExecutableFile(atPath: p) { return p }
        }
        return nil
    }
}
