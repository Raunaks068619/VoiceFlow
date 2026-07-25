import AppKit
import Combine
import QuartzCore
import SwiftUI

enum NotchPillState: Equatable {
    case idle
    case proximity
    case listening
    case thinking
    case done
    case handsFree
    case errorMini(message: String)
    case panelHover
    case panelTranscript(text: String)
    case panelError(title: String, desc: String, tip: String)
}

/// Swipeable pages inside the open hover panel.
enum NotchPanelMode: String, CaseIterable {
    case transcriptions
    case notes
    case memory
    case stats

    var title: String {
        switch self {
        case .transcriptions: return "Latest transcriptions"
        case .notes: return "Notes"
        case .memory: return "Memory"
        case .stats: return "Today"
        }
    }

    var panelHeight: CGFloat {
        switch self {
        case .transcriptions: return NotchPillScreenGeometry.expandedPanelHeight
        case .notes: return 164
        case .memory: return 138
        case .stats: return 112
        }
    }

    var next: NotchPanelMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }

    var previous: NotchPanelMode {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + all.count - 1) % all.count]
    }
}

final class NotchPillModel: ObservableObject {
    private static let panelModeDefaultsKey = "notch.panelMode"

    @Published var state: NotchPillState = .idle
    @Published var activePanelMode: NotchPanelMode = NotchPanelMode(
        rawValue: UserDefaults.standard.string(forKey: panelModeDefaultsKey) ?? ""
    ) ?? .transcriptions {
        didSet {
            UserDefaults.standard.set(activePanelMode.rawValue, forKey: Self.panelModeDefaultsKey)
        }
    }
    @Published var audioLevel: Float = 0
    @Published var hasAllPermissions: Bool = true
    @Published var missingPermissionNames: [String] = []
    @Published var hardwareNotchSize: CGSize = NotchPillScreenGeometry.fallbackNotchSize
    @Published var isExternalDock: Bool = false
    @Published var liveTranscript: String = ""

    var lastError: (title: String, desc: String, tip: String)?

    /// Set by the window. Driven by the SwiftUI surface's `.onContinuousHover`
    /// so hover detection keeps working even though the window is a fixed,
    /// oversized canvas around the morphing pill.
    var onHoverChanged: ((Bool) -> Void)?
}

enum NotchPillScreenGeometry {
    static let fallbackNotchSize = CGSize(width: 162, height: 32)
    static let externalDockSize = CGSize(width: 116, height: 8)
    static let surfaceHeightExtension: CGFloat = 2
    static let defaultVisibleExpansion: CGFloat = 63
    static let maxSurfaceWidth: CGFloat = 456
    static let openPanelWidthExpansion: CGFloat = 32
    static let expandedPanelHeight: CGFloat = 176
    static let listeningPanelHeight: CGFloat = 62
    static let errorPanelHeight: CGFloat = 136
    // The missing-permissions list is capped at two lines, just like error
    // notice copy, so both states need the same worst-case vertical allowance.
    static let permissionsPanelHeight: CGFloat = errorPanelHeight
    static let morphDuration: TimeInterval = 0.50

    private static let lanePadding: CGFloat = 10
    private static let statusTrailingPadding: CGFloat = 18
    private static let stateWidthBreathingRoom: CGFloat = 8
    private static let notchMarkWidth: CGFloat = 14
    private static let statusSpacing: CGFloat = 6
    private static let statusFontSize: CGFloat = 10
    private static let recordingMeterWidth: CGFloat = 38
    private static let thinkingDotsWidth: CGFloat = 24
    private static let doneTickWidth: CGFloat = 18
    private static let pulseWidth: CGFloat = 8

    static func notchFrame(on screen: NSScreen) -> CGRect? {
        if #available(macOS 12.0, *),
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            let notchWidth = rightArea.minX - leftArea.maxX
            if notchWidth > 0 {
                return CGRect(
                    x: leftArea.maxX,
                    y: min(leftArea.minY, rightArea.minY),
                    width: notchWidth,
                    height: max(leftArea.height, rightArea.height)
                )
            }
        }

