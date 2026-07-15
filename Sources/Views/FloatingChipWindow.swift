import AppKit
import SwiftUI

enum FeedbackSurfaceStyle: String, CaseIterable {
    case dynamicNotch = "dynamic_notch"
    case draggableChip = "draggable_chip"

    static let userDefaultsKey = "feedback_surface_style"

    static var current: FeedbackSurfaceStyle {
        let stored = UserDefaults.standard.string(forKey: userDefaultsKey)
        return stored.flatMap(FeedbackSurfaceStyle.init(rawValue:)) ?? .dynamicNotch
    }

    var title: String {
        switch self {
        case .dynamicNotch: return "Dynamic Notch"
        case .draggableChip: return "Draggable Chip"
        }
    }

    var subtitle: String {
        switch self {
        case .dynamicNotch:
            return "Docked to the camera notch with hover panel and morphing states."
        case .draggableChip:
            return "Small movable bottom chip that stays out of the menu bar."
        }
    }

    var icon: String {
        switch self {
        case .dynamicNotch: return "capsule.tophalf.filled"
        case .draggableChip: return "arrow.up.and.down.and.arrow.left.and.right"
        }
    }
}

extension Notification.Name {
    static let voiceFlowFeedbackSurfaceStyleChanged = Notification.Name("Vordi.FeedbackSurfaceStyleChanged")
}

protocol FeedbackSurface: AnyObject {
    func show()
    func hide()
    func setRecording()
    func setProcessing()
    func setDone()
    func setIdle()
    func setHandsFree()
    func setHandsFreeExitedAnimating()
    func flashPermissionsWarning(durationSeconds: Double)
    func flashNoInputWarning(durationSeconds: Double)
    func flashTranscriptCopied(durationSeconds: Double)
    func flashNoAudioWarning(durationSeconds: Double)
    func flashNoOutputWarning(durationSeconds: Double)
    func setPermissionsAvailable(_ available: Bool)
    func setMissingPermissions(_ names: [String])
    func updateAudioLevel(_ level: Float)
    func setLiveTranscript(_ text: String)
}

extension NotchPillWindow: FeedbackSurface {
    func setLiveTranscript(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.model.liveTranscript = text
        }
    }
}

final class FloatingChipModel: ObservableObject {
    enum ChipState: Equatable {
        case idle
        case recording
        case processing
        case done
        case noInputWarning
        case transcriptCopied
        case permissionsMissing
        case noAudioWarning
        case noOutputWarning
        case handsFree
    }

    @Published var state: ChipState = .idle
    @Published var audioLevel: Float = 0
    @Published var hasAllPermissions: Bool = true
    @Published var chipHitBounds: CGRect = .zero
}

private struct FloatingChipHitBoundsKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private final class FloatingChipHostingView: NSHostingView<FloatingChipView> {
    weak var model: FloatingChipModel?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let model else { return super.hitTest(point) }
        let bounds = model.chipHitBounds
        if bounds == .zero { return super.hitTest(point) }

        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point)
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

final class FloatingChipWindow: NSPanel, FeedbackSurface {
    let model = FloatingChipModel()

    private static let windowSize = NSSize(width: 420, height: 40)
    private static let originKey = "floating_chip_origin"

    private var flashTimer: Timer?

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        isMovable = true
        isMovableByWindowBackground = false
        isExcludedFromWindowsMenu = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true

