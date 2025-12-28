import Foundation
import AVFoundation

public enum AudioProcessing {
    
    // MARK: - Audio Level Calculation
    public static func calculateNormalizedAudioLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData else { return 0 }
        
        let channelDataArray = UnsafeBufferPointer(start: channelData[0], count: Int(buffer.frameLength))
        var sum: Float = 0
        for sample in channelDataArray {
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let level = 20 * log10(max(rms, 0.0001))
        // Normalize level to 0...1 range roughly (-40dB to 0dB)
        let normalizedLevel = max(0, min(1, (level + 40) / 40))
        
        return normalizedLevel
    }
    
    // MARK: - Audio Format Conversion
    public static func convertToMono16kHz(buffer: AVAudioPCMBuffer, from format: AVAudioFormat, targetSampleRate: Double = 16000) -> [Float]? {
        // Target format: mono, 16kHz, float32
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        
        // If already in correct format, just extract samples
        if format.sampleRate == targetSampleRate && format.channelCount == 1 {
            guard let channelData = buffer.floatChannelData?[0] else { 
                return nil 
            }
            let samples = Array(UnsafeBufferPointer(start: channelData, count: Int(buffer.frameLength)))
            return samples
        }
        
        // Create converter
        guard let converter = AVAudioConverter(from: format, to: targetFormat) else {
            return nil
        }
        
        // Calculate output frame count based on sample rate ratio
        let ratio = targetSampleRate / format.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputFrameCount
        ) else { return nil }
        
        var error: NSError?
        var inputConsumed = false
        
        let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        
        if status == .error, let error = error {
            #if DEBUG
            print("Audio conversion error: \(error)")
            #endif
            return nil
        }
        
        guard let channelData = outputBuffer.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: channelData, count: Int(outputBuffer.frameLength)))
    }
    
    // MARK: - Audio Chunk Processing
    public struct ChunkParameters {
        public let minSeconds: Double
        public let optimalSeconds: Double
        public let maxSeconds: Double
        
        public static let `default` = ChunkParameters(
            minSeconds: 2.0,
            optimalSeconds: 4.0,
            maxSeconds: 30.0
        )
        
        public init(minSeconds: Double = 2.0, optimalSeconds: Double = 4.0, maxSeconds: Double = 30.0) {
            self.minSeconds = minSeconds
            self.optimalSeconds = optimalSeconds
            self.maxSeconds = maxSeconds
        }
    }
    
    public static func extractOptimalChunk(
        from buffer: inout [Float],
        sampleRate: Double,
        parameters: ChunkParameters = .default
    ) -> [Float]? {
        let minSamples = Int(sampleRate * parameters.minSeconds)
        let optimalSamples = Int(sampleRate * parameters.optimalSeconds)
        let maxSamples = Int(sampleRate * parameters.maxSeconds)
        
        guard buffer.count >= minSamples else {
            return nil
        }
        
        let samplesToProcess: [Float]
        if buffer.count >= optimalSamples {
            // Take optimal chunk size
            samplesToProcess = Array(buffer.prefix(min(optimalSamples, maxSamples)))
            // Put the remaining back
            buffer = Array(buffer.dropFirst(samplesToProcess.count))
        } else {
            // Take all available (at least minSeconds worth)
            samplesToProcess = buffer
            buffer.removeAll()
        }
        
        return samplesToProcess
    }
    
}