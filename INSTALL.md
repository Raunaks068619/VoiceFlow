# 📦 Installing VoiceFlow on Another Mac

VoiceFlow is distributed as a `.dmg`. There are two install paths depending on whether the build is **signed + notarized** by an Apple Developer ID, or **ad-hoc / unsigned** (open-source build).

---

## 🅰️ Signed + Notarized DMG (recommended)

This requires an Apple Developer Program membership ($99/yr). The user experience is seamless:

1. Double-click `VoiceFlow-vX.Y.Z.dmg`
2. Drag `VoiceFlow.app` to `/Applications`
3. Launch from `/Applications` → accept permission prompts
4. Done.

No right-click bypass needed. macOS Gatekeeper trusts the notarization ticket.

---

## 🅱️ Unsigned / Ad-hoc DMG (free open-source workflow)

When the DMG is built with `scripts/release_dmg_unsigned.sh`, macOS flags it with the `com.apple.quarantine` attribute. Symptoms your friend is hitting:

- **"App is damaged and can't be opened"** on second launch
- **No microphone prompt** appears at all
- **App quits immediately** after first action

This is Gatekeeper quarantine + hardened runtime blocking access — it has nothing to do with your code.

### The one-shot fix (run once after installing)

After dragging `VoiceFlow.app` to `/Applications`, open **Terminal** and run:

```bash
xattr -dr com.apple.quarantine /Applications/VoiceFlow.app
codesign --force --deep --sign - /Applications/VoiceFlow.app
```

What this does:

| Command | Why |
|---|---|
| `xattr -dr com.apple.quarantine` | Strips the Gatekeeper quarantine flag recursively. Stops macOS from nuking the app on second launch. |
| `codesign --force --deep --sign -` | Re-applies a fresh ad-hoc signature on the friend's machine so TCC (the permissions database) treats it as a stable identity. Without this, every launch looks like "a new app" and mic permission never sticks. |

Then launch it:

```bash
open /Applications/VoiceFlow.app
```

### First-run permission flow

1. Click the waveform icon in the menu bar
2. Onboarding window opens
3. Grant **Microphone**, **Accessibility**, **Input Monitoring**
4. Quit and relaunch once (TCC sometimes needs a restart to fully register)

---

## 🔍 Why permissions were silently failing before

Two bugs were fixed in this version:

1. **Missing `com.apple.security.device.audio-input` entitlement.** The project has `ENABLE_HARDENED_RUNTIME: YES` but the entitlements file was empty (`<dict/>`). Under hardened runtime, macOS requires explicit entitlements for each protected resource. No entitlement → no mic prompt, ever. Fixed in `Resources/VoiceFlow.entitlements`.

2. **Ad-hoc signature instability across machines.** Apps signed with `-` (ad-hoc) get a signature tied to the build machine's state. When copied via DMG, macOS sees a mismatched identity and revokes TCC permissions, causing the "works first time, crashes next time" pattern. Re-signing on the target machine (step 2 above) gives it a stable local identity.

---

## 🛠️ Troubleshooting

**"VoiceFlow can't be opened because Apple cannot check it for malicious software"**
→ Right-click the app → Open → Open anyway. Or run the `xattr` command above.

**Mic permission toggle exists in System Settings but mic still doesn't work**
→ Toggle it off and back on. Sometimes:
```bash
tccutil reset Microphone com.voiceflow.app
```
then relaunch.

**App launches, recording overlay shows, but no transcription**
→ Check Console.app for `VoiceFlow` logs. Most common cause is a missing or invalid OpenAI API key in Settings.

**App quits after first function click**
→ You're on a stale unsigned build. Re-run the `xattr` + `codesign --sign -` fix and relaunch.