        return nil
    }

    static func detect(on screen: NSScreen) -> CGSize {
        notchFrame(on: screen)?.size ?? fallbackNotchSize
    }

    static func anchorX(on screen: NSScreen) -> CGFloat {
        screen.frame.midX
    }

    static func hasHardwareNotch(on screen: NSScreen) -> Bool {
        notchFrame(on: screen) != nil
    }

    static func defaultSurfaceSize(for notchSize: CGSize, isExternalDock: Bool = false) -> CGSize {
        let defaultPillWidth = defaultPillWidth(
            state: .idle,
            notchSize: notchSize,
            isExternalDock: isExternalDock
        )
        return CGSize(
            width: defaultPillWidth + backgroundSideExpansion(state: .idle, isExternalDock: isExternalDock) * 2,
            height: rowHeight(state: .idle, notchSize: notchSize, isExternalDock: isExternalDock)
        )
    }

    static func surfaceSize(
        state: NotchPillState,
        notchSize: CGSize,
        isExternalDock: Bool,
        liveTranscript: String,
        panelMode: NotchPanelMode = .transcriptions,
        hasAllPermissions: Bool = true
    ) -> CGSize {
        let rowHeight = rowHeight(state: state, notchSize: notchSize, isExternalDock: isExternalDock)
        let defaultPillWidth = defaultPillWidth(
            state: state,
            notchSize: notchSize,
            isExternalDock: isExternalDock
        )
        let centerGapWidth = centerGapWidth(
            state: state,
            notchSize: notchSize,
            isExternalDock: isExternalDock,
            defaultPillWidth: defaultPillWidth
        )
        let requestedPillWidth = pillWidth(
            state: state,
            centerGapWidth: centerGapWidth,
            defaultPillWidth: defaultPillWidth,
            hasAllPermissions: hasAllPermissions
        )
        let sideExpansion = backgroundSideExpansion(state: state, isExternalDock: isExternalDock)
        let pillWidth = min(requestedPillWidth, max(0, maxSurfaceWidth - sideExpansion * 2))
        let width = min(maxSurfaceWidth, pillWidth + sideExpansion * 2)
        let height = rowHeight
            + inlineTranscriptHeight(state: state, liveTranscript: liveTranscript)
            + expandedPanelHeightValue(for: state, panelMode: panelMode, hasAllPermissions: hasAllPermissions)

        return CGSize(width: ceil(width), height: ceil(height))
    }

    /// The window is STATIC at this maximum size — it is never resized as the
    /// pill morphs. All shape morphing happens in SwiftUI inside this fixed
    /// canvas, so the animating corners are never clipped by a moving window
    /// edge (the root cause of the "radius snaps to 0 mid-collapse" bug).
    /// Mirrors the comparison island's static-window approach.
    static func maxWindowSize(notchSize: CGSize, isExternalDock: Bool) -> CGSize {
        let row = notchSize.height + surfaceHeightExtension
        return CGSize(
            width: maxSurfaceWidth,
            height: ceil(row + expandedPanelHeight + 8)
        )
    }

    static func rowHeight(
        state: NotchPillState,
        notchSize: CGSize,
        isExternalDock: Bool
    ) -> CGFloat {
        isExternalCompactResting(state: state, isExternalDock: isExternalDock)
            ? externalDockSize.height
            : notchSize.height + surfaceHeightExtension
    }

    static func defaultPillWidth(
        state: NotchPillState,
        notchSize: CGSize,
        isExternalDock: Bool
    ) -> CGFloat {
        isExternalCompactResting(state: state, isExternalDock: isExternalDock)
            ? externalDockSize.width
            : max(248, notchSize.width + defaultVisibleExpansion)
    }

    static func centerGapWidth(
        state: NotchPillState,
        notchSize: CGSize,
        isExternalDock: Bool,
        defaultPillWidth: CGFloat
    ) -> CGFloat {
        isExternalCompactResting(state: state, isExternalDock: isExternalDock)
            ? defaultPillWidth
            : notchSize.width
    }

    static func backgroundSideExpansion(state: NotchPillState, isExternalDock: Bool) -> CGFloat {
        if isExternalCompactResting(state: state, isExternalDock: isExternalDock) {
            return 0
        }
        return backgroundSideExpansion(for: state)
    }

    static func isExternalCompactResting(state: NotchPillState, isExternalDock: Bool) -> Bool {
        guard isExternalDock else { return false }
        switch state {
        case .idle, .proximity:
            return true
        default:
            return false
        }
    }

    private static func pillWidth(
        state: NotchPillState,
        centerGapWidth: CGFloat,
        defaultPillWidth: CGFloat,
        hasAllPermissions: Bool
    ) -> CGFloat {
        if hasAllPermissions {
            switch state {
            case .idle, .proximity:
                return defaultPillWidth
            default:
                break
            }
        }

        let leftContentWidth = lanePadding
            + notchMarkWidth
            + statusSpacing
            + measuredStatusTextWidth(statusLabel(for: state, hasAllPermissions: hasAllPermissions))
            + statusTrailingPadding
        let laneWidth = max(leftContentWidth, rightContentWidth(for: state)) + stateWidthBreathingRoom
        let baseWidth = max(defaultPillWidth, ceil(centerGapWidth + laneWidth * 2))
        switch state {
        case .panelHover, .panelTranscript, .panelError:
            return min(maxSurfaceWidth, baseWidth + openPanelWidthExpansion)
        default:
            return baseWidth
        }
    }

    private static func backgroundSideExpansion(for state: NotchPillState) -> CGFloat {
        switch state {
        case .idle, .proximity:
            return 10
        case .thinking:
            return 18
        case .listening, .handsFree, .panelTranscript:
            return 20
        case .done:
            return 18
        case .errorMini, .panelHover, .panelError:
            return 16
        }
    }

    private static func inlineTranscriptHeight(state _: NotchPillState, liveTranscript _: String) -> CGFloat {
        0
    }

    private static func expandedPanelHeightValue(
        for state: NotchPillState,
        panelMode: NotchPanelMode,
        hasAllPermissions: Bool
    ) -> CGFloat {
        if case .panelHover = state { return hasAllPermissions ? panelMode.panelHeight : permissionsPanelHeight }
        if case .panelTranscript = state { return listeningPanelHeight }
        if case .panelError = state { return errorPanelHeight }
        return 0
    }

    private static func rightContentWidth(for state: NotchPillState) -> CGFloat {
        switch state {
        case .listening, .handsFree, .panelTranscript:
            return lanePadding + recordingMeterWidth
        case .thinking:
            return lanePadding + thinkingDotsWidth
        case .done:
            return lanePadding + doneTickWidth
        default:
            return lanePadding + pulseWidth
        }
    }

    private static func statusLabel(for state: NotchPillState, hasAllPermissions: Bool) -> String {
        switch state {
        case .listening, .panelTranscript:
            return "Listening"
        case .thinking:
            return "Thinking"
        case .done:
            return "Done"
        case .handsFree:
            return "Hands free"
        case .errorMini(let message):
            return compactErrorLabel(for: message)
        case .panelError(let title, _, _):
            return compactErrorLabel(for: title)
        case .panelHover:
            return hasAllPermissions ? AppBrand.name : "Permissions required"
        case .idle, .proximity:
            return hasAllPermissions ? "Ready" : "Permissions required"
        }
    }

    private static func compactErrorLabel(for text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("microphone") || lower.contains("permission") {
            return "Permissions"
        }
        if lower.contains("input") {
            return "No input"
        }
        if lower.contains("clipboard") || lower.contains("copied") {
            return "Copied"
        }
        if lower.contains("audio") {
            return "No audio"
        }
        return "No output"
    }

    private static func measuredStatusTextWidth(_ label: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: statusFontSize, weight: .regular)
        return ceil((label as NSString).size(withAttributes: [.font: font]).width)
    }
}

