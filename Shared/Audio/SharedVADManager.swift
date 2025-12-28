import Foundation
import AVFoundation

// MARK: - VAD State
public enum VADState {
    case silent
    case speaking
    case endingSpeech
}

// MARK: - VAD Parameters
public struct VADParameters {
    public let voiceThreshold: Float
    public let silenceDuration: TimeInterval
    public let minSpeechDuration: TimeInterval
    public let smoothingWindow: Int
    public let chunkSize: Int
    
    public static let `default` = VADParameters(
        voiceThreshold: 0.15,
        silenceDuration: 0.4,
        minSpeechDuration: 0.2,
        smoothingWindow: 3,
        chunkSize: 512
    )
    
    public init(
        voiceThreshold: Float = 0.15,
        silenceDuration: TimeInterval = 0.4,
        minSpeechDuration: TimeInterval = 0.2,
        smoothingWindow: Int = 3,
        chunkSize: Int = 512
    ) {
        self.voiceThreshold = voiceThreshold
        self.silenceDuration = silenceDuration
        self.minSpeechDuration = minSpeechDuration
        self.smoothingWindow = smoothingWindow
        self.chunkSize = chunkSize
    }
}

// MARK: - Thread-Safe Audio Buffer
private actor AudioBufferActor {
    private var audioBuffer: [Float] = []
    private let maxBufferSize = 16000 * 10 // 10 seconds at 16kHz
    
    func append(_ samples: [Float]) {
        audioBuffer.append(contentsOf: samples)
        
        // Trim buffer if it exceeds max size
        if audioBuffer.count > maxBufferSize {
            let excess = audioBuffer.count - maxBufferSize
            audioBuffer.removeFirst(excess)
            #if DEBUG
            print("VAD AudioBuffer: Trimmed \(excess) samples to maintain max size")
            #endif
        }
    }
    
    func extractChunk(size: Int) -> [Float]? {
        guard audioBuffer.count >= size else { return nil }
        let chunk = Array(audioBuffer.prefix(size))
        audioBuffer.removeFirst(size)
        return chunk
    }
    
    func clear() {
        audioBuffer.removeAll(keepingCapacity: false)
    }
    
    func count() -> Int {
        return audioBuffer.count
    }
}

// MARK: - Shared VAD Manager
@MainActor
public protocol SharedVADDelegate: AnyObject {
    func vadDidStartSpeech(at timestamp: TimeInterval)
    func vadDidEndSpeech(at timestamp: TimeInterval, duration: TimeInterval)
    func vadDidUpdateVoiceProbability(_ probability: Float)
}

public class SharedVADManager {
    public weak var delegate: SharedVADDelegate?
    
    public private(set) var vadState: VADState = .silent
    private var speechStartTime: TimeInterval?
    private var silenceStartTime: TimeInterval?
    private var currentTime: TimeInterval = 0
    
    public let parameters: VADParameters
    private var probabilityHistory: [Float] = []
    private let probabilityLock = NSLock()
    private let sampleRate: Double = 16000
    private let chunkDuration: TimeInterval
    
    private let bufferActor = AudioBufferActor()
    
    public init(parameters: VADParameters = .default) {
        self.parameters = parameters
        self.chunkDuration = Double(parameters.chunkSize) / sampleRate
    }
    
