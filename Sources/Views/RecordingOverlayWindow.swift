import SwiftUI
import AppKit

enum RecordingOverlayState: Equatable {
    case recording
    case processing
}

/// Notch-shaped status chip pinned directly below the camera housing.
///
/// Visual target: solid black rounded rectangle that looks like a continuation
/// of the Apple notch. On non-notched Macs it still reads as a "floating
/// black chip under the menu bar," which is the same design language.
///
/// Implementation notes:
/// - Uses `NSPanel` (not `NSWindow`) so `.nonactivatingPanel` is legal.
/// - Window level: `CGWindowLevelForKey(.statusWindow) + 2`. We avoid
///   `.screenSaver` because macOS 26 (Tahoe) silently filters that level
///   for non-screen-recording apps, which causes the chip to render
///   _below_ the menu bar (invisible). `.statusWindow + 2` always sits
///   above the menu bar and is permitted for any app.
/// - Slide-in animation uses a custom cubic bezier with spring overshoot.
final class RecordingOverlayWindow: NSPanel {
    let model = RecordingOverlayModel()
    private let overlaySize = NSSize(width: 160, height: 38)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 160, height: 38)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        self.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: RecordingOverlayView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: overlaySize)
        hosting.autoresizingMask = [.width, .height]

        self.contentView = hosting
        self.setContentSize(overlaySize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Final resting position: centered horizontally, sitting just below the
    /// menu bar (and notch on notched MacBooks).
    ///
    /// We anchor to `visibleFrame.maxY` rather than `frame.maxY`. On notched
    /// MacBooks, `frame.maxY` is the absolute top of the display panel —
    /// which is the camera notch hole. Positioning content there gets the
    /// middle of the chip clipped by the notch hardware. `visibleFrame.maxY`
    /// already accounts for both the menu bar AND the notch overlap, so
    /// anchoring there guarantees the chip sits in usable screen real estate.
    ///
    /// Gap: 4pt of breathing room below the menu bar so the chip doesn't
    /// look fused to it.
    private func finalFrame(on screen: NSScreen) -> NSRect {
        let x = screen.frame.midX - overlaySize.width / 2
        let topAvailable = screen.visibleFrame.maxY
        let y = topAvailable - overlaySize.height - 4
        return NSRect(origin: NSPoint(x: x, y: y), size: overlaySize)
    }

    /// Shows the chip with a FreeFlow-style slide-in from above.
    func show(state: RecordingOverlayState = .recording) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main
                ?? NSScreen.screens.first
            guard let screen else { return }

            let final = self.finalFrame(on: screen)

            // Start hidden above the screen edge (the chip "drops in").
            let hidden = NSRect(
                x: final.origin.x,
                y: screen.frame.maxY,
                width: final.width,
                height: final.height
            )

            self.model.state = state
            self.model.audioLevel = 0
            self.setFrame(hidden, display: true)
            self.alphaValue = 1
            self.orderFrontRegardless()
            // Re-assert level — some macOS versions reset it on space-join.
            self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.34, 1.56, 0.64, 1.0
                )
                self.animator().setFrame(final, display: true)
            }
        }
    }

    func setState(_ newState: RecordingOverlayState) {
        DispatchQueue.main.async { [weak self] in
            self?.model.state = newState
        }
    }

    /// Push a live amplitude sample (0...1). Safe to call from any thread.
    func updateAudioLevel(_ level: Float) {
        if Thread.isMainThread {
            model.audioLevel = level
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.model.audioLevel = level
            }
        }
    }

    /// Hides with a quick slide-up + fade combo.
    func hide() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main

            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                self.animator().alphaValue = 0.0
                if let screen {
                    let upFrame = NSRect(
                        x: self.frame.origin.x,
                        y: screen.frame.maxY,
                        width: self.frame.width,
                        height: self.frame.height
                    )
                    self.animator().setFrame(upFrame, display: true)
                }
            }, completionHandler: { [weak self] in
                self?.orderOut(nil)
                self?.model.audioLevel = 0
            })
        }
    }
}

/// View-model for the overlay.
///
/// Single `audioLevel: Float` (0...1) — the WaveformView derives all 9 bar
/// heights from this one value via static multipliers. Same pattern as
/// FreeFlow: cheaper to publish, cleaner to animate, no array churn.
final class RecordingOverlayModel: ObservableObject {
    @Published var state: RecordingOverlayState = .recording
    @Published var audioLevel: Float = 0
}

struct RecordingOverlayView: View {
    @ObservedObject var model: RecordingOverlayModel

    var body: some View {
        ZStack {
            // Solid black "notch extension" shape.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .shadow(color: .black.opacity(0.35), radius: 6, x: 0, y: 2)

            // Subtle inner highlight along the top edge sells the "glass" feel.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)

            content
                .padding(.horizontal, 14)
        }
        .frame(width: 160, height: 38)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: model.state)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .recording:
            WaveformView(audioLevel: model.audioLevel)
        case .processing:
            ProcessingWaveformView()
        }
    }
}

// MARK: - Waveform views (FreeFlow pattern)

/// Single bar of the live waveform. Maps an amplitude (0...1) to a height
/// between `minHeight` and `maxHeight`. Always renders at least `minHeight`
/// so an idle waveform reads as a flat line of pills, not invisible.
private struct WaveformBar: View {
    let amplitude: CGFloat

    private let minHeight: CGFloat = 3
    private let maxHeight: CGFloat = 22

    var body: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 3, height: minHeight + (maxHeight - minHeight) * amplitude)
    }
}

/// 9-bar live waveform driven by a single audioLevel scalar.
///
/// Pattern lifted from FreeFlow:
/// - Static multipliers [0.35 ... 1.0 ... 0.35] give the wave its shape.
///   The center bar always reaches highest, edges stay shorter — creates
///   the classic "voice level meter" look without per-bar audio analysis.
/// - Per-bar spring response widens slightly toward the edges, plus a
///   tiny per-bar delay scaled by distance from center. Effect: the
///   center pulses first, the wave "ripples" outward.
/// - Animation key = audioLevel (single scalar). SwiftUI re-evaluates
///   the body on every change, but the animation engine batches the
///   per-bar springs cleanly.
private struct WaveformView: View {
    let audioLevel: Float

    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.35, 0.55, 0.75, 0.9, 1.0, 0.9, 0.75, 0.55, 0.35]
    private static let centerIndex = CGFloat((barCount - 1) / 2)

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                WaveformBar(amplitude: barAmplitude(for: index))
                    .animation(
                        .spring(
                            response: barResponse(for: index),
                            dampingFraction: 0.88
                        )
                        .delay(barDelay(for: index)),
                        value: audioLevel
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func barAmplitude(for index: Int) -> CGFloat {
        let level = CGFloat(audioLevel)
        return min(level * Self.multipliers[index], 1.0)
    }

    private func barResponse(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        let normalizedDistance = distance / Self.centerIndex
        return 0.18 + Double(normalizedDistance) * 0.06
    }

    private func barDelay(for index: Int) -> Double {
        let distance = abs(CGFloat(index) - Self.centerIndex)
        return Double(distance) * 0.01
    }
}

/// Self-driven shimmer for the processing/transcribing phase. Same 9-bar
/// shape, but heights driven by paired sine waves on a TimelineView so
/// the chip looks "alive" while we wait for STT + polish.
private struct ProcessingWaveformView: View {
    private static let barCount = 9
    private static let multipliers: [CGFloat] = [0.42, 0.58, 0.76, 0.9, 1.0, 0.9, 0.76, 0.58, 0.42]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate

            HStack(spacing: 2.5) {
                ForEach(0..<Self.barCount, id: \.self) { index in
                    let wave = 0.5 + 0.5 * sin((time * 5.6) - Double(index) * 0.5)
                    let shimmer = 0.5 + 0.5 * sin((time * 2.8) + Double(index) * 0.75)
                    let amplitude = min(
                        0.16 + CGFloat(wave) * Self.multipliers[index] * 0.52 + CGFloat(shimmer) * 0.08,
                        1.0
                    )

                    WaveformBar(amplitude: amplitude)
                        .opacity(0.45 + CGFloat(wave) * 0.5)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
