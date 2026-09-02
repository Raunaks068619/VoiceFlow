# Runtime Lab Voice and Background Routing Design

## Goal

Let the standalone Runtime Lab consume every completed Vordi dictation without rebuilding Vordi. Commands execute normally by default. Background-safe execution is activated only when the spoken command explicitly asks for it.

## User-visible behavior

Runtime Lab watches Vordi's saved successful runs under `~/Library/Application Support/Vordi/runs/`. Each new final transcript is submitted once to the existing Codex task queue.

Normal examples:

- `Open YouTube` may use the normal browser or Computer Use behavior.
- `Write hello in the current field` may use foreground interaction.

Background examples:

- `Open YouTube in the background`
- `Run this in background`
- `Do this in a different process`
- `Open this in a new window`

These phrases set a background-execution flag for that command only. They do not permanently change the mode for later commands.

## Routing rules

The intent classifier is deterministic and case-insensitive. It recognizes the explicit phrases:

- `in background`
- `in the background`
- `run this in background`
- `different process`
- `separate process`
- `new window`
- `separate window`

Normal commands retain all configured tools and existing confirmation safeguards.

Background commands receive an additional runtime instruction:

- Do not use Computer Use.
- Do not activate, raise, or focus application windows.
- Prefer Browser Use background tabs for web tasks.
- Prefer shell processes and file operations for non-browser tasks.
- If the request cannot be completed without foreground interaction, stop and explain instead of taking over the screen.

The user's transcript is otherwise passed to Codex unchanged so Codex, rather than a rigid verb parser, interprets actions such as `open`, `write`, `search`, or `create`.

## Components

### Vordi run watcher

A Runtime Lab service watches `index.json` for newly inserted run IDs, then reads the matching `run.json`. It accepts successful runs and extracts `postProcessing.finalText`, falling back to `transcription.rawText` and then `previewText`.

On startup, existing runs are recorded as already seen so old dictations are never replayed. The watcher retries partially written files briefly and deduplicates every run ID for the lifetime of the app.

### Command queue

Voice commands enter the same FIFO queue as commands submitted in the Runtime Lab UI. Only one Codex turn runs at a time. This prevents overlapping browser actions and ensures every completed Vordi command is handled in order.

### Background intent classifier

A small pure function returns `background` or `normal` from the transcript. Its result is displayed in the activity trace so the user can see why a command did or did not run invisibly.

## Safety and boundaries

- Existing destructive and consequential-action confirmation rules remain active in both modes.
- Runtime Lab does not monitor the clipboard, preventing ordinary copy operations from becoming commands.
- Runtime Lab does not modify Vordi or its installed build.
- If Vordi is dictating into another focused text field, its current build may still paste the transcript there. The run watcher also sends it to Runtime Lab. Avoiding that duplicate insertion requires a future Vordi command-mode change.
- Background mode prevents Computer Use for that command. Browser tasks may still surface a Chrome permission, authentication, CAPTCHA, download, or MFA prompt when the site requires human interaction.

## Error handling

- Missing Vordi run directory: show `Waiting for Vordi` and keep watching.
- Run logging disabled: explain that Vordi's Run Log must be enabled for the bridge.
- Invalid or incomplete JSON: retry after a short delay without marking the run as consumed.
- Empty or unsuccessful run: ignore it.
- Unsupported background request: return a clear explanation and do not fall back to foreground control.

## Verification

- Unit-test all background phrases, case variants, and ordinary commands that must remain normal.
- Unit-test transcript extraction and run-ID deduplication.
- Verify startup does not replay historical Vordi runs.
- Verify two new runs are queued and executed in order.
- Verify background prompts explicitly disable Computer Use and foreground activation.
- Verify normal prompts retain the standard tool policy.

## V1 success criteria

With Runtime Lab running, the user can dictate from anywhere. A new successful Vordi run appears once in Runtime Lab and executes automatically. Commands containing an explicit background phrase avoid Computer Use and foreground focus; all other commands use normal behavior.
