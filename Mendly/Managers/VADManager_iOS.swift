import Foundation
import AVFoundation

// MARK: - iOS VAD Manager Delegate
protocol VADManagerDelegate_iOS: AnyObject {
    func vadManager(_ manager: VADManager_iOS, didStartSpeechAt timestamp: TimeInterval)
    func vadManager(_ manager: VADManager_iOS, didEndSpeechAt timestamp: TimeInterval, duration: TimeInterval)
    func vadManager(_ manager: VADManager_iOS, didUpdateVoiceProbability probability: Float)
}

// MARK: - iOS VAD Manager Wrapper
@MainActor
class VADManager_iOS {
    weak var delegate: VADManagerDelegate_iOS?
    private let sharedVAD = SharedVADManager()
    
    // Cache the current speaking state for synchronous access
    private(set) var isSpeaking: Bool = false
    
    init() {
        // Set up delegation
        sharedVAD.delegate = self
    }
    
    func processAudioBuffer(_ buffer: AVAudioPCMBuffer, at timestamp: TimeInterval) -> Bool {
        // Process async
        Task {
            await sharedVAD.processAudioBuffer(buffer, at: timestamp)
        }
        
        // Return current cached state
        return isSpeaking
    }
    
    func reset() {
        Task {
            await sharedVAD.reset()
            isSpeaking = false
        }
    }
    
    func forceEndSpeech() {
        sharedVAD.forceEndSpeech()
        isSpeaking = false
    }
}

// MARK: - Shared VAD Delegate
extension VADManager_iOS: SharedVADDelegate {
    func vadDidStartSpeech(at timestamp: TimeInterval) {
        isSpeaking = true
        delegate?.vadManager(self, didStartSpeechAt: timestamp)
    }
    
    func vadDidEndSpeech(at timestamp: TimeInterval, duration: TimeInterval) {
        isSpeaking = false
        delegate?.vadManager(self, didEndSpeechAt: timestamp, duration: duration)
    }
    
    func vadDidUpdateVoiceProbability(_ probability: Float) {
        delegate?.vadManager(self, didUpdateVoiceProbability: probability)
    }
}