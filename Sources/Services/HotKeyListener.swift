import Foundation
import AppKit
import Carbon
import ApplicationServices

// MARK: - Hotkey configuration model
//
// Vordi's global shortcuts used to be hardcoded (Fn = push-to-talk,
// Fn+Ctrl = hands-free, Esc = exit). They're now user-configurable. The
// model below is the single source of truth, persisted by
// `HotkeySettingsStore` and pushed into `HotKeyListener` at runtime.

/// The modifier keys a combo can require. Stored as a bitmask so a whole combo
/// is a single `Int`. Bridges to `CGEventFlags` (used by the event-tap
/// listener) and `NSEvent.ModifierFlags` (used by the Settings recorder).
struct HotkeyModifiers: OptionSet, Codable, Equatable, Hashable {
    let rawValue: Int

    static let fn      = HotkeyModifiers(rawValue: 1 << 0)
    static let control = HotkeyModifiers(rawValue: 1 << 1)
    static let option  = HotkeyModifiers(rawValue: 1 << 2)
    static let shift   = HotkeyModifiers(rawValue: 1 << 3)
    static let command = HotkeyModifiers(rawValue: 1 << 4)

    init(rawValue: Int) { self.rawValue = rawValue }

    /// Build from AppKit modifier flags — the recorder capture path.
    init(nsFlags: NSEvent.ModifierFlags) {
        var m: HotkeyModifiers = []
        if nsFlags.contains(.function) { m.insert(.fn) }
        if nsFlags.contains(.control)  { m.insert(.control) }
        if nsFlags.contains(.option)   { m.insert(.option) }
        if nsFlags.contains(.shift)    { m.insert(.shift) }
        if nsFlags.contains(.command)  { m.insert(.command) }
        self = m
    }

    /// Number of distinct modifiers held.
    var count: Int { rawValue.nonzeroBitCount }

    /// Ordered display tokens, macOS convention: fn ⌃ ⌥ ⇧ ⌘.
    var displayTokens: [String] {
        var t: [String] = []
        if contains(.fn)      { t.append("fn") }
        if contains(.control) { t.append("⌃") }
        if contains(.option)  { t.append("⌥") }
        if contains(.shift)   { t.append("⇧") }
        if contains(.command) { t.append("⌘") }
        return t
    }

    /// Bridge to the flags the CGEvent tap sees.
    var cgFlags: CGEventFlags {
        var f: CGEventFlags = []
        if contains(.fn)      { f.insert(.maskSecondaryFn) }
        if contains(.control) { f.insert(.maskControl) }
        if contains(.option)  { f.insert(.maskAlternate) }
        if contains(.shift)   { f.insert(.maskShift) }
        if contains(.command) { f.insert(.maskCommand) }
        return f
    }
}

/// A single bindable combo.
/// - Modifier-only (`keyCode == nil`): a held chord like `fn` or `⌃⌥`,
///   detected via `flagsChanged`. Used for push-to-talk and hands-free.
/// - Key + modifiers (`keyCode != nil`): a `keyDown` like Esc. Used for the
///   hands-free exit gesture.
struct HotkeyBinding: Codable, Equatable, Hashable {
    var modifiers: HotkeyModifiers
    var keyCode: Int?

    var isModifierOnly: Bool { keyCode == nil }

    /// Tokens for the badge UI, e.g. `["⌃", "⌥"]` or `["esc"]`.
    var displayTokens: [String] {
        var tokens = modifiers.displayTokens
        if let code = keyCode {
            tokens.append(HotkeyKeyNames.name(for: code))
        }
        return tokens
    }

    var displayString: String { displayTokens.joined(separator: " ") }
}

/// Human-readable labels for a `keyDown` keyCode (US-ANSI layout). Only used
/// for display — the stored value is always the raw virtual keyCode.
enum HotkeyKeyNames {
    static func name(for keyCode: Int) -> String {
        if let named = special[keyCode] { return named }
        if let ansi = ansi[keyCode] { return ansi }
        return "key\(keyCode)"
    }

    private static let special: [Int: String] = [
        53: "esc", 49: "space", 36: "return", 76: "enter",
        48: "tab", 51: "delete", 117: "fwd-del",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6"
    ]

