import Foundation

/// Analyzes a diarized conversation using an LLM to provide tone-adaptive relationship
/// feedback and actionable improvement steps for each speaker.
class ConversationAnalysisService {
    static let shared = ConversationAnalysisService()

    private let openAI = OpenAIService.shared

    // MARK: - V2 Pipeline

    private let bouncerPrompt = """
    You are the connection validator for a relationship app. Your ONLY job is to evaluate the input transcript using strict YES/NO criteria to determine if it is a valid, analyzable conversation between two partners.

    EVALUATION CRITERIA (Evaluate as YES/true or NO/false)
    1. Two_Voices_Present: Are there at least two distinct speakers interacting?
    2. Intelligible_Dialogue: Is there actual conversational substance (e.g., full sentences, not just silence, ambient noise, or isolated grunts)?
    3. Interactive_Conversation: Are the speakers addressing each other directly (e.g., not a single person practicing a speech, reading a list, or a TV playing in the background)?

    DECISION LOGIC
    - If ALL criteria are YES (true) -> "is_valid_couple_conversation": true
    - If ANY criteria is NO (false) -> "is_valid_couple_conversation": false, and assign the corresponding "fail_reason".

    Return ONLY valid JSON. Do not include markdown formatting.

    {
      "criteria_checks": {
        "two_voices_present": boolean,
        "intelligible_dialogue": boolean,
        "interactive_conversation": boolean
      },
      "is_valid_couple_conversation": boolean,
      "fail_reason": null | "one_speaker" | "audio_quality" | "not_a_conversation",
      "user_message": "String or null"
    }

    Error Message Library:
    - one_speaker: "We mainly heard one voice. For fair mediation, we need to hear both partners. Please try again."
    - audio_quality: "We couldn't hear you clearly. Please check your microphone or move to a quieter spot."
    - not_a_conversation: "We didn't detect a clear back-and-forth conversation. Please ensure you are recording a dialogue."
    """

    private let vibePrompt = """
    You are a witty social media observer. Your job is to listen to a couple's conversation and generate a "Viral Relationship Wrap-Up" similar to Spotify Wrapped.

    TONE GUIDELINES
    - Style: "Roast" humor, Gen Z slang (but not cringe), punchy.
    - Perspective: You are their brutally honest friend, not their counselor.
    - Constraint: Do NOT be mean-spirited. Be "fun shady," not "cruel."

    TASKS
    1. Archetyping: Assign a pop-culture trope to the couple (e.g., "The Yapper vs. The Listener").
    2. Energy Read: Describe each person's vibe using a metaphor (e.g., "Golden Retriever Energy," "Black Cat Energy," "Stressed Accountant").
    3. Scoring: Give a "Vibe Score" (0-100) based on how well they communicated.

    Return ONLY valid JSON. Do not include markdown formatting.

    {
      "viral_card": {
        "headline_archetype": "String (Short & Funny)",
        "vibe_score": Integer (0-100),
        "energy_profile": {
          "speaker_A_vibe": "String (Metaphor for 🔵)",
          "speaker_B_vibe": "String (Metaphor for 🟠)"
        }
      }
    }
    """

    private let coachPrompt = """
    You are "The Digital Referee," a high-performance Relationship Communication Coach. You use the Gottman Method and Non-Violent Communication (NVC) frameworks.

    OBJECTIVE
    Analyze the transcript to help the couple de-escalate conflict. You do NOT diagnose mental health issues; you "call fouls" on communication errors and suggest "better plays."

    TASKS
    1. Foul Detection: Scan for the "Four Horsemen": Criticism, Contempt, Defensiveness, Stonewalling.
    2. Instant Replay: You MUST extract the exact quote where the foul occurred.
    3. The Fix: Rewrite that specific quote using the NVC formula: "I feel [emotion] because I need [need]. Can we [request]?"
    4. Homework: Assign one specific, actionable drill.

    CRITICAL: If the conversation is calm and constructive with no fouls, set all fouls to false and provide an empty coaching_opportunities array. Do NOT invent fouls that aren't present.

    Return ONLY valid JSON. Do not include markdown formatting.

    {
      "coaching_analysis": {
        "game_summary": "Neutral, objective recap of the conflict (2-3 sentences).",
        "fouls_detected": {
          "criticism": boolean,
          "contempt": boolean,
          "defensiveness": boolean,
          "stonewalling": boolean
        },
        "coaching_opportunities": [
          {
            "speaker": "🔵" | "🟠",
            "call_made": "Criticism" | "Defensiveness" | "Contempt" | "Stonewalling" | "Aggression",
            "instant_replay_quote": "Exact string from text",
            "why_whistle_blew": "Explanation of why this triggers the partner.",
            "better_play": "Specific NVC rephrase suggestion."
          }
        ],
        "post_game_drill": {
          "drill_name": "String",
          "instructions": "String"
        }
      }
    }
    """

