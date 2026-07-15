import Foundation

/// Drives the continuous hands-free dictation loop.
///
/// While hands-free is active the audio engine runs continuously; each ~2s pause
/// "harvests" the current utterance as a WAV. This controller owns the queue of
/// harvested segments and a **serial worker** that transcribes + injects them
/// one at a time, in order — so paste ordering is preserved even when per-segment
/// transcription latencies vary. The owner (AppDelegate) supplies the actual
/// "transcribe + inject one segment" work via `processSegment`.
///
/// Threading: main-thread only, matching the app's GCD style. The single
/// cross-thread point — the shared audio buffer — is guarded inside
/// `AudioRecorder`, not here. Every method below must be called on the main
/// thread, and `processSegment`'s completion must also be invoked on main.
final class ContinuousDictationController {

    enum Phase {
        case idle        // not in continuous hands-free
        case listening   // engine running, accumulating + draining utterances
        case exiting     // user closed hands-free; drain remaining queue, then teardown
    }

    private(set) var phase: Phase = .idle
    var isListening: Bool { phase == .listening }

    private struct PendingSegment {
        let wav: Data
        let context: ContextSnapshot
    }

    private var queue: [PendingSegment] = []
    private var isWorkerBusy = false
    /// Chunks actually injected this session. Drives the "prepend a space before
    /// every chunk except the first" rule, and is incremented only when a chunk
    /// produced non-empty injected text (so a mid-stream empty/filtered chunk
    /// doesn't make the next chunk skip its separator).
    private var injectedChunkCount = 0

    /// Transcribe + inject one harvested segment. Supplied by the owner.
    /// Args: (wav, context, alreadyInjectedCount, completion(injected: Bool)).
    /// `completion` MUST be called exactly once, on the main thread, for the
    /// queue to advance — pass `false` on any failure/empty so the loop drains.
    var processSegment: ((Data, ContextSnapshot, Int, @escaping (Bool) -> Void) -> Void)?

    /// Fired once the queue has fully drained after `beginExit()`. The owner
    /// returns the recording surface to idle here.
    var onExitDrained: (() -> Void)?

    /// Enter the loop. Resets all per-session state.
    func start() {
        phase = .listening
        queue.removeAll()
        isWorkerBusy = false
        injectedChunkCount = 0
    }

    /// A new utterance was harvested mid-session. Enqueue and pump the worker.
    func enqueue(wav: Data, context: ContextSnapshot) {
        guard phase == .listening || phase == .exiting else { return }
        queue.append(PendingSegment(wav: wav, context: context))
        pumpWorker()
    }

    /// User closed hands-free. The owner must enqueue the final in-flight
    /// utterance (if any) BEFORE calling this. Drains the remaining queue, then
    /// fires `onExitDrained`.
    func beginExit() {
        guard phase == .listening else { return }  // no-op on double Fn/Esc
        phase = .exiting
        pumpWorker()
    }

    private func pumpWorker() {
        guard !isWorkerBusy else { return }
        guard let head = queue.first else {
            if phase == .exiting { finishExit() }
            return
        }
        isWorkerBusy = true

        guard let processSegment else {
            // No processor wired — drop to avoid a permanent stall.
            queue.removeFirst()
            isWorkerBusy = false
            pumpWorker()
            return
        }

        let alreadyInjected = injectedChunkCount
        processSegment(head.wav, head.context, alreadyInjected) { [weak self] injected in
            guard let self else { return }
            if injected { self.injectedChunkCount += 1 }
            if !self.queue.isEmpty { self.queue.removeFirst() }
            self.isWorkerBusy = false
            self.pumpWorker()
        }
    }

    private func finishExit() {
        phase = .idle
        queue.removeAll()
        isWorkerBusy = false
        injectedChunkCount = 0
        onExitDrained?()
    }
}
