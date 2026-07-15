# vordi-mcp

A tiny, **dependency-free, read-only** [MCP](https://modelcontextprotocol.io) server that lets local AI agents (Claude Code, Codex, Cursor) read your Vordi dictation history. It reads `~/Library/Application Support/Vordi/runs` directly — **no Vordi process required, nothing leaves your machine.**

This is the bridge that makes Vordi *agent-readable memory*: ask your coding agent "what did I dictate about X" and it answers from your own history.

## Tools

| Tool | What it does |
|---|---|
| `vordi_list_runs` | Recent dictations (newest first) — id, date, app, status, word count, text |
| `vordi_get_run` | Full detail of one run — raw + polished transcript, provider, model, context, timing |
| `vordi_search_transcripts` | Full-text search across your dictation history — ranked, with highlighted snippets |

Read-only. No write tools, no audio, no screenshots — by design (those come later, behind explicit consent).

## Build

```bash
swift build -c release
# binary → .build/release/vordi-mcp
```

## Connect your agent

Use the absolute path to the binary. (Once bundled inside Vordi.app it'll live at
`/Applications/Vordi.app/Contents/MacOS/vordi-mcp`; until then use the build path.)

**Claude Code**
```bash
claude mcp add vordi -- /ABSOLUTE/PATH/vordi-mcp/.build/release/vordi-mcp
```

**Cursor** — `~/.cursor/mcp.json`
```json
{ "mcpServers": { "vordi": { "command": "/ABSOLUTE/PATH/vordi-mcp/.build/release/vordi-mcp" } } }
```

**Codex** — `~/.codex/config.toml`
```toml
[mcp_servers.vordi]
command = "/ABSOLUTE/PATH/vordi-mcp/.build/release/vordi-mcp"
```

Then ask the agent: *"Use Vordi to find what I dictated about &lt;topic&gt;."*

## Protocol

JSON-RPC 2.0 over stdio (newline-delimited). Implements `initialize`, `tools/list`,
`tools/call`, `ping`. Diagnostics go to stderr; stdout is the protocol channel only.

## Search index

`vordi_search_transcripts` is backed by **SQLite FTS5** over the *complete* polished + raw
transcripts (not just the preview). The index is the server's own cache at
`~/Library/Application Support/Vordi/mcp-index.db`, built incrementally — each call indexes
only runs added since the last one (a run id is read from the folder name, no file read).
Zero external dependencies: FTS5 ships with macOS's system SQLite. If the DB can't be
opened it falls back to a substring scan, so search always works.

## Roadmap

- P1: graph / notes / magic-words / masked-config read tools; in-app per-scope consent grants.
- P2: write tools (set config, magic-word CRUD) via an app-owned control channel.
- Distribution: publish to the official MCP Registry; package as a Claude Desktop Extension (MCPB); submit a Codex plugin.
