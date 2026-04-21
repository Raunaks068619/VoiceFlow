# VoiceFlow Onboarding Plan

> First launch today dumps users into a settings pane. That's the single biggest install-to-active drop-off point we have. This plan ports FreeFlow's onboarding architecture to VoiceFlow's language-first identity.

**Core thesis:** onboarding is the product's first impression. A user who successfully dictates their first sentence in under 90 seconds becomes a power user; one who bounces off permission prompts uninstalls in a day.

---

## Mental model

FreeFlow's onboarding is a **linear enum state machine** with a "Continue" gate that's only unlocked when the current step is satisfied. Each step owns its own view, its own satisfied-predicate, and (for side-effect steps) its own polling loop. Nothing is nested; the whole flow is one big `switch step` in a `SetupView`.

We steal that shape. Where VoiceFlow diverges from FreeFlow is **language configuration** — it's our reason to exist, so it gets its own onboarding step, not a post-onboarding preference.

---

## Step sequence (6 steps)

FreeFlow has 12. We ruthlessly cut — first-launch attention is precious.

| # | Step | Why it's here | Cut from FreeFlow |
|---|------|---------------|-------------------|
| 1 | **Welcome** | Identity + value prop + one-sentence pitch | — |
| 2 | **API Key** | Zero-config is impossible with BYO-key model | — |
| 3 | **Permissions** | Mic + Accessibility in ONE step (polled) | Split into 3 steps (mic / accessibility / screen recording) |
| 4 | **Languages + Output Style** | Our differentiator — pick what you speak | `commandMode`, `vocabulary`, `launchAtLogin`, `toggleShortcut` |
| 5 | **Try It** | Live dictation with real transcript | — |
| 6 | **Ready** | Confirmation + "here's your menu bar icon" pointer | — |

