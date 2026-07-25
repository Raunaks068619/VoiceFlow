# Vordi Moat Plan — Memory + Agent-Readable Dictation

## Thesis
Stop competing as "another Mac dictation app." That category is a commodity (same Whisper/Groq models as everyone), saturated (20+ apps), and led by funded teams (Wispr Flow: $81M, $700M val). At parity, you lose.

**Win as the local memory layer for everything you say — wired into your AI agents.**
Dictation = the capture layer. **Memory + the MCP bridge = the moat.** Nobody else owns this.

## Positioning line
> Speak. Vordi types it, cleans it, and **remembers** it — and your AI agents (Claude, Cursor, Codex) can **read it**.

---

## Lane A — The Bridge (the moat): `vordi-mcp`
The single most important thing to build. Makes the positioning real.

**P0 — read-only v0 (~1–2 days, zero app changes; reads on-disk JSON directly)**
- [x] `vordi-mcp` standalone dependency-free stdio binary (SwiftPM pkg at `/vordi-mcp`, 205 KB release)
- [x] 3 tools: `vordi_list_runs`, `vordi_get_run` (raw + polished transcript + context), `vordi_search_transcripts` — **built + tested against real run history**. Search upgraded to **SQLite FTS5 over full transcripts** (ranked + snippets, zero-dep, incremental index).
- [x] Connect docs for Claude Code / Cursor / Codex (`vordi-mcp/README.md`)
- [x] Bundle the binary inside Vordi.app (`Contents/MacOS/vordi-mcp`) via the build script — copies + signs helper, now **self-verifies** (runs `initialize`) and prints the connect command. (Runs on next `build-and-install.sh`.)
- [x] In-app **"Connect AI Agents"** settings pane: one-click connect/disconnect for Claude Code / Cursor / Codex + copy-paste fallback + read-only note. `MCPConnectionManager` (direct config merge — JSON for Claude/Cursor, TOML block for Codex) + `AgentConnectView`, wired into Settings. Build passes; Claude-merge preservation validated against real config.
- [ ] **Record the demo**: dictate → ask Claude "what did I say about X" → it answers from Vordi memory. This is the landing centerpiece. _(everything it needs is now built)_

**P0.5 — keep Memory fresh for the MCP (so agents never read stale/empty memory)**
- [x] Batched auto-sync: every 20 successful dictations → background low-priority Sync (embeddings + entities + FTS). Off the hot path — fixes the "manual sync → month with no embeddings" gap without the per-transcription hang that got auto-index removed. (`IndexerService.noteSavedRun` ← `RunStore.save`)
- [ ] Flush fallback: also drain the trailing <20 on app quit / idle so the tail can't strand
- [x] MCP keyword search now full-transcript: `SearchIndex` builds the MCP's own FTS5 cache (`mcp-index.db`) **incrementally from run.json on every search** → always fresh, independent of app Sync (sidesteps the stale-`memory.db` problem entirely for keyword search). Ranked + highlighted snippets, substring fallback if FTS5 unavailable.

**P1 — full read surface + safety**
- [ ] Read tools: brain graph (nodes+edges), notes, magic words, masked config
- [ ] Consent model: read-only by default (`--read-only`), in-Vordi per-(client, scope) grant, **API keys masked**, **screenshots a separate explicit grant**

**P2 — writes (defer)**
- [ ] `set_config` (allowlisted keys), magic-word CRUD, note append — via an app-owned control channel (watched inbox dir / loopback). Not needed for launch.

## Lane B — The Landing (sell the moat)
**P0**
- [ ] New hero = ONE benefit + the demo video. Kill the spec sheet (delete "microphone probing and health checks" etc.)
- [ ] 3-step "how it works": **Speak → Remembered → Your agents read it**
- [ ] "Connect your agent" section showing the real copy-paste config (proof it's real, not vapor)

**P1**
- [ ] "Who it's for" = developers living in Claude/Cursor/Codex
- [ ] Business-model stance (free/OSS wedge → paid Memory/sync tier? state it)
- [ ] Social-proof slot; demote Notes/Insights from headline features

## Lane C — Cut / freeze (protect focus)
- [ ] Freeze net-new features: no new Notes polish, no Insights expansion, no second feedback widget, no new transformer profiles
- [ ] Quality-only fixes — and ONLY where the moat lives: knowledge-graph interactivity, screenshot privacy gate (the graph/Memory must feel great now that it's the headline)
- [ ] Everything else: parked

## Lane D — Distribution (after read-only server works; none require hosting user data)
- [ ] Publish `vordi-mcp` to the **official MCP Registry** (reverse-DNS namespace via your GitHub) — easiest, vendor-neutral discovery
- [ ] Package as a **Claude Desktop Extension (MCPB)** + submit the desktop-extension form
- [ ] Submit a **Codex plugin** bundling the MCP config (Apps SDK dashboard review)
- [ ] Skip the ChatGPT cloud apps store for now — it needs a hosted server + OAuth, which fights the local-first moat
- [ ] Prereqs for all three: privacy-policy page + support email + logo (do alongside the landing)

## Prerequisites / known data gaps (from the audit — none block read-only v0)
- Brain-graph **edges aren't stored** (derived at query time) → MCP graph tool re-derives via KnowledgeGraphService
- **Screenshots** are a transient separate file + most sensitive payload → separate consented tool, off by default
- **No command catalog** beyond Magic Words → only expose magic words as "commands"
- **Configs** are a flat UserDefaults bag, API keys in plaintext → mask keys, allowlist any writable keys

## Sequence (do in this order)
1. Build `vordi-mcp` read-only v0 (3 tools) — the moat becomes real
2. Record the agent-reads-your-memory demo
3. Rewrite the landing hero around that demo + the connect story
4. Add "Connect your agent" config section + 3-step how-it-works
5. **Ship read-only MCP + new landing together — that's the launch**
6. Then: consent model + more read tools (P1); writes later (P2)
7. Freeze unrelated feature work throughout