    private let analystPrompt = """
    You are the "Lead Data Scientist" for a relationship psychology lab. Your task is to code a raw conversation transcript into a structured dataset. You do NOT have access to audio; you must rely exclusively on linguistic markers, syntax, and semantic patterns.

    ANALYTICAL TASKS

    1. STRUCTURAL DYNAMICS (The "Power Balance")
    - Word Count Ratio: Who is holding the floor?
    - Turn-Taking Speed: Are exchanges short (rapid-fire arguing) or long (monologues)?
    - Interruption Proxies: Detect mid-sentence cut-offs (e.g., "--", "wait", "let me finish").

    2. LINGUISTIC PATTERNS (The "Vibe Check")
    - Pronoun Usage: Compare "You" statements (often accusatory) vs. "I" statements (vulnerability).
    - Absolutes: Count occurrences of "always," "never," "every time" (markers of rigidity).
    - Negation Density: Frequency of "no," "not," "don't," "wrong."

    3. GOTTMAN CODEBOOK (The "Four Horsemen")
    - Criticism: "You are [adjective]" or "You always [verb]."
    - Contempt: Insults, sarcasm markers ("Great job," "Brilliant"), mockery.
    - Defensiveness: "I didn't," "It's not my fault," "You do it too."
    - Stonewalling: Persistent one-word answers ("Fine," "Okay," "Whatever") in response to long queries.

    4. CONFLICT RESOLUTION MARKERS
    - Repair Attempts: Did a speaker try to de-escalate? (e.g., "I'm sorry," "Let's take a breath," "I see your point").
    - Validation: Did a speaker acknowledge the other? (e.g., "I understand," "That makes sense").
    - Outcome: Did the conversation end in Resolution, Compromise, Stalemate, or Escalation?

    Return ONLY valid JSON. Do not include markdown formatting.

    {
      "interaction_metrics": {
        "word_count": { "speaker_A": Integer, "speaker_B": Integer },
        "average_turn_length_words": Integer,
        "conversation_style": "Lecture" | "Debate" | "Ping-Pong" | "Monologue",
        "interruption_markers_detected": Integer
      },
      "linguistic_markers": {
        "you_statements_count": { "speaker_A": Integer, "speaker_B": Integer },
        "i_statements_count": { "speaker_A": Integer, "speaker_B": Integer },
        "absolutes_used": ["always", "never"],
        "profanity_count": Integer
      },
      "gottman_profile": {
        "criticism": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" },
        "contempt": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" },
        "defensiveness": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" },
        "stonewalling": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" }
      },
      "repair_mechanics": {
        "repair_attempts_count": Integer,
        "successful_repairs": Integer,
        "validation_instances": Integer
      },
      "topic_analysis": {
        "primary_category": "Finances" | "Chores" | "Intimacy" | "Family" | "Work" | "Personality",
        "specific_subject": "String",
        "outcome_tag": "Unresolved" | "Compromise" | "Apology_Given" | "Escalated_Walkout"
      }
    }
    """

    // MARK: - Solo V2 Prompts