    private static let ansi: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 28: "8", 29: "0", 31: "O",
        32: "U", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N",
        46: "M", 30: "]", 33: "[", 39: "'", 41: ";", 42: "\\",
        43: ",", 44: "/", 47: ".", 50: "`", 27: "-"
    ]
}

/// The three rebindable actions.
enum HotkeyAction: String, CaseIterable, Identifiable {
    case pushToTalk
    case handsFree
    case exitHandsFree

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pushToTalk:    return "Push to talk"
        case .handsFree:     return "Hands-free mode"
        case .exitHandsFree: return "Exit hands-free"
        }
    }

    var subtitle: String {
        switch self {
        case .pushToTalk:    return "Hold to dictate, release to paste."
        case .handsFree:     return "Press once to start, again to stop."
        case .exitHandsFree: return "Also stops hands-free mode."
        }
    }

    var icon: String {
        switch self {
        case .pushToTalk:    return "mic.fill"
        case .handsFree:     return "waveform"
        case .exitHandsFree: return "escape"
        }
    }

    /// Push-to-talk and hands-free are held/pressed modifier chords; exit is a
    /// plain key. Drives which recorder behavior + validation applies.
    var isModifierOnly: Bool { self != .exitHandsFree }
}

/// The full set of bindings.
struct HotkeyConfig: Codable, Equatable {
    var pushToTalk: HotkeyBinding
    var handsFree: HotkeyBinding
    var exitHandsFree: HotkeyBinding

    static let `default` = HotkeyConfig(
        pushToTalk:    HotkeyBinding(modifiers: [.fn], keyCode: nil),
        handsFree:     HotkeyBinding(modifiers: [.fn, .control], keyCode: nil),
        exitHandsFree: HotkeyBinding(modifiers: [], keyCode: 53) // Esc
    )

    subscript(action: HotkeyAction) -> HotkeyBinding {
        get {
            switch action {
            case .pushToTalk:    return pushToTalk
            case .handsFree:     return handsFree
            case .exitHandsFree: return exitHandsFree
            }
        }
        set {
            switch action {
            case .pushToTalk:    pushToTalk = newValue
            case .handsFree:     handsFree = newValue
            case .exitHandsFree: exitHandsFree = newValue
            }
        }
    }

    /// The default binding for an action — the one exception to the
    /// "must be a combo" rule (bare fn / Esc are grandfathered).
    func defaultBinding(for action: HotkeyAction) -> HotkeyBinding {
        HotkeyConfig.default[action]
    }

    /// Validate a candidate binding for an action. Custom bindings must be a
    /// modifier combo so a single bare modifier can't misfire globally (the
    /// Right-Option mistake). The built-in default is always allowed.
    func validate(_ binding: HotkeyBinding, for action: HotkeyAction) -> String? {
        if binding == defaultBinding(for: action) { return nil }
        switch action {
        case .pushToTalk, .handsFree:
            if binding.keyCode != nil {
                return "Use a modifier combo (no letter key)."
            }
            if binding.modifiers.count < 2 {
                return "Pick at least two modifiers, e.g. ⌃⌥."
            }
            return nil
        case .exitHandsFree:
            if binding.keyCode == nil {
                return "Press a key such as Esc."
            }
            return nil
        }
    }
}

/// Disk-backed store for the hotkey configuration.
///
/// Storage: a single JSON blob in `UserDefaults` under `hotkey_config_v1`.
/// Observed by both the AppDelegate (to reconfigure the listener) and the
/// Settings UI.
final class HotkeySettingsStore: ObservableObject {
    static let shared = HotkeySettingsStore()

    private static let defaultsKey = "hotkey_config_v1"

