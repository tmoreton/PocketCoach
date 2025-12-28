import Foundation

public struct TranscriptionTextProcessor {
    
    // MARK: - Text Cleaning
    public static func cleanTranscriptionText(_ text: String) -> String {
        var cleaned = text
        
        // Remove standalone dashes and double dashes
        cleaned = cleaned.replacingOccurrences(of: " - ", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "--", with: " ")
        cleaned = cleaned.replacingOccurrences(of: "- ", with: " ")
        cleaned = cleaned.replacingOccurrences(of: " -", with: " ")
        
        // Fix double punctuation
        cleaned = cleaned.replacingOccurrences(of: "..", with: ".")
        cleaned = cleaned.replacingOccurrences(of: ",,", with: ",")
        cleaned = cleaned.replacingOccurrences(of: "??", with: "?")
        cleaned = cleaned.replacingOccurrences(of: "!!", with: "!")
        
        // Fix spacing around punctuation
        cleaned = cleaned.replacingOccurrences(of: " .", with: ".")
        cleaned = cleaned.replacingOccurrences(of: " ,", with: ",")
        cleaned = cleaned.replacingOccurrences(of: " ?", with: "?")
        cleaned = cleaned.replacingOccurrences(of: " !", with: "!")
        
        // Remove multiple spaces
        while cleaned.contains("  ") {
            cleaned = cleaned.replacingOccurrences(of: "  ", with: " ")
        }
        
        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleaned
    }
    
    // MARK: - Sentence Processing
    private static let incompleteSuffixes = [
        "the", "a", "an", "to", "of", "in", "on", "at", "for", 
        "and", "but", "or", "so", "with", "is", "are", "was", 
        "were", "have", "has", "had", "will", "would", "could", 
        "should", "can", "may", "might"
    ]
    
    public static func shouldMergeWithPrevious(_ previous: String, _ new: String, lastTranscriptionTime: Date) -> Bool {
        // Check if previous text ends with incomplete sentence indicators
        let previousWords = previous.lowercased().split(separator: " ")
        if let lastWord = previousWords.last {
            if incompleteSuffixes.contains(String(lastWord)) {
                return true
            }
        }
        
        // Check if new text starts with lowercase (continuation)
        if let firstChar = new.first, 
           firstChar.isLowercase && 
           !previous.hasSuffix(".") && 
           !previous.hasSuffix("!") && 
           !previous.hasSuffix("?") {
            return true
        }
        
        // Check if previous doesn't end with sentence terminator
        if !previous.hasSuffix(".") && !previous.hasSuffix("!") && !previous.hasSuffix("?") {
            // If time between transcriptions is short, likely same sentence
            let timeSinceLastTranscription = Date().timeIntervalSince(lastTranscriptionTime)
            if timeSinceLastTranscription < 4.0 { // Within 4 seconds
                return true
            }
        }
        
        return false
    }
    
    public static func isCompleteSentence(_ text: String, lastTranscriptionTime: Date) -> Bool {
        // Check for sentence-ending punctuation
        if text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?") {
            return true
        }
        
        // Check if significant time has passed (user has paused)
        let timeSinceLastTranscription = Date().timeIntervalSince(lastTranscriptionTime)
        if timeSinceLastTranscription > 5.0 { // More than 5 seconds
            return true
        }
        
        return false
    }
    
    // MARK: - Text Validation
    public static func isValidTranscriptionText(_ text: String) -> Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleaned.isEmpty && cleaned != "." && cleaned != ","
    }
    
    // MARK: - Text Truncation
    public static func truncateTranscription(_ text: String, maxLength: Int, keepPercentage: Double = 0.8) -> String {
        guard text.count > maxLength else { return text }
        
        let keepLength = Int(Double(maxLength) * keepPercentage)
        if let index = text.index(text.endIndex, offsetBy: -keepLength, limitedBy: text.startIndex) {
            return "..." + String(text[index...])
        }
        
        return text
    }
    
    // MARK: - Text Capitalization
    public static func ensureFirstLetterCapitalized(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        
        if let firstChar = text.first {
            return String(firstChar).uppercased() + text.dropFirst()
        }
        
        return text
    }
}

// MARK: - Transcription Buffer Manager
public class TranscriptionBuffer {
    private var pendingTranscription = ""
    private var currentTranscription = ""
    private var lastTranscriptionTime = Date()
    private let maxTranscriptionLength: Int
    
    public init(maxTranscriptionLength: Int = 50000) {
        self.maxTranscriptionLength = maxTranscriptionLength
    }
    
    public var current: String {
        return currentTranscription
    }
    
    public var pending: String {
        return pendingTranscription
    }
    
    public func appendToPending(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedText = TranscriptionTextProcessor.cleanTranscriptionText(trimmedText)
        
        guard TranscriptionTextProcessor.isValidTranscriptionText(cleanedText) else {
            return
        }
        
        if pendingTranscription.isEmpty {
            pendingTranscription = cleanedText
        } else {
            // Check if we should merge with previous or start new
            let shouldMerge = TranscriptionTextProcessor.shouldMergeWithPrevious(
                pendingTranscription, 
                cleanedText, 
                lastTranscriptionTime: lastTranscriptionTime
            )
            if shouldMerge {
                pendingTranscription += " " + cleanedText
            } else {
                // Commit previous pending and start new
                commitPending()
                pendingTranscription = cleanedText
            }
        }
        
        // Check if current pending is complete
        if TranscriptionTextProcessor.isCompleteSentence(pendingTranscription, lastTranscriptionTime: lastTranscriptionTime) {
            commitPending()
        }
        
        lastTranscriptionTime = Date()
    }
    
    public func commitPending() {
        guard !pendingTranscription.isEmpty else { return }
        
        // Ensure first letter is capitalized
        let finalText = TranscriptionTextProcessor.ensureFirstLetterCapitalized(pendingTranscription)
        
        // Add to current transcription
        if currentTranscription.isEmpty {
            currentTranscription = finalText
        } else {
            currentTranscription += " " + finalText
        }
        
        // Trim if transcription gets too long
        currentTranscription = TranscriptionTextProcessor.truncateTranscription(
            currentTranscription, 
            maxLength: maxTranscriptionLength
        )
        
        pendingTranscription = ""
    }
    
    public func checkAndCommitPending() {
        if !pendingTranscription.isEmpty {
            let timeSinceLastTranscription = Date().timeIntervalSince(lastTranscriptionTime)
            if timeSinceLastTranscription > 5.0 { // More than 5 seconds of silence
                commitPending()
            }
        }
    }
    
    public func clear() {
        pendingTranscription = ""
        currentTranscription = ""
        lastTranscriptionTime = Date()
    }
    
    public func reset() {
        clear()
    }
}