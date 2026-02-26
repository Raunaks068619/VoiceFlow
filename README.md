# VoiceFlow

VoiceFlow is a macOS menu-bar voice typing app inspired by Freeflow-style workflows:
- Hold a hotkey to record
- Release to transcribe
- Insert text into the active app

Menu option:
<img width="299" height="323" alt="Screenshot 2026-02-26 at 4 22 21 PM" src="https://github.com/user-attachments/assets/ebc1b997-a68b-48a8-947c-ec3a7d0255bd" />
Settings:
<img width="471" height="522" alt="Screenshot 2026-02-26 at 4 22 34 PM" src="https://github.com/user-attachments/assets/b404a794-d1c3-42d9-a53b-af5d75ef8db9" />
More Settings:
<img width="472" height="524" alt="Screenshot 2026-02-26 at 4 22 40 PM" src="https://github.com/user-attachments/assets/d4e89312-a0c6-4f2b-a536-d4c1a18a1296" />
Onboarding:
<img width="521" height="450" alt="Screenshot 2026-02-26 at 4 22 58 PM" src="https://github.com/user-attachments/assets/b87bebd1-1d53-4f86-a7ca-bf342eeacdda" />

Test Speech to text ENGLISH:
<img width="764" height="756" alt="Screenshot 2026-02-26 at 4 29 26 PM" src="https://github.com/user-attachments/assets/41bb65bd-d3f4-45d5-9410-030d93679b4b" />
Tets Speech to text Hindi+English
<img width="700" height="737" alt="Screenshot 2026-02-26 at 4 29 38 PM" src="https://github.com/user-attachments/assets/9da697fd-1575-49cc-b339-2396dfd0c1f4" />


It supports:
- Global hotkeys (`Fn` and fallback `Right Option`)
- OpenAI speech transcription
- Cleanup modes (`Verbatim`, `Clean`, `Clean + Hinglish`)
- Dictation vs Rewrite processing modes
- Background-noise filtering

## Requirements

- macOS 13+
- Xcode 15+
- OpenAI API key

## Project Structure

- `Sources/App` - app lifecycle and menu bar integration
- `Sources/Services` - hotkey listener, audio recorder, transcription, text injection
- `Sources/Views` - popover UI, onboarding, settings, recording overlay
- `Resources` - `Info.plist`, entitlements

## Run Locally (Xcode)

1. Open the project:
   - `VoiceFlow.xcodeproj`
2. In Xcode, select scheme:
   - `VoiceFlow`
3. Build and run:
   - `Product -> Run`

The app runs in the menu bar (accessory app), not as a regular Dock app.

## First-Time Setup

On first launch, onboarding appears.

1. Add your OpenAI API key.
2. Grant **Microphone** permission.
3. Grant **Accessibility** permission.
4. (Recommended) Grant **Input Monitoring** permission:
   - `System Settings -> Privacy & Security -> Input Monitoring`
   - Add `VoiceFlow.app` from Xcode build output if needed.

## Keyboard Setup

- Primary trigger: `Fn`
- Fallback trigger: `Right Option`

If `Fn` does not work:
1. Set `System Settings -> Keyboard -> Press 🌐 key to` as `Do Nothing`.
2. Disable/reassign Dictation shortcut from `Press 🌐 Twice`.
3. Use `Right Option` fallback.

## Settings Guide

Open from menu bar -> `Settings...`

- **Language**
  - `Auto-detect` recommended
- **Output Quality**
  - `Verbatim`: closest to raw transcript
  - `Clean`: grammar/punctuation cleanup
  - `Clean + Hinglish`: English stays English; Hindi is converted to Latin-script Hindi
- **Transcription Mode**
  - `Dictation`: preserve spoken phrasing
  - `Rewrite`: cleaner intent-focused phrasing
- **Microphone Filter**
  - Higher value filters more background noise
  - Start around `0.008` to `0.012`

## How Transcription Works

Pipeline:
1. Record audio from microphone
2. Apply light voice activity filtering
3. Transcribe with OpenAI speech model (with fallback)
4. Post-process text by selected mode/style
5. Insert into active app using paste-based injection

## Troubleshooting

### App UI works but no transcription output

Check Xcode logs for:
- `Recording started`
- `Recording stopped`
- `Transcription success: ... chars`
- `Transcription error: ...`

### No hotkey trigger

- Confirm Accessibility is enabled for VoiceFlow
- Enable Input Monitoring for VoiceFlow
- Use `Right Option` if `Fn` is intercepted by system settings

### Background conversations are captured

- Increase `Microphone Filter` threshold in Settings
- Move mic away from noise source
- Use directional/external mic if possible

### Wrong script or language style

Use:
- `Language: Auto-detect`
- `Output Quality: Clean + Hinglish`
- `Transcription Mode: Dictation`

## Notes

- This app is intended for local development/testing from Xcode.
- API usage incurs OpenAI costs based on your account/model usage.