    @Published var config: HotkeyConfig {
        didSet { persist() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(HotkeyConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }
    }

    func binding(for action: HotkeyAction) -> HotkeyBinding { config[action] }

    /// Commit a binding if it passes validation. Returns an error string to
    /// show inline, or `nil` on success.
    @discardableResult
    func setBinding(_ binding: HotkeyBinding, for action: HotkeyAction) -> String? {
        if let error = config.validate(binding, for: action) { return error }
        config[action] = binding
        return nil
    }

    func resetToDefaults() { config = .default }

    private func persist() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

// MARK: - Listener

enum HotKeyStartResult: Equatable {
    case started
    case failedMissingAccessibility
    case failedMissingInputMonitoring
    case failedUnknown
}

class HotKeyListener {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    var onHandsFreeToggle: (() -> Void)?
    /// Fired on the configured exit key (default Esc). AppDelegate uses this to
    /// leave hands-free mode. No-op when not in hands-free mode.
    var onEscape: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isTriggerActive = false
    private var isHandsFreeChordActive = false
    /// After a hands-free chord is released we must not immediately re-arm
    /// push-to-talk on the same base-key hold — otherwise releasing the extra
    /// modifier would start a stray recording. Cleared once the push combo is
    /// fully released.
    private var suppressPushUntilRelease = false

    /// Chord-disambiguation debounce. When the push-to-talk combo is a strict
    /// subset of the hands-free combo (default: Fn ⊂ Fn+Control), a bare
    /// push-to-talk press is ambiguous — it may be the leading edge of the
    /// hands-free chord, i.e. the user pressing Fn a few ms before Control.
    /// Starting push-to-talk immediately in that window would (a) fire a stray
    /// recording and (b) leave the owner's `isRecording` set, which makes the
    /// hands-free toggle bail out of starting the *continuous* engine — so
    /// hands-free would flip its UI on but never actually harvest utterances.
    /// We hold the push-to-talk start for one short window; if the chord
    /// completes first, the next `flagsChanged` cancels it. Only ever touched on
    /// the main runloop (the tap is installed there — see `start()`).
    private let chordDisambiguationWindow: TimeInterval = 0.06
    private var pendingPushToTalkStart: DispatchWorkItem?

    // Config-driven combos. Default to the historical Fn / Fn+Ctrl / Esc so the
    // listener still behaves correctly if start() runs before configure().
    private var pushToTalkFlags: CGEventFlags = [.maskSecondaryFn]
    private var handsFreeFlags: CGEventFlags = [.maskSecondaryFn, .maskControl]
    private var exitKeyCode: Int64 = 53
    private var exitFlags: CGEventFlags = []

    /// Only these flags are considered when comparing combos — ignoring
    /// caps-lock/numeric-pad noise keeps the "currently held" set stable.
    private static let relevantMask: CGEventFlags =
        [.maskSecondaryFn, .maskControl, .maskAlternate, .maskShift, .maskCommand]

    deinit {
        stop()
    }

    /// Apply a configuration. Safe to call at any time, including while the tap
    /// is live — the next event uses the new combos.
    func configure(pushToTalk: HotkeyBinding, handsFree: HotkeyBinding, exit: HotkeyBinding) {
        pushToTalkFlags = pushToTalk.modifiers.cgFlags
        handsFreeFlags = handsFree.modifiers.cgFlags
        exitKeyCode = Int64(exit.keyCode ?? 53)
        exitFlags = exit.modifiers.cgFlags
    }

    func start() -> HotKeyStartResult {
        stop()
        if !AXIsProcessTrusted() {
            return .failedMissingAccessibility
        }
        if !CGPreflightListenEventAccess() {
            return .failedMissingInputMonitoring
        }

        // Listen for flagsChanged (modifier chords) AND keyDown (exit key).
        // Combining both into one tap is cheaper than running two taps.
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
                      | (1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return nil }
                let listener = Unmanaged<HotKeyListener>.fromOpaque(refcon).takeUnretainedValue()
                return listener.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return .failedUnknown
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("HotKeyListener started with passive CGEvent tap")
        return .started
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isTriggerActive = false
        isHandsFreeChordActive = false
        suppressPushUntilRelease = false
        cancelPendingPushToTalkStart()
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return nil
        }

        // Exit key: used to leave hands-free mode. AppDelegate decides whether
        // the press is meaningful (no-op if not in hands-free).
        if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == exitKeyCode {
            let held = event.flags.intersection(Self.relevantMask)
            if exitFlags.isEmpty || held.contains(exitFlags) {
                DispatchQueue.main.async { [weak self] in
                    self?.onEscape?()
                }
            }
            return nil
        }

        guard type == .flagsChanged else {
            return nil
        }

        let current = event.flags.intersection(Self.relevantMask)
        handleFlagsChanged(current: current)
        return nil
    }

    private func handleFlagsChanged(current: CGEventFlags) {
        // The modifier set just changed, so any push-to-talk start we were
        // holding back for chord disambiguation is now stale — re-decide below.
        cancelPendingPushToTalkStart()

        // Hands-free chord takes priority. `.contains` on an OptionSet is a
        // subset test, so this fires when every required modifier is held.
        let hfHeld = !handsFreeFlags.isEmpty && current.contains(handsFreeFlags)
        if hfHeld {
            if !isHandsFreeChordActive {
                isHandsFreeChordActive = true
                // Drop push-to-talk without an onKeyUp — the toggle handler
                // owns the pipeline from here. (Preserves prior behavior.)
                isTriggerActive = false
                DispatchQueue.main.async { [weak self] in
                    print("Hands-free chord detected — toggling")
                    DebugLog.log("HotKey: hands-free chord DETECTED → onHandsFreeToggle")
                    self?.onHandsFreeToggle?()
                }
            }
            return
        }

        if isHandsFreeChordActive {
            // Chord just released; arm the suppression so we don't re-trigger
            // push-to-talk on the same hold.
            isHandsFreeChordActive = false
            suppressPushUntilRelease = true
        }

        let ptHeld = !pushToTalkFlags.isEmpty && current.contains(pushToTalkFlags)

        if suppressPushUntilRelease {
            if isTriggerActive { setTriggerActive(false) }
            if !ptHeld { suppressPushUntilRelease = false }
            return
        }

        // Push-to-talk released (or a non-matching modifier set) → deactivate.
        if !ptHeld {
            setTriggerActive(false)
            return
        }

        // Push-to-talk is held. If it's already recording, nothing to do.
        if isTriggerActive { return }

        // Rising edge. If push-to-talk is a strict subset of the hands-free
        // chord, this may be the first key of that chord (Fn before Control),
        // so defer the start by one short window. Control arriving cancels it
        // via `cancelPendingPushToTalkStart()` at the top of this method; if the
        // window elapses with only push-to-talk held, we start recording. When
        // the combos are disjoint there's nothing to disambiguate, so start now.
        if pushToTalkIsSubsetOfHandsFree {
            schedulePendingPushToTalkStart()
        } else {
            setTriggerActive(true)
        }
    }

    /// True when holding push-to-talk could be the leading edge of the hands-free
    /// chord (push-to-talk ⊂ hands-free). When the combos are equal or disjoint
    /// there is nothing to disambiguate and push-to-talk starts immediately.
    private var pushToTalkIsSubsetOfHandsFree: Bool {
        !pushToTalkFlags.isEmpty
            && !handsFreeFlags.isEmpty
            && pushToTalkFlags != handsFreeFlags
            && handsFreeFlags.contains(pushToTalkFlags)
    }

    private func schedulePendingPushToTalkStart() {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingPushToTalkStart = nil
            // Only start if the chord never completed and push-to-talk wasn't
            // suppressed while we waited.
            guard !self.isHandsFreeChordActive, !self.suppressPushUntilRelease else { return }
            self.setTriggerActive(true)
        }
        pendingPushToTalkStart = work
        DispatchQueue.main.asyncAfter(deadline: .now() + chordDisambiguationWindow, execute: work)
    }

    private func cancelPendingPushToTalkStart() {
        pendingPushToTalkStart?.cancel()
        pendingPushToTalkStart = nil
    }

    private func setTriggerActive(_ active: Bool) {
        guard active != isTriggerActive else { return }
        isTriggerActive = active
        DispatchQueue.main.async { [weak self] in
            if active {
                print("Push-to-talk pressed")
                DebugLog.log("HotKey: push-to-talk DOWN")
                self?.onKeyDown?()
            } else {
                print("Push-to-talk released")
                self?.onKeyUp?()
            }
        }
    }
}