    public func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at timestamp: TimeInterval) async -> Bool {
        currentTime = timestamp
        
        guard let channelData = buffer.floatChannelData else { return false }
        
        let frameLength = Int(buffer.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))
        
        // Process audio through buffer actor
        await bufferActor.append(samples)
        
        var currentVADState = false
        
        // Process chunks
        while let chunk = await bufferActor.extractChunk(size: parameters.chunkSize) {
            let voiceProbability = analyzeChunk(chunk)
            await updateVADState(voiceProbability: voiceProbability)
            
            // Notify delegate
            await delegate?.vadDidUpdateVoiceProbability(voiceProbability)
        }
        
        currentVADState = vadState == .speaking
        
        return currentVADState
    }
    
    private func analyzeChunk(_ chunk: [Float]) -> Float {
        // Simple energy calculation
        let energy = chunk.reduce(0) { $0 + abs($1) } / Float(chunk.count)
        
        // RMS calculation
        let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
        
        // Zero crossing rate
        var zeroCrossingRate: Float = 0
        for i in 1..<chunk.count {
            if (chunk[i] >= 0 && chunk[i-1] < 0) || (chunk[i] < 0 && chunk[i-1] >= 0) {
                zeroCrossingRate += 1
            }
        }
        zeroCrossingRate /= Float(chunk.count - 1)
        
        #if DEBUG
        if Int.random(in: 0..<20) == 0 { // Log occasionally
            print("VAD analysis: energy=\(energy), rms=\(rms), zcr=\(zeroCrossingRate)")
        }
        #endif
        
        // Thresholds
        let energyThreshold: Float = 0.0008
        let rmsThreshold: Float = 0.0015
        let zcrLowThreshold: Float = 0.02
        let zcrHighThreshold: Float = 0.8
        
        var probability: Float = 0
        
        // Calculate probability
        if energy > energyThreshold {
            let energyRatio = min(energy / (energyThreshold * 10), 1.0)
            probability += 0.4 * energyRatio
        }
        
        if rms > rmsThreshold {
            let rmsRatio = min(rms / (rmsThreshold * 10), 1.0)
            probability += 0.5 * rmsRatio
        }
        
        if zeroCrossingRate > zcrLowThreshold && zeroCrossingRate < zcrHighThreshold {
            probability += 0.3
        }
        
        // Bonus for combined indicators
        if energy > energyThreshold && rms > rmsThreshold {
            probability += 0.2
        }
        
        probability = min(1.0, max(0.0, probability))
        
        // Smoothing (lock-protected — analyzeChunk is called from audio thread)
        probabilityLock.lock()
        probabilityHistory.append(probability)
        if probabilityHistory.count > parameters.smoothingWindow {
            probabilityHistory.removeFirst()
        }
        let smoothedProbability = probabilityHistory.reduce(0, +) / Float(probabilityHistory.count)
        probabilityLock.unlock()

        return smoothedProbability
    }
    
    @MainActor
    private func updateVADState(voiceProbability: Float) async {
        switch vadState {
        case .silent:
            if voiceProbability >= parameters.voiceThreshold {
                vadState = .speaking
                speechStartTime = currentTime
                #if DEBUG
                print("VAD: Speech started at \(currentTime)")
                #endif
                delegate?.vadDidStartSpeech(at: currentTime)
            }
            
        case .speaking:
            if voiceProbability < parameters.voiceThreshold {
                vadState = .endingSpeech
                silenceStartTime = currentTime
            }
            
        case .endingSpeech:
            if voiceProbability >= parameters.voiceThreshold {
                // Resume speaking
                vadState = .speaking
                silenceStartTime = nil
            } else if let silenceStart = silenceStartTime {
                let silenceDurationCurrent = currentTime - silenceStart
                if silenceDurationCurrent >= parameters.silenceDuration {
                    // Confirm end of speech
                    vadState = .silent
                    if let speechStart = speechStartTime {
                        let speechDuration = silenceStart - speechStart
                        if speechDuration >= parameters.minSpeechDuration {
                            #if DEBUG
                            print("VAD: Speech ended at \(currentTime), duration: \(speechDuration)s")
                            #endif
                            delegate?.vadDidEndSpeech(at: silenceStart, duration: speechDuration)
                        }
                    }
                    speechStartTime = nil
                    silenceStartTime = nil
                }
            }
        }
    }
    
    public func reset() async {
        vadState = .silent
        speechStartTime = nil
        silenceStartTime = nil
        probabilityLock.lock()
        probabilityHistory.removeAll()
        probabilityLock.unlock()
        await bufferActor.clear()
    }
    
    @MainActor
    public func forceEndSpeech() {
        if vadState == .speaking || vadState == .endingSpeech {
            if let speechStart = speechStartTime {
                let duration = currentTime - speechStart
                vadState = .silent
                #if DEBUG
                print("VAD: Force ending speech, duration: \(duration)s")
                #endif
                delegate?.vadDidEndSpeech(at: currentTime, duration: duration)
            }
            speechStartTime = nil
            silenceStartTime = nil
        }
    }
}