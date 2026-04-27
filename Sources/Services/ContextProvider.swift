import Foundation
import AppKit
import ApplicationServices

/// Captures "what the user was doing" at hotkey-press time.
///
/// **Capture strategy** (ordered, fail-soft):
/// 1. Read `NSWorkspace.shared.frontmostApplication` — almost always works.
/// 2. AX path: `kAXSelectedTextAttribute` on the focused element.
///    Fast, deterministic. Fails on Electron, Chrome, terminals.
/// 3. Clipboard fallback: only when explicitly opted in (default OFF).
///    Round-trip Cmd+C with pasteboard preserve/restore. Reliable but
///    invasive (an extra Cmd+C goes to the focused app).
///
/// **Concurrency**: must be called on the main queue. AX & NSWorkspace are
/// not thread-safe. The `snapshot()` call is fast (<5ms typical) so blocking
/// the main thread for it is fine.
///
/// **Privacy**: selection text is held in memory (not persisted by default).
/// `RunStore` only writes selection to disk if `isContextSaveEnabled` is on.
final class ContextProvider {
    static let shared = ContextProvider()
    private init() {}

    // User defaults keys — single source of truth so settings UI binds
    // against the same strings the runtime reads.
    enum Keys {
        /// Master toggle for context capture. When OFF, snapshot() returns
        /// `.empty` regardless of all other settings. Default ON because
        /// the foundation features (per-app insights, dev-mode triggers)
        /// require it; selection capture itself is gated by clipboardEnabled.
        static let contextCaptureEnabled = "context_capture_enabled"
        /// Whether the clipboard-fallback selection capture is allowed.
        /// Default OFF — opt-in because it sends an extra Cmd+C to the
        /// focused app, which power users hate when wrong.
        static let clipboardSelectionEnabled = "clipboard_selection_enabled"
        /// Whether captured selection text gets persisted to RunStore.
        /// Default OFF — selections often contain code/secrets the user
        /// doesn't want lying around. UI lives in Settings → Privacy.
        static let persistSelectionEnabled = "persist_selection_enabled"
    }

    var isContextCaptureEnabled: Bool {
        if UserDefaults.standard.object(forKey: Keys.contextCaptureEnabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Keys.contextCaptureEnabled)
    }

    var isClipboardSelectionEnabled: Bool {
        UserDefaults.standard.bool(forKey: Keys.clipboardSelectionEnabled)
    }

    var shouldPersistSelection: Bool {
        UserDefaults.standard.bool(forKey: Keys.persistSelectionEnabled)
    }

    /// Capture the snapshot. SAFE TO CALL on main thread; takes ~1–10ms.
    /// If you suspect it's slowing the hotkey response, profile with
    /// `Instruments → Time Profiler` — but as of writing, the AX query
    /// is the longest-pole and consistently sub-5ms on M-series.
    func snapshot(hotkey: HotkeyIdentifier = .primary) -> ContextSnapshot {
        guard isContextCaptureEnabled else {
            return .empty(hotkey: hotkey)
        }

        let frontApp = NSWorkspace.shared.frontmostApplication
        let bundleID = frontApp?.bundleIdentifier
        let appName = frontApp?.localizedName
        let surface = AppSurfaceCatalog.surface(for: bundleID)

        // Selection capture — short-circuit when we're foreground (would
        // capture our own UI's selection state, which is meaningless).
        let isOurApp = bundleID == Bundle.main.bundleIdentifier
        if isOurApp {
            return ContextSnapshot(
                frontmostBundleID: bundleID,
                frontmostAppName: appName,
                surface: surface,
                selection: "",
                selectionSource: .none,
                hotkey: hotkey,
                capturedAt: Date()
            )
        }

        let (selection, source) = captureSelection()
        return ContextSnapshot(
            frontmostBundleID: bundleID,
            frontmostAppName: appName,
            surface: surface,
            selection: selection,
            selectionSource: source,
            hotkey: hotkey,
            capturedAt: Date()
        )
    }

    // MARK: - Selection capture