    private let soloVibePrompt = """
    You are a witty social media observer. Your job is to listen to a single person's speech and generate a "Personal Vibe Wrap-Up" similar to Spotify Wrapped.

    TONE GUIDELINES
    - Style: "Roast" humor, Gen Z slang (but not cringe), punchy.
    - Perspective: You are their brutally honest best friend, not their counselor.
    - Constraint: Do NOT be mean-spirited. Be "fun shady," not "cruel."

    TASKS
    1. Archetyping: Assign a pop-culture trope to the person (e.g., "Main Character Energy," "Overthinker Supreme," "Chaos Coordinator").
    2. Energy Read: Describe their vibe using a metaphor (e.g., "Golden Retriever Energy," "Stressed Accountant," "Midnight Philosopher").
    3. Scoring: Give a "Vibe Score" (0-100) based on their clarity, self-awareness, and emotional balance.

    Return ONLY valid JSON. Do not include markdown formatting.

    {
      "viral_card": {
        "headline_archetype": "String (Short & Funny)",
        "vibe_score": Integer (0-100),
        "energy_profile": {
          "speaker_A_vibe": "String (Metaphor)",
          "speaker_B_vibe": "N/A"
        }
      }
    }
    """

    private let soloCoachPrompt = """
    You are a personal communication coach analyzing a single person's speech. You help people become more effective communicators and more self-aware thinkers.

    OBJECTIVE
    Analyze the transcript to identify communication patterns and thinking habits that help or hinder clear, healthy expression.

    TASKS
    1. Pattern Detection: Scan for these common solo communication patterns:
       - Rumination: Circular thinking, rehashing the same point without resolution.
       - Catastrophizing: Jumping to worst-case scenarios, "always/never" thinking.
       - Self-Criticism: Harsh self-judgment, imposter syndrome language.
       - Avoidance: Deflecting from core issues, surface-level discussion of deep topics.
       - Emotional Clarity: Ability to name and express feelings precisely.
    2. Instant Replay: Extract exact quotes where patterns appear.
    3. The Fix: Suggest a reframed version of problematic quotes.
    4. Homework: Assign one specific, actionable exercise.

    CRITICAL: If the speech is clear, organized, and healthy, set all patterns to false and provide an empty coaching_opportunities array. Do NOT invent problems that aren't present.

    Return ONLY valid JSON. Do not include markdown formatting.

    {
      "coaching_analysis": {
        "game_summary": "Neutral, objective recap of what the person discussed (2-3 sentences).",
        "fouls_detected": {
          "criticism": boolean,
          "contempt": boolean,
          "defensiveness": boolean,
          "stonewalling": boolean
        },
        "coaching_opportunities": [
          {
            "speaker": "🔵",
            "call_made": "Rumination" | "Catastrophizing" | "Self-Criticism" | "Avoidance" | "Unclear Expression",
            "instant_replay_quote": "Exact string from text",
            "why_whistle_blew": "Explanation of why this pattern is unhelpful.",
            "better_play": "Specific reframed suggestion."
          }
        ],
        "post_game_drill": {
          "drill_name": "String",
          "instructions": "String"
        }
      }
    }
    """

    private let soloAnalystPrompt = """
    You are the "Lead Data Scientist" for a personal communication lab. Your task is to analyze a single person's speech transcript for linguistic patterns and communication effectiveness. You do NOT have access to audio; you must rely exclusively on linguistic markers, syntax, and semantic patterns.

    ANALYTICAL TASKS

    1. STRUCTURAL DYNAMICS
    - Word Count: Total words spoken.
    - Turn Length: Average length of thought segments.
    - Speech Style: Is this a monologue, stream-of-consciousness, structured reflection, or venting?

    2. LINGUISTIC PATTERNS
    - Pronoun Usage: "I" statements (self-awareness) vs. "You/They" statements (externalizing).
    - Absolutes: Count occurrences of "always," "never," "every time" (markers of cognitive distortions).
    - Negation Density: Frequency of "no," "not," "don't," "can't," "wrong."
    - Emotional Vocabulary: Range and specificity of emotion words used.

    3. SELF-TALK PATTERNS
    - Self-Criticism: "I'm so stupid," "I always mess up," self-blaming language.
    - Self-Compassion: "I did my best," "It's okay," self-accepting language.
    - Clarity: Does the person articulate feelings precisely or use vague language?
    - Resolution: Does the speech move toward clarity/action or stay circular?

    4. TOPIC ANALYSIS
    - What is the primary subject being discussed?
    - Is there a clear outcome or conclusion?

    Return ONLY valid JSON. Do not include markdown formatting.

    {
      "interaction_metrics": {
        "word_count": { "speaker_A": Integer, "speaker_B": 0 },
        "average_turn_length_words": Integer,
        "conversation_style": "Monologue" | "Stream-of-Consciousness" | "Structured Reflection" | "Venting",
        "interruption_markers_detected": 0
      },
      "linguistic_markers": {
        "you_statements_count": { "speaker_A": Integer, "speaker_B": 0 },
        "i_statements_count": { "speaker_A": Integer, "speaker_B": 0 },
        "absolutes_used": ["always", "never"],
        "profanity_count": Integer
      },
      "gottman_profile": {
        "criticism": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" },
        "contempt": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" },
        "defensiveness": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" },
        "stonewalling": { "detected": boolean, "severity": 1-5, "example_quote": "String or null" }
      },
      "repair_mechanics": {
        "repair_attempts_count": 0,
        "successful_repairs": 0,
        "validation_instances": 0
      },
      "topic_analysis": {
        "primary_category": "Self-Reflection" | "Relationships" | "Work" | "Emotions" | "Planning" | "Venting",
        "specific_subject": "String",
        "outcome_tag": "Clarity_Gained" | "Unresolved" | "Action_Planned" | "Emotional_Release"
      }
    }
    """

