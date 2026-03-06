import Foundation

/// Provides realistic mock data for App Store screenshot capture.
/// Activated via `-SCREENSHOT_MODE` launch argument.
enum ScreenshotMockData {

    // MARK: - Launch Argument Detection

    static var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_MODE")
    }

    static var shouldShowOnboarding: Bool {
        ProcessInfo.processInfo.arguments.contains("-SHOW_ONBOARDING")
    }

    static var shouldForceDarkMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-FORCE_DARK_MODE")
    }

    static var isVideoMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-VIDEO_MODE")
    }

    static var isRecordingScreenshot: Bool {
        ProcessInfo.processInfo.arguments.contains("-SCREENSHOT_RECORD")
    }

    static var shouldShowConversation: Bool {
        ProcessInfo.processInfo.arguments.contains("-SHOW_CONVERSATION")
    }

    // MARK: - Mock Utterances (realistic couples conversation)

    static let mockUtterances: [SpeakerUtterance] = [
        SpeakerUtterance(
            speakerId: "A", speakerLabel: "Alex",
            text: "I feel like we haven't really talked about how the move is affecting us. I've been stressed and I don't think I've been showing up the way I want to.",
            startTime: 0.0, endTime: 12.5
        ),
        SpeakerUtterance(
            speakerId: "B", speakerLabel: "Jordan",
            text: "I appreciate you saying that. Honestly, I've been feeling a little disconnected too. Like we're both just going through the motions with the boxes and logistics.",
            startTime: 12.5, endTime: 24.0
        ),
        SpeakerUtterance(
            speakerId: "A", speakerLabel: "Alex",
            text: "Yeah, exactly. And when you stayed late at work last Thursday, I know it's not a big deal but it kind of felt like the move wasn't a priority for you.",
            startTime: 24.0, endTime: 36.0
        ),
        SpeakerUtterance(
            speakerId: "B", speakerLabel: "Jordan",
            text: "That's fair. I should have communicated better about that. I was trying to finish a deadline so I could take Friday off to help, but I didn't tell you that part.",
            startTime: 36.0, endTime: 48.0
        ),
        SpeakerUtterance(
            speakerId: "A", speakerLabel: "Alex",
            text: "Oh, I didn't know that. That actually changes things. I think I jumped to conclusions because I was already feeling overwhelmed.",
            startTime: 48.0, endTime: 58.0
        ),
        SpeakerUtterance(
            speakerId: "B", speakerLabel: "Jordan",
            text: "I get it. Maybe we can set aside some time this weekend just for us? No boxes, no checklists. Just reconnect a little.",
            startTime: 58.0, endTime: 68.0
        ),
        SpeakerUtterance(
            speakerId: "A", speakerLabel: "Alex",
            text: "I'd really love that. And I'm sorry for being short with you this week. You didn't deserve that.",
            startTime: 68.0, endTime: 76.0
        ),
        SpeakerUtterance(
            speakerId: "B", speakerLabel: "Jordan",
            text: "We're a team. Let's just keep talking like this. It helps more than you know.",
            startTime: 76.0, endTime: 84.0
        )
    ]

    // MARK: - Mock Analysis V2

    static let mockAnalysisV2: SessionAnalysisV2 = {
        let validation = ValidationResult(
            twoVoicesPresent: true,
            intelligibleDialogue: true,
            interactiveConversation: true,
            isValidCoupleConversation: true,
            failReason: nil,
            userMessage: nil
        )

        let vibeCard = VibeCard(
            headlineArchetype: "The Reconnectors",
            vibeScore: 78,
            speakerAVibe: "Vulnerable & reflective",
            speakerBVibe: "Supportive & solution-oriented"
        )

        let coaching = CoachingAnalysis(
            gameSummary: "A healthy check-in where both partners acknowledged feeling disconnected during a stressful move. Alex initiated with vulnerability, and Jordan responded with accountability and a concrete plan to reconnect. Strong repair mechanics throughout.",
            foulsDetected: FoulsDetected(
                criticism: false,
                contempt: false,
                defensiveness: false,
                stonewalling: false
            ),
            coachingOpportunities: [
                CoachingOpportunity(
                    speaker: "Alex",
                    callMade: "Mind-reading",
                    instantReplayQuote: "it kind of felt like the move wasn't a priority for you",
                    whyWhistleBlew: "Alex assumed Jordan's intentions without asking first, turning a logistical gap into a character judgment.",
                    betterPlay: "Try: 'When you stayed late, I felt worried we weren't on the same page. Can you help me understand what happened?'"
                ),
                CoachingOpportunity(
                    speaker: "Jordan",
                    callMade: "Withheld context",
                    instantReplayQuote: "I was trying to finish a deadline so I could take Friday off to help, but I didn't tell you that part",
                    whyWhistleBlew: "Jordan had good intentions but didn't share the plan, leaving Alex to fill in the blanks with stress-colored assumptions.",
                    betterPlay: "A quick text earlier in the day — 'Staying late tonight so I can take Friday off for moving' — would have prevented the disconnect."
                )
            ],
            postGameDrill: PostGameDrill(
                drillName: "The 5-Minute Daily Download",
                instructions: "Each evening this week, set a 5-minute timer. Take turns sharing one thing that stressed you and one thing you appreciated about each other that day. No problem-solving allowed — just listening."
            )
        )

        let analyst = AnalystReport(
            interactionMetrics: InteractionMetrics(
                wordCountA: 98,
                wordCountB: 94,
                averageTurnLengthWords: 24,
                conversationStyle: "Collaborative",
                interruptionMarkersDetected: 0
            ),
            linguisticMarkers: LinguisticMarkers(
                youStatementsA: 2,
                youStatementsB: 1,
                iStatementsA: 5,
                iStatementsB: 3,
                absolutesUsed: [],
                profanityCount: 0
            ),
            gottmanProfile: GottmanProfile(
                criticism: GottmanItem(detected: false, severity: 0, exampleQuote: nil),
                contempt: GottmanItem(detected: false, severity: 0, exampleQuote: nil),
                defensiveness: GottmanItem(detected: false, severity: 0, exampleQuote: nil),
                stonewalling: GottmanItem(detected: false, severity: 0, exampleQuote: nil)
            ),
            repairMechanics: RepairMechanics(
                repairAttemptsCount: 3,
                successfulRepairs: 3,
                validationInstances: 4
            ),
            topicAnalysis: TopicAnalysis(
                primaryCategory: "Life Transition",
                specificSubject: "Moving logistics & emotional disconnection",
                outcomeTag: "Resolved"
            )
        )

        return SessionAnalysisV2(
            validation: validation,
            vibeCard: vibeCard,
            coaching: coaching,
            analyst: analyst
        )
    }()

    // MARK: - Mock Coaching Session

    static let mockSession: CoachingSession = {
        var session = CoachingSession(startedAt: Date().addingTimeInterval(-300))
        session.endedAt = Date()
        session.utterances = mockUtterances
        session.analysisV2 = mockAnalysisV2
        return session
    }()

    // MARK: - Mock History Items

    static let mockHistoryItems: [HistoryItem] = [
        HistoryItem(
            text: "Alex: I feel like we haven't really talked about how the move is affecting us...\nJordan: I appreciate you saying that. Honestly, I've been feeling a little disconnected too...",
            analysisV2: mockAnalysisV2,
            durationSeconds: 84,
            utterances: mockUtterances
        ),
        HistoryItem(
            text: "Sam: Can we talk about the budget? I noticed we went over on dining out again this month.\nTaylor: I know, but some of those were work dinners I couldn't avoid...",
            analysisV2: SessionAnalysisV2(
                validation: ValidationResult(twoVoicesPresent: true, intelligibleDialogue: true, interactiveConversation: true, isValidCoupleConversation: true, failReason: nil, userMessage: nil),
                vibeCard: VibeCard(headlineArchetype: "The Negotiators", vibeScore: 62, speakerAVibe: "Organized & direct", speakerBVibe: "Defensive but willing"),
                coaching: CoachingAnalysis(
                    gameSummary: "A budget discussion that started tense but found common ground. Some defensiveness detected early on, but both partners eventually moved toward compromise.",
                    foulsDetected: FoulsDetected(criticism: false, contempt: false, defensiveness: true, stonewalling: false),
                    coachingOpportunities: [],
                    postGameDrill: PostGameDrill(drillName: "Budget Date Night", instructions: "Schedule a monthly 'money date' with snacks. Review spending together in a relaxed setting.")
                ),
                analyst: nil
            ),
            durationSeconds: 156
        ),
        HistoryItem(
            text: "Riley: I just feel like you don't listen to me sometimes.\nMorgan: I'm listening right now. What do you need me to hear?",
            analysisV2: SessionAnalysisV2(
                validation: ValidationResult(twoVoicesPresent: true, intelligibleDialogue: true, interactiveConversation: true, isValidCoupleConversation: true, failReason: nil, userMessage: nil),
                vibeCard: VibeCard(headlineArchetype: "The Bridge Builders", vibeScore: 71, speakerAVibe: "Frustrated but open", speakerBVibe: "Calm & attentive"),
                coaching: nil,
                analyst: nil
            ),
            durationSeconds: 210
        )
    ]
}
