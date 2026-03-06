import Foundation
import FluidAudio

enum SpeakerTextAligner {

    /// Align ASR token timings with diarization speaker segments to produce speaker-attributed utterances.
    ///
    /// Token times from ASR are chunk-relative (start at 0). `chunkTimeOffset` shifts them to session-absolute time.
    /// Each token is assigned to the speaker segment that overlaps its midpoint. Consecutive tokens from the same
    /// speaker are merged into a single `SpeakerUtterance`.
    static func align(
        tokenTimings: [TokenTiming]?,
        text: String,
        speakerSegments: [TimedSpeakerSegment],
        chunkTimeOffset: TimeInterval
    ) -> [SpeakerUtterance] {
        guard !speakerSegments.isEmpty else {
            // No speaker segments — return all text as unknown speaker
            return text.isEmpty ? [] : [
                SpeakerUtterance(
                    speakerId: "unknown",
                    speakerLabel: "Speaker ?",
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: chunkTimeOffset,
                    endTime: chunkTimeOffset
                )
            ]
        }

        // Fallback: no token timings — assign entire text to dominant speaker
        guard let timings = tokenTimings, !timings.isEmpty else {
            let dominant = dominantSpeaker(in: speakerSegments)
            return text.isEmpty ? [] : [
                SpeakerUtterance(
                    speakerId: dominant.speakerId,
                    speakerLabel: labelFor(dominant.speakerId),
                    text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                    startTime: chunkTimeOffset + Double(dominant.startTimeSeconds),
                    endTime: chunkTimeOffset + Double(dominant.endTimeSeconds)
                )
            ]
        }

        // Step 1: Assign each token to a speaker based on its midpoint.
        // When multiple segments overlap, pick the shortest (most focused), then highest quality.
        typealias AttributedToken = (speaker: String, token: String, start: TimeInterval, end: TimeInterval)
        var attributed: [AttributedToken] = []

        for timing in timings {
            let absoluteStart = chunkTimeOffset + timing.startTime
            let absoluteEnd = chunkTimeOffset + timing.endTime
            // Midpoint must be session-absolute to match against diarization segments
            let midpoint = Float((absoluteStart + absoluteEnd) / 2.0)

            let overlapping = speakerSegments.filter { segment in
                midpoint >= segment.startTimeSeconds && midpoint <= segment.endTimeSeconds
            }

            let speaker: TimedSpeakerSegment?
            if overlapping.count > 1 {
                speaker = overlapping.min(by: { a, b in
                    let durA = a.endTimeSeconds - a.startTimeSeconds
                    let durB = b.endTimeSeconds - b.startTimeSeconds
                    if abs(durA - durB) > 0.5 { return durA < durB }
                    return a.qualityScore > b.qualityScore
                })
            } else {
                speaker = overlapping.first ?? nearestSpeaker(to: midpoint, in: speakerSegments)
            }

            let speakerId = speaker?.speakerId ?? dominantSpeaker(in: speakerSegments).speakerId
            attributed.append((speaker: speakerId, token: timing.token, start: absoluteStart, end: absoluteEnd))
        }

        // Step 2: Group tokens into sentences, then assign each sentence to the
        // majority speaker. This prevents individual words getting split to the
        // wrong speaker mid-sentence due to overlapping diarization segments.
        let sentences = groupTokensIntoSentences(attributed)
        var sentenceAttributed: [AttributedToken] = []

        for sentence in sentences {
            // Majority vote: which speaker owns most tokens in this sentence?
            var speakerCounts: [String: Int] = [:]
            for tok in sentence {
                speakerCounts[tok.speaker, default: 0] += 1
            }

            let isShortGroup = sentence.count <= 8
            let hasMultipleSpeakers = speakerCounts.count > 1
            let lastToken = sentence.last?.token.trimmingCharacters(in: .whitespaces) ?? ""
            let isQuestion = lastToken.hasSuffix("?")
            let isExclamation = lastToken.hasSuffix("!")

            // Check if the minority speaker has enough tokens to be meaningful.
            // A 1-2 token minority in a short group is likely diarizer noise at a
            // segment boundary, not a real interjection. Only bypass majority voting
            // when the minority speaker has ≥3 tokens (a real short utterance).
            let minorityCount = speakerCounts.values.min() ?? 0
            let isMeaningfulSplit = minorityCount >= 3

            if isShortGroup && hasMultipleSpeakers && (isQuestion || isExclamation) && isMeaningfulSplit {
                // Short questions/exclamations are often interjections from the other speaker.
                // Don't majority-vote — keep the original per-token speaker assignments
                // so they naturally split into separate utterances during token merging.
                for tok in sentence {
                    sentenceAttributed.append(tok)
                }
            } else {
                let winningSpeaker = speakerCounts.max(by: { $0.value < $1.value })?.key ?? sentence[0].speaker

                // Re-assign all tokens in this sentence to the winning speaker
                for tok in sentence {
                    sentenceAttributed.append((speaker: winningSpeaker, token: tok.token, start: tok.start, end: tok.end))
                }
            }
        }

        // Step 3: Merge consecutive tokens from the same speaker
        return mergeTokens(sentenceAttributed)
    }

