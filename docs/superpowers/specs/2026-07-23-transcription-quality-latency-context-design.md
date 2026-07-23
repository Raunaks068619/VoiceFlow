# Transcription Quality, Latency, and Screenshot Context Design

## Goal

Improve Vordi's dictation quality and responsiveness by:

- using `gpt-4o-mini-transcribe` for batch and realtime speech-to-text;
- restoring text cleanup with a current fast, inexpensive Groq model;
- restoring screenshot summarization with a current vision model;
- showing immediate feedback and starting audio sooner after Fn is pressed;
- adding a repeatable comparison harness for `gpt-4o-mini-transcribe` and `gpt-4o-transcribe`.

## Current Failures

### Text cleanup

Vordi sends cleanup requests to Groq's retired
`meta-llama/llama-4-scout-17b-16e-instruct` model. The request fails quickly,
and the pipeline silently returns raw STT text. In the latest 50 saved runs,
all 48 successful runs recorded unchanged raw and final text with no cleanup
model or prompt.

### Screenshot summarization

Screenshot capture succeeds, but the same retired Llama 4 Scout model handles
vision requests, so summaries are absent. There is also a race: screenshot
summarization starts asynchronously, while transcription captures an earlier
context value. A summary that finishes later can be omitted from post-processing
and the persisted run.

### Fn responsiveness

Fn is delayed by a 60 ms chord-disambiguation window. The hotkey handler,
recording entry point, and feedback surfaces then add repeated main-queue hops.
The floating chip animates its state change over 150 ms. AudioRecorder also
rebuilds AVAudioEngine for every recording.

Existing debug logs show:

- callback-to-audio-start median: 137 ms;
- callback-to-audio-start p95: 409 ms;
- estimated physical-Fn-to-audio-start median: 197 ms;
- estimated physical-Fn-to-audio-start p95: 469 ms.

### STT routing and prompting

Recent runs all use Groq `whisper-large-v3`. The OpenAI realtime setting is on,
but no OpenAI key is configured. The shared STT prompt always asks for Indic
transliteration, including English-output runs where that instruction conflicts
with the selected output contract.

## Model Allocation

Use a model selected for each task rather than one model for all AI work.

### Speech-to-text

- Default model: `gpt-4o-mini-transcribe`
- Batch endpoint: OpenAI audio transcriptions
- Realtime endpoint: OpenAI realtime transcription
- Benchmark-only comparison: `gpt-4o-transcribe`

OpenAI key policy:

- An OpenAI API key is required for normal dictation.
- Do not silently route normal dictation to Groq when the key is absent.
- Surface a clear missing-key error with a direct path to Settings.
- Never log the key or include it in Run Log or benchmark artifacts.
- Existing Vordi Settings storage remains unchanged in this scope.

### Text cleanup

- Provider: Groq
- Model: `openai/gpt-oss-20b`
- Reasoning effort: low
- Reasoning output: hidden
- Completion output should be capped to a small transcript-appropriate limit.

This model is independent of the transcription provider. It keeps cleanup fast
and inexpensive while `gpt-4o-mini-transcribe` handles recognition.

### Screenshot summarization

- Provider: Groq
- Model: `qwen/qwen3.6-27b`
- Reasoning: disabled
- Reasoning output: hidden
- Input: screenshot plus active app, window title, surface, and selected text
- Output: exactly two short factual sentences

The screenshot model must remain separate from the text-cleanup model because
GPT-OSS 20B does not accept image input.

### Model catalog and migration

Centralize active model identifiers so routing, UI labels, metadata, and tests
cannot drift.

On launch, migrate stored polish backend IDs that reference the retired Llama
4 Scout model to Groq GPT-OSS 20B. Historical run records remain unchanged.

## STT Prompt Contracts

Build the prompt from the selected output style.

### Original

- Transcribe the spoken language faithfully.
- Preserve proper nouns, technical terms, and user vocabulary.
- Do not translate or rewrite.

### English

- Transcribe the spoken content faithfully in its original language.
- Preserve English technical terms and proper nouns.
- Do not translate at the STT stage.
- The cleanup stage owns translation to natural English.

### Romanized

- Preserve the spoken meaning and language mix.
- Render Indic speech using Latin letters.
- Preserve English technical terms and user vocabulary.

Batch and realtime transcription must use the same style-specific prompt.

