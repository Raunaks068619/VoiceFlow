import Foundation
import AppKit
import Carbon
import ApplicationServices

enum HotKeyStartResult: Equatable {
    case started
    case failedMissingAccessibility
    case failedMissingInputMonitoring
    case failedUnknown
}

class HotKeyListener {
    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var flagsMonitor: Any?
    private var isTriggerActive = false
    private var lastRawFnEventTime: TimeInterval = 0
    private let fnKeyCode: Int64 = 63
    private let rightOptionKeyCode: Int64 = 61
    
    func start() -> HotKeyStartResult {
        stop()
        if !AXIsProcessTrusted() {
            return .failedMissingAccessibility
        }
        if !CGPreflightListenEventAccess() {
            return .failedMissingInputMonitoring
        }

        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
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
        
        print("HotKeyListener started with CGEvent tap")

        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(
                keyCode: Int64(event.keyCode),
                hasFnFlag: event.modifierFlags.contains(.function),
                hasOptionFlag: event.modifierFlags.contains(.option)
            )
        }
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
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
        isTriggerActive = false
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passRetained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasFnFlag = event.flags.contains(.maskSecondaryFn)
        let hasOptionFlag = event.flags.contains(.maskAlternate)
        handleFlagsChanged(keyCode: keyCode, hasFnFlag: hasFnFlag, hasOptionFlag: hasOptionFlag)
        
        return Unmanaged.passRetained(event)
    }

    private func handleFlagsChanged(keyCode: Int64, hasFnFlag: Bool, hasOptionFlag: Bool) {
        // Fn is the ONLY trigger. Right Option previously acted as a fallback
        // but caused accidental activation when users genuinely wanted Option
        // as a modifier. If Fn doesn't register on a given keyboard, the fix
        // is System Settings → Keyboard → Globe/Fn Key Usage, not a fallback.
        if keyCode == fnKeyCode {
            // Always trust the fn flag. Press = flag ON, Release = flag OFF.
            // Previous implementation toggled on "raw fn without flag" which caused
            // stuck-recording bugs when the release event arrived without the flag.
            setTriggerActive(hasFnFlag, pressedLog: "Fn pressed!", releasedLog: "Fn released!")
            lastRawFnEventTime = Date().timeIntervalSinceReferenceDate
            return
        }

        // Any other flag change: if the fn modifier dropped, force-release.
        if !hasFnFlag && isTriggerActive {
            setTriggerActive(false, pressedLog: "Fn pressed!", releasedLog: "Fn released (flags cleared)!")
        }
    }

    private func setTriggerActive(_ active: Bool, pressedLog: String, releasedLog: String) {
        guard active != isTriggerActive else { return }
        isTriggerActive = active
        DispatchQueue.main.async { [weak self] in
            if active {
                print(pressedLog)
                self?.onKeyDown?()
            } else {
                print(releasedLog)
                self?.onKeyUp?()
            }
        }
    }
}
