import Foundation
import AVFoundation

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var rawAudioBuffer: [AVAudioPCMBuffer] = []
    private var isRecording = false
    private var recordingCallback: ((Data?) -> Void)?
    private var noiseGateThreshold: Float = 0.015
    private var firstVoicedIndex: Int?
    private var lastVoicedIndex: Int?

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
    // ~21ms per 1024-frame buffer at 48kHz. Keep ~500ms tail so trailing
    // consonants and soft endings ('huh', 'hai') don't get clipped.
    private let trailingPaddingBufferCount = 24
    // Keep ~200ms of lead-in before the first detected voice activity. This
    // captures the onset ramp of the first word — the phoneme attack is
    // almost always below steady-state RMS for 20-80ms, and clipping it
    // makes Whisper mis-hear or drop the word entirely.
    private let leadingPaddingBufferCount = 10

    override init() {
        super.init()
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
    }

    func startRecording() -> Bool {
        guard let audioEngine = audioEngine, !isRecording else { return false }

        rawAudioBuffer.removeAll()
        firstVoicedIndex = nil
        lastVoicedIndex = nil
        noiseGateThreshold = max(0.001, min(0.08, UserDefaults.standard.float(forKey: "noise_gate_threshold")))
        // Reset converter — input format can change between sessions if
        // user switches mic (different sample rate / channel count).
        pcm16Converter = nil
        pcm16OutputFormat = nil

        let format = inputNode?.outputFormat(forBus: 0)

        // Remove any leftover tap from a previous failed start before installing a new one.
        inputNode?.removeTap(onBus: 0)

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
        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let copiedBuffer = self.copyBuffer(buffer) else { return }
            let index = self.rawAudioBuffer.count
            self.rawAudioBuffer.append(copiedBuffer)
            let rms = self.calculateRMS(buffer: copiedBuffer)
            if rms >= self.noiseGateThreshold {
                if self.firstVoicedIndex == nil { self.firstVoicedIndex = index }
                self.lastVoicedIndex = index
            }
            // Additive: if streaming is enabled, also emit PCM16 @ 24kHz.
            // Failure here is silent — streaming is best-effort on top of
            // the batch pipeline, not a replacement.
            if self.onPCM16Samples != nil {
                if let pcm16 = self.convertToPCM16At24kHz(buffer: copiedBuffer) {
                    self.onPCM16Samples?(pcm16)
                }
            }
        }

        do {
            try audioEngine.start()
            isRecording = true
            print("Recording started")
            return true
        } catch {
            inputNode?.removeTap(onBus: 0)
            print("Failed to start audio engine: \(error)")
            return false
        }
    }

    func stopRecording(completion: @escaping (Data?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }

        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        isRecording = false

        let selectedBuffers: [AVAudioPCMBuffer]
        if let first = firstVoicedIndex, let last = lastVoicedIndex {
            // Trim leading/trailing silence with padding on both sides. Interior
            // silence is preserved — a 3-second pause mid-sentence stays a
            // 3-second pause, so Whisper can segment properly.
            let start = max(0, first - leadingPaddingBufferCount)
            let end = min(rawAudioBuffer.count - 1, last + trailingPaddingBufferCount)
            selectedBuffers = Array(rawAudioBuffer[start...end])
            print("Recording stopped (voiced range \(first)...\(last) of \(rawAudioBuffer.count), trimmed to \(start)...\(end))")
        } else {
            // No voice activity detected at all — user probably tapped Fn by
            // mistake. Send the raw audio anyway; Whisper will return empty
            // and the empty-guard in WhisperService will drop it quietly.
            selectedBuffers = rawAudioBuffer
            print("Recording stopped (no voice detected, sending raw audio)")
        }

        let audioData = convertBuffersToWAV(from: selectedBuffers)
        completion(audioData)
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