        let host = FloatingChipHostingView(rootView: FloatingChipView(model: model))
        host.model = model
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.windowSize)
        host.autoresizingMask = [.width, .height]
        contentView = host
        setContentSize(Self.windowSize)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowMoved),
            name: NSWindow.didMoveNotification,
            object: self
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func handleWindowMoved() {
        let origin = frame.origin
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.originKey)
    }

    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.repositionToBottom()
            self.alphaValue = 1
            self.orderFrontRegardless()
            self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.orderOut(nil)
        }
    }

    func setRecording() {
        setState(.recording, resetAudio: true)
    }

    func setProcessing() {
        setState(.processing)
    }

    func setDone() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flashTimer?.invalidate()
            withAnimation(.easeInOut(duration: 0.15)) {
                self.model.state = .done
                self.model.audioLevel = 0
            }
            self.flashTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                self?.setIdle()
            }
        }
    }

    func setIdle() {
        setState(.idle, resetAudio: true)
    }

    func setHandsFree() {
        setState(.handsFree)
    }

    func setHandsFreeExitedAnimating() {
        setState(.processing)
    }

    func flashPermissionsWarning(durationSeconds: Double = 5.0) {
        flash(.permissionsMissing, durationSeconds: durationSeconds)
    }

    func flashNoInputWarning(durationSeconds: Double = 4.5) {
        flash(.noInputWarning, durationSeconds: durationSeconds) {
            NotificationCenter.default.post(name: Notification.Name("Vordi.DismissChipWarning"), object: nil)
        }
    }

    func flashTranscriptCopied(durationSeconds: Double = 4.5) {
        flash(.transcriptCopied, durationSeconds: durationSeconds) {
            NotificationCenter.default.post(name: Notification.Name("Vordi.DismissChipWarning"), object: nil)
        }
    }

    func flashNoAudioWarning(durationSeconds: Double = 3.0) {
        flash(.noAudioWarning, durationSeconds: durationSeconds)
    }

    func flashNoOutputWarning(durationSeconds: Double = 4.0) {
        flash(.noOutputWarning, durationSeconds: durationSeconds)
    }

    func setPermissionsAvailable(_ available: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.model.hasAllPermissions != available else { return }
            self.model.hasAllPermissions = available
        }
    }

    func setMissingPermissions(_ names: [String]) {}

    func updateAudioLevel(_ level: Float) {
        let normalized = min(max(level, 0), 1)
        if Thread.isMainThread {
            model.audioLevel = normalized
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.model.audioLevel = normalized
            }
        }
    }

    func setLiveTranscript(_ text: String) {}

    private func setState(_ state: FloatingChipModel.ChipState, resetAudio: Bool = false) {
        DispatchQueue.main.async { [weak self] in
            self?.flashTimer?.invalidate()
            withAnimation(.easeInOut(duration: 0.15)) {
                self?.model.state = state
                if resetAudio {
                    self?.model.audioLevel = 0
                }
            }
        }
    }

    private func flash(
        _ state: FloatingChipModel.ChipState,
        durationSeconds: Double,
        onDismiss: (() -> Void)? = nil
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.flashTimer?.invalidate()
            withAnimation(.easeInOut(duration: 0.15)) {
                self.model.state = state
                self.model.audioLevel = 0
            }
            self.flashTimer = Timer.scheduledTimer(withTimeInterval: durationSeconds, repeats: false) { [weak self] _ in
                guard let self, self.model.state == state else { return }
                self.setIdle()
                onDismiss?()
            }
        }
    }

    private func repositionToBottom() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = Self.windowSize

        if let saved = UserDefaults.standard.string(forKey: Self.originKey) {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                let candidate = NSRect(
                    x: CGFloat(parts[0]),
                    y: CGFloat(parts[1]),
                    width: size.width,
                    height: size.height
                )
                if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(candidate) }) {
                    setFrame(candidate, display: true)
                    return
                }
            }
        }

        setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + 24,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    deinit {
        flashTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

private extension Color {
    static let floatingChipFill = Color(red: 0.13, green: 0.13, blue: 0.15)
    static let floatingChipBorder = Color.white.opacity(0.22)
}

private struct FloatingChipGlass: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Capsule(style: .continuous).fill(Color.floatingChipFill))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.floatingChipBorder, lineWidth: 1))
    }
}

private struct FloatingChipCursorOnHover: ViewModifier {
    let cursor: NSCursor

