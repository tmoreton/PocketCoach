import SwiftUI

// MARK: - V2 Analysis View

struct AnalysisViewV2: View {
    let analysisV2: SessionAnalysisV2
    var utterances: [SpeakerUtterance] = []
    var debugAudio: [Float]?
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) var dismiss
    @State private var showingDiarization = false
    #if DEBUG
    @State private var showingDebugComparison = false
    #endif

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(.subheadline, weight: .bold))
                            .foregroundColor(Constants.therapyPrimaryColor)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Constants.therapyPrimaryColor.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                // MARK: - Vibe Hero
                if let vibe = analysisV2.vibeCard {
                    vibeHeroSection(vibe: vibe)
                        .padding(.bottom, 24)
                }

                // MARK: - Diarization Toggle
                if !utterances.isEmpty {
                    diarizationToggle
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }

                // MARK: - Content Cards
                VStack(spacing: 16) {
                    // Coach Section
                    if let coaching = analysisV2.coaching {
                        coachSection(coaching: coaching)
                    }

                    // Analyst Section
                    if let analyst = analysisV2.analyst {
                        analystSection(analyst: analyst)
                    }

                    #if DEBUG
                    // Debug: Diarization Comparison
                    if debugAudio != nil {
                        Button(action: { showingDebugComparison = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "ant")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Compare Diarization (Debug)")
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .foregroundColor(.orange)
                            .padding(14)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    #endif
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(Constants.adaptiveBackgroundColor.ignoresSafeArea())
        .onAppear { Analytics.analysisViewed() }
        #if DEBUG
        .sheet(isPresented: $showingDebugComparison) {
            if let audio = debugAudio {
                DiarizationComparisonView(audio: audio, sampleRate: Constants.sampleRate)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        #endif
    }

    // MARK: - Vibe Hero Section

    private func vibeHeroSection(vibe: VibeCard) -> some View {
        VStack(spacing: 16) {
            // Archetype headline
            Text(vibe.headlineArchetype)
                .font(.custom("DMSerifDisplay-Regular", size: 24))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)

            // Coach score gauge
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 10)
                        .frame(width: 100, height: 100)
                    Circle()
                        .trim(from: 0, to: CGFloat(vibe.vibeScore) / 100.0)
                        .stroke(
                            vibeColor(vibe.vibeScore),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .frame(width: 100, height: 100)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(vibe.vibeScore)")
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(vibeColor(vibe.vibeScore))
                        Text("/100")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                Text("COACH SCORE")
                    .font(.system(size: 10, weight: .black))
                    .kerning(1.0)
                    .foregroundColor(.secondary.opacity(0.7))
            }

            // Energy profiles side by side
            HStack(spacing: 12) {
                energyProfileCard(label: "🔵", vibe: vibe.speakerAVibe, color: .blue)
                energyProfileCard(label: "🟠", vibe: vibe.speakerBVibe, color: .orange)
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private func energyProfileCard(label: String, vibe: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .black))
                .kerning(1.0)
                .foregroundColor(color.opacity(0.7))
            Text(vibe)
                .font(.system(.caption, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundColor(.primary.opacity(0.85))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.08 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(color.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Coach Section

    @ViewBuilder
    private func coachSection(coaching: CoachingAnalysis) -> some View {
        // Game Summary
        cardSection {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("GAME SUMMARY", icon: "sportscourt")
                Text(coaching.gameSummary)
                    .font(.system(.subheadline))
                    .foregroundColor(.primary.opacity(0.85))
                    .lineSpacing(5)
            }
        }

        // Fouls Detected
        cardSection {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("FOULS DETECTED", icon: "exclamationmark.triangle")
                HStack(spacing: 8) {
                    foulBadge("Criticism", active: coaching.foulsDetected.criticism)
                    foulBadge("Contempt", active: coaching.foulsDetected.contempt)
                    foulBadge("Defensiveness", active: coaching.foulsDetected.defensiveness)
                    foulBadge("Stonewalling", active: coaching.foulsDetected.stonewalling)
                }
            }
        }

        // Coaching Opportunities
        if !coaching.coachingOpportunities.isEmpty {
            ForEach(coaching.coachingOpportunities) { opportunity in
                CoachingOpportunityCard(opportunity: opportunity)
            }
        }

        // Post-Game Drill
        cardSection {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("POST-GAME DRILL", icon: "figure.2.arms.open", color: Constants.therapyPrimaryColor)
                DrillCard(drill: coaching.postGameDrill)
            }
        }
    }

    // MARK: - Analyst Section

    @ViewBuilder
    private func analystSection(analyst: AnalystReport) -> some View {
        // Interaction Metrics
        cardSection {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("INTERACTION METRICS", icon: "chart.bar")

                // Word count ratio bar
                let totalWords = analyst.interactionMetrics.wordCountA + analyst.interactionMetrics.wordCountB
                if totalWords > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Word Count")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        GeometryReader { geo in
                            let ratioA = CGFloat(analyst.interactionMetrics.wordCountA) / CGFloat(totalWords)
                            HStack(spacing: 2) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.blue.opacity(0.6))
                                    .frame(width: geo.size.width * ratioA)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.orange.opacity(0.6))
                            }
                        }
                        .frame(height: 12)
                        HStack {
                            Text("🔵 \(analyst.interactionMetrics.wordCountA)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.blue)
                            Spacer()
                            Text("🟠 \(analyst.interactionMetrics.wordCountB)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.orange)
                        }
                    }
                }

                HStack(spacing: 12) {
                    metricBadge(label: "Style", value: analyst.interactionMetrics.conversationStyle)
                    metricBadge(label: "Interruptions", value: "\(analyst.interactionMetrics.interruptionMarkersDetected)")
                    metricBadge(label: "Avg Turn", value: "\(analyst.interactionMetrics.averageTurnLengthWords)w")
                }
            }
        }

        // Linguistic Markers
        cardSection {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("LINGUISTIC MARKERS", icon: "textformat")

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\"You\" Statements")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("🔵 \(analyst.linguisticMarkers.youStatementsA)  🟠 \(analyst.linguisticMarkers.youStatementsB)")
                            .font(.system(.caption, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\"I\" Statements")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Text("🔵 \(analyst.linguisticMarkers.iStatementsA)  🟠 \(analyst.linguisticMarkers.iStatementsB)")
                            .font(.system(.caption, weight: .bold))
                            .foregroundColor(.primary.opacity(0.8))
                    }
                }

                if !analyst.linguisticMarkers.absolutesUsed.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Absolutes Used")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        FlowLayout(spacing: 6) {
                            ForEach(analyst.linguisticMarkers.absolutesUsed, id: \.self) { word in
                                Text(word)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }

                if analyst.linguisticMarkers.profanityCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.bubble.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red.opacity(0.7))
                        Text("Profanity: \(analyst.linguisticMarkers.profanityCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.red.opacity(0.7))
                    }
                }
            }
        }

        // Gottman Profile
        cardSection {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("GOTTMAN PROFILE", icon: "shield.lefthalf.filled")
                gottmanRow("Criticism", item: analyst.gottmanProfile.criticism)
                gottmanRow("Contempt", item: analyst.gottmanProfile.contempt)
                gottmanRow("Defensiveness", item: analyst.gottmanProfile.defensiveness)
                gottmanRow("Stonewalling", item: analyst.gottmanProfile.stonewalling)
            }
        }

        // Repair Mechanics
        cardSection {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("REPAIR MECHANICS", icon: "wrench.and.screwdriver")
                HStack(spacing: 20) {
                    VStack(spacing: 2) {
                        Text("\(analyst.repairMechanics.successfulRepairs)/\(analyst.repairMechanics.repairAttemptsCount)")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.green)
                        Text("Repairs")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    VStack(spacing: 2) {
                        Text("\(analyst.repairMechanics.validationInstances)")
                            .font(.system(size: 20, weight: .black))
                            .foregroundColor(.blue)
                        Text("Validations")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }

        // Topic Analysis
        cardSection {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel("TOPIC ANALYSIS", icon: "tag")
                HStack(spacing: 8) {
                    Text(analyst.topicAnalysis.primaryCategory)
                        .font(.system(.caption, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Constants.therapyPrimaryColor.opacity(0.12))
                        .foregroundColor(Constants.therapyPrimaryColor)
                        .clipShape(Capsule())
                    Text(analyst.topicAnalysis.outcomeTag)
                        .font(.system(.caption, weight: .bold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(outcomeColor(analyst.topicAnalysis.outcomeTag).opacity(0.12))
                        .foregroundColor(outcomeColor(analyst.topicAnalysis.outcomeTag))
                        .clipShape(Capsule())
                }
                Text(analyst.topicAnalysis.specificSubject)
                    .font(.system(.subheadline))
                    .foregroundColor(.primary.opacity(0.85))
            }
        }
    }

    // MARK: - Component Helpers

    private var diarizationToggle: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    showingDiarization.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "person.2.wave.2")
                        .font(.system(size: 12, weight: .bold))
                    Text("Conversation")
                        .font(.system(size: 11, weight: .black))
                        .kerning(0.8)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(showingDiarization ? 90 : 0))
                }
                .foregroundColor(.secondary)
                .padding(16)
            }
            .buttonStyle(.plain)

            if showingDiarization {
                Divider()
                    .padding(.horizontal, 16)
                ConversationView(utterances: utterances)
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.5)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Constants.therapyCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func foulBadge(_ name: String, active: Bool) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .black))
            .kerning(0.5)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(active ? Color.red.opacity(0.15) : Color.secondary.opacity(0.06))
            .foregroundColor(active ? .red : .secondary.opacity(0.4))
            .clipShape(Capsule())
    }

    private func metricBadge(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.caption, weight: .black))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func gottmanRow(_ label: String, item: GottmanItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(.caption, weight: .bold))
                    .foregroundColor(item.detected ? .red : .secondary)
                Spacer()
                // Severity bar
                HStack(spacing: 3) {
                    ForEach(1...5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level <= item.severity ? severityColor(item.severity) : Color.secondary.opacity(0.12))
                            .frame(width: 16, height: 6)
                    }
                }
            }
            if let quote = item.exampleQuote, !quote.isEmpty {
                Text("\"\(quote)\"")
                    .font(.system(.caption2))
                    .italic()
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Card Builders

    @ViewBuilder
    private func cardSection<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Constants.therapyCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func sectionLabel(_ title: String, icon: String, color: Color = .secondary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .black))
                .kerning(1.0)
        }
        .foregroundColor(color.opacity(0.7))
    }

    // MARK: - Color Helpers

    private func vibeColor(_ score: Int) -> Color {
        switch score {
        case 0..<30: return .red
        case 30..<50: return .orange
        case 50..<70: return .yellow
        case 70..<90: return .green
        default: return .green
        }
    }

    private func severityColor(_ severity: Int) -> Color {
        switch severity {
        case 1...2: return .yellow
        case 3: return .orange
        case 4...5: return .red
        default: return .secondary
        }
    }

    private func outcomeColor(_ tag: String) -> Color {
        switch tag {
        case "Compromise", "Apology_Given": return .green
        case "Unresolved": return .orange
        case "Escalated_Walkout": return .red
        default: return .secondary
        }
    }
}