final class NotchPillHostingView: NSHostingView<NotchPillView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchPillCanvasView: NSView {
    weak var model: NotchPillModel?

    init(frame frameRect: NSRect, model: NotchPillModel) {
        self.model = model
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// The window is a fixed oversized canvas; only the visible morphing pill
    /// should absorb clicks. Everything outside it (the transparent slack the
    /// static window keeps so the shape never gets clipped) passes clicks
    /// through to whatever is underneath.
    private var currentPillRect: NSRect {
        guard let model else { return bounds }
        let size = NotchPillScreenGeometry.surfaceSize(
            state: model.state,
            notchSize: model.hardwareNotchSize,
            isExternalDock: model.isExternalDock,
            liveTranscript: model.liveTranscript,
            panelMode: model.activePanelMode,
            hasAllPermissions: model.hasAllPermissions
        )
        return NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        ).insetBy(dx: -2, dy: -2)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard currentPillRect.contains(point) else { return nil }
        return super.hitTest(point) ?? self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class NotchPillWindow: NSPanel {
    let model = NotchPillModel()

    private static let minimumAudioUpdateInterval: TimeInterval = 1.0 / 20.0
    private static let hoverPanelClosePollInterval: TimeInterval = 1.0 / 30.0
    private static let mousePassthroughPollInterval: TimeInterval = 1.0 / 30.0
    private static let hoverRegionOutset: CGFloat = 2

    private var cancellables = Set<AnyCancellable>()
    private var flashTimer: Timer?
    private var hoverPanelCloseTimer: Timer?
    private var mousePassthroughTimer: Timer?
    private var lastAudioLevelUpdate: Date = .distantPast
    private weak var anchoredScreen: NSScreen?
    private weak var canvasView: NotchPillCanvasView?

    init() {
        let initialSize = NotchPillScreenGeometry.maxWindowSize(
            notchSize: NotchPillScreenGeometry.fallbackNotchSize,
            isExternalDock: false
        )

        super.init(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        isMovable = false
        isExcludedFromWindowsMenu = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        minSize = NSSize(width: 20, height: 24)
        contentMinSize = NSSize(width: 20, height: 24)

        let hosting = NotchPillHostingView(rootView: NotchPillView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: initialSize)
        hosting.autoresizingMask = [.width, .height]

        let canvas = NotchPillCanvasView(frame: NSRect(origin: .zero, size: initialSize), model: model)
        canvas.autoresizingMask = [.width, .height]
        canvas.addSubview(hosting)

        // Hover is driven by the SwiftUI surface's `.onContinuousHover` (robust
        // against the fixed oversized window), routed through the model.
        model.onHoverChanged = { [weak self] hovering in
            self?.handleCanvasHover(hovering)
        }

        contentView = canvas
        canvasView = canvas
        setContentSize(initialSize)
        observeSurfaceBounds()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reposition(animated: false)
            self.alphaValue = 1
            self.orderFrontRegardless()
            self.level = .statusBar
            self.startMousePassthroughMonitor()
            self.syncMousePassthrough()
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.stopMousePassthroughMonitor()
            self.ignoresMouseEvents = true
            self.orderOut(nil)
        }
    }

    func setRecording() {
        setState(.panelTranscript(text: ""), resetAudio: true, clearTranscript: true)
    }

    func setProcessing() {
        setState(.thinking)
    }

    func setDone() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flashTimer?.invalidate()
            self.model.state = .done
            self.model.audioLevel = 0
            self.model.liveTranscript = ""
            self.flashTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
                guard let self else { return }
                // Only auto-collapse if we're STILL showing Done. If the user
                // tapped the pill to open the quick panel, don't yank it shut.
                guard case .done = self.model.state else { return }
                self.model.state = .idle
            }
        }
    }

    func setIdle() {
        DispatchQueue.main.async { [weak self] in
            self?.flashTimer?.invalidate()
            self?.model.state = .idle
            self?.model.audioLevel = 0
            self?.model.liveTranscript = ""
            self?.lastAudioLevelUpdate = .distantPast
        }
    }

    func setHandsFree() {
        setState(.handsFree)
    }

    func setHandsFreeExitedAnimating() {
        setState(.thinking)
    }

    func setPermissionsAvailable(_ available: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.hasAllPermissions != available else { return }
            self.model.hasAllPermissions = available
        }
    }

    func setMissingPermissions(_ names: [String]) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.missingPermissionNames != names else { return }
            self.model.missingPermissionNames = names
        }
    }

    func flashPermissionsWarning(durationSeconds: Double = 5.0) {
        flash(
            message: "Permissions required - complete setup",
            title: "Permissions required",
            desc: "\(AppBrand.name) needs the required permissions before transcription can run.",
            tip: "Click Fix Permissions, then grant each required permission in the onboarding flow.",
            durationSeconds: durationSeconds
        )
    }

    func flashNoInputWarning(durationSeconds: Double = 4.5) {
        flash(
            message: "No input field detected - use Cmd+V to paste",
            title: "No input field detected",
            desc: "\(AppBrand.name) couldn't find an active text field. Use Cmd+V to paste the transcription manually.",
            tip: "Click into any text field first, then hold Fn to dictate directly into it.",
            durationSeconds: durationSeconds
        ) {
            NotificationCenter.default.post(
                name: Notification.Name("Vordi.DismissChipWarning"),
                object: nil
            )
        }
    }

    func flashTranscriptCopied(durationSeconds: Double = 4.5) {
        flash(
            message: "Transcript copied to clipboard - use Cmd+V to paste",
            title: "Transcript copied to clipboard",
            desc: "No input field was found. The transcription is on your clipboard temporarily.",
            tip: "Use Cmd+V to paste it, or click into a text field before dictating.",
            durationSeconds: durationSeconds
        ) {
            NotificationCenter.default.post(
                name: Notification.Name("Vordi.DismissChipWarning"),
                object: nil
            )
        }
    }

    func flashNoAudioWarning(durationSeconds: Double = 3.0) {
        flash(
            message: "No audio detected - adjust mic sensitivity in Settings",
            title: "No audio detected",
            desc: "No voice was captured during the Fn hold. The noise gate may be too aggressive.",
            tip: "Increase mic sensitivity in Settings > Microphone Sensitivity.",
            durationSeconds: durationSeconds
        )
    }

    func flashNoOutputWarning(durationSeconds: Double = 4.0) {
        flash(
            message: "No output was generated - check the logs",
            title: "No output was generated",
            desc: "The flow ran but produced no text output. This may be a flow configuration issue.",
            tip: "Open the run logs to inspect which step failed or returned empty.",
            durationSeconds: durationSeconds
        )
    }

    func updateAudioLevel(_ level: Float) {
        if Thread.isMainThread {
            applyAudioLevel(level)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.applyAudioLevel(level)
            }
        }
    }

    private func setState(
        _ state: NotchPillState,
        resetAudio: Bool = false,
        clearTranscript: Bool = false
    ) {
        let update = { [weak self] in
            self?.flashTimer?.invalidate()
            self?.model.state = state
            if resetAudio {
                self?.model.audioLevel = 0
                self?.lastAudioLevelUpdate = .distantPast
            }
            if clearTranscript {
                self?.model.liveTranscript = ""
            }
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }

    private func applyAudioLevel(_ level: Float) {
        let normalizedLevel = min(max(level, 0), 1)
        let now = Date()
        let levelDelta = abs(normalizedLevel - model.audioLevel)
        guard
            now.timeIntervalSince(lastAudioLevelUpdate) >= Self.minimumAudioUpdateInterval
                || levelDelta > 0.35
        else {
            return
        }

        lastAudioLevelUpdate = now
        model.audioLevel = normalizedLevel
    }

    private func flash(
        message: String,
        title: String,
        desc: String,
        tip: String,
        durationSeconds: Double,
        onDismiss: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flashTimer?.invalidate()
            self.model.lastError = (title: title, desc: desc, tip: tip)
            self.model.state = .panelError(title: title, desc: desc, tip: tip)
            self.model.audioLevel = 0
            self.flashTimer = Timer.scheduledTimer(withTimeInterval: durationSeconds, repeats: false) { [weak self] _ in
                guard let self, case .panelError = self.model.state else { return }
                self.model.state = .idle
                onDismiss?()
            }
        }
    }

    private func reposition(animated: Bool = true) {
        let screen = preferredScreen()
        guard let screen else { return }

        anchoredScreen = screen
        let detectedNotchSize = NotchPillScreenGeometry.detect(on: screen)
        if model.hardwareNotchSize != detectedNotchSize {
            model.hardwareNotchSize = detectedNotchSize
        }
        let isExternalDock = !NotchPillScreenGeometry.hasHardwareNotch(on: screen)
        if model.isExternalDock != isExternalDock {
            model.isExternalDock = isExternalDock
        }

        applyFrame(on: screen, animated: animated)
    }

    private func observeSurfaceBounds() {
        Publishers.MergeMany(
            model.$state.map { _ in () }.eraseToAnyPublisher(),
            model.$hardwareNotchSize.map { _ in () }.eraseToAnyPublisher(),
            model.$isExternalDock.map { _ in () }.eraseToAnyPublisher(),
            model.$liveTranscript.map { _ in () }.eraseToAnyPublisher(),
            model.$activePanelMode.map { _ in () }.eraseToAnyPublisher()
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resizeToCurrentSurface()
                self?.syncHoverPanelCloseMonitor()
                self?.syncMousePassthrough()
            }
            .store(in: &cancellables)
    }

    private func applyFrame(on providedScreen: NSScreen? = nil) {
        applyFrame(on: providedScreen, animated: true)
    }

    private func applyFrame(on providedScreen: NSScreen? = nil, animated _: Bool) {
        let screen = providedScreen
            ?? anchoredScreen
            ?? preferredScreen()
        guard let screen else { return }

        anchoredScreen = screen
        let isExternalDock = !NotchPillScreenGeometry.hasHardwareNotch(on: screen)
        if model.isExternalDock != isExternalDock {
            model.isExternalDock = isExternalDock
        }

        // STATIC window: always the fixed max canvas, anchored top-center on the
        // notch. We never animate or resize the NSWindow — the pill morphs only
        // in SwiftUI inside it, so the shape's corners are never clipped by a
        // moving window edge. Reposition only (screen / notch-size change).
        let windowSize = NotchPillScreenGeometry.maxWindowSize(
            notchSize: model.hardwareNotchSize,
            isExternalDock: isExternalDock
        )
        let targetFrame = surfaceFrame(for: windowSize, on: screen)
        guard frame != targetFrame else { return }
        contentView?.frame = NSRect(origin: .zero, size: windowSize)
        setFrame(targetFrame, display: true)
    }

    private func preferredScreen() -> NSScreen? {
        let mouseScreen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        return screenWithHardwareNotch(containing: NSEvent.mouseLocation)
            ?? mouseScreen
            ?? NSScreen.main
            ?? NSScreen.screens.first
    }

    private func screenWithHardwareNotch(containing point: NSPoint) -> NSScreen? {
        NSScreen.screens.first {
            NSMouseInRect(point, $0.frame, false)
                && NotchPillScreenGeometry.hasHardwareNotch(on: $0)
        }
    }

    private func handleCanvasHover(_ hovering: Bool) {
        if hovering {
            switch model.state {
            case .idle, .proximity:
                openHoverPanelIfMouseInside()
            default:
                break
            }
        } else {
            if case .panelHover = model.state {
                guard !isMouseInsideHoverRegion(for: .panelHover) else { return }
                model.state = .idle
            } else {
                guard !isMouseInsideHoverRegion(for: model.state) else { return }
            }
        }
    }

    private func openHoverPanelIfMouseInside(at point: NSPoint = NSEvent.mouseLocation) {
        guard isMouseInsideHoverRegion(for: model.state, at: point) else { return }
        model.state = .panelHover
    }

    private func syncHoverPanelCloseMonitor() {
        if case .panelHover = model.state {
            startHoverPanelCloseMonitor()
        } else {
            stopHoverPanelCloseMonitor()
        }
    }

    private func startHoverPanelCloseMonitor() {
        guard hoverPanelCloseTimer == nil else { return }

        let timer = Timer(timeInterval: Self.hoverPanelClosePollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard case .panelHover = self.model.state else {
                self.stopHoverPanelCloseMonitor()
                return
            }

            if !self.isMouseInsideHoverRegion(for: .panelHover) {
                self.model.state = .idle
                self.stopHoverPanelCloseMonitor()
            }
        }

        hoverPanelCloseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopHoverPanelCloseMonitor() {
        hoverPanelCloseTimer?.invalidate()
        hoverPanelCloseTimer = nil
    }

    private func startMousePassthroughMonitor() {
        guard mousePassthroughTimer == nil else { return }

        let timer = Timer(timeInterval: Self.mousePassthroughPollInterval, repeats: true) { [weak self] _ in
            self?.syncMousePassthrough()
        }

        mousePassthroughTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopMousePassthroughMonitor() {
        mousePassthroughTimer?.invalidate()
        mousePassthroughTimer = nil
    }

    private func syncMousePassthrough() {
        guard isVisible else {
            ignoresMouseEvents = true
            return
        }

        let mouseLocation = NSEvent.mouseLocation
        let shouldAcceptMouse = isMouseInsideHoverRegion(for: model.state, at: mouseLocation)
        let shouldIgnoreMouse = !shouldAcceptMouse

        if ignoresMouseEvents != shouldIgnoreMouse {
            ignoresMouseEvents = shouldIgnoreMouse
        }

        if shouldAcceptMouse {
            switch model.state {
            case .idle, .proximity:
                openHoverPanelIfMouseInside(at: mouseLocation)
            default:
                break
            }
        }
    }

    private func isMouseInsideHoverRegion(
        for state: NotchPillState,
        at point: NSPoint = NSEvent.mouseLocation
    ) -> Bool {
        let screen = anchoredScreen ?? preferredScreen()
        guard let screen else { return false }

        let size = NotchPillScreenGeometry.surfaceSize(
            state: state,
            notchSize: model.hardwareNotchSize,
            isExternalDock: model.isExternalDock,
            liveTranscript: model.liveTranscript,
            panelMode: model.activePanelMode,
            hasAllPermissions: model.hasAllPermissions
        )
        let hoverFrame = surfaceFrame(for: size, on: screen)
            .insetBy(dx: -Self.hoverRegionOutset, dy: -Self.hoverRegionOutset)

        return hoverFrame.contains(point)
    }

    private func surfaceFrame(for size: NSSize, on screen: NSScreen) -> NSRect {
        let x = NotchPillScreenGeometry.anchorX(on: screen) - size.width / 2
        let y = screen.frame.maxY - size.height + 2
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    private func resizeToCurrentSurface() {
        applyFrame()
    }

    deinit {
        hoverPanelCloseTimer?.invalidate()
        mousePassthroughTimer?.invalidate()
        flashTimer?.invalidate()
    }
}