    // MARK: - Private

    /// Group tokens into clauses by splitting on:
    /// 1. Sentence-ending punctuation (.?!)
    /// 2. Significant time gaps between tokens (>300ms) — likely a speaker change
    /// 3. Comma boundaries when the diarization speaker also changes — catches mid-sentence turns
    ///
    /// Smaller groups = more precise speaker majority voting, catching speaker changes
    /// that happen within what ASR considers a single sentence.
    private static func groupTokensIntoSentences(
        _ tokens: [(speaker: String, token: String, start: TimeInterval, end: TimeInterval)]
    ) -> [[(speaker: String, token: String, start: TimeInterval, end: TimeInterval)]] {
        guard !tokens.isEmpty else { return [] }

        let timeGapThreshold: TimeInterval = 0.3 // 300ms gap = likely speaker change

        var groups: [[(speaker: String, token: String, start: TimeInterval, end: TimeInterval)]] = []
        var current: [(speaker: String, token: String, start: TimeInterval, end: TimeInterval)] = []

        for (i, token) in tokens.enumerated() {
            // Check for time gap BEFORE adding this token
            if !current.isEmpty, let lastEnd = current.last?.end {
                let gap = token.start - lastEnd
                if gap >= timeGapThreshold {
                    // Significant pause — split here (likely speaker change)
                    groups.append(current)
                    current = []
                }
            }

            current.append(token)

            let trimmed = token.token.trimmingCharacters(in: .whitespaces)

            // Split on sentence-ending punctuation
            if trimmed.hasSuffix(".") || trimmed.hasSuffix("?") || trimmed.hasSuffix("!") {
                if !current.isEmpty {
                    groups.append(current)
                    current = []
                }
            }
        }

        // Don't lose trailing tokens
        if !current.isEmpty {
            groups.append(current)
        }

        return groups
    }

    private static func dominantSpeaker(in segments: [TimedSpeakerSegment]) -> TimedSpeakerSegment {
        // Speaker with longest total duration
        var durations: [String: Float] = [:]
        for seg in segments {
            durations[seg.speakerId, default: 0] += seg.durationSeconds
        }
        let dominantId = durations.max(by: { $0.value < $1.value })?.key ?? segments.first!.speakerId
        return segments.first { $0.speakerId == dominantId } ?? segments.first!
    }

    /// Find the nearest speaker segment to a given time, weighted by duration and quality.
    /// Longer, higher-quality segments win over short noisy ones that happen to be slightly closer.
    private static func nearestSpeaker(to time: Float, in segments: [TimedSpeakerSegment]) -> TimedSpeakerSegment? {
        segments.min(by: { a, b in
            let distA = min(abs(a.startTimeSeconds - time), abs(a.endTimeSeconds - time))
            let distB = min(abs(b.startTimeSeconds - time), abs(b.endTimeSeconds - time))
            // Weight by inverse of (duration × quality) — high-quality long segments get lower adjusted distance
            let weightA = max(a.durationSeconds * a.qualityScore, 0.01)
            let weightB = max(b.durationSeconds * b.qualityScore, 0.01)
            return distA / weightA < distB / weightB
        })
    }

    private static func mergeTokens(_ tokens: [(speaker: String, token: String, start: TimeInterval, end: TimeInterval)]) -> [SpeakerUtterance] {
        guard !tokens.isEmpty else { return [] }

        var utterances: [SpeakerUtterance] = []
        var currentSpeaker = tokens[0].speaker
        var currentText = tokens[0].token
        var currentStart = tokens[0].start
        var currentEnd = tokens[0].end

        for i in 1..<tokens.count {
            let t = tokens[i]
            if t.speaker == currentSpeaker {
                currentText += t.token
                currentEnd = t.end
            } else {
                let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    utterances.append(SpeakerUtterance(
                        speakerId: currentSpeaker,
                        speakerLabel: labelFor(currentSpeaker),
                        text: trimmed,
                        startTime: currentStart,
                        endTime: currentEnd
                    ))
                }
                currentSpeaker = t.speaker
                currentText = t.token
                currentStart = t.start
                currentEnd = t.end
            }
        }

        // Final utterance
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            utterances.append(SpeakerUtterance(
                speakerId: currentSpeaker,
                speakerLabel: labelFor(currentSpeaker),
                text: trimmed,
                startTime: currentStart,
                endTime: currentEnd
            ))
        }

        return utterances
    }

    static func labelFor(_ speakerId: String) -> String {
        if let lastPart = speakerId.split(separator: "_").last, let num = Int(lastPart) {
            return num == 0 ? "🔵" : "🟠"
        }
        return speakerId
    }
}
