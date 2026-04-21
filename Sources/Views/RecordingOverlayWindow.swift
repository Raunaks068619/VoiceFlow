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
/// - `NSHostingView.sizingOptions = []` prevents SwiftUI ↔ AppKit layout
///   feedback loops on macOS 14+ (the panel size is driven by AppKit only).
/// - `level = .screenSaver` ensures visibility above fullscreen apps,
///   screen sharing overlays, and video players (same as FreeFlow).
/// - Slide-in animation uses a custom cubic bezier with spring overshoot.
final class RecordingOverlayWindow: NSPanel {
    private let model = RecordingOverlayModel()
    private let overlaySize = NSSize(width: 190, height: 34)

    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 190, height: 34)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // .screenSaver: renders above everything including fullscreen apps.
        // This is what FreeFlow uses — guarantees the chip is always visible.
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.ignoresMouseEvents = true
        self.isFloatingPanel = true
        self.hidesOnDeactivate = false
        self.becomesKeyOnlyIfNeeded = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let hosting = NSHostingView(rootView: RecordingOverlayView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: overlaySize)
        hosting.autoresizingMask = [.width, .height]

        self.contentView = hosting
        self.setContentSize(overlaySize)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// The final resting position: centered horizontally, 2pt below screen top.
    private func finalFrame(on screen: NSScreen) -> NSRect {
        let x = screen.frame.midX - overlaySize.width / 2
        let y = screen.frame.maxY - overlaySize.height - 2
        return NSRect(origin: NSPoint(x: x, y: y), size: overlaySize)
    }

    /// Shows the chip with a FreeFlow-style slide-in from above.
    ///
    /// The animation uses a custom cubic bezier (0.34, 1.56, 0.64, 1.0)
    /// that overshoots the final position and settles back — creating a
    /// satisfying "drop into place" spring effect in just 180ms.
    func show(state: RecordingOverlayState = .recording) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                ?? NSScreen.main
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
            self.setFrame(hidden, display: true)
            self.alphaValue = 1
            self.orderFrontRegardless()

            // Spring overshoot bezier: overshoots then settles.
            // Control point y=1.56 > 1.0 is what creates the overshoot.
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
                // Slide back up while fading.
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
            })
        }
    }
}

final class RecordingOverlayModel: ObservableObject {
    @Published var state: RecordingOverlayState = .recording
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
        .frame(width: 190, height: 34)
        // Spring transition between recording ↔ processing states.
        // Same parameters as FreeFlow: snappy response with minimal ringing.
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: model.state)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .recording:
            WaveformIndicator()
        case .processing:
            PulsingDotsIndicator()
        }
    }
}

// MARK: - Waveform (recording state)

/// 7-bar animated waveform. Each bar oscillates on a staggered sine wave,
/// creating a "live mic listening" visual without needing real audio levels.
///
/// Timer lifecycle: uses `onAppear`/`onDisappear` so the 50ms timer only
/// runs while the view is actually on-screen.
private struct WaveformIndicator: View {
    @State private var phase: Double = 0
    @State private var timerCancellable: Timer? = nil
    private let barCount = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 2.5, height: barHeight(for: i))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            timerCancellable = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                phase += 0.18
            }
        }
        .onDisappear {
            timerCancellable?.invalidate()
            timerCancellable = nil
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let offset = Double(index) * 0.55
        let wave = sin(phase + offset)
        return CGFloat(6 + (wave + 1) * 6)
    }
}

// MARK: - Pulsing dots (processing state)

/// Three dots that fade in/out in staggered sequence. Matches the
/// "…" loading affordance used in iMessage / Apple Intelligence.
private struct PulsingDotsIndicator: View {
    @State private var tick: Int = 0
    @State private var timerRef: Timer? = nil

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: 5, height: 5)
                    .opacity(i == (tick % 3) ? 1.0 : 0.3)
                    .scaleEffect(i == (tick % 3) ? 1.15 : 0.9)
                    .animation(.easeInOut(duration: 0.25), value: tick)
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            timerRef = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
                tick &+= 1
            }
        }
        .onDisappear {
            timerRef?.invalidate()
            timerRef = nil
        }
    }
}
