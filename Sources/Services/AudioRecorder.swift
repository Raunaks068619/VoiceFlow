import Foundation
import AVFoundation

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    /// Mirrors whether this recorder installed a tap on `inputNode`.
    /// AVFoundation raises an uncaught Objective-C exception when a second tap
    /// is installed on the same bus, so tap ownership must be explicit rather
    /// than inferred from `isRecording`.
    private var inputTapInstalled = false
    /// Cancels the delayed 350 ms teardown when a capture is aborted or its
    /// lifecycle is superseded (for example Fn transitioning to Fn+Control).
    private var pendingStopWorkItem: DispatchWorkItem?
    private var rawAudioBuffer: [AVAudioPCMBuffer] = []
    private var isRecording = false
    private var recordingCallback: ((Data?) -> Void)?
    private var noiseGateThreshold: Float = 0.015
    private var firstVoicedIndex: Int?
    private var lastVoicedIndex: Int?
    /// Total number of buffers whose RMS exceeded the noise gate. Used
    /// in `stopRecording` to enforce a *minimum voiced duration* — not
    /// just a single voiced buffer. Hard-gates the "user pressed Fn,
    /// brushed the mic for 30ms, released" pattern that produces tiny
    /// blips that Whisper hallucinates over.
    private var voicedBufferCount: Int = 0

    // MARK: - Realtime streaming hook
    //
    // Optional callback fired for every input buffer, carrying 16-bit PCM
    // mono audio resampled to 24 kHz — the format OpenAI's Realtime API
    // expects. When set, we convert each incoming buffer and pass it along
    // in parallel with our existing batch collection. The batch path stays
    // untouched, so if streaming fails the caller can still fall back to
    // the full WAV produced by `stopRecording`.
    //
    // We cache the AVAudioConverter because each init-allocates internal
    // buffers; creating one per tap callback halves throughput.
    var onPCM16Samples: ((Data) -> Void)?
    private var pcm16Converter: AVAudioConverter?
    private var pcm16OutputFormat: AVAudioFormat?

    /// Fires the raw captured buffer (input format) for every tap callback, so an
    /// on-device speech recognizer can drive a live preview. Additive and
    /// best-effort — nil when the on-device preview is off. Fires on the tap
    /// thread; the owner is responsible for hopping to wherever it consumes it.
    var onLiveSpeechBuffer: ((AVAudioPCMBuffer) -> Void)?

    // MARK: - Live amplitude (UI meter)
    //
    // Fires the latest normalized RMS (0...1) for every input buffer, so the
    // recording overlay can render a real audio-reactive waveform instead of
    // a canned sine animation. We reuse the RMS we already compute for the
    // noise gate — zero extra DSP cost.
    //
    // Throttle policy: tap fires ~46Hz at 48kHz/1024. We push every sample
    // because SwiftUI coalesces @Published updates within a runloop tick;
    // the cost is one Float marshal across the main queue.
    var onAmplitude: ((Float) -> Void)?
    // ~21ms per 1024-frame buffer at 48kHz. Keep ~700ms tail so trailing
    // consonants, soft endings ('huh', 'hai'), and the natural release
    // of the user's last syllable don't get clipped. Bumped from 500ms
    // after a regression where final words were getting cut.
    private let trailingPaddingBufferCount = 32
    // Keep ~200ms of lead-in before the first detected voice activity. This
    // captures the onset ramp of the first word — the phoneme attack is
    // almost always below steady-state RMS for 20-80ms, and clipping it
    // makes Whisper mis-hear or drop the word entirely.
    private let leadingPaddingBufferCount = 10
    // Grace period after `stopRecording` is invoked, before we actually
    // tear down the engine. Why: the trailing-padding pass can only pad
    // with buffers that already exist. If the user releases Fn the
    // instant they finish speaking, `lastVoicedIndex` IS the final
    // buffer — there's nothing to pad with, so the trailing word gets
    // clipped. This grace period lets the input tap collect ~350ms more
    // audio after the user's release, giving the padding logic real
    // buffers to work with. Cost: 350ms of perceived latency between
    // Fn release and transcript landing. Worth it — every regression
    // report was about cut-off words at the end.
    private let stopGraceMilliseconds: Int = 350

    /// Minimum number of voiced buffers required to dispatch the
    /// recording to STT. Below this, we treat the recording as
    /// silence + transient noise and drop it without ever hitting
    /// Whisper.
    ///
    /// Math: at 48kHz with 1024-frame buffers, each buffer is ~21.3ms.
    /// 6 buffers ≈ 128ms — below the duration of even short words
    /// like "yes" or "no" (typically 200–300ms with leading/trailing
    /// transients). Real dictations always cross this; phantom-mic
    /// triggers (Fn brushed accidentally, knuckle on the mic, single
    /// burst of fan noise) don't.
    ///
    /// Combined with `firstVoicedIndex != nil` from the existing gate,
    /// we now require: SOMETHING voiced was captured AND the voiced
    /// content lasted at least ~128ms. Both conditions must hold.
    private let minimumVoicedBuffers: Int = 6

    // MARK: - Continuous hands-free (pause-triggered segment harvest)
    //
    // When `continuousHandsFree` is true the tap additionally watches for a
    // ~2s in-utterance pause and fires `onUtteranceSilence` ONCE per utterance.
    // The owner then calls `harvestSegment()` to cut the buffered audio for that
    // utterance while the engine keeps running for the next one. None of this
    // touches the normal hold-to-dictate path (flag defaults to false).
    var onUtteranceSilence: (() -> Void)?
    private var continuousHandsFree = false
    /// In-utterance pause that triggers a harvest, in seconds.
    private let handsFreeSilenceThreshold: TimeInterval = 2.0
    /// `handsFreeSilenceThreshold` expressed in tap buffers. Recomputed from the
    /// live input sample rate on each start (mic rates vary), so the wall-clock
    /// pause is correct regardless of device.
    private var silenceBufferTarget = 94
    private var consecutiveSilentBuffers = 0
    /// Latch so one long pause fires `onUtteranceSilence` exactly once. Reset
    /// when voiced audio resumes (next utterance) or on harvest.
    private var silenceFiredForCurrentUtterance = false
    /// Guards `rawAudioBuffer` + voiced markers. The tap (render thread) is now
    /// a second writer alongside `harvestSegment()` (main thread); without a
    /// lock the cut would race the append. Cheap: ~tens of ns at ~46Hz.
    private let bufferLock = NSLock()

    override init() {
        super.init()
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
        inputTapInstalled = false
    }

    private func removeInputTapIfNeeded() {
        guard inputTapInstalled else { return }
        inputNode?.removeTap(onBus: 0)
        inputTapInstalled = false
    }

    /// A persistent AVAudioEngine can retain a stale input format after a mic
    /// switch, Bluetooth profile change, or wake from sleep. Rebuilding it for
    /// each new capture gives installTap a fresh node and current hardware
    /// format, while also guaranteeing no prior tap can survive.
    private func resetAudioEngineForNewCapture() {
        removeInputTapIfNeeded()
        if audioEngine?.isRunning == true { audioEngine?.stop() }
        setupAudioEngine()
    }

    func startRecording(continuousHandsFree: Bool = false) -> Bool {
        guard !isRecording else { return false }

        pendingStopWorkItem?.cancel()
        pendingStopWorkItem = nil
        resetAudioEngineForNewCapture()
        guard let audioEngine, let inputNode else { return false }

        rawAudioBuffer.removeAll()
        firstVoicedIndex = nil
        lastVoicedIndex = nil
        voicedBufferCount = 0
        noiseGateThreshold = max(0.001, min(0.08, UserDefaults.standard.float(forKey: "noise_gate_threshold")))
        // Reset converter — input format can change between sessions if
        // user switches mic (different sample rate / channel count).
        pcm16Converter = nil
        pcm16OutputFormat = nil

        // Continuous hands-free silence detection state.
        self.continuousHandsFree = continuousHandsFree
        consecutiveSilentBuffers = 0
        silenceFiredForCurrentUtterance = false

        let format = inputNode.outputFormat(forBus: 0)
        // installTap does not report an invalid hardware format as a Swift
        // error. It raises NSException and terminates the process. This format
        // can briefly be 0 Hz / 0 channels during device transitions, so fail
        // this recording attempt cleanly and let the next press retry.
        guard format.sampleRate.isFinite,
              format.sampleRate > 0,
              format.channelCount > 0 else {
            DebugLog.log("AudioRecorder: invalid input format; start skipped sr=\(format.sampleRate) channels=\(format.channelCount)")
            return false
        }
        // Derive the pause threshold in buffers from the live sample rate
        // (1024 frames per tap buffer). At 48kHz this is ~94 buffers ≈ 2s.
        let sampleRate = format.sampleRate
        silenceBufferTarget = max(1, Int(handsFreeSilenceThreshold * sampleRate / 1024.0))

        // Capture ALL audio into rawAudioBuffer and remember which buffers had
        // voice activity. Previously we ran a real-time noise gate that dropped
        // sub-threshold buffers entirely; that caused two failure modes:
        //
        // 1. Long pauses mid-recording → the gate ran out of hangover and
        //    started dropping. When the user resumed speaking, the onset ramp
        //    of the first post-pause word was often below threshold, so its
        //    leading phoneme was cut. Whisper then mis-heard or dropped the
        //    word entirely.
        // 2. Gated concatenation removed all internal silences, which broke
        //    Whisper's internal VAD-based segmentation.
        //
        // New approach: keep every buffer verbatim. On stop, trim only the
        // *leading and trailing* silence using the voiced-index markers, with
        // generous padding on both sides. This preserves mid-recording pauses
        // (which are semantically meaningful) while still shaving bandwidth.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let copiedBuffer = self.copyBuffer(buffer) else { return }
            let rms = self.calculateRMS(buffer: copiedBuffer)

            // Mutate shared buffer/voiced state under the lock so a concurrent
            // harvestSegment() (main thread) can't race the append.
            var fireSilence = false
            self.bufferLock.lock()
            let index = self.rawAudioBuffer.count
            self.rawAudioBuffer.append(copiedBuffer)
            let voiced = rms >= self.noiseGateThreshold
            if voiced {
                if self.firstVoicedIndex == nil { self.firstVoicedIndex = index }
                self.lastVoicedIndex = index
                self.voicedBufferCount += 1
            }
            // Continuous hands-free: detect a ~2s in-utterance pause and arm a
            // one-shot harvest. Only counts silence AFTER voiced onset, so it
            // never fires on the initial "entered the mode but said nothing"
            // silence; the latch makes it fire once per utterance.
            if self.continuousHandsFree {
                if voiced {
                    self.consecutiveSilentBuffers = 0
                    self.silenceFiredForCurrentUtterance = false
                } else if self.firstVoicedIndex != nil {
                    self.consecutiveSilentBuffers += 1
                    if self.consecutiveSilentBuffers >= self.silenceBufferTarget
                        && self.voicedBufferCount >= self.minimumVoicedBuffers
                        && !self.silenceFiredForCurrentUtterance {
                        self.silenceFiredForCurrentUtterance = true
                        fireSilence = true
                    }
                }
            }
            self.bufferLock.unlock()

            // Push live amplitude to any UI meter subscriber. Normalize and
            // mild non-linear curve so quiet speech still moves the bars
            // (raw RMS for normal speech sits around 0.02–0.10, which would
            // barely budge a linear meter). sqrt + clamp gives a perceptually
            // smoother response — same trick AVAudioRecorder's metering uses.
            if let onAmplitude = self.onAmplitude {
                let normalized = min(1.0, sqrt(rms) * 1.6)
                DispatchQueue.main.async { onAmplitude(normalized) }
            }
            // Additive: if streaming is enabled, also emit PCM16 @ 24kHz.
            // Failure here is silent — streaming is best-effort on top of
            // the batch pipeline, not a replacement.
            if self.onPCM16Samples != nil {
                if let pcm16 = self.convertToPCM16At24kHz(buffer: copiedBuffer) {
                    self.onPCM16Samples?(pcm16)
                }
            }
            // Additive: feed the on-device live-preview recognizer the raw buffer.
            self.onLiveSpeechBuffer?(copiedBuffer)
            if fireSilence {
                DispatchQueue.main.async { [weak self] in self?.onUtteranceSilence?() }
            }
        }
        inputTapInstalled = true

        do {
            try audioEngine.start()
            isRecording = true
            print("Recording started")
            DebugLog.log("AudioRecorder: engine STARTED continuous=\(continuousHandsFree) silenceTarget=\(silenceBufferTarget) noiseGate=\(noiseGateThreshold) sr=\(sampleRate)")
            return true
        } catch {
            removeInputTapIfNeeded()
            print("Failed to start audio engine: \(error)")
            DebugLog.log("AudioRecorder: engine START FAILED continuous=\(continuousHandsFree) error=\(error)")
            return false
        }
    }

    func stopRecording(completion: @escaping (Data?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        // Grace period: keep the tap installed for a few hundred ms after
        // the user releases Fn. This guarantees the trailing-padding logic
        // has actual buffers to pad with — without it, words dictated up
        // to the moment of release get clipped. See the constant comment
        // for the full rationale.
        pendingStopWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingStopWorkItem = nil

            self.removeInputTapIfNeeded()
            self.audioEngine?.stop()
            self.isRecording = false
            self.continuousHandsFree = false

            // Snapshot under the lock (a final in-flight tap callback may still
            // be landing), then trim + encode off-lock.
            self.bufferLock.lock()
            let buffers = self.rawAudioBuffer
            let first = self.firstVoicedIndex
            let last = self.lastVoicedIndex
            let voiced = self.voicedBufferCount
            self.bufferLock.unlock()

            let audioData = self.encodeVoicedSegment(
                buffers: buffers, firstVoiced: first, lastVoiced: last, voicedCount: voiced
            )
            completion(audioData)
        }
        pendingStopWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(stopGraceMilliseconds),
            execute: work
        )
    }

    /// Trim leading/trailing silence (with padding) from a captured buffer run
    /// and WAV-encode it, enforcing the `minimumVoicedBuffers` gate. Returns nil
    /// when the run lacks enough voiced content. Pure over its arguments — no
    /// engine/tap access — so both `stopRecording` and `harvestSegment` share it.
    ///
    /// TWO conditions must both hold to produce audio:
    ///   1. At least one buffer crossed the RMS noise gate (first/last set)
    ///   2. At least `minimumVoicedBuffers` total voiced buffers (≈128ms)
    /// This kills: held-but-silent, accidental mic tap, single fan burst.
    private func encodeVoicedSegment(
        buffers: [AVAudioPCMBuffer],
        firstVoiced: Int?,
        lastVoiced: Int?,
        voicedCount: Int
    ) -> Data? {
        guard let first = firstVoiced, let last = lastVoiced,
              voicedCount >= minimumVoicedBuffers else {
            print("Segment dropped (insufficient voiced audio: \(voicedCount) voiced of \(buffers.count), need ≥\(minimumVoicedBuffers) — no STT call)")
            return nil
        }
        // Trim leading/trailing silence with padding on both sides. Interior
        // silence is preserved — a mid-sentence pause stays a pause so Whisper's
        // segmenter has a chance.
        let start = max(0, first - leadingPaddingBufferCount)
        let end = min(buffers.count - 1, last + trailingPaddingBufferCount)
        guard start <= end else { return nil }
        let selected = Array(buffers[start...end])
        print("Segment encoded (voiced range \(first)...\(last), \(voicedCount) voiced of \(buffers.count) total, trimmed to \(start)...\(end))")
        return convertBuffersToWAV(from: selected)
    }

    /// Continuous hands-free only: cut the audio accumulated for the current
    /// utterance into a WAV, reset the accumulators, and let the tap keep
    /// running for the next utterance (the engine is NOT stopped). Returns nil
    /// when the cut lacks enough voiced content. Call on the main thread.
    func harvestSegment() -> Data? {
        guard continuousHandsFree, isRecording else { return nil }
        bufferLock.lock()
        let buffers = rawAudioBuffer
        let first = firstVoicedIndex
        let last = lastVoicedIndex
        let voiced = voicedBufferCount
        // Reset so the NEXT utterance starts clean; tap keeps appending.
        rawAudioBuffer.removeAll(keepingCapacity: true)
        firstVoicedIndex = nil
        lastVoicedIndex = nil
        voicedBufferCount = 0
        consecutiveSilentBuffers = 0
        silenceFiredForCurrentUtterance = false
        bufferLock.unlock()
        return encodeVoicedSegment(buffers: buffers, firstVoiced: first, lastVoiced: last, voicedCount: voiced)
    }

    /// Tear down the engine at the end of a continuous hands-free session. The
    /// owner harvests the final in-flight utterance BEFORE calling this. No
    /// grace period is needed — every utterance is already followed by ≥2s of
    /// real trailing silence, so the trailing-padding has plenty to work with.
    func stopContinuous() {
        guard continuousHandsFree else { return }
        pendingStopWorkItem?.cancel()
        pendingStopWorkItem = nil
        removeInputTapIfNeeded()
        audioEngine?.stop()
        isRecording = false
        continuousHandsFree = false
        consecutiveSilentBuffers = 0
        silenceFiredForCurrentUtterance = false
    }

    /// Immediately tear down the engine/tap and DROP the current capture without
    /// transcribing it — no grace period, no completion. Used when a push-to-talk
    /// recording (started because Fn landed a beat before Control) must be
    /// converted into a hands-free session: we discard the stray audio so the
    /// engine can be restarted cleanly in continuous mode. Safe to call when not
    /// recording (no-op). Main thread.
    func abort() {
        pendingStopWorkItem?.cancel()
        pendingStopWorkItem = nil
        removeInputTapIfNeeded()
        audioEngine?.stop()
        isRecording = false
        continuousHandsFree = false
        bufferLock.lock()
        rawAudioBuffer.removeAll()
        firstVoicedIndex = nil
        lastVoicedIndex = nil
        voicedBufferCount = 0
        consecutiveSilentBuffers = 0
        silenceFiredForCurrentUtterance = false
        bufferLock.unlock()
    }

    private func convertBuffersToWAV(from buffers: [AVAudioPCMBuffer]) -> Data? {
        guard !buffers.isEmpty else { return nil }
        
        // Get format from first buffer
        guard let format = buffers.first?.format else { return nil }
        
        // Calculate total frames
        var totalFrames: AVAudioFrameCount = 0
        for buffer in buffers {
            totalFrames += buffer.frameLength
        }
        
        // Create output buffer
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: totalFrames) else {
            return nil
        }
        
        // Copy all buffers into output buffer
        var offset: AVAudioFrameCount = 0
        for buffer in buffers {
            let frames = buffer.frameLength
            if let srcData = buffer.floatChannelData, let dstData = outputBuffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    memcpy(dstData[channel].advanced(by: Int(offset)), 
                           srcData[channel], 
                           Int(frames) * MemoryLayout<Float>.size)
                }
            }
            offset += frames
        }
        outputBuffer.frameLength = totalFrames
        
        // Convert to WAV data
        return convertToWAV(buffer: outputBuffer, format: format)
    }
    
    private func convertToWAV(buffer: AVAudioPCMBuffer, format: AVAudioFormat) -> Data {
        var data = Data()
        
        let sampleRate = Int(format.sampleRate)
        let channels = Int(format.channelCount)
        let frameCount = Int(buffer.frameLength)
        let bytesPerSample = 2 // 16-bit
        let dataSize = frameCount * channels * bytesPerSample
        let fileSize = 36 + dataSize
        
        // RIFF header
        data.append("RIFF".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(fileSize).littleEndian) { Data($0) })
        data.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        data.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) }) // PCM
        data.append(withUnsafeBytes(of: UInt16(channels).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt32(sampleRate * channels * bytesPerSample).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(channels * bytesPerSample).littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: UInt16(bytesPerSample * 8).littleEndian) { Data($0) })
        
        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(withUnsafeBytes(of: UInt32(dataSize).littleEndian) { Data($0) })
        
        // Audio samples
        if let floatData = buffer.floatChannelData {
            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let sample = floatData[channel][frame]
                    let intSample = Int16(max(-1, min(1, sample)) * Float(Int16.max))
                    data.append(withUnsafeBytes(of: intSample.littleEndian) { Data($0) })
                }
            }
        }
        
        return data
    }

    private func calculateRMS(buffer: AVAudioPCMBuffer) -> Float {
        guard
            let channelData = buffer.floatChannelData,
            buffer.frameLength > 0
        else {
            return 0
        }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var sum: Float = 0

        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var channelSum: Float = 0
            for index in 0..<frameCount {
                let sample = samples[index]
                channelSum += sample * sample
            }
            sum += channelSum / Float(frameCount)
        }

        return sqrt(sum / Float(channelCount))
    }

    /// Convert an input buffer (whatever the mic delivered — typically
    /// 48 kHz stereo float32) to 16-bit PCM mono at 24 kHz, the format
    /// OpenAI's Realtime API accepts. Returns raw PCM16 bytes, little-endian,
    /// no WAV header — exactly what goes over the WebSocket.
    ///
    /// The converter is lazily created and cached across buffers; changing
    /// input format (e.g. mic swap) invalidates it in `startRecording`.
    private func convertToPCM16At24kHz(buffer: AVAudioPCMBuffer) -> Data? {
        let outFormat = pcm16OutputFormat ?? AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true
        )
        guard let outFormat else { return nil }
        pcm16OutputFormat = outFormat

        let converter = pcm16Converter ?? AVAudioConverter(from: buffer.format, to: outFormat)
        guard let converter else { return nil }
        pcm16Converter = converter

        // Output capacity: scale by sample-rate ratio + slop for resampler
        // delay. 2x is plenty for any downmix we'd hit in practice.
        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            return nil
        }

        var inputConsumed = false
        var error: NSError?
        let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
            if inputConsumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            inputStatus.pointee = .haveData
            return buffer
        }

        guard status != .error, error == nil, outBuffer.frameLength > 0 else {
            return nil
        }

        let byteCount = Int(outBuffer.frameLength) * Int(outFormat.streamDescription.pointee.mBytesPerFrame)
        guard let int16Data = outBuffer.int16ChannelData?[0] else { return nil }
        return Data(bytes: int16Data, count: byteCount)
    }

    private func copyBuffer(_ source: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameCapacity) else {
            return nil
        }
        copy.frameLength = source.frameLength

        let frameCount = Int(source.frameLength)
        let channelCount = Int(source.format.channelCount)
        guard
            let src = source.floatChannelData,
            let dst = copy.floatChannelData
        else {
            return nil
        }

        for channel in 0..<channelCount {
            memcpy(dst[channel], src[channel], frameCount * MemoryLayout<Float>.size)
        }
        return copy
    }
}
