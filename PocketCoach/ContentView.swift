//
//  ContentView.swift
//  PocketCoach
//
//  Created by Tim Moreton on 12/20/25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var historyManager: SharedHistoryManager
    @EnvironmentObject var transcriptionManager: AudioTranscriptionManager_iOS
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @State private var shouldShowHistory = false
    @State private var shouldStartRecording = false

    var body: some View {
        NavigationStack {
            RecordView(shouldShowHistory: $shouldShowHistory, shouldStartRecording: $shouldStartRecording)
        }
        // Model pre-loading is handled by PocketCoachApp.preloadModelsIfNeeded()
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("StartRecordingFromIntent"))) { _ in
            shouldStartRecording = true
        }
    }
}

struct RecordView: View {
    @EnvironmentObject var transcriptionManager: AudioTranscriptionManager_iOS
    @EnvironmentObject var liveActivityManager: LiveActivityManager
    @Environment(\.colorScheme) var colorScheme

    @State private var showingHistory = false
    @State private var showingSettings = false
    @Binding var shouldShowHistory: Bool
    @Binding var shouldStartRecording: Bool
    @State private var showingAnalysis = false
    @State private var showingDiarization = ScreenshotMockData.shouldShowConversation
    @State private var hasAutoShownAnalysis = false

    private var hasSessionUtterances: Bool {
        transcriptionManager.currentSession?.utterances.isEmpty == false
    }

    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Constants.coachingPrimaryColor.opacity(colorScheme == .dark ? 0.08 : 0.12),
                Constants.adaptiveBackgroundColor.opacity(0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 350)
        .position(x: UIScreen.main.bounds.width / 2, y: 100)
        .ignoresSafeArea()
    }

    var body: some View {
        ZStack {
            // Background Layer
            Constants.adaptiveBackgroundColor.ignoresSafeArea()

            // Subtle Top Gradient
            backgroundGradient

            VStack(spacing: 0) {
                // Minimalist Top Bar
                HStack {
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showingSettings = true
                        }
                    }) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(12)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("settingsButton")

                    Spacer()

                    Button(action: { showingHistory = true }) {
                        Image(systemName: "clock")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(12)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("historyButton")
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                if transcriptionManager.isDiarizing || transcriptionManager.isAnalyzing {
                    // MARK: - Processing State (loading with progress)
                    processingProgressView
                } else if let analysisV2 = transcriptionManager.currentSession?.analysisV2, analysisV2.isValid {
                    // MARK: - Post-Analysis V2 View
                    analysisResultsViewV2(analysisV2: analysisV2)
                } else if transcriptionManager.analysisPhase == .invalidConversation {
                    // MARK: - Invalid Conversation State
                    invalidConversationView
                } else {
                    // MARK: - Recording State
                    Spacer()

                    VStack(spacing: 8) {
                        AnimatedRecordingButton(
                            isRecording: $transcriptionManager.isTranscribing,
                            action: {
                                if !transcriptionManager.isModelReady && !transcriptionManager.isModelLoading {
                                    Task {
                                        do {
                                            try await transcriptionManager.initializeModelIfNeeded()
                                            // Model loaded successfully - start recording automatically
                                            await MainActor.run {
                                                transcriptionManager.liveActivityManager = liveActivityManager
                                                transcriptionManager.quickRecord()
                                            }
                                        } catch {
                                            print("Manual model initialization failed: \(error)")
                                        }
                                    }
                                    return
                                }

                                hasAutoShownAnalysis = false
                                transcriptionManager.liveActivityManager = liveActivityManager
                                transcriptionManager.quickRecord()
                                Analytics.sessionStarted()
                            },
                            isDisabled: false,
                            loadingText: nil
                        )
                        .onLongPressGesture(minimumDuration: 2.0) {
                            Task {
                                await transcriptionManager.fluidAudioManager.forceResetModelState()
                                transcriptionManager.isModelLoading = false
                                transcriptionManager.isModelReady = false
                            }
                            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        }

                        // Status text
                        Text(getStatusTextForButton())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        if transcriptionManager.isTranscribing {
                            AudioLevelVisualizer(audioLevel: transcriptionManager.audioLevel)
                                .frame(height: 12)
                                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                                .padding(.top, 8)
                        }
                    }

                    Spacer()

                    // Bottom: live transcript card + error card (only during recording, before analysis)
                    VStack(spacing: 16) {
                        // Analysis Error Card
                        if let error = transcriptionManager.analysisError {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.primary.opacity(0.8))
                                    .lineSpacing(2)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.1 : 0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        }

                        // Live transcript card (only while actively recording)
                        if transcriptionManager.isTranscribing && !transcriptionManager.currentTranscription.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack(spacing: 12) {
                                    Image(systemName: "pencil.and.outline")
                                        .foregroundColor(Constants.coachingCardForeground)
                                        .font(.system(size: 14, weight: .bold))
                                    Text("TRANSCRIPTION")
                                        .font(.system(size: 11, weight: .black))
                                        .kerning(1.2)
                                        .foregroundColor(Constants.coachingCardForeground.opacity(0.8))

                                    Spacer()

                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 6, height: 6)
                                        .shimmer()
                                }

                                ScrollViewReader { proxy in
                                    ScrollView {
                                        Text(transcriptionManager.currentTranscription)
                                            .font(.body)
                                            .lineSpacing(8)
                                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.95) : .black.opacity(0.85))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .id("transcriptionBottom")
                                    }
                                    .frame(maxHeight: UIScreen.main.bounds.height * 0.3)
                                    .scrollIndicators(.hidden)
                                    .onChange(of: transcriptionManager.currentTranscription) { _ in
                                        withAnimation {
                                            proxy.scrollTo("transcriptionBottom", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                            .padding(32)
                            .background(
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .fill(Constants.coachingCardBackground)
                                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.12), radius: 20, x: 0, y: 10)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 32, style: .continuous)
                                    .stroke(Constants.coachingPrimaryColor.opacity(0.15), lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                        }
                    }
                    .padding(.bottom, 0)
                }
            }
            .blur(radius: showingSettings ? 10 : 0)
            .disabled(showingSettings)

            // Settings Overlay
            if showingSettings {
                ZStack {
                    Color.black.opacity(colorScheme == .dark ? 0.4 : 0.2)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showingSettings = false
                            }
                        }

                    SettingsView(isPresented: $showingSettings)
                        .frame(maxWidth: UIScreen.main.bounds.width * 0.9)
                        .fixedSize(horizontal: false, vertical: true)
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .shadow(color: Color.black.opacity(0.2), radius: 30, x: 0, y: 15)
                        .transition(.move(edge: .bottom).combined(with: .scale(scale: 0.95)).combined(with: .opacity))
                }
                .ignoresSafeArea()
                .zIndex(10)
            }
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
                .interactiveDismissDisabled(false)
        }
        .sheet(isPresented: $showingAnalysis) {
            if let analysisV2 = transcriptionManager.currentSession?.analysisV2, analysisV2.isValid {
                AnalysisViewV2(
                    analysisV2: analysisV2,
                    utterances: transcriptionManager.currentSession?.utterances ?? [],
                    debugAudio: {
                        #if DEBUG
                        return transcriptionManager.debugLastAudio
                        #else
                        return nil
                        #endif
                    }()
                )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
        }
        .onChange(of: shouldShowHistory) { newValue in
            if newValue {
                showingHistory = true
                shouldShowHistory = false
            }
        }
        .onChange(of: shouldStartRecording) { newValue in
            if newValue {
                transcriptionManager.liveActivityManager = liveActivityManager
                transcriptionManager.quickRecord()
                shouldStartRecording = false
            }
        }
        .onChange(of: transcriptionManager.analysisPhase) { newPhase in
            if newPhase == .complete && !hasAutoShownAnalysis && !ScreenshotMockData.isScreenshotMode {
                hasAutoShownAnalysis = true
                showingAnalysis = true
                Analytics.analysisViewed()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }

    // MARK: - Invalid Conversation View

    private var invalidConversationView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)

                Text(transcriptionManager.validationMessage ?? "We couldn't analyze this conversation.")
                    .font(.system(.subheadline, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary.opacity(0.85))
                    .lineSpacing(4)
                    .padding(.horizontal, 20)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.08 : 0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.orange.opacity(0.15), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                    transcriptionManager.clearTranscription()
                    transcriptionManager.currentSession = nil
                    transcriptionManager.analysisPhase = .idle
                    transcriptionManager.validationMessage = nil
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .bold))
                    Text("Try Again")
                        .font(.system(.subheadline, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Constants.coachingPrimaryColor)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Constants.coachingPrimaryColor.opacity(0.3), radius: 8, y: 4)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .transition(.opacity)
    }

    // MARK: - Processing Progress View

    private var processingProgressView: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 32) {
                // Animated progress circle
                ZStack {
                    Circle()
                        .stroke(Constants.coachingPrimaryColor.opacity(0.15), lineWidth: 8)
                        .frame(width: 80, height: 80)
                    Circle()
                        .trim(from: 0, to: processingProgress)
                        .stroke(
                            Constants.coachingPrimaryColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.5), value: processingProgress)

                    Text("\(Int(processingProgress * 100))%")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(Constants.coachingPrimaryColor)
                }

                // Status label
                Text(processingStatusText)
                    .font(.system(.subheadline, weight: .bold))
                    .foregroundColor(.primary.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.3), value: processingStatusText)

                // Step indicators
                VStack(spacing: 14) {
                    processingStep(
                        label: "Identifying speakers",
                        isActive: transcriptionManager.isDiarizing,
                        isComplete: !transcriptionManager.isDiarizing && transcriptionManager.isAnalyzing
                    )
                    processingStep(
                        label: "Analyzing conversation",
                        isActive: transcriptionManager.isAnalyzing && transcriptionManager.analysisPhase == .validating,
                        isComplete: transcriptionManager.isAnalyzing && transcriptionManager.analysisPhase == .analyzing
                    )
                    processingStep(
                        label: "Generating insights",
                        isActive: transcriptionManager.isAnalyzing && transcriptionManager.analysisPhase == .analyzing,
                        isComplete: false
                    )
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Constants.coachingCardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .transition(.opacity)
    }

    private var processingProgress: CGFloat {
        if transcriptionManager.isDiarizing {
            return 0.3
        } else if transcriptionManager.analysisPhase == .validating {
            return 0.5
        } else if transcriptionManager.analysisPhase == .analyzing {
            return 0.8
        } else {
            return 0.1
        }
    }

    private var processingStatusText: String {
        if transcriptionManager.isDiarizing {
            return "Identifying speakers..."
        } else if transcriptionManager.analysisPhase == .validating {
            return "Checking conversation..."
        } else {
            return "Analyzing conversation..."
        }
    }

    private func processingStep(label: String, isActive: Bool, isComplete: Bool) -> some View {
        HStack(spacing: 12) {
            ZStack {
                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Constants.coachingPrimaryColor)
                } else if isActive {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
            .frame(width: 22, height: 22)

            Text(label)
                .font(.system(.caption, weight: isActive ? .bold : .medium))
                .foregroundColor(isActive ? .primary : (isComplete ? Constants.coachingPrimaryColor : .secondary))

            Spacer()
        }
    }

    // MARK: - V2 Analysis Results View

    @ViewBuilder
    private func analysisResultsViewV2(analysisV2: SessionAnalysisV2) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Vibe archetype headline + score
                if let vibe = analysisV2.vibeCard {
                    VStack(spacing: 14) {
                        HStack(spacing: 14) {
                            VibeGauge(score: vibe.vibeScore)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(vibe.headlineArchetype)
                                    .font(.custom("DMSerifDisplay-Regular", size: 18))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)
                                Text("\(vibe.vibeScore)/100 coach score")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }
                    .padding(20)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Constants.coachingCardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Constants.coachingPrimaryColor.opacity(0.15), lineWidth: 1)
                    )
                }

                // Game summary
                if let coaching = analysisV2.coaching {
                    Text(coaching.gameSummary)
                        .font(.subheadline)
                        .foregroundColor(.primary.opacity(0.85))
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(Constants.coachingCardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.secondary.opacity(0.08), lineWidth: 1)
                        )

                    // Fouls detected badge row
                    HStack(spacing: 8) {
                        foulInlineBadge("Criticism", active: coaching.foulsDetected.criticism)
                        foulInlineBadge("Contempt", active: coaching.foulsDetected.contempt)
                        foulInlineBadge("Defensive", active: coaching.foulsDetected.defensiveness)
                        foulInlineBadge("Stonewalling", active: coaching.foulsDetected.stonewalling)
                    }
                }

                // Diarization toggle
                if let utterances = transcriptionManager.currentSession?.utterances, !utterances.isEmpty {
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
                        .accessibilityIdentifier("conversationToggle")
                        .buttonStyle(.plain)

                        if showingDiarization {
                            Divider()
                                .padding(.horizontal, 16)
                            ConversationView(utterances: utterances)
                                .frame(maxHeight: UIScreen.main.bounds.height * 0.4)
                                .padding(.bottom, 12)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Constants.coachingCardBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }

                // View Full Analysis button
                Button(action: {
                    showingAnalysis = true
                    Analytics.analysisViewed()
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }) {
                    HStack {
                        Text("View Full Analysis")
                            .font(.system(.subheadline, weight: .bold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(Constants.coachingPrimaryColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Constants.coachingPrimaryColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Constants.coachingPrimaryColor.opacity(0.2), lineWidth: 1)
                    )
                }

                // New Session button
                newSessionButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
        }
        .transition(.opacity)
    }

    private func foulInlineBadge(_ name: String, active: Bool) -> some View {
        Text(name)
            .font(.system(size: 9, weight: .black))
            .kerning(0.3)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(active ? Color.red.opacity(0.15) : Color.secondary.opacity(0.06))
            .foregroundColor(active ? .red : .secondary.opacity(0.4))
            .clipShape(Capsule())
    }

    private var newSessionButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                transcriptionManager.clearTranscription()
                transcriptionManager.currentSession = nil
                transcriptionManager.analysisPhase = .idle
                transcriptionManager.validationMessage = nil
                hasAutoShownAnalysis = false
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                Text("New Session")
                    .font(.system(.subheadline, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Constants.coachingPrimaryColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Constants.coachingPrimaryColor.opacity(0.3), radius: 8, y: 4)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Status Helpers

    private func getStatusTextForButton() -> String {
        if !transcriptionManager.isModelReady {
            return "Preparing..."
        } else if transcriptionManager.isTranscribing {
            return "Session in progress"
        } else if !transcriptionManager.currentTranscription.isEmpty {
            return "Tap to start a session"
        } else {
            return "Tap to start a session"
        }
    }

    private func shareTranscription() {
        Analytics.sessionExported()
        let activityVC = UIActivityViewController(
            activityItems: [transcriptionManager.currentTranscription],
            applicationActivities: nil
        )

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SharedHistoryManager())
        .environmentObject(AudioTranscriptionManager_iOS())
        .environmentObject(LiveActivityManager())
}