// MARK: - Coaching Opportunity Card

struct CoachingOpportunityCard: View {
    let opportunity: CoachingOpportunity
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false

    private var foulColor: Color {
        switch opportunity.callMade {
        case "Criticism": return .orange
        case "Contempt": return .red
        case "Defensiveness": return .yellow
        case "Stonewalling": return .purple
        default: return .red
        }
    }

    static func speakerEmoji(_ speaker: String) -> String {
        let lower = speaker.lowercased()
        if lower.contains("a") || lower.contains("1") { return "🔵" }
        if lower.contains("b") || lower.contains("2") { return "🟠" }
        return "🔵"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded.toggle() }
            }) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(foulColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Image(systemName: "flag.fill")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(foulColor)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.speakerEmoji(opportunity.speaker))
                            .font(.system(size: 18))
                            .foregroundColor(foulColor)
                        Text(opportunity.callMade)
                            .font(.system(.caption2, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .padding(18)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 18)

                VStack(alignment: .leading, spacing: 14) {
                    // Instant Replay
                    VStack(alignment: .leading, spacing: 4) {
                        Text("INSTANT REPLAY")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.8)
                            .foregroundColor(.secondary.opacity(0.7))
                        Text("\"\(opportunity.instantReplayQuote)\"")
                            .font(.system(.caption))
                            .italic()
                            .foregroundColor(.primary.opacity(0.7))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    // Why the Whistle Blew
                    VStack(alignment: .leading, spacing: 4) {
                        Text("WHY THE WHISTLE BLEW")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.8)
                            .foregroundColor(.orange.opacity(0.7))
                        Text(opportunity.whyWhistleBlew)
                            .font(.system(.caption))
                            .foregroundColor(.primary.opacity(0.8))
                            .lineSpacing(3)
                    }

                    // Better Play
                    VStack(alignment: .leading, spacing: 4) {
                        Text("BETTER PLAY")
                            .font(.system(size: 10, weight: .black))
                            .kerning(0.8)
                            .foregroundColor(.green.opacity(0.7))
                        Text(opportunity.betterPlay)
                            .font(.system(.caption, weight: .medium))
                            .foregroundColor(.primary.opacity(0.85))
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.green.opacity(colorScheme == .dark ? 0.08 : 0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.green.opacity(0.15), lineWidth: 1)
                            )
                    }
                }
                .padding(18)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(foulColor.opacity(colorScheme == .dark ? 0.06 : 0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(foulColor.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Drill Card

struct DrillCard: View {
    let drill: PostGameDrill
    @Environment(\.colorScheme) var colorScheme
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { isExpanded.toggle() } }) {
                HStack(spacing: 10) {
                    Image(systemName: "figure.2.arms.open")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Constants.therapyPrimaryColor)
                    Text(drill.drillName)
                        .font(.system(.subheadline, weight: .bold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.5))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.vertical, 10)
                Text("INSTRUCTIONS")
                    .font(.system(size: 10, weight: .black))
                    .kerning(0.8)
                    .foregroundColor(Constants.therapyPrimaryColor.opacity(0.7))
                    .padding(.bottom, 4)
                Text(drill.instructions)
                    .font(.system(.caption))
                    .foregroundColor(.primary.opacity(0.8))
                    .lineSpacing(4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.therapyPrimaryColor.opacity(colorScheme == .dark ? 0.06 : 0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Constants.therapyPrimaryColor.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Vibe Score Gauge (compact, for inline use)

struct VibeGauge: View {
    let score: Int

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
                .frame(width: 52, height: 52)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100.0)
                .stroke(gaugeColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(width: 52, height: 52)
                .rotationEffect(.degrees(-90))
            Text("\(score)")
                .font(.system(size: 16, weight: .black))
                .foregroundColor(gaugeColor)
        }
    }

    private var gaugeColor: Color {
        switch score {
        case 0..<30: return .red
        case 30..<50: return .orange
        case 50..<70: return .yellow
        case 70..<90: return .green
        default: return .green
        }
    }
}

// MARK: - Shared Components

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(.system(size: 10, weight: .black))
                .kerning(1.0)
        }
        .foregroundColor(.secondary.opacity(0.7))
    }
}

struct BulletPoint: View {
    let text: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color.opacity(0.7))
                .frame(width: 14, height: 14)
                .padding(.top, 2)
            Text(text)
                .font(.system(.caption))
                .foregroundColor(.primary.opacity(0.8))
                .lineSpacing(2)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(in: proposal.width ?? 0, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(in: bounds.width, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func layout(in width: CGFloat, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += maxHeight + spacing
                maxHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            maxHeight = max(maxHeight, size.height)
            x += size.width + spacing
            totalHeight = y + maxHeight
        }

        return (CGSize(width: width, height: totalHeight), positions)
    }
}