    /// Analyze a conversation using the 4-prompt V2 pipeline.
    /// Routes to solo pipeline when conversationMode is "solo".
    func analyzeConversationV2(utterances: [SpeakerUtterance], sessionId: String = UUID().uuidString, conversationMode: String = "couple") async -> SessionAnalysisV2? {
        guard !utterances.isEmpty else { return nil }

        // Ensure user has consented to AI data sharing
        guard UserDefaults.standard.bool(forKey: "hasAcceptedAIDataConsent") else {
            #if DEBUG
            print("AI data consent not granted — skipping analysis")
            #endif
            return nil
        }

        // Route to solo pipeline when in solo mode
        if conversationMode == "solo" {
            return await analyzeConversationV2Solo(utterances: utterances, sessionId: sessionId)
        }

        let uniqueSpeakerIds = Set(utterances.map { $0.speakerId }).count
        let uniqueSpeakerLabels = Set(utterances.map { $0.speakerLabel }).count
        let diarizedSpeakerCount = max(uniqueSpeakerIds, uniqueSpeakerLabels)
        let transcript = utterances.map { "\($0.speakerLabel): \($0.text)" }.joined(separator: "\n")

        #if DEBUG
        print("=== V2 PIPELINE START (session: \(sessionId.prefix(8))) ===")
        print("Sending \(utterances.count) utterances through 4-prompt pipeline...")
        print("Unique speaker IDs: \(uniqueSpeakerIds), unique labels: \(uniqueSpeakerLabels)")
        #endif

        // P1: Bouncer — validate the conversation before running full analysis
        guard let validation = await runBouncer(transcript: transcript, sessionId: sessionId, diarizedSpeakerCount: diarizedSpeakerCount) else {
            #if DEBUG
            print("P1 Bouncer: FAILED to run — returning nil")
            #endif
            return nil
        }

        #if DEBUG
        print("P1 Bouncer: valid=\(validation.isValidCoupleConversation), reason=\(validation.failReason ?? "none")")
        #endif

        // If bouncer rejects, return early with the validation result (no analysis)
        guard validation.isValidCoupleConversation else {
            return SessionAnalysisV2(
                validation: validation,
                vibeCard: nil,
                coaching: nil,
                analyst: nil
            )
        }

        // Step 1: Run Coach first (its fouls/summary informs Vibe and Analyst)
        let coachResult = await runCoach(transcript: transcript, sessionId: sessionId)

        #if DEBUG
        print("P3 Coach: \(coachResult != nil ? "OK" : "FAILED")")
        #endif

        // Build coach context summary for downstream prompts
        let coachContext: String
        if let coach = coachResult {
            let fouls = [
                coach.foulsDetected.criticism ? "criticism" : nil,
                coach.foulsDetected.contempt ? "contempt" : nil,
                coach.foulsDetected.defensiveness ? "defensiveness" : nil,
                coach.foulsDetected.stonewalling ? "stonewalling" : nil
            ].compactMap { $0 }
            coachContext = "Coach summary: \(coach.gameSummary) Fouls: \(fouls.isEmpty ? "none" : fouls.joined(separator: ", "))."
        } else {
            coachContext = ""
        }

        // Step 2: Run Vibe and Analyst in parallel, informed by Coach results
        async let vibe = runVibe(transcript: transcript, sessionId: sessionId, coachContext: coachContext)
        async let analyst = runAnalyst(transcript: transcript, sessionId: sessionId)

        let vibeResult = await vibe
        let analystResult = await analyst

        #if DEBUG
        print("P2 Vibe: \(vibeResult != nil ? "OK" : "FAILED")")
        print("P4 Analyst: \(analystResult != nil ? "OK" : "FAILED")")
        print("=== V2 PIPELINE COMPLETE ===")
        #endif

        return SessionAnalysisV2(
            validation: validation,
            vibeCard: vibeResult,
            coaching: coachResult,
            analyst: analystResult
        )
    }

