# VoiceFlow — Session Context

> Paste this into a new Cowork chat to resume where we left off.
> Last updated: April 18, 2026

---

## What Is VoiceFlow

A macOS-native dictation app. Hold Fn → speak → release → transcribed + polished text is injected into the active text field. Built in pure Swift + SwiftUI, no Electron. Targets macOS 13+.

**Bundle ID**: `com.voiceflow.app`
**Project location**: `~/Documents/VoiceFlow/`
**Xcode project**: `VoiceFlow.xcodeproj` (manual pbxproj, no SPM packages)

---

## File Map

```
Sources/
├── App/
│   └── VoiceFlowApp.swift          # @main scene (MenuBarExtra) + AppDelegate (all orchestration)
│                                     # Also contains: PermissionService, PermissionState, PermissionPane
├── Models/
│   └── RunModel.swift               # Run, RunStatus, CaptureStage, TranscriptionStage, PostProcessingStage, RunSummary
├── Services/
│   ├── AudioRecorder.swift          # AVAudioEngine-based capture, outputs WAV Data
│   ├── HotKeyListener.swift         # CGEvent tap + NSEvent global monitor for Fn key
│   ├── RunRecorder.swift            # RunSession builder — accumulates pipeline stages, flushes to RunStore
│   ├── RunStore.swift               # Filesystem ring buffer (~/Library/Application Support/VoiceFlow/runs/), @Published summaries
│   ├── TextInjector.swift           # CGEvent-based keystroke injection into active text field
│   └── WhisperService.swift         # Whisper API transcription + LLM post-processing, hallucination blocklist, TranscriptionMetadata
├── Views/
│   ├── AccessibilityGuideView.swift # Onboarding card for Accessibility permission
│   ├── InputMonitoringGuideView.swift # Onboarding card for Input Monitoring permission
│   ├── MainDashboardView.swift      # Primary window — sidebar (General + Run Log tabs) + content area. Also defines RecordingStateStore
│   ├── MenuBarView.swift            # MenuBarExtra dropdown content, observes AppDelegate via @EnvironmentObject
│   ├── RecordingOverlayWindow.swift # NSPanel notch chip — spring slide-in animation, WaveformIndicator, PulsingDotsIndicator
│   ├── RunLogView.swift             # RunLogView (list), RunRowView, RunDetailView (pipeline stages + audio playback)
│   └── SettingsView.swift           # Settings window + OnboardingView (inline)
Resources/
├── Info.plist
├── VoiceFlow.entitlements           # com.apple.security.device.audio-input (CRITICAL — was empty before, caused all mic issues)
└── VoiceFlow.icns
```

---

## Architecture Decisions

