# 🔐 Installing VoiceFlow — Permissions Guide

A short walkthrough for getting VoiceFlow running. **5 minutes**, mostly waiting for permission prompts.

---

## ⚠️ Prerequisite — Managed-Mac users (GoFynd / Hexnode)

If your Mac is **managed by Hexnode** (or any MDM — JAMF, Kandji, Mosyle), you **must** have the following Hexnode policies allowed *before* anything else works:

- 🎤 **Microphone access for third-party apps** — without this, the OS-level mic switch is greyed out and nothing you do in System Settings will change it.
- ♿ **Accessibility access for third-party apps** — required for VoiceFlow to inject text into other apps.
- ⌨️ **Input Monitoring** — required for the global Fn-key hotkey.
- 🛡️ **Allow apps not from the App Store** (`Gatekeeper / Privacy & Security`) — VoiceFlow is open-source, distributed via DMG, not the App Store.

**If any of these are blocked at the MDM level**, the toggles in `System Settings → Privacy & Security` will either be missing or refuse to flip. **Ask IT to clear those policies for your machine first.** No amount of clicking around in System Settings will work otherwise — the OS is honoring a higher-priority denial.

If your Mac is **personal / unmanaged**, skip this section entirely.

---

## 1️⃣ Install

Easiest — Homebrew (handles quarantine + ad-hoc signing for you):

```bash
brew install --cask raunaks068619/voiceflow/voiceflow
```

Or manually:

1. Download the latest DMG from <https://github.com/Raunaks068619/VoiceFlow/releases/latest>
2. Open the DMG, drag **VoiceFlow.app** to **Applications**
3. **Right-click → Open** the first time (Gatekeeper warning is normal — this is an ad-hoc signed build)
4. Open Terminal once and run:
   ```bash
   xattr -dr com.apple.quarantine /Applications/VoiceFlow.app
   codesign --force --deep --sign - /Applications/VoiceFlow.app
   ```
   (Homebrew install does this automatically — only needed for manual install.)

---

## 2️⃣ Grant the three macOS permissions

VoiceFlow's onboarding window walks you through these on first launch. If you skipped it or want to re-do it, the manual paths are below.

### 🎤 Microphone

> **Why:** record your voice when you hold Fn.

`System Settings → Privacy & Security → Microphone` → toggle **VoiceFlow** ON.

If VoiceFlow doesn't appear in the list, hold Fn once with the app running — that triggers the OS prompt that adds the entry.

### ♿ Accessibility

> **Why:** type the transcribed text into your active text field (Slack, Cursor, Notion, anywhere).

`System Settings → Privacy & Security → Accessibility` → click **➕** → navigate to `/Applications/VoiceFlow.app` → toggle ON.

### ⌨️ Input Monitoring

> **Why:** detect the global Fn keypress from any app.

`System Settings → Privacy & Security → Input Monitoring` → click **➕** → add **VoiceFlow.app** → toggle ON.

---

## 3️⃣ Verify

1. Open VoiceFlow from Applications (it lives in your menu bar — look for the orange waveform).
2. Open the dashboard → **Settings** tab → **Permissions** card. All three should read **Granted** in green.
3. Click into any text field (Notes, Slack, your terminal — anywhere with a blinking cursor).
4. **Hold Fn**, speak a sentence, **release Fn**.
5. Within ~2s, your transcript appears at the cursor. ✨

---

## 🛠️ Troubleshooting

| Problem | Fix |
|--|--|
| **Toggles in System Settings are greyed out / missing** | MDM (Hexnode) is blocking them. Ask IT to clear the relevant policy. No software fix exists. |
| **Mic toggle is ON but VoiceFlow shows "not granted"** | Toggle off + back on. If still stuck: `tccutil reset Microphone com.voiceflow.app` in Terminal, then relaunch. |
| **Hold Fn does nothing** | Input Monitoring isn't granted, OR the Fn key is remapped (System Settings → Keyboard → "Press fn key to:" should be set to **Do Nothing** or **Show Emoji & Symbols**, NOT **Change Input Source**). |
| **"VoiceFlow can't be opened because Apple cannot check it..."** | Right-click → Open → Open anyway. Or: `xattr -dr com.apple.quarantine /Applications/VoiceFlow.app` |
| **Recording works but no text appears** | Accessibility permission missing, OR your cursor isn't in a text field when you release Fn. Check the floating chip — it warns when there's no text input focused. |
| **Hindi gets transcribed but stays in Hindi** | Settings → Output Style → pick **English** (translates to English) or **Hinglish** (preserves bilingual mix in Latin script). |
| **App quits after first click on Fn** | Stale ad-hoc signature. Re-run the `xattr` + `codesign --sign -` block from step 1. |

---

## 💬 Need help?

Open an issue at <https://github.com/Raunaks068619/VoiceFlow/issues> or DM Raunak on Slack.

Include:
- macOS version (`sw_vers`)
- Whether your Mac is MDM-managed (and which MDM)
- Output of `~/Documents/VoiceFlow/scripts/verify_build.sh` if you have the repo locally
- Console.app logs filtered for `VoiceFlow` around the time of the failure