    // MARK: - P1 Bouncer

    private func runBouncer(transcript: String, sessionId: String, diarizedSpeakerCount: Int = 1) async -> ValidationResult? {
        let userMessage = "Here is the conversation transcript to validate:\n\n\(transcript)"

        do {
            let response = try await openAI.chatCompletion(
                systemPrompt: bouncerPrompt,
                userMessage: userMessage,
                model: OpenAIService.model,
                temperature: 0.1,
                maxTokens: 512,
                sessionId: sessionId
            )
            guard var result = parseBouncer(response) else { return nil }

            // If diarization already found multiple speakers, trust it over the LLM's guess
            if diarizedSpeakerCount >= 2 && !result.twoVoicesPresent {
                #if DEBUG
                print("P1 Bouncer: overriding two_voices_present (diarization found \(diarizedSpeakerCount) speakers)")
                #endif
                result = ValidationResult(
                    twoVoicesPresent: true,
                    intelligibleDialogue: result.intelligibleDialogue,
                    interactiveConversation: result.interactiveConversation,
                    isValidCoupleConversation: result.intelligibleDialogue && result.interactiveConversation,
                    failReason: result.intelligibleDialogue && result.interactiveConversation ? nil : result.failReason,
                    userMessage: result.intelligibleDialogue && result.interactiveConversation ? nil : result.userMessage
                )
            }

            return result
        } catch {
            #if DEBUG
            print("P1 Bouncer error: \(error)")
            #endif
            return nil
        }
    }