    func body(content: Content) -> some View {
        content.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private extension View {
    func floatingChipGlass() -> some View {
        modifier(FloatingChipGlass())
    }

    func floatingChipCursorOnHover(_ cursor: NSCursor) -> some View {
        modifier(FloatingChipCursorOnHover(cursor: cursor))
    }
}

struct FloatingChipView: View {
    @ObservedObject var model: FloatingChipModel
    @State private var hovering = false

    var body: some View {
        HStack {
            Spacer()
            chipShape
                .floatingChipCursorOnHover(.openHand)
                .animation(.easeInOut(duration: 0.18), value: model.state)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: FloatingChipHitBoundsKey.self,
                            value: geo.frame(in: .named("floatingChipHost"))
                        )
                    }
                )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .coordinateSpace(name: "floatingChipHost")
        .onPreferenceChange(FloatingChipHitBoundsKey.self) { rect in
            model.chipHitBounds = rect
        }
    }

    @ViewBuilder
    private var chipShape: some View {
        switch model.state {
        case .idle:
            idleChip
        case .recording:
            recordingChip
        case .processing:
            processingChip
        case .done:
            doneChip
        case .noInputWarning:
            warningChip(
                badge: "Tip",
                icon: "info.circle.fill",
                color: Color(red: 0.85, green: 0.70, blue: 1.0),
                text: "Click a textbox and use Cmd+V to paste",
                actionIcon: "xmark",
                action: {
                    NotificationCenter.default.post(name: Notification.Name("Vordi.DismissChipWarning"), object: nil)
                }
            )
        case .transcriptCopied:
            warningChip(
                badge: "Copied",
                icon: "doc.on.clipboard.fill",
                color: Color(red: 0.59, green: 0.16, blue: 1.00),
                text: "Transcript copied - use Cmd+V to paste",
                actionIcon: "xmark",
                action: {
                    NotificationCenter.default.post(name: Notification.Name("Vordi.DismissChipWarning"), object: nil)
                }
            )
        case .permissionsMissing:
            warningChip(
                badge: "Action",
                icon: "exclamationmark.shield.fill",
                color: Theme.accent,
                text: "Grant permissions to dictate",
                actionIcon: "chevron.right",
                action: {
                    NotificationCenter.default.post(name: Notification.Name("Vordi.OpenOnboardingPermissions"), object: nil)
                }
            )
        case .noAudioWarning:
            warningChip(
                badge: "Quiet",
                icon: "mic.slash.fill",
                color: Color(red: 1.0, green: 0.85, blue: 0.55),
                text: "Didn't catch that - adjust Mic Sensitivity",
                actionIcon: "chevron.right",
                action: {
                    NotificationCenter.default.post(name: Notification.Name("Vordi.OpenSettings"), object: nil)
                }
            )
        case .noOutputWarning:
            warningChip(
                badge: "Filtered",
                icon: "exclamationmark.triangle.fill",
                color: Color(red: 1.0, green: 0.85, blue: 0.55),
                text: "No output generated - check Run Log",
                actionIcon: "chevron.right",
                action: {
                    NotificationCenter.default.post(name: Notification.Name("Vordi.OpenRunLog"), object: nil)
                }
            )
        case .handsFree:
            handsFreeChip
        }
    }

