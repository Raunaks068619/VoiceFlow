# 🎙️ VoiceFlow

VoiceFlow is a macOS menu-bar voice typing app inspired by Freeflow workflows.

## ✨ Highlights

- Hold a hotkey to record, release to transcribe
- Smart output modes: `Verbatim`, `Clean`, `Clean + Hinglish`
- `Dictation` vs `Rewrite` mode
- Background-noise filtering
- Paste-based insertion for stable typing

## 🖼️ Product Showcase

### Menu Bar Popover
<img width="299" height="323" alt="VoiceFlow Menu" src="https://github.com/user-attachments/assets/ebc1b997-a68b-48a8-947c-ec3a7d0255bd" />

### Settings (General)
<img width="471" height="522" alt="VoiceFlow Settings" src="https://github.com/user-attachments/assets/b404a794-d1c3-42d9-a53b-af5d75ef8db9" />

### Settings (Advanced)
<img width="472" height="524" alt="VoiceFlow Advanced Settings" src="https://github.com/user-attachments/assets/d4e89312-a0c6-4f2b-a536-d4c1a18a1296" />

### Onboarding Flow
<img width="521" height="450" alt="VoiceFlow Onboarding" src="https://github.com/user-attachments/assets/b87bebd1-1d53-4f86-a7ca-bf342eeacdda" />

### English Transcription Example
<img width="764" height="756" alt="English Transcription Example" src="https://github.com/user-attachments/assets/41bb65bd-d3f4-45d5-9410-030d93679b4b" />

### Hindi + English (Hinglish) Example
<img width="700" height="737" alt="Hindi English Hinglish Example" src="https://github.com/user-attachments/assets/9da697fd-1575-49cc-b339-2396dfd0c1f4" />

## 🧰 Requirements

- macOS 13+
- Xcode 15+
- OpenAI API key

## 🚀 Run Locally

1. Open `VoiceFlow.xcodeproj` in Xcode
2. Select scheme `VoiceFlow`
3. Run: `Product -> Run`

VoiceFlow runs as a menu-bar app (no Dock icon by design).

## 🔐 First-Time Setup

1. Add your OpenAI API key
2. Grant **Microphone** permission
3. Grant **Accessibility** permission
4. Recommended: grant **Input Monitoring**
   - `System Settings -> Privacy & Security -> Input Monitoring`
   - Add `VoiceFlow.app` from Xcode build output if needed

## ⌨️ Hotkeys

- Primary: `Fn`
- Fallback: `Right Option`

If `Fn` does not work:
1. Set `System Settings -> Keyboard -> Press 🌐 key to` = `Do Nothing`
2. Disable/reassign Dictation shortcut from `Press 🌐 Twice`
3. Use `Right Option` fallback

## ⚙️ Settings Guide

- **Language**: `Auto-detect` recommended
- **Output Quality**:
  - `Verbatim`: closest to raw speech
  - `Clean`: grammar/punctuation cleanup
  - `Clean + Hinglish`: English stays English, Hindi becomes Latin-script Hindi
- **Transcription Mode**:
  - `Dictation`: preserve spoken phrasing
  - `Rewrite`: cleaner final intent text
- **Microphone Filter**:
  - Higher value = more background filtering
  - Good starting range: `0.008` to `0.012`

## 🧠 Transcription Pipeline

1. Record audio
2. Voice activity filtering (with fallback)
3. STT transcription (primary + fallback model)
4. Post-processing by mode/style
5. Inject text into active app

## 🛠️ Troubleshooting

### UI works but no transcription output

Check Xcode logs:
- `Recording started`
- `Recording stopped`
- `Transcription success: ... chars`
- `Transcription error: ...`

### Hotkey not triggering

- Verify Accessibility permission
- Verify Input Monitoring permission
- Try `Right Option` fallback

### Too much background speech

- Increase `Microphone Filter`
- Reduce ambient noise / use better mic

### Wrong language/script style

Use:
- `Language: Auto-detect`
- `Output Quality: Clean + Hinglish`
- `Transcription Mode: Dictation`

## 📁 Project Structure

- `Sources/App` - app lifecycle and menu bar behavior
- `Sources/Services` - recording, hotkeys, transcription, injection
- `Sources/Views` - popover, onboarding, settings, overlay
- `Resources` - plist and entitlements

## 📝 Notes

- Built for local development and testing with Xcode
- OpenAI API usage incurs model-based costs
