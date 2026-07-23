# Groq Default and Menu-Bar Visibility

## Goal

Restore Vordi's zero-setup transcription experience and make its branding
clearly visible in both the macOS menu bar and the opened menu.

## Transcription routing

- New installations default to Groq and work through the bundled beta key.
- A user-provided Groq key overrides the bundled key.
- `whisper-large-v3-turbo` handles the fastest English/verbatim path.
- `whisper-large-v3` handles multilingual, Romanized, and translation paths.
- OpenAI transcription remains an optional user choice and benchmark target.
- Missing OpenAI credentials must never block the default Groq experience.
- Screenshot summarization remains asynchronous and must not delay transcript
  insertion.
- Transcript cleanup continues on Groq `openai/gpt-oss-20b`.
- Screenshot understanding continues on Groq `qwen/qwen3.6-27b`.

## Menu-bar rendering

- The compact menu-bar mark uses the transparent Vordi waveform as an AppKit
  template image.
- macOS owns the template tint so the mark remains visible against light,
  dark, wallpaper-tinted, active, and inactive menu-bar backgrounds.
- The opened dark menu displays the transparent white Vordi mark explicitly.
- The transparent logo asset is included in the Xcode application resources;
  missing-resource fallbacks are not the normal rendering path.
- The menu-bar icon stays within the standard 18 by 18 point visual area.

## Validation

- Confirm a clean install resolves transcription to Groq without an OpenAI key.
- Confirm Groq Turbo and full V3 routes remain reachable.
- Confirm screenshot summarization does not block the transcription pipeline.
- Build and install the Release app.
- Capture the live menu bar closed and opened, checking that both marks are
  visible.
- Run the existing bundle verifier.