    private var idleChip: some View {
        HStack(spacing: 6) {
            Button {
                NotificationCenter.default.post(name: Notification.Name("Vordi.OpenRunLog"), object: nil)
            } label: {
                floatingIcon("clock.arrow.circlepath")
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
            .help("Open Run Log")
            .opacity(hovering ? 1 : 0)
            .scaleEffect(hovering ? 1 : 0.4, anchor: .trailing)
            .offset(x: hovering ? 0 : 8)
            .allowsHitTesting(hovering)

            Button {
                if !model.hasAllPermissions {
                    NotificationCenter.default.post(name: Notification.Name("Vordi.OpenOnboardingPermissions"), object: nil)
                }
            } label: {
                ZStack {
                    Capsule(style: .continuous)
                        .fill(model.hasAllPermissions ? Color.floatingChipFill : Theme.accent)
                    Capsule(style: .continuous)
                        .strokeBorder(Color.floatingChipBorder, lineWidth: hovering ? 1 : 0.5)
                    if hovering {
                        VFBrandLogo(size: 16, variant: .dark, cornerRadius: 4)
                            .transition(.opacity)
                    }
                }
                .frame(width: hovering ? 64 : 40, height: hovering ? 24 : 4)
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
            .help(model.hasAllPermissions ? "Drag to move" : "Click to fix permissions")

            Button {
                NotificationCenter.default.post(name: Notification.Name("Vordi.OpenSettings"), object: nil)
            } label: {
                floatingIcon("gearshape.fill")
            }
            .buttonStyle(.plain)
            .vfClickableCursor()
            .help("Open Settings")
            .opacity(hovering ? 1 : 0)
            .scaleEffect(hovering ? 1 : 0.4, anchor: .leading)
            .offset(x: hovering ? 0 : -8)
            .allowsHitTesting(hovering)
        }
        .frame(height: 30)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: hovering)
    }

    private var recordingChip: some View {
        FloatingChipWaveform(audioLevel: model.audioLevel)
            .frame(width: 100, height: 24)
            .floatingChipGlass()
    }

    private var processingChip: some View {
        FloatingChipShimmer()
            .frame(width: 100, height: 24)
            .floatingChipGlass()
    }

    private var doneChip: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Theme.success)
            Text("Done")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.86))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 6)
        .floatingChipGlass()
    }

    private var handsFreeChip: some View {
        HStack(spacing: 8) {
            FloatingPulsingDot(color: Theme.accent)
                .frame(width: 8, height: 8)
            FloatingChipWaveform(audioLevel: model.audioLevel)
                .frame(width: 56, height: 18)
            Text("HANDS FREE")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(0.6)
                .foregroundColor(.white.opacity(0.85))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .floatingChipGlass()
        .help("Hands-free mode - press Fn or Escape to stop")
    }

    private func warningChip(
        badge: String,
        icon: String,
        color: Color,
        text: String,
        actionIcon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.18)))

                Text(text)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)

                Spacer(minLength: 4)

                Image(systemName: actionIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.white.opacity(0.10)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .floatingChipGlass()
        }
        .buttonStyle(.plain)
        .vfClickableCursor()
    }

    private func floatingIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 24, height: 24)
            .background(Circle().fill(Color.floatingChipFill))
            .overlay(Circle().strokeBorder(Color.floatingChipBorder, lineWidth: 1))
    }
}

private struct FloatingChipWaveform: View {
    let audioLevel: Float

    private static let multipliers: [CGFloat] = [0.45, 0.65, 0.85, 1.0, 0.85, 0.65, 0.45]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.multipliers.indices, id: \.self) { index in
                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: barHeight(for: index))
                    .animation(.spring(response: 0.12, dampingFraction: 0.75), value: audioLevel)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        let minHeight: CGFloat = 3
        let maxHeight: CGFloat = 14
        let amplitude = min(level * Self.multipliers[index], 1.0)
        return minHeight + (maxHeight - minHeight) * amplitude
    }
}

private struct FloatingChipShimmer: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    let phase = sin(time * 4.0 - Double(index) * 0.4) * 0.5 + 0.5
                    Capsule()
                        .fill(Color.white.opacity(0.35 + phase * 0.5))
                        .frame(width: 2, height: 8)
                }
            }
        }
    }
}

private struct FloatingPulsingDot: View {
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = 0.5 + 0.5 * sin(time * 2.4)
            ZStack {
                Circle()
                    .fill(color.opacity(0.32))
                    .scaleEffect(0.85 + CGFloat(phase) * 0.7)
                Circle()
                    .fill(color)
                    .opacity(0.55 + phase * 0.45)
            }
        }
    }
}
