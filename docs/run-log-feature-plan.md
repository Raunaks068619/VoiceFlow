# 📜 Run Log — Feature Plan

> **Status:** Proposed · **Owner:** Raunak · **Target:** v1.2.x
> **Inspired by:** FreeFlow's Run Log tab (screenshot-based context capture + local-only pipeline transparency)

---

## 1. Summary

Persist each dictation run (audio, screenshot, raw transcript, processed output, prompts, metadata) to local disk as an observable, replayable timeline. Expose via a **Run Log** tab in the main window. Ring-buffered to the last *N* runs. Privacy-first: never leaves the machine.

**Why it's powerful in one line:** It turns VoiceFlow from a black-box dictation tool into a *transparent, auditable, trust-building* pipeline — users see what the model heard, what context it had, and why the output looks the way it does.

---

## 2. Validation — Should we build this?

### Signal (why it's a strong idea)
- **Trust.** Speech → LLM pipelines are opaque. Showing "here's what we captured, here's the prompt, here's the result" converts a magic box into a tool people *understand*. Huge for retention.
- **Debuggability.** When output is wrong (hallucination, wrong language, missing words), user can immediately see *where* it broke — capture? transcription? post-processing? This is **free product feedback** we'd otherwise be guessing at.
- **Differentiation.** Most paid tools (Superwhisper, Whispr, MacWhisper) don't expose the full pipeline. FreeFlow does and it's their core UX hook.
- **Recovery.** User dictated something, switched apps, lost it? Run Log is their undo-tape.
- **Zero marginal server cost.** 100% local — no backend, no compliance overhead.

### Counter-signals (why to be careful)
- **Disk bloat.** Audio + screenshots × N runs. Mitigated by ring buffer + configurable cap.
- **Privacy surface expands.** We're now persisting screen recordings. Must be opt-in-visible + purge-on-quit toggle.
- **Scope creep risk.** "Run Log" can easily turn into "full dictation IDE." Stay disciplined — MVP is read-only history + delete.
- **Competes for attention.** If the log is buried in tabs, users won't find it. If it's front-and-center, it distracts from the core dictation loop.

### Verdict
✅ **Build it.** The trust + debug value is too high to skip. Tier it — MVP is small (~1 week), full version ships trust features incrementally.

---

## 3. Competitive Teardown — What FreeFlow actually does

From the screenshots:

| Layer | What they capture | UI surface |
|---|---|---|
| 🎙 Audio | Full run WAV | Inline player (play/scrub, 0:04 duration visible) |
| 📸 Context | Active app screenshot + metadata (app name, bundle ID, window title, selected text) | Thumbnail + collapsible prompt |
| 🧠 Context synthesis | LLaMA-4-Scout infers "what user is doing + writing intent" — prepended to transcription prompt | `Show Prompt ▼` toggle reveals full system+user messages |
| 🗣 Transcription | Raw Whisper output (Groq `whisper-large-v3`) | Monospaced block |
| ✍️ Post-process | Cleaned/polished transcript + its prompt | `Show Prompt ▼` toggle |
| 💾 Storage | Last 20 runs, local only | `Clear History` button |
| 🎨 UX | Numbered pipeline stages (1→2→3), icons, clean card layout | Same visual language as settings panel |

**The killer detail:** each stage's *prompt* is revealable. That's what converts "black box" to "glass box."

---

## 4. Domain Model

Think of a `Run` as an **immutable ledger entry** — a transaction record of one dictation. Once stored, never mutated. Only deleted.

```
Run
├── id: UUID
├── createdAt: Date
├── duration: TimeInterval
├── status: .success | .failed(reason)
│
├── Capture
│   ├── audioURL: URL              // file://.../audio.wav
│   ├── screenshotURL: URL?        // file://.../context.jpg (optional if SR denied)
│   ├── activeApp: AppContext      // bundle, name, window title, selection
│   └── contextSummary: String?    // LLM-synthesized "what user is doing"
│
├── Transcription
│   ├── provider: String           // "groq/whisper-large-v3"
│   ├── rawText: String            // verbatim whisper output
│   └── latencyMs: Int
│
├── PostProcessing
│   ├── mode: .rewrite | .clean | .cleanHinglish | .raw
│   ├── prompt: String             // full system+user
│   ├── model: String              // "openai/gpt-4o-mini" etc
│   ├── finalText: String
│   ├── latencyMs: Int
│   └── droppedLanguageGuardTriggered: Bool  // observability
│
└── Injection
    ├── targetApp: String
    └── injectedCharCount: Int
```

**Why this shape:** each stage is a bounded context with its own inputs/outputs. If we ever want to rerun just post-processing with a new prompt (V2 feature), the Run already has everything needed — we don't have to re-record audio.

---

## 5. Architecture

### Core principle: observation ≠ orchestration

The existing pipeline must NOT know about the Run Log. We wire in via **events**, not direct calls. If Run Log service crashes, dictation still works.

