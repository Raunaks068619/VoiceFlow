import Foundation
import AppKit
import ApplicationServices

/// A single app on a screenshot override list. `name` is captured at
/// add-time (from the picked `.app`) purely for display — matching is
/// always by `bundleID`.
struct ScreenshotAppRule: Codable, Identifiable, Equatable {
    let bundleID: String
    let name: String
    var id: String { bundleID }
}

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
        /// Whether Vordi captures the frontmost window screenshot and
        /// sends it to the context-summary model. Default ON for this
        /// experimental build so the FreeFlow-style flow is testable.
        static let screenshotContextEnabled = "screenshot_context_enabled"
        /// User override lists layered on top of the built-in dev-surface
        /// default. Both stored as JSON `[ScreenshotAppRule]`.
        ///   - skip:  apps the user forces OFF (never screenshot).
        ///   - force: apps the user forces ON (screenshot even if the
        ///            category default would skip them, e.g. re-enabling
        ///            a specific IDE).
        static let screenshotSkipApps = "screenshot_skip_apps"
        static let screenshotForceApps = "screenshot_force_apps"
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

    var isScreenshotContextEnabled: Bool {
        if UserDefaults.standard.object(forKey: Keys.screenshotContextEnabled) == nil { return true }
        return UserDefaults.standard.bool(forKey: Keys.screenshotContextEnabled)
    }

    // MARK: - Screenshot exclusion overrides

    /// User-managed override lists. Runtime reads these directly from
    /// UserDefaults at capture time so Settings edits take effect on the
    /// next dictation without any restart or notification plumbing.
    var screenshotSkipApps: [ScreenshotAppRule] { decodeRules(Keys.screenshotSkipApps) }
    var screenshotForceApps: [ScreenshotAppRule] { decodeRules(Keys.screenshotForceApps) }

    /// Should we take a screenshot for this app? Precedence:
    /// 1. Force list (user said "always screenshot this") wins outright.
    /// 2. Skip list (user said "never screenshot this") is next.
    /// 3. Otherwise fall back to the category default — dev/text surfaces
    ///    are skipped, everything else is captured.
    func shouldCaptureScreenshot(bundleID: String?, surface: AppSurface) -> Bool {
        if let id = bundleID {
            if screenshotForceApps.contains(where: { $0.bundleID == id }) { return true }
            if screenshotSkipApps.contains(where: { $0.bundleID == id }) { return false }
        }
        return AppSurfaceCatalog.benefitsFromScreenshot(surface)
    }

    /// Add an app to the "never screenshot" list (and clear any stale
    /// force-override for the same app). Idempotent on bundle ID.
    func addSkipApp(_ rule: ScreenshotAppRule) {
        var force = screenshotForceApps
        force.removeAll { $0.bundleID == rule.bundleID }
        setRules(force, key: Keys.screenshotForceApps)

        var skip = screenshotSkipApps
        guard !skip.contains(where: { $0.bundleID == rule.bundleID }) else { return }
        skip.append(rule)
        setRules(skip, key: Keys.screenshotSkipApps)
    }

    func removeSkipApp(bundleID: String) {
        var skip = screenshotSkipApps
        skip.removeAll { $0.bundleID == bundleID }
        setRules(skip, key: Keys.screenshotSkipApps)
    }

    /// Add an app to the "always screenshot" list (and clear any stale
    /// skip-override for the same app). Idempotent on bundle ID.
    func addForceApp(_ rule: ScreenshotAppRule) {
        var skip = screenshotSkipApps
        skip.removeAll { $0.bundleID == rule.bundleID }
        setRules(skip, key: Keys.screenshotSkipApps)

        var force = screenshotForceApps
        guard !force.contains(where: { $0.bundleID == rule.bundleID }) else { return }
        force.append(rule)
        setRules(force, key: Keys.screenshotForceApps)
    }

    func removeForceApp(bundleID: String) {
        var force = screenshotForceApps
        force.removeAll { $0.bundleID == bundleID }
        setRules(force, key: Keys.screenshotForceApps)
    }

    private func decodeRules(_ key: String) -> [ScreenshotAppRule] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let rules = try? JSONDecoder().decode([ScreenshotAppRule].self, from: data)
        else { return [] }
        return rules
    }

    private func setRules(_ rules: [ScreenshotAppRule], key: String) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: key)
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
        let windowInfo = activeWindowInfo(for: frontApp)
        let screenshot = captureScreenshot(windowInfo: windowInfo, bundleID: bundleID, surface: surface)

        // Selection capture — short-circuit when we're foreground (would
        // capture our own UI's selection state, which is meaningless).
        let isOurApp = bundleID == Bundle.main.bundleIdentifier
        if isOurApp {
            return ContextSnapshot(
                frontmostBundleID: bundleID,
                frontmostAppName: appName,
                windowTitle: windowInfo?.title,
                surface: surface,
                selection: "",
                selectionSource: .none,
                hotkey: hotkey,
                capturedAt: Date(),
                screenshot: nil
            )
        }

        let (selection, source) = captureSelection()
        return ContextSnapshot(
            frontmostBundleID: bundleID,
            frontmostAppName: appName,
            windowTitle: windowInfo?.title,
            surface: surface,
            selection: selection,
            selectionSource: source,
            hotkey: hotkey,
            capturedAt: Date(),
            screenshot: screenshot
        )
    }

    // MARK: - Screenshot capture

    private struct ActiveWindowInfo {
        let windowID: CGWindowID
        let title: String?
        let width: Int
        let height: Int
    }

    private func activeWindowInfo(for app: NSRunningApplication?) -> ActiveWindowInfo? {
        guard let pid = app?.processIdentifier else { return nil }
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows {
            guard
                let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
                ownerPID == pid,
                let windowID = window[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            let layer = window[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }

            let alpha = window[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0 else { continue }

            guard
                let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
                let width = boundsDict["Width"] as? Int,
                let height = boundsDict["Height"] as? Int,
                width >= 120,
                height >= 80
            else { continue }

            let rawTitle = (window[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return ActiveWindowInfo(
                windowID: windowID,
                title: rawTitle?.isEmpty == true ? nil : rawTitle,
                width: width,
                height: height
            )
        }

        return nil
    }

    private func captureScreenshot(
        windowInfo: ActiveWindowInfo?,
        bundleID: String?,
        surface: AppSurface
    ) -> ContextScreenshot? {
        guard isScreenshotContextEnabled else {
            return ContextScreenshot(status: .disabled)
        }

        // App exclusion — dev/text surfaces (and user overrides) skip the
        // shot entirely. Bail before requesting Screen Recording or doing
        // any pixel work; downstream sees `.skippedApp` and never calls the
        // vision model, so no tokens are spent.
        guard shouldCaptureScreenshot(bundleID: bundleID, surface: surface) else {
            return ContextScreenshot(status: .skippedApp)
        }

        guard CGPreflightScreenCaptureAccess() else {
            return ContextScreenshot(status: .denied)
        }

        guard let windowInfo else {
            return ContextScreenshot(status: .unavailable)
        }

        let imageOptions: CGWindowImageOption = [.boundsIgnoreFraming, .bestResolution]
        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowInfo.windowID,
            imageOptions
        ) else {
            return ContextScreenshot(status: .failed)
        }

        guard let data = jpegData(from: cgImage, maxPixelDimension: 1280, compression: 0.58) else {
            return ContextScreenshot(status: .failed)
        }

        return ContextScreenshot(
            status: .captured,
            filename: "context.jpg",
            mimeType: "image/jpeg",
            width: windowInfo.width,
            height: windowInfo.height,
            capturedAt: Date(),
            imageData: data
        )
    }

    private func jpegData(
        from image: CGImage,
        maxPixelDimension: CGFloat,
        compression: CGFloat
    ) -> Data? {
        let originalWidth = CGFloat(image.width)
        let originalHeight = CGFloat(image.height)
        let scale = min(1.0, maxPixelDimension / max(originalWidth, originalHeight))
        let size = NSSize(width: max(1, originalWidth * scale), height: max(1, originalHeight * scale))

        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSImage(cgImage: image, size: NSSize(width: originalWidth, height: originalHeight))
            .draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .jpeg, properties: [.compressionFactor: compression])
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
        return String(head) + "\n...[truncated by \(AppBrand.name), selection exceeded 8K chars]"
    }
}

extension ContextSnapshot {
    /// Empty snapshot used when capture is disabled or the app is foregrounded
    /// to itself.
    static func empty(hotkey: HotkeyIdentifier = .primary) -> ContextSnapshot {
        ContextSnapshot(
            frontmostBundleID: nil,
            frontmostAppName: nil,
            windowTitle: nil,
            surface: .unknown,
            selection: "",
            selectionSource: .none,
            hotkey: hotkey,
            capturedAt: Date(),
            screenshot: nil
        )
    }
}
