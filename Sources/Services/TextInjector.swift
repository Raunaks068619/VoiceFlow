import Foundation
import AppKit
import Carbon

class TextInjector {
    private var lastInjectedSignature: String?
    private var lastInjectedAt: TimeInterval = 0

    func injectText(_ text: String) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        let now = Date().timeIntervalSinceReferenceDate
        let signature = "\(normalized.count):\(normalized.hashValue)"
        if signature == lastInjectedSignature && now - lastInjectedAt < 1.0 {
            print("Skipping duplicate text injection")
            return
        }

        lastInjectedSignature = signature
        lastInjectedAt = now
        injectViaPasteboard(normalized)
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
            Thread.sleep(forTimeInterval: 0.01)
            vUp.post(tap: .cghidEventTap)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                pasteboard.clearContents()
                if let oldContent = currentContent {
                    pasteboard.setString(oldContent, forType: .string)
                }
            }
        }
    }
}