### Menu Bar: SwiftUI `MenuBarExtra` (not NSPopover/NSPanel)
- Switched from NSPopover → custom NSPanel → MenuBarExtra across this session
- MenuBarExtra handles positioning, focus, fullscreen behavior, dismissal automatically
- MenuBarView observes AppDelegate via `@EnvironmentObject` — no manual refresh needed
- Same pattern as FreeFlow (https://github.com/zachlatta/freeflow)

### Recording Overlay: NSPanel at `.screenSaver` level
- Spring overshoot slide-in animation: `CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1.0)` — 180ms
- Slide-up + fade-out on hide
- Spring content transitions: `.spring(response: 0.28, dampingFraction: 0.8)` for recording↔processing
- Timer lifecycle: `onAppear`/`onDisappear` — timers only run while visible (fixed 94% CPU idle bug)

### Permission Polling: PermissionService
- Polls every 2s (was 750ms — caused CPU issues with MenuBarExtra)
- **Stops polling entirely** once all 3 permissions are granted
- Guards against redundant `@Published` assignments (same-value sets fire objectWillChange in Swift)
- Fires `onPermissionNewlyGranted` callback for hot-reload of HotKeyListener

### STT Pipeline
- **Current**: OpenAI Whisper API (`whisper-1`) — ~2-4s per 10s clip
- **Post-processing**: GPT-4o-mini — ~500ms-1.5s
- **Hallucination blocklist**: 20+ Hindi phrases blocked (Whisper hallucinates on silence)
- TranscriptionMetadata captures provider, rawText, latencies, prompts, guard flags

### Run Log
- Domain: immutable ledger entries (Run) with 3 pipeline stages (Capture → Transcription → PostProcess)
- Storage: filesystem ring buffer at `~/Library/Application Support/VoiceFlow/runs/`, max 20 runs
- `index.json` for lightweight list rendering, per-run folders with `audio.wav` + `run.json`
- RunRecorder creates RunSession instances that accumulate stage data

### Code Signing
- Ad-hoc signed (`-` identity) with hardened runtime
- Entitlements: `com.apple.security.device.audio-input` (REQUIRED for mic)
- Both `AVCaptureDevice.requestAccess(for: .audio)` AND `AVAudioApplication.requestRecordPermission` called for ad-hoc compatibility
- `IOHIDRequestAccess` for Input Monitoring (not `CGRequestListenEventAccess` which is broken for ad-hoc)

---

## Build & Install

```bash
cd ~/Documents/VoiceFlow

# Build
xcodebuild -project VoiceFlow.xcodeproj -scheme VoiceFlow -configuration Release -derivedDataPath build/DerivedData clean build

# Install (if /Applications/VoiceFlow.app is user-owned)
ditto build/DerivedData/Build/Products/Release/VoiceFlow.app /Applications/VoiceFlow.app
codesign --force --deep --sign - -o runtime --entitlements Resources/VoiceFlow.entitlements /Applications/VoiceFlow.app

# Install (if /Applications/VoiceFlow.app is root-owned — needs admin)
# Use: osascript -e 'do shell script "ditto ... && chown -R $(whoami):staff ..." with administrator privileges'

# Launch
open /Applications/VoiceFlow.app
```

**DMG installer**: `~/Documents/VoiceFlow/VoiceFlow-Installer.dmg` (770KB, ad-hoc signed)
- Not notarized — testers must right-click → Open → "Open" on first launch
- Contains VoiceFlow.app + /Applications symlink for drag-and-drop

---

## Bugs Fixed This Session

| Bug | Root Cause | Fix |
|-----|-----------|-----|
| Menu bar popup vanishes in fullscreen | NSPopover `.transient` auto-dismisses on focus loss | Replaced with MenuBarExtra (SwiftUI native) |
| 94.6% CPU at idle | `Timer.publish().autoconnect()` in overlay never stopped | `onAppear`/`onDisappear` lifecycle management |
| CPU climbs to 63% over time | PermissionService `@Published` set every 750ms (even same value) triggers MenuBarExtra re-render cascade | Guard redundant assignments + slow to 2s + stop when all granted |
| Mic never granted / not in privacy pane | `VoiceFlow.entitlements` was EMPTY (`<dict/>`) | Added `com.apple.security.device.audio-input` |
| Mic prompt never fires | No explicit mic request on launch + Fn key doesn't work without Accessibility | Delayed mic request on launch (1s) + fallback in startRecording |
| Whisper hallucinates Hindi on silence | Mic not granted → audio is silence → Whisper fills in | Extended hallucination blocklist with 20+ Hindi phrases |
| Onboarding not showing after reinstall | `has_completed_onboarding` persists in UserDefaults across installs | `defaults delete com.voiceflow.app` |
| App root-owned after admin install | `cp -R` with admin privileges → root ownership | `chown -R user:staff` after install |

---

## Pending / Next Steps

### STT Speed Optimization (researched, not implemented)
Best options validated:
1. **Groq Whisper API** — quickest win, drop-in batch replacement, 150x realtime (~67ms for 10s audio). Minimal code change.
2. **Deepgram Nova-3** — streaming WebSocket, sub-300ms partials, transforms UX (live transcription while speaking). ~1-2 days work.
3. **whisper.cpp / MLX** — local offline fallback, 2-3x faster than Python Whisper on Apple Silicon.

Recommended architecture: `STTProvider` protocol with streaming + batch methods, hybrid online/offline.

### Run Log Feature
- Code complete (RunModel, RunStore, RunRecorder, RunLogView) but **never tested end-to-end** — was blocked by mic issues
- Needs verification: record → check run appears in log → verify audio playback + transcript display

### Distribution
- DMG created but ad-hoc signed only
- For public distribution: need Apple Developer account ($99/yr) for notarization
- Consider auto-update mechanism (Sparkle framework)

### Open Items
- Test Run Log end-to-end now that mic should be working
- Implement Groq Whisper API integration for speed
- Consider adding user-configurable API key input in Settings
- The `OnboardingView` is defined inline in `SettingsView.swift` — should be its own file if it grows
- UI/UX polish: the main dashboard could use visual refinement

---

## Key Technical Gotchas

1. **macOS TCC identity** = bundle_id + code_signature + path + ownership. Changing ANY of these resets permissions.
2. **`AVAudioEngine.start()` does NOT trigger mic prompt** — it succeeds silently with silence. Must use `AVCaptureDevice.requestAccess` explicitly.
3. **`@Published` fires on every set, not just changes** — always guard with `if old != new` when polling.
4. **Write tool can mangle plists** — use `osascript` heredoc for XML files if needed.
5. **`CGRequestListenEventAccess`** is broken for ad-hoc signed apps since Monterey — use `IOHIDRequestAccess` instead.
6. **MenuBarExtra content** must use `@EnvironmentObject` pattern (declared in Scene body, not imperatively created).

---

## User Preferences (Raunak)

- TypeScript + Node.js primarily, but this project is Swift
- Thinks in systems, values "why" over "how"
- Startup/MVP mindset — 20% effort for 80% value
- Wants emojis, structured responses, dense and direct
- SDE2 at GoFynd — production-readiness matters
- Inspired by FreeFlow (https://github.com/zachlatta/freeflow)
