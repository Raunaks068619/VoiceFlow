import Foundation
import AVFoundation
import Combine

/// Lightweight, settings-only audio capture for live mic level visualization.
///
/// **Why a separate service from AudioRecorder**: AudioRecorder is the
/// recording-pipeline owner and its tap only runs while Fn is held. A
/// probe needs to spin up on demand (Settings card "Test mic" button)
/// without any of the recording machinery — no buffer accumulation, no
/// PCM16 conversion, no run-log session, no noise-gate state. Cleanest
/// way is its own minimal AVAudioEngine instance.
///
/// **Lifecycle**: the probe owns its engine. `start()` is idempotent
/// (re-starting tears down the previous engine first). `stop()` is
/// idempotent + safe to call from `onDisappear`. Auto-stops after a
/// bounded duration to defend against the user navigating away with
/// the mic still open.
///
/// **Concurrency**: AVAudioEngine taps fire on a high-priority audio
/// thread; we marshal updates to main via `DispatchQueue.main.async`
/// so SwiftUI can drive `@Published`-bound views safely.
final class MicrophoneProbe: ObservableObject {
    /// Normalized RMS of the most recent buffer, 0...1. Same curve as
    /// AudioRecorder.onAmplitude (sqrt + 1.6× clamp) so visual response
    /// matches the recording overlay.
    @Published private(set) var currentLevel: Float = 0
    /// True while the engine is running. Drives the "Stop" button label
    /// + animated state on the meter.
    @Published private(set) var isProbing: Bool = false

    private var engine: AVAudioEngine?
    private var stopTask: DispatchWorkItem?

    /// Maximum probe duration before auto-stop. Long enough to read a
    /// few sentences out loud; short enough that a forgotten probe
    /// doesn't quietly hold the mic for an hour.
    static let maxDurationSeconds: TimeInterval = 12

    deinit {
        // Engine teardown must happen on a thread that's still alive;
        // the delegate's deinit runs on whatever queue released the
        // last reference. Stop synchronously here.
        teardownEngineSync()
    }

    /// Begin live capture for up to `maxDurationSeconds`. Calling while
    /// already probing is safe — it restarts the timer.
    func start() {
        // Idempotent restart: tear down any existing engine first so we
        // don't end up with two taps on the input bus.
        teardownEngineSync()

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        // Defensive: a zero-channel-count format means the system hasn't
        // attached a real input device (mic permission denied, no mic
        // present). Bail out instead of crashing inside installTap.
        guard format.channelCount > 0 else {
            print("MicrophoneProbe: input format has no channels — aborting probe")
            return
        }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            let rms = MicrophoneProbe.calculateRMS(buffer: buffer)
            // Same perceptual curve as AudioRecorder.onAmplitude. Keeps the
            // probe meter visually consistent with the recording overlay.
            let normalized = min(1.0, sqrt(rms) * 1.6)
            DispatchQueue.main.async {
                self.currentLevel = normalized
            }
        }

        do {
            try engine.start()
            self.engine = engine
            DispatchQueue.main.async { [weak self] in
                self?.isProbing = true
            }

            // Auto-stop guard.
            let task = DispatchWorkItem { [weak self] in self?.stop() }
            stopTask = task
            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.maxDurationSeconds,
                execute: task
            )
        } catch {
            print("MicrophoneProbe: engine.start() failed — \(error)")
            teardownEngineSync()
        }
    }

    /// Stop capture. Safe to call when not probing.
    func stop() {
        teardownEngineSync()
        DispatchQueue.main.async { [weak self] in
            self?.isProbing = false
            self?.currentLevel = 0
        }
    }

    // MARK: - Private

    private func teardownEngineSync() {
        stopTask?.cancel()
        stopTask = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
    }

    /// Mirror of AudioRecorder.calculateRMS so we match the same scale
    /// the recording-time noise gate uses. Static so deinit can call
    /// it without holding a self reference.
    private static func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?.pointee else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<frameLength {
            let s = channelData[i]
            sum += s * s
        }
        return (sum / Float(frameLength)).squareRoot()
    }

    /// Convert a noise-gate threshold (raw RMS, 0.001...0.05) to the
    /// same normalized 0...1 scale the meter renders on. Lets the UI
    /// place the threshold marker visually consistent with the live
    /// level bar.
    static func normalizedThreshold(_ rawThreshold: Double) -> Float {
        let clamped = max(0.0001, min(0.08, rawThreshold))
        return min(1.0, Float(clamped.squareRoot()) * 1.6)
    }
}
