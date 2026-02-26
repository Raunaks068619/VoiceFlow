import Foundation
import AVFoundation

class AudioRecorder: NSObject {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var gatedAudioBuffer: [AVAudioPCMBuffer] = []
    private var rawAudioBuffer: [AVAudioPCMBuffer] = []
    private var isRecording = false
    private var recordingCallback: ((Data?) -> Void)?
    private var noiseGateThreshold: Float = 0.015
    private var voicedBufferCount = 0
    private var hangoverBuffersRemaining = 0
    private let hangoverBufferCount = 6
    
    override init() {
        super.init()
        setupAudioEngine()
    }
    
    private func setupAudioEngine() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine?.inputNode
    }
    
    func startRecording() {
        guard let audioEngine = audioEngine, !isRecording else { return }
        
        gatedAudioBuffer.removeAll()
        rawAudioBuffer.removeAll()
        voicedBufferCount = 0
        hangoverBuffersRemaining = 0
        noiseGateThreshold = max(0.001, min(0.08, UserDefaults.standard.float(forKey: "noise_gate_threshold")))
        
        let format = inputNode?.outputFormat(forBus: 0)
        
        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard let copiedBuffer = self.copyBuffer(buffer) else { return }
            self.rawAudioBuffer.append(copiedBuffer)
            let rms = self.calculateRMS(buffer: copiedBuffer)
            if rms >= self.noiseGateThreshold {
                self.gatedAudioBuffer.append(copiedBuffer)
                self.voicedBufferCount += 1
                self.hangoverBuffersRemaining = self.hangoverBufferCount
            } else if self.hangoverBuffersRemaining > 0 {
                self.gatedAudioBuffer.append(copiedBuffer)
                self.hangoverBuffersRemaining -= 1
            }
        }
        
        do {
            try audioEngine.start()
            isRecording = true
            print("Recording started")
        } catch {
            print("Failed to start audio engine: \(error)")
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
        if voicedBufferCount > 0 {
            selectedBuffers = gatedAudioBuffer
        } else {
            selectedBuffers = rawAudioBuffer
            print("Recording stopped (noise gate too strict, using raw audio fallback)")
        }

        // Convert buffers to WAV data
        let audioData = convertBuffersToWAV(from: selectedBuffers)
        completion(audioData)
        
        print("Recording stopped")
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