```
┌──────────────┐     ┌───────────────┐     ┌──────────────┐     ┌──────────────┐
│ AudioRecorder│──▶──│ WhisperService│──▶──│ PostProcessor│──▶──│ TextInjector │
└──────┬───────┘     └───────┬───────┘     └───────┬──────┘     └──────┬───────┘
       │                     │                     │                    │
       └──── emits stage events on shared bus ─────┴────────────────────┘
                                │
                                ▼
                       ┌────────────────┐
                       │  RunRecorder   │  (subscriber)
                       └────────┬───────┘
                                │
                                ▼
                       ┌────────────────┐
                       │   RunStore     │  (disk persistence)
                       └────────┬───────┘
                                │
                                ▼
                       ┌────────────────┐
                       │  RunLogView    │  (observes RunStore)
                       └────────────────┘
```

### New components

| Component | Responsibility | File |
|---|---|---|
| `RunEventBus` | `Combine` publisher of pipeline stage events | `Sources/Services/RunEventBus.swift` |
| `RunRecorder` | Subscribes to events, accumulates current-run state, flushes completed `Run` to store | `Sources/Services/RunRecorder.swift` |
| `RunStore` | Disk persistence, ring buffer, CRUD, observable list | `Sources/Services/RunStore.swift` |
| `ScreenshotService` | Capture active window image on dictation start | `Sources/Services/ScreenshotService.swift` |
| `ContextSynthesizer` *(V2)* | Calls LLM to produce context-summary sentence from screenshot+metadata | `Sources/Services/ContextSynthesizer.swift` |
| `RunLogView` | List + detail SwiftUI view | `Sources/Views/RunLogView.swift` |
| `RunDetailView` | Audio player + pipeline stages + prompt toggles | `Sources/Views/RunDetailView.swift` |

### Touchpoints in existing code (minimal surgery)

- **`AudioRecorder.swift`** → emit `.captureStarted(runID)`, `.captureFinished(runID, audioURL)`.
- **`WhisperService.swift`** → emit `.transcriptionCompleted(runID, rawText, latency)` and `.postProcessCompleted(runID, prompt, finalText, latency, guardTriggered)`.
- **`VoiceFlowApp.swift`** → register `RunRecorder` on app start.
- No changes to `TextInjector` / `HotKeyListener` needed for MVP (we only need injection metadata for V2).

---

## 6. Storage schema

**Location:** `~/Library/Application Support/VoiceFlow/runs/`

**Per-run folder:** `runs/<ISO8601>_<uuid>/`

```
runs/
├── index.json                        // array of RunSummary (id, createdAt, preview text, status)
└── 2026-04-16T10-32-45_<uuid>/
    ├── audio.wav
    ├── context.jpg                   // optional
    └── run.json                      // full Run record
```

**Ring buffer:** on write, if `index.length > maxRuns`, delete oldest folder + rebuild index. Default `maxRuns = 20`, user-configurable (10/20/50/100).

**Why filesystem, not Core Data / SQLite:**
- Audio + images are already files; putting them in a DB is worse
- Human-inspectable if something breaks
- Delete = `FileManager.removeItem` — trivial purge semantics
- `index.json` is tiny; `JSONEncoder` round-trip is fine for <100 rows

---

## 7. UI / UX

### Sidebar
```
┌────────────────┐
│ ⚙ General      │
│ 📜 Run Log     │ ← new
│ 🧠 Dictionary  │ ← future
└────────────────┘
```

### Run Log list (follows FreeFlow's pattern)
- Header: `Run Log` + subtitle `Stored locally. Only the X most recent runs are kept.` + `Clear History` button
- Rows (chronological, newest first):
  - `⚠️ <date> <time>` + preview first 80 chars of final text (or `(no transcript)` if failed)
  - Disclosure chevron → expands detail inline OR pushes to detail pane
  - Trash icon → single-run delete with confirm
- Failed runs get a red left-border + ⚠️ icon

### Run detail (expanded)
1. **Audio player** — waveform + play/scrub + duration
2. **Stage 1: Capture Context** — screenshot thumbnail (click-to-expand) + `Show Prompt ▼` + context summary paragraph
3. **Stage 2: Transcribe Audio** — "Sent audio to \<model\>" + monospace raw text
4. **Stage 3: Post-Process** — status line + `Show Prompt ▼` + final text in monospace

### Empty state
- Icon + "No runs yet. Hold ⎘ to start dictating." — not a dead-end

### Trust & transparency affordances
- Settings toggle: `☑ Keep run history (last N runs)` — uncheck = no recording at all
- Settings toggle: `☑ Capture screenshot context` — decouples SR usage from history
- `Clear History` button always visible; one-click nuke

---

## 8. Privacy & Security