## Pipeline and Concurrency

### Recording start

1. Receive the Fn rising edge.
2. Update the feedback surface immediately.
3. Start audio capture.
4. Capture app/window context after audio is live.
5. Start screenshot summarization in parallel with the user's speech.

### Fn and hands-free disambiguation

Remove the 60 ms deferred push-to-talk start. Start push-to-talk immediately.
If Control follows and completes the hands-free chord, use the existing safe
transition:

1. abort the short push-to-talk recording;
2. reset push-to-talk state;
3. enter continuous hands-free capture.

Fn release must stop only the active push-to-talk recording. Hands-free release
semantics remain unchanged.

### Main-thread behavior

Callbacks that are already on the main thread mutate state directly. Code that
may arrive off-main dispatches once. Feedback surfaces follow the same rule and
do not add unconditional queue hops.

### Audio engine lifecycle

Reuse AVAudioEngine between ordinary recordings.

Mark the engine for rebuild when:

- macOS reports an audio-engine configuration change;
- the machine wakes from sleep;
- the current input format is invalid;
- engine start fails.

On a start failure, rebuild and retry once. If the retry fails, return the
existing user-facing audio warning. Input taps are still removed between runs.

### Context summary coordination

Represent screenshot summarization as one task per capture ID.

- Start it once after screenshot capture.
- Reuse the same task wherever enriched context is requested.
- Never issue duplicate vision requests for one recording.
- At the post-STT boundary, await STT and the context task before cleanup.
- If screenshot summarization fails, continue with app/window metadata.
- Attach the resolved context to the Run before persistence.
- Cancel stale context work when a newer recording begins.

The vision request overlaps recording and STT, so the join should normally add
no visible latency. Add a bounded timeout so a slow vision request cannot block
dictation indefinitely.

## Error Handling and Observability

### Missing OpenAI key

- Do not start a paid transcription request.
- Keep captured audio local.
- Show an actionable error that opens Settings.
- Store a failed Run entry without secrets.

### Cleanup failure

- Preserve raw STT as the safe fallback.
- Record the selected cleanup model and the provider error category.
- Do not record the cleanup model as `none`.
- Do not expose provider credentials or full sensitive response bodies.

### Screenshot-summary failure

Persist a summary status with:

- requested model;
- success, timeout, cancelled, or failed state;
- sanitized failure reason;
- latency.

Run Log should distinguish “not requested,” “captured but summary failed,” and
“summary available.”

## Benchmark Harness

Add a command-line benchmark that reads saved Vordi run folders without
modifying them.

Inputs:

- a specific list of run IDs or the latest N successful runs;
- OpenAI API key from the environment or Vordi's configured app setting;
- optional ground-truth JSON keyed by run ID.

For each WAV, run:

- `gpt-4o-mini-transcribe`;
- `gpt-4o-transcribe`.

Capture:

- transcript;
- request latency;
- audio duration;
- estimated request cost;
- normalized transcript difference;
- word error rate when ground truth exists;
- proper-noun matches for configured vocabulary.

Outputs:

- human-readable terminal comparison;
- machine-readable JSON report in a user-selected output path.

The harness must redact API keys and must not alter Run Log data. If no OpenAI
key is available, it exits with an actionable message rather than producing a
partial benchmark.

## Verification

### Automated

- Build Vordi successfully.
- Test hotkey state transitions for Fn, Fn+Control, and release ordering.
- Test style-specific STT prompt selection.
- Test retired-model migration.
- Test cleanup failure metadata.
- Test one-context-task-per-capture coordination.
- Test benchmark WER and cost calculations with local fixtures.

### Runtime

- Fn feedback begins immediately.
- Audio begins without the 60 ms intentional delay.
- Fn+Control still enters and exits hands-free reliably.
- A dictated English sentence uses `gpt-4o-mini-transcribe`.
- Cleanup metadata names Groq GPT-OSS 20B and final text is not an automatic raw
  passthrough.
- A captured screenshot produces a Qwen summary in Run Log.
- Missing OpenAI key produces an actionable error.
- The benchmark command compares mini and full 4o once a key is configured.

## Out of Scope

- Changing the draggable chip's approved resting visual.
- Replacing RunStore persistence.
- Adding a backend proxy or account system.
- Sending historical audio to an API automatically.
- Making `gpt-4o-transcribe` the production default.
