# VoiceFlow — AI Handoff Context

> Paste this entire file at the start of a new ChatGPT/Claude/Gemini chat.
> Then ask your question. The assistant will have enough context to be useful
> without a 20-message ramp-up.

---

## 🎯 What is VoiceFlow

A **macOS-native dictation app** for bilingual (Hindi/English) power users.
Think Wispr Flow, but open-ended about language and output style.

- **Trigger**: Hold `Fn` anywhere on macOS → speak → release → text appears at cursor.
- **Transport**: OpenAI Whisper STT (`gpt-4o-mini-transcribe`) → optional polish via `gpt-4.1-nano`.
- **Distribution**: BYO OpenAI API key. No server. No account. Local plist storage.
- **Stage**: Working beta. ~5 testers. Ad-hoc signed DMG shipping.

**Who it's for (today):** Founder-mode engineers and ops folks who code-switch Hindi/English all day and hate re-typing WhatsApp replies.

**Why it exists:** Native macOS dictation is English-only. Wispr Flow is English-first + subscription. Nothing handles Hinglish code-switching gracefully.

---

## 🧱 Stack

| Layer | Choice |
|---|---|
| Language | Swift 5 |
| UI | SwiftUI + AppKit (menu bar + global hotkey) |
| Audio | AVAudioEngine |
| STT | OpenAI `gpt-4o-mini-transcribe` (Whisper-family) |
| Polish/Translate | OpenAI `gpt-4.1-nano` via Chat Completions |
| Alt backends | LM Studio, Ollama (OpenAI-compatible endpoints) |
| Packaging | Ad-hoc codesign + hardened runtime + `hdiutil` UDZO DMG |
| Persistence | `UserDefaults` (plist) |
| Platform | macOS 13+, arm64 only (Apple Silicon) |

**No backend.** No cloud. User's API key hits `api.openai.com` directly.

---

## 🗂️ File Layout

```
/Users/raunaksingh/Documents/VoiceFlow/
├── Sources/
│   ├── App/
│   │   └── VoiceFlowApp.swift        # App entry, hotkey, dispatch
│   ├── Views/
│   │   ├── MainDashboardView.swift   # Main UI (Settings + Run Log tabs)
│   │   └── SettingsView.swift        # Legacy settings pane
│   └── Services/
│       └── WhisperService.swift      # STT + polish + translate pipeline
├── build_beta_dmg.sh                 # Packages VoiceFlow-Beta.dmg
└── VoiceFlow-Beta.dmg                # Shareable ad-hoc build
```

---

## 🧠 Core Domain Model

### `TranscriptOutputStyle` (enum)
Drives the polish pipeline. Four modes:

| Case | Behavior |
|---|---|
| `verbatim` | Raw Whisper output. No polish. |
| `clean` | Remove fillers, fix punctuation. Keep source language. |
| `cleanHinglish` | Devanagari → Latin transliteration. Keep mixed Hindi/English readable. |
| `translateEnglish` | Translate any spoken language → natural English. |

### `TranscriptProcessingMode` (enum)
- `dictation` — preserve user phrasing (default)
- `rewrite` — tighten grammar, collapse restarts

### `PolishBackend` (abstraction)
Runtime choice: OpenAI / LM Studio / Ollama. All use Chat Completions API shape.

---

## 🔀 Dispatch Logic (the "smart default")

In `VoiceFlowApp.swift` around line 630:

```swift
let userSelectedStyle = TranscriptOutputStyle(rawValue: outputModeRaw) ?? .cleanHinglish
let effectiveStyle: TranscriptOutputStyle = {
    if userSelectedStyle == .verbatim { return .verbatim }
    if language == "en" { return .translateEnglish }   // English lock = auto-translate
    return userSelectedStyle
}()
let transcriptionLanguage = (effectiveStyle == .translateEnglish && language == "en") ? "auto" : language
```

**The key product insight**: when user locks Language to English but speaks Hindi, we *translate* instead of failing. Language selector becomes the "output language I want" knob, not just the STT hint.

---

## 🎚️ Current UX Surface

**Main dashboard has 2 knobs:**
1. **Language**: `Auto` / `English` (more coming — see Open Problems)
2. **Output Style**: Verbatim / Clean / Clean+Hinglish