| Concern | Mitigation |
|---|---|
| Screenshots of sensitive content | Opt-in toggle, default OFF in MVP. Blur password fields (V2, uses AX API). |
| Audio of private speech | Same opt-in; never leaves disk; auto-purge on ring-buffer overflow. |
| Disk encryption | Rely on FileVault (macOS default). No app-level crypto in MVP. |
| Accidental sharing | Add `💡 This file contains sensitive data — never commit/upload.` to index.json header. |
| Future cloud sync | **Explicitly out of scope.** If ever added, separate opt-in flow + E2E. |

**Messaging to user (must be present):**
> "Run Log is stored only on this Mac at `~/Library/Application Support/VoiceFlow/runs/`. It never syncs, uploads, or leaves your device. You can clear it anytime."

---

## 9. Phased rollout

### 🟢 MVP (v1.2.0) — "The glass box" — ~3-4 days
Minimum to deliver 80% of the value.

- [ ] `Run` + `RunStore` (filesystem, ring buffer, JSON)
- [ ] `RunEventBus` + `RunRecorder` subscriber
- [ ] Instrument `AudioRecorder` + `WhisperService` to emit events
- [ ] Persist `audio.wav` copy (we already write this — just move on success)
- [ ] **Skip** screenshot + context synthesis in MVP
- [ ] `RunLogView` with list + inline-expand detail (no sidebar nav yet — just a new tab on main window)
- [ ] Raw transcript + final text + prompt visible
- [ ] Audio playback via `AVAudioPlayer`
- [ ] Single-run delete + `Clear History`
- [ ] Settings toggle: `Keep run history (last N)`, default ON, N=20

**Why this slice:** proves the architecture, delivers trust+debug value immediately, skips the heaviest lift (screenshot + vision LLM).

### 🟡 V1.1 — "Context capture" — ~2-3 days
- [ ] `ScreenshotService` — uses existing Screen Recording permission, captures frontmost window
- [ ] Inject screenshot into post-process prompt as context
- [ ] Display screenshot + metadata in Run detail
- [ ] Settings toggle: `Capture screenshot context`, default OFF

### 🔵 V1.2 — "Context synthesis" — ~1-2 days
- [ ] `ContextSynthesizer` — LLaMA-4-Scout-style tiny vision model call to produce one-sentence context summary
- [ ] Show context summary in Run detail stage 1
- [ ] Only fires if user enables "smart context"

### 🟣 V2 — "Replay & retry" — stretch
- [ ] "Rerun with different prompt" button (reuses stored audio)
- [ ] "Copy final text" / "Copy raw transcript"
- [ ] Export run as ZIP
- [ ] Search across history
- [ ] Waveform visualization (not just scrubber)
- [ ] Password-field blur via AX API

---

## 10. Tradeoffs & decisions to make

| Decision | Options | Recommendation |
|---|---|---|
| **Audio format** | WAV (lossless, big) vs AAC (small, CPU) | **WAV in MVP** — we already produce it; Whisper needed it. Compress later if disk pressure emerges. |
| **Default N** | 10 / 20 / 50 | **20** (matches FreeFlow; ~10-15MB disk) |
| **Sidebar vs tab** | New sidebar section vs settings tab | **Top-level sidebar item** — it's a first-class feature, not a setting |
| **Opt-in by default?** | ON by default vs OFF by default | **ON for transcript, OFF for screenshot.** Text-only history is low-risk and drives the trust value. |
| **Failed runs** | Store or discard | **Store** — these are where debugging value is *highest* |
| **Event bus impl** | Combine publishers vs NotificationCenter vs AsyncStream | **Combine** — already in use for permission state, type-safe |

---

## 11. Open questions / parking lot

- Do we show **model cost/tokens** per run? (useful for power users; might feel transactional)
- Should the push-to-talk overlay have a shortcut to open Run Log? (`⌘⇧H` from menu bar popover?)
- Do we include **diffs** between raw and final text? (visual highlight of what post-processing changed — could be a *killer* trust feature)
- What happens on **app update** — are old-schema runs readable? (Need `schemaVersion` field on Run + migration strategy, or just nuke-on-mismatch)
- Does the existence of Run Log change how we handle **crashes mid-run**? (Orphaned partial runs need a cleanup pass on launch)

---

## 12. Success criteria

We'll know this feature works if:
- [ ] Users open Run Log within first 3 sessions (instrumentation needed)
- [ ] Support conversations shift from *"why did it say X?"* to *"here's the Run Log entry, help me understand stage 3"*
- [ ] Disk usage stays <50MB for default settings
- [ ] Zero impact on dictation latency (event emission must be `DispatchQueue.global().async`)
- [ ] No privacy incidents (nothing ever leaves the device)

---

## Follow-ups

- 📸 Prototype `ScreenshotService` in a scratch file to validate CGWindowList API before committing to architecture
- 🧪 Write a failure-mode test: what if disk is full during run write? (Run should still succeed; log write fails gracefully)
- 📏 Measure actual per-run size on real dictation samples before shipping — calibrate default N
- 🎨 Design review of Run Log detail layout — consider collapsible-by-default vs expanded-by-default stages
