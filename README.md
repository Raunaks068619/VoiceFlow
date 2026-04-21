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
4. Grant **Input Monitoring** permission
   - `System Settings -> Privacy & Security -> Input Monitoring`
   - Add `VoiceFlow.app` from Xcode build output if needed
5. Onboarding `Done` stays disabled until all required permissions are granted.

## 🛡️ Permission Model

VoiceFlow requires 3 permissions:
- **Microphone**: capture audio
- **Accessibility**: inject transcribed text into the active app
- **Input Monitoring**: listen for global hotkeys

If any permission is missing:
- Hotkeys are unavailable
- Menu warning appears
- Settings shows permission health and quick-fix actions

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

## 📦 Signed + Notarized DMG Release

Use the provided release script:

```bash
scripts/release_dmg.sh \
  --version v1.0.0 \
  --app-path dist/VoiceFlow.app \
  --bundle-id com.voiceflow.app
```

Required environment:
- `DEVELOPER_ID_APP_CERT`
- Notarization auth:
  - `NOTARYTOOL_KEYCHAIN_PROFILE`, or
  - `APPLE_ID` + `APPLE_APP_SPECIFIC_PASSWORD` + `TEAM_ID`

Output:
- `dist/VoiceFlow-<version>.dmg`
- `dist/checksums.txt`

For friend testing:
1. Share the notarized DMG from `dist/`
2. Friend drags app to `/Applications`
3. Friend launches app and grants permissions in onboarding

## 📦 Installing on Another Mac (Unsigned Build)

See [INSTALL.md](./INSTALL.md) for the full walkthrough, including the one-shot
`xattr` + `codesign --sign -` fix for the "permissions don't stick / app crashes
after first use" problem on unsigned DMGs.

TL;DR after installing an unsigned build:

```bash
xattr -dr com.apple.quarantine /Applications/VoiceFlow.app
codesign --force --deep --sign - /Applications/VoiceFlow.app
open /Applications/VoiceFlow.app
```

Or just double-click `First Run (fix permissions).command` from the DMG.

## 📄 License

MIT — see [LICENSE](./LICENSE). Note: MIT is a *copyright* license for the
source code. It has **nothing to do with macOS code signing**. Distributing a
DMG that launches cleanly on another Mac still requires either an Apple
Developer ID certificate or the quarantine-strip workaround above.

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

### Input Monitoring prompt does not appear

- Open Onboarding or Settings and click `Request` for Input Monitoring
- Click `Open Settings` to jump directly to privacy pane
- If still missing, quit app, remove old entry from Input Monitoring list, relaunch and request again

### Too much background speech

- Increase `Microphone Filter`
- Reduce ambient noise / use better mic

### Wrong language/script style

Use:
- `Language: Auto-detect`
- `Output Quality: Clean + Hinglish`
- `Transcription Mode: Dictation`

### Quick permission matrix

| Symptom | Likely missing permission | Fix |
|---|---|---|
| No recording starts from hotkey | Input Monitoring | Request in onboarding, then open Input Monitoring settings |
| Recording works but no text typed | Accessibility | Request accessibility and enable app in system list |
| No audio captured | Microphone | Request microphone and confirm selected input device |

## 📁 Project Structure

- `Sources/App` - app lifecycle and menu bar behavior
- `Sources/Services` - recording, hotkeys, transcription, injection
- `Sources/Views` - popover, onboarding, settings, overlay
- `Resources` - plist and entitlements

## 📝 Notes

- Built for local development and testing with Xcode
- OpenAI API usage incurs model-based costs
