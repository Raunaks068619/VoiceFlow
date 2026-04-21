import Foundation
import AppKit
import Carbon

class TextInjector {
    private var lastInjectedSignature: String?
    private var lastInjectedAt: TimeInterval = 0

    /// Delivered when injection is suppressed (e.g., VoiceFlow is foreground).
    /// The transcript is still on the clipboard so the user can paste manually.
    var onInjectionSuppressed: ((String) -> Void)?

    func injectText(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }

            let now = Date().timeIntervalSinceReferenceDate
            let signature = "\(normalized.count):\(normalized.hashValue)"
            if signature == self.lastInjectedSignature && now - self.lastInjectedAt < 1.0 {
                print("Skipping duplicate text injection")
                return
            }

            self.lastInjectedSignature = signature
            self.lastInjectedAt = now

            // Guard: if VoiceFlow itself is foreground (e.g. Settings window is
            // focused), DO NOT auto-paste. The user almost certainly doesn't
            // want transcript text injected into our own UI — and if focus is
            // on a SecureField like "OpenAI API Key", pasting silently
            // corrupts the stored credential (SwiftUI writes the mangled
            // value back to UserDefaults with no way to tell).
            // Instead, copy to clipboard and notify the caller so they can
            // show a non-intrusive banner.
            if Self.isVoiceFlowForeground() {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(normalized, forType: .string)
                print("Injection suppressed — VoiceFlow is frontmost. Transcript copied to clipboard.")
                self.onInjectionSuppressed?(normalized)
                return
            }

            self.injectViaPasteboard(normalized)
        }
    }

    /// True when VoiceFlow is the frontmost application. We compare by bundle
    /// identifier rather than PID because helper processes (e.g. SwiftUI
    /// previews or XPC) share the same bundle id and should be treated as
    /// "us" for this check.
    private static func isVoiceFlowForeground() -> Bool {
        guard let frontBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else {
            return false
        }
        return frontBundleID == Bundle.main.bundleIdentifier
    }

    private func injectViaPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let currentContent = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)

        if let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
           let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false) {
            vDown.flags = .maskCommand
            vUp.flags = .maskCommand
            vDown.post(tap: .cghidEventTap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                vUp.post(tap: .cghidEventTap)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                if let oldContent = currentContent {
                    pasteboard.setString(oldContent, forType: .string)
                }
            }
        }
    }
}