    private func parseBouncer(_ json: String) -> ValidationResult? {
        guard let data = cleanJSON(json).data(using: .utf8) else { return nil }

        struct LLMBouncer: Decodable {
            struct Checks: Decodable {
                let two_voices_present: Bool
                let intelligible_dialogue: Bool
                let interactive_conversation: Bool
            }
            let criteria_checks: Checks
            let is_valid_couple_conversation: Bool
            let fail_reason: String?
            let user_message: String?
        }

        do {
            let parsed = try JSONDecoder().decode(LLMBouncer.self, from: data)
            return ValidationResult(
                twoVoicesPresent: parsed.criteria_checks.two_voices_present,
                intelligibleDialogue: parsed.criteria_checks.intelligible_dialogue,
                interactiveConversation: parsed.criteria_checks.interactive_conversation,
                isValidCoupleConversation: parsed.is_valid_couple_conversation,
                failReason: parsed.fail_reason,
                userMessage: parsed.user_message
            )
        } catch {
            #if DEBUG
            print("P1 Bouncer parse error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - P2 Vibe

    private func runVibe(transcript: String, sessionId: String, coachContext: String = "") async -> VibeCard? {
        var userMessage = "Here is the conversation transcript:\n\n\(transcript)"
        if !coachContext.isEmpty {
            userMessage += "\n\nContext from communication coach analysis: \(coachContext)"
        }

        do {
            let response = try await openAI.chatCompletion(
                systemPrompt: vibePrompt,
                userMessage: userMessage,
                model: OpenAIService.model,
                temperature: 0.7,
                maxTokens: 1024,
                sessionId: sessionId
            )
            return parseVibe(response)
        } catch {
            #if DEBUG
            print("P2 Vibe error: \(error)")
            #endif
            return nil
        }
    }

    private func parseVibe(_ json: String) -> VibeCard? {
        guard let data = cleanJSON(json).data(using: .utf8) else { return nil }

        struct LLMVibe: Decodable {
            struct Card: Decodable {
                let headline_archetype: String
                let vibe_score: Int
                struct Energy: Decodable {
                    let speaker_A_vibe: String
                    let speaker_B_vibe: String
                }
                let energy_profile: Energy
            }
            let viral_card: Card
        }

        do {
            let parsed = try JSONDecoder().decode(LLMVibe.self, from: data)
            let card = parsed.viral_card
            return VibeCard(
                headlineArchetype: card.headline_archetype,
                vibeScore: card.vibe_score,
                speakerAVibe: card.energy_profile.speaker_A_vibe,
                speakerBVibe: card.energy_profile.speaker_B_vibe
            )
        } catch {
            #if DEBUG
            print("P2 Vibe parse error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - P3 Coach

    private func runCoach(transcript: String, sessionId: String) async -> CoachingAnalysis? {
        let userMessage = "Here is the conversation transcript:\n\n\(transcript)"

        do {
            let response = try await openAI.chatCompletion(
                systemPrompt: coachPrompt,
                userMessage: userMessage,
                model: OpenAIService.model,
                temperature: 0.1,
                maxTokens: 2048,
                sessionId: sessionId
            )
            return parseCoach(response)
        } catch {
            #if DEBUG
            print("P3 Coach error: \(error)")
            #endif
            return nil
        }
    }

    private func parseCoach(_ json: String) -> CoachingAnalysis? {
        guard let data = cleanJSON(json).data(using: .utf8) else { return nil }

        struct LLMOpportunity: Decodable {
            let speaker: String
            let call_made: String
            let instant_replay_quote: String
            let why_whistle_blew: String
            let better_play: String
        }

        struct LLMDrill: Decodable {
            let drill_name: String
            let instructions: String
        }

        struct LLMFouls: Decodable {
            let criticism: Bool
            let contempt: Bool
            let defensiveness: Bool
            let stonewalling: Bool
        }

        struct LLMCoaching: Decodable {
            let game_summary: String
            let fouls_detected: LLMFouls
            let coaching_opportunities: [LLMOpportunity]
            let post_game_drill: LLMDrill
        }

        struct LLMCoachRoot: Decodable {
            let coaching_analysis: LLMCoaching
        }

        do {
            let parsed = try JSONDecoder().decode(LLMCoachRoot.self, from: data)
            let ca = parsed.coaching_analysis

            return CoachingAnalysis(
                gameSummary: ca.game_summary,
                foulsDetected: FoulsDetected(
                    criticism: ca.fouls_detected.criticism,
                    contempt: ca.fouls_detected.contempt,
                    defensiveness: ca.fouls_detected.defensiveness,
                    stonewalling: ca.fouls_detected.stonewalling
                ),
                coachingOpportunities: ca.coaching_opportunities.map {
                    CoachingOpportunity(
                        speaker: $0.speaker,
                        callMade: $0.call_made,
                        instantReplayQuote: $0.instant_replay_quote,
                        whyWhistleBlew: $0.why_whistle_blew,
                        betterPlay: $0.better_play
                    )
                },
                postGameDrill: PostGameDrill(
                    drillName: ca.post_game_drill.drill_name,
                    instructions: ca.post_game_drill.instructions
                )
            )
        } catch {
            #if DEBUG
            print("P3 Coach parse error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - P4 Analyst

    private func runAnalyst(transcript: String, sessionId: String) async -> AnalystReport? {
        let userMessage = "Here is the conversation transcript:\n\n\(transcript)"

        do {
            let response = try await openAI.chatCompletion(
                systemPrompt: analystPrompt,
                userMessage: userMessage,
                model: OpenAIService.model,
                temperature: 0.2,
                maxTokens: 2048,
                sessionId: sessionId
            )
            return parseAnalyst(response)
        } catch {
            #if DEBUG
            print("P4 Analyst error: \(error)")
            #endif
            return nil
        }
    }

    private func parseAnalyst(_ json: String) -> AnalystReport? {
        guard let data = cleanJSON(json).data(using: .utf8) else { return nil }

        struct LLMWordCount: Decodable {
            let speaker_A: Int
            let speaker_B: Int
        }
        struct LLMInteraction: Decodable {
            let word_count: LLMWordCount
            let average_turn_length_words: Int
            let conversation_style: String
            let interruption_markers_detected: Int
        }
        struct LLMStatements: Decodable {
            let speaker_A: Int
            let speaker_B: Int
        }
        struct LLMLinguistic: Decodable {
            let you_statements_count: LLMStatements
            let i_statements_count: LLMStatements
            let absolutes_used: [String]
            let profanity_count: Int
        }
        struct LLMGottmanItem: Decodable {
            let detected: Bool
            let severity: Int
            let example_quote: String?
        }
        struct LLMGottman: Decodable {
            let criticism: LLMGottmanItem
            let contempt: LLMGottmanItem
            let defensiveness: LLMGottmanItem
            let stonewalling: LLMGottmanItem
        }
        struct LLMRepair: Decodable {
            let repair_attempts_count: Int
            let successful_repairs: Int
            let validation_instances: Int
        }
        struct LLMTopic: Decodable {
            let primary_category: String
            let specific_subject: String
            let outcome_tag: String
        }
        struct LLMAnalystRoot: Decodable {
            let interaction_metrics: LLMInteraction
            let linguistic_markers: LLMLinguistic
            let gottman_profile: LLMGottman
            let repair_mechanics: LLMRepair
            let topic_analysis: LLMTopic
        }

        do {
            let parsed = try JSONDecoder().decode(LLMAnalystRoot.self, from: data)

            return AnalystReport(
                interactionMetrics: InteractionMetrics(
                    wordCountA: parsed.interaction_metrics.word_count.speaker_A,
                    wordCountB: parsed.interaction_metrics.word_count.speaker_B,
                    averageTurnLengthWords: parsed.interaction_metrics.average_turn_length_words,
                    conversationStyle: parsed.interaction_metrics.conversation_style,
                    interruptionMarkersDetected: parsed.interaction_metrics.interruption_markers_detected
                ),
                linguisticMarkers: LinguisticMarkers(
                    youStatementsA: parsed.linguistic_markers.you_statements_count.speaker_A,
                    youStatementsB: parsed.linguistic_markers.you_statements_count.speaker_B,
                    iStatementsA: parsed.linguistic_markers.i_statements_count.speaker_A,
                    iStatementsB: parsed.linguistic_markers.i_statements_count.speaker_B,
                    absolutesUsed: parsed.linguistic_markers.absolutes_used,
                    profanityCount: parsed.linguistic_markers.profanity_count
                ),
                gottmanProfile: GottmanProfile(
                    criticism: GottmanItem(detected: parsed.gottman_profile.criticism.detected, severity: parsed.gottman_profile.criticism.severity, exampleQuote: parsed.gottman_profile.criticism.example_quote),
                    contempt: GottmanItem(detected: parsed.gottman_profile.contempt.detected, severity: parsed.gottman_profile.contempt.severity, exampleQuote: parsed.gottman_profile.contempt.example_quote),
                    defensiveness: GottmanItem(detected: parsed.gottman_profile.defensiveness.detected, severity: parsed.gottman_profile.defensiveness.severity, exampleQuote: parsed.gottman_profile.defensiveness.example_quote),
                    stonewalling: GottmanItem(detected: parsed.gottman_profile.stonewalling.detected, severity: parsed.gottman_profile.stonewalling.severity, exampleQuote: parsed.gottman_profile.stonewalling.example_quote)
                ),
                repairMechanics: RepairMechanics(
                    repairAttemptsCount: parsed.repair_mechanics.repair_attempts_count,
                    successfulRepairs: parsed.repair_mechanics.successful_repairs,
                    validationInstances: parsed.repair_mechanics.validation_instances
                ),
                topicAnalysis: TopicAnalysis(
                    primaryCategory: parsed.topic_analysis.primary_category,
                    specificSubject: parsed.topic_analysis.specific_subject,
                    outcomeTag: parsed.topic_analysis.outcome_tag
                )
            )
        } catch {
            #if DEBUG
            print("P4 Analyst parse error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Solo V2 Pipeline

    /// Analyze a single person's speech using the solo prompt pipeline.
    private func analyzeConversationV2Solo(utterances: [SpeakerUtterance], sessionId: String) async -> SessionAnalysisV2? {
        let transcript = utterances.map { $0.text }.joined(separator: "\n")

        #if DEBUG
        print("=== SOLO V2 PIPELINE START (session: \(sessionId.prefix(8))) ===")
        print("Sending \(utterances.count) utterances through solo pipeline...")
        #endif

        // Solo mode: skip bouncer validation (single voice is expected)
        let validation = ValidationResult(
            twoVoicesPresent: false,
            intelligibleDialogue: true,
            interactiveConversation: false,
            isValidCoupleConversation: true, // Mark as valid so downstream UI shows results
            failReason: nil,
            userMessage: nil
        )

        // Step 1: Run Solo Coach first
        let coachResult = await runSoloCoach(transcript: transcript, sessionId: sessionId)

        #if DEBUG
        print("Solo Coach: \(coachResult != nil ? "OK" : "FAILED")")
        #endif

        // Build coach context for Vibe
        let coachContext: String
        if let coach = coachResult {
            coachContext = "Coach summary: \(coach.gameSummary)"
        } else {
            coachContext = ""
        }

        // Step 2: Run Solo Vibe and Solo Analyst in parallel
        async let vibe = runSoloVibe(transcript: transcript, sessionId: sessionId, coachContext: coachContext)
        async let analyst = runSoloAnalyst(transcript: transcript, sessionId: sessionId)

        let vibeResult = await vibe
        let analystResult = await analyst

        #if DEBUG
        print("Solo Vibe: \(vibeResult != nil ? "OK" : "FAILED")")
        print("Solo Analyst: \(analystResult != nil ? "OK" : "FAILED")")
        print("=== SOLO V2 PIPELINE COMPLETE ===")
        #endif

        return SessionAnalysisV2(
            validation: validation,
            vibeCard: vibeResult,
            coaching: coachResult,
            analyst: analystResult
        )
    }

    private func runSoloVibe(transcript: String, sessionId: String, coachContext: String = "") async -> VibeCard? {
        var userMessage = "Here is the transcript of a single person speaking:\n\n\(transcript)"
        if !coachContext.isEmpty {
            userMessage += "\n\nContext from communication coach analysis: \(coachContext)"
        }

        do {
            let response = try await openAI.chatCompletion(
                systemPrompt: soloVibePrompt,
                userMessage: userMessage,
                model: OpenAIService.model,
                temperature: 0.7,
                maxTokens: 1024,
                sessionId: sessionId
            )
            return parseVibe(response)
        } catch {
            #if DEBUG
            print("Solo Vibe error: \(error)")
            #endif
            return nil
        }
    }

    private func runSoloCoach(transcript: String, sessionId: String) async -> CoachingAnalysis? {
        let userMessage = "Here is the transcript of a single person speaking:\n\n\(transcript)"

        do {
            let response = try await openAI.chatCompletion(
                systemPrompt: soloCoachPrompt,
                userMessage: userMessage,
                model: OpenAIService.model,
                temperature: 0.1,
                maxTokens: 2048,
                sessionId: sessionId
            )
            return parseCoach(response)
        } catch {
            #if DEBUG
            print("Solo Coach error: \(error)")
            #endif
            return nil
        }
    }

    private func runSoloAnalyst(transcript: String, sessionId: String) async -> AnalystReport? {
        let userMessage = "Here is the transcript of a single person speaking:\n\n\(transcript)"

        do {
            let response = try await openAI.chatCompletion(
                systemPrompt: soloAnalystPrompt,
                userMessage: userMessage,
                model: OpenAIService.model,
                temperature: 0.2,
                maxTokens: 2048,
                sessionId: sessionId
            )
            return parseAnalyst(response)
        } catch {
            #if DEBUG
            print("Solo Analyst error: \(error)")
            #endif
            return nil
        }
    }

    // MARK: - Helpers

    private func cleanJSON(_ json: String) -> String {
        json
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