Skipped entirely: screen recording (we don't need it), hold-vs-toggle shortcut config (Fn is hardcoded), command mode (not shipped), vocabulary (not shipped), launch-at-login (moved to Settings tab as opt-in).

---

## File layout

```
Sources/Views/Onboarding/
├── SetupView.swift              # Root coordinator + enum + nav
├── Steps/
│   ├── WelcomeStep.swift
│   ├── APIKeyStep.swift
│   ├── PermissionsStep.swift    # Mic + Accessibility combined
│   ├── LanguageStep.swift
│   ├── TestTranscriptionStep.swift
│   └── ReadyStep.swift
└── Components/
    ├── StepIndicator.swift      # 6 dots
    └── NavigationBar.swift      # Back + Continue + step dots
```

One enum drives everything:

```swift
private enum SetupStep: Int, CaseIterable {
    case welcome = 0
    case apiKey
    case permissions
    case language
    case testTranscription
    case ready
}
```

---

## State machine contract

```swift
@State private var currentStep: SetupStep = .welcome

// Each step declares whether it satisfies the "Continue" gate.
private var canContinue: Bool {
    switch currentStep {
    case .welcome: return true
    case .apiKey: return isAPIKeyValidated
    case .permissions: return micGranted && accessibilityGranted
    case .language: return true  // has a default
    case .testTranscription: return true  // user can skip
    case .ready: return true
    }
}

private func next() {
    guard let next = SetupStep(rawValue: currentStep.rawValue + 1) else {
        completeOnboarding()
        return
    }
    currentStep = next
}

private func back() {
    guard let prev = SetupStep(rawValue: currentStep.rawValue - 1) else { return }
    currentStep = prev
}
```

**Root layout** mirrors FreeFlow:

```swift
VStack(spacing: 0) {
    stepContent              // 1 step visible at a time, switch currentStep
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    Divider()
    NavigationBar(...)       // Back · dots · Continue
}
.frame(width: 560, height: 680)
.fixedSize()
```

---

## Step-by-step implementation notes

### Step 1: Welcome

Pure marketing. One headline, one subhead, one CTA. No state.

```
[VoiceFlow logo, 64pt]
"Hold Fn. Speak Hindi or English. Done."
Built for the 600M people who code-switch.
                                    [Get Started]
```

No back button. Continue is always enabled.

### Step 2: API Key

`SecureField` bound to `@State apiKeyInput`. Continue calls an async validator:

```swift
func validateAPIKey(_ key: String) async -> Result<Void, APIError> {
    // Cheapest valid endpoint: GET /v1/models
    var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
    req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    do {
        let (_, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return .failure(.network) }
        switch http.statusCode {
        case 200: return .success(())
        case 401: return .failure(.invalidKey)
        default:  return .failure(.unknown(http.statusCode))
        }
    } catch {
        return .failure(.network)
    }
}
```

Why roundtrip validation (not length-check): `sk-` prefix matching catches typos but not revoked keys or account-billing-disabled. The one round-trip saves a "nothing works and I don't know why" support thread.

Show a spinner while validating, persist to UserDefaults on success, advance on success.

### Step 3: Permissions (combined)

**Key insight:** macOS shows permission prompts for mic and accessibility in different ways. Mic opens a modal on first request; Accessibility opens System Settings. We need to handle both in one view with polling so the user doesn't have to click "I did it" — we detect the grant automatically.

```swift
@State private var micGranted = false
@State private var accessibilityGranted = false
@State private var pollTimer: Timer?

.onAppear {
    refresh()
    pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        DispatchQueue.main.async { refresh() }
    }
}
.onDisappear { pollTimer?.invalidate() }

private func refresh() {
    micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    accessibilityGranted = AXIsProcessTrusted()
}
```

UI is two rows with live checkmarks. Each row has a "Grant" button:

- Mic button → `AVCaptureDevice.requestAccess(for: .audio)` which triggers the system modal
- Accessibility button → opens Settings directly: `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)`

Continue unlocks when BOTH are green.

### Step 4: Language + Output Style

This is where VoiceFlow's identity shows. Two sections in one step:

```
What languages do you speak?
[✓ English] [✓ Hindi] [Hinglish] [Auto-detect]     ← multi-select

How should output look?
( ) Verbatim — exactly what you said
(•) Clean — remove fillers, fix punctuation        ← default
( ) Clean + Hinglish — Latin script for mixed
```

Continue is always enabled; defaults are chosen. Writes to:
- `UserDefaults.standard.set(lang, forKey: "language")` (stored as array or single value depending on final picker shape)
- `UserDefaults.standard.set(style, forKey: "output_mode")`

This is the step FreeFlow **doesn't have** — they're English-only, so it's a no-op. For us, this one screen is the reason someone downloaded us.

### Step 5: Try It

FreeFlow's `TestPhase` enum is clean — steal it verbatim:

```swift
enum TestPhase: Equatable { case idle, recording, transcribing, done(String) }
@State private var phase: TestPhase = .idle
```

UI:

```
Press and hold Fn. Say anything.
          [🎤 animated waveform]

[Transcript appears here when done]
                       [Skip]  [Continue]
```

Hook the existing `HotKeyListener` (but scoped to this view — use a separate listener instance so the user hasn't technically "started using" the app yet). On Fn-down → phase = .recording + show waveform. On Fn-up → call `WhisperService.transcribeAndPolishWithMetadata`, phase = .transcribing. On result → phase = .done(text), show text, enable Continue.

On error or empty transcript → red message, "try again" prompt, Continue still enabled (we don't gate on success — they can try later from the menu bar).

This step converts. The moment the user sees their own words come back, they get it.

### Step 6: Ready

```
You're all set.

VoiceFlow lives in your menu bar.
Hold Fn anywhere to dictate.

      [↑ points to menu bar icon]

                     [Start Dictating]
```

"Start Dictating" → dismisses setup window + sets `UserDefaults.standard.set(true, forKey: "onboarding_completed")`.

---

## Integration points

### Gate onboarding on first launch

In `VoiceFlowApp.applicationDidFinishLaunching`:

```swift
if !UserDefaults.standard.bool(forKey: "onboarding_completed") {
    showOnboardingWindow()
} else {
    showMainWindow()
}
```

The existing `onboardingWindow` property on AppDelegate is ready for this — we just need to populate it.

### Re-openable onboarding

Add a hidden "Reset Onboarding" button in Settings → footer (behind a secret key combo like ⌥-click). Useful for debugging + for screen-recording demos ("here's what a new user sees").

---

## Execution order (minimum viable onboarding)

Ship in this order — each step independently adds value.

1. **SetupView skeleton** + enum + navigation bar + step dots (1 evening)
2. **Welcome + Ready steps** (trivial, pad the edges so the flow has shape)
3. **Permissions step** with live polling (2 evenings — the AX poll is where bugs hide)
4. **API Key step** with async validation (1 evening)
5. **Language + Output Style step** (1 evening — reuse existing pickers)
6. **Test transcription step** (2 evenings — scoped hotkey listener is non-trivial)

**Total estimate: ~7 evenings.** Ship step-by-step, gate on `if UserDefaults.standard.bool(forKey: "onboarding_completed") { skip }` so partial builds still work.

---

## Tradeoffs flagged explicitly

| Decision | Why | Cost |
|---|---|---|
| Combine mic + accessibility into one step | FreeFlow's split feels bureaucratic; our audience is power users | If Accessibility prompt is slow, both appear stalled |
| Validate API key via network roundtrip | Catches revoked/billing-dead keys early | +1 network hop, needs offline fallback prompt |
| Skip shortcut config | Fn is hardcoded today, saves a step | Users who want ⌘-Space or similar can't customize |
| Skip launch-at-login in onboarding | Not critical-path for first success | Users may not discover it; add banner in Settings |
| Polling via Timer (not Combine/async stream) | Simpler, matches FreeFlow, 1Hz is fine | One more thing to invalidate on disappear |

---

## What we're NOT shipping

- Step for switching between OpenAI / Groq (OpenAI default, Settings has the toggle)
- Step for polish backend (OpenAI default, Settings has the toggle)
- Vocabulary / custom words (not in product yet)
- Toggle-mode shortcut (only hold-Fn today)
- Real-time streaming opt-in (default OFF, Settings has the toggle)

All of these belong in Settings, not onboarding. The onboarding contract is: **shortest path from launch to "I dictated something and it worked."**

---

## Success metric

Proxy metric for validating this works without analytics:

> Did the user's first Run Log entry happen within 120 seconds of first launch?

Already captured in RunStore timestamps + install time from the app bundle's creation date. No new instrumentation needed.