    /// Try AX first; clipboard only if user opted in & AX returned nothing.
    /// Returns (selectionText, sourceTag).
    private func captureSelection() -> (String, SelectionSource) {
        // AX path
        if let axText = readSelectedTextViaAX(), !axText.isEmpty {
            return (truncate(axText), .ax)
        }

        // Clipboard path (opt-in)
        guard isClipboardSelectionEnabled else {
            return ("", .none)
        }

        if let clipText = readSelectedTextViaClipboard(), !clipText.isEmpty {
            return (truncate(clipText), .clipboard)
        }

        return ("", .failed)
    }

    /// AX selection — works in native Cocoa apps & well-behaved Electron
    /// surfaces. Specifically works in: Xcode, Sublime, Notes, Slack
    /// composer, Pages. Specifically fails: VS Code, Cursor, Windsurf,
    /// Chrome content area (sometimes works), iTerm, Terminal.
    private func readSelectedTextViaAX() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedResult == .success, let focused = focusedRef else {
            print("ContextProvider: AX focused-element query failed (\(focusedResult.rawValue))")
            return nil
        }

        // Force-cast is safe — AX returns AXUIElement for this attribute.
        let element = focused as! AXUIElement

        var selectedRef: CFTypeRef?
        let selResult = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedRef
        )
        guard selResult == .success, let cfString = selectedRef as? String else {
            return nil
        }

        let trimmed = cfString.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Clipboard fallback — Cmd+C round-trip with pasteboard preserve.
    ///
    /// **Order matters**: snapshot pasteboard.changeCount BEFORE firing Cmd+C.
    /// Wait briefly for the target app to update the pasteboard, then check
    /// if changeCount moved. If yes, read the new contents. Restore the
    /// previous pasteboard state on the way out.
    ///
    /// **Timing**: 80ms wait is empirically tuned. Most apps respond in
    /// 5–30ms; iTerm has been seen at 60ms; anything past 80ms is probably
    /// not going to respond at all (no selection or app blocked).
    private func readSelectedTextViaClipboard() -> String? {
        let pasteboard = NSPasteboard.general

        // Snapshot the previous contents BEFORE we trigger Cmd+C.
        let preserved: [(NSPasteboard.PasteboardType, Data)] = pasteboard.types?.compactMap { type in
            guard let data = pasteboard.data(forType: type) else { return nil }
            return (type, data)
        } ?? []

        let beforeChangeCount = pasteboard.changeCount

        // Send Cmd+C to the focused app.
        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
            let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        else { return nil }
        cDown.flags = .maskCommand
        cUp.flags = .maskCommand
        cDown.post(tap: .cghidEventTap)
        cUp.post(tap: .cghidEventTap)

        // Spin briefly waiting for the pasteboard to change. We poll rather
        // than `usleep(80_000)`-and-check because some apps are FAST and
        // we don't want to unnecessarily delay the hotkey response.
        let deadline = Date().addingTimeInterval(0.08)
        var captured: String?
        while Date() < deadline {
            if pasteboard.changeCount != beforeChangeCount {
                captured = pasteboard.string(forType: .string)
                break
            }
            // 5ms tick — small enough to feel snappy, large enough to not
            // burn the CPU.
            usleep(5_000)
        }

        // Restore the previous pasteboard regardless of whether we got
        // anything. We may overwrite the user's just-copied selection,
        // but they didn't intend to copy — they intended to dictate.
        pasteboard.clearContents()
        for (type, data) in preserved {
            pasteboard.setData(data, forType: type)
        }

        guard let text = captured?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Cap selection size sent to LLMs. Most useful selections are
    /// well under this. Past ~8KB the prompt becomes prohibitively
    /// expensive AND most providers start trimming silently.
    private static let maxSelectionChars = 8_000

    private func truncate(_ s: String) -> String {
        guard s.count > Self.maxSelectionChars else { return s }
        let head = s.prefix(Self.maxSelectionChars)
        return String(head) + "\n…[truncated by VoiceFlow — selection exceeded 8K chars]"
    }
}

extension ContextSnapshot {
    /// Empty snapshot used when capture is disabled or the app is foregrounded
    /// to itself.
    static func empty(hotkey: HotkeyIdentifier = .primary) -> ContextSnapshot {
        ContextSnapshot(
            frontmostBundleID: nil,
            frontmostAppName: nil,
            surface: .unknown,
            selection: "",
            selectionSource: .none,
            hotkey: hotkey,
            capturedAt: Date()
        )
    }
}