**Plus Run Log tab** — every dictation logged with timing, source audio path, error details. Critical for debugging transcripts gone wrong.

---

## ✅ What Works

- Fn-hold global hotkey (AVFoundation + CGEventTap)
- Real-time STT via OpenAI Whisper
- Polish via `gpt-4.1-nano` with skip heuristic (Devanagari + filler detection)
- Hindi → English real-time translation (when Language=English)
- Menu bar app with Settings + Run Log
- Ad-hoc signed DMG shareable to other Macs

## ❌ Known Issues / Rough Edges

1. **Bengali translation fails silently.** STT detects Bengali fine, but `translateToEnglish()` prompt is Hindi-biased ("most likely Hindi, English, or Hinglish"). Non-Hindi scripts fall through. Fix: generalize the prompt.

2. **No Apple Developer signing.** Ad-hoc means testers hit "VoiceFlow is damaged" dialog. Workaround is `xattr -cr /Applications/VoiceFlow.app`. Real fix: $99/yr Dev ID + notarization.

3. **arm64 only.** Intel Macs can't run it.

4. **Language dropdown will bloat** as we add Bengali/Tamil/Marathi/etc. Wispr handles this with onboarding-time language-selection (you pick what you speak, not every run).

5. **No auto-update.** Every build = new DMG + manual reinstall. Sparkle framework is the fix.

6. **No onboarding.** First launch dumps user into Settings. Should be a 2-step flow: "what languages do you speak?" + "default output style?"

---

## 🧭 Product Decisions & Tradeoffs

| Decision | Rationale | Tradeoff |
|---|---|---|
| **BYO API key** | No backend cost, faster to ship, user owns their data | Each tester needs OpenAI account + billing = onboarding friction |
| **OpenAI only (for MVP)** | Best Hindi STT quality in 2026; one API to debug | Vendor lock-in; no offline fallback |
| **Hindi-first, English-output** | Target user is bilingual Indian — this combo is underserved | Narrows audience vs. "every language" positioning |
| **Menu bar app, not dock** | Dictation should be ambient, not a "launch the app" flow | Less discoverable; users forget it's installed |
| **Local plist storage** | Zero-config, privacy-preserving | No cross-device sync |
| **Ad-hoc signed DMG** | Ship to 5 testers today, defer $99/yr until validated | Each tester does one-time Terminal command |

---

## 🗺️ Roadmap (my current priority order)

**Now (this week)**
- Fix Bengali translator prompt → generalize to "any language → English"
- Expand Language enum to include top 5 Indian languages
- Ship Wispr-style 2-step onboarding

**Next**
- Output Presets (5 templates: Default / WhatsApp / Email / Meeting / LinkedIn) — the 20% effort / 80% value play
- Apple Developer ID signing + notarization (kills install friction)
- Sparkle auto-update

**Later**
- Offline Whisper.cpp for privacy-first tier
- Usage dashboard (cost tracking per dictation)
- Team/org version with shared proxy key

---

## 🧪 How to Build / Run Locally

```bash
# Build & install
cd /Users/raunaksingh/Documents/VoiceFlow
./build.sh                            # swift build + codesign + install to /Applications

# Package beta DMG
./build_beta_dmg.sh                   # outputs VoiceFlow-Beta.dmg + SHA-256
```

**Runtime permissions needed on user Mac:**
- Microphone (record voice)
- Accessibility (paste text into other apps via CGEvent)

---

## 💬 How to use this context

When asking another AI for help, include:
1. This file (paste verbatim at start of chat).
2. The specific file(s) you want changed (paste relevant code).
3. Your actual question.

**Good prompt shape:**
> "Here's my project context [paste this file]. Here's `WhisperService.swift` [paste].
> I want to generalize the Bengali translation bug — the `translateToEnglish()`
> prompt assumes Hindi. Propose a language-agnostic prompt that still handles
> code-switching well."

**Bad prompt shape:**
> "Fix my Swift app it doesn't translate."

---

*Last updated: 2026-04-20 · Build SHA-256: `9cdef12b111a9f34e693f0a5c22ee4f26214922130513913f49309146d0d1404`*
