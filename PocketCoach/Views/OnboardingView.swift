import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var hasRequestedMicPermission = false
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var fluidAudioManager = FluidAudioManager.shared

    let totalPages = 4

    var body: some View {
        ZStack {
            // Background gradient - calming teal
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.29, green: 0.48, blue: 0.41),
                    Color(red: 0.42, green: 0.62, blue: 0.54)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                TabView(selection: $currentPage) {
                    WelcomePage()
                        .tag(0)

                    FeaturesPage()
                        .tag(1)

                    PermissionsPage(
                        hasRequestedMicPermission: $hasRequestedMicPermission
                    )
                    .tag(2)

                    GetStartedPage(
                        isModelReady: fluidAudioManager.isModelReady,
                        isInitializing: fluidAudioManager.isInitializing,
                        onComplete: completeOnboarding
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color.white : Color.white.opacity(0.5))
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentPage == index ? 1.2 : 1.0)
                            .animation(.spring(), value: currentPage)
                    }
                }
                .padding(.bottom, 40)

                // Navigation buttons
                if currentPage < totalPages - 1 {
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        HStack {
                            Text("Next")
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .foregroundColor(Color(red: 0.29, green: 0.48, blue: 0.41))
                        .padding(.horizontal, 30)
                        .padding(.vertical, 15)
                        .background(Color.white)
                        .cornerRadius(25)
                    }
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        Analytics.registrationCompleted()
        withAnimation(.spring()) {
            isPresented = false
        }
    }
}

// MARK: - Onboarding Pages

struct WelcomePage: View {
    @State private var logoScale: CGFloat = 0.0
    @State private var textOpacity: Double = 0.0

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            Image("AppLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 150, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 32))
                .scaleEffect(logoScale)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        logoScale = 1.0
                    }
                }

            VStack(spacing: 15) {
                Text("Welcome to")
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.9))

                Text("PocketCoach")
                    .font(.custom("DMSerifDisplay-Regular", size: 42))
                    .foregroundColor(.white)

                Text("Better conversations start here")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .opacity(textOpacity)
            .onAppear {
                withAnimation(.easeIn(duration: 0.8).delay(0.3)) {
                    textOpacity = 1.0
                }
            }

            Spacer()
            Spacer()
        }
    }
}

struct FeaturesPage: View {
    @State private var features: [Bool] = [false, false, false, false]

    let featureList = [
        ("mic.fill", "Record Conversations", "Capture sessions and revisit them anytime"),
        ("person.2.wave.2", "Know Who Said What", "See each partner's words side by side"),
        ("brain.head.profile", "Understand Patterns", "Spot communication habits and grow together"),
        ("lock.shield.fill", "Private & Secure", "Everything stays on your device")
    ]

    var body: some View {
        VStack(spacing: 30) {
            Text("How It Works")
                .font(.custom("DMSerifDisplay-Regular", size: 34))
                .foregroundColor(.white)
                .padding(.top, 60)

            VStack(spacing: 25) {
                ForEach(0..<featureList.count, id: \.self) { index in
                    HStack(spacing: 20) {
                        Image(systemName: featureList[index].0)
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .frame(width: 50)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(featureList[index].1)
                                .font(.headline)
                                .foregroundColor(.white)

                            Text(featureList[index].2)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 40)
                    .opacity(features[index] ? 1.0 : 0.0)
                    .offset(x: features[index] ? 0 : -50)
                }
            }
            .onAppear {
                for i in 0..<features.count {
                    withAnimation(.spring().delay(Double(i) * 0.15)) {
                        features[i] = true
                    }
                }
            }

            Spacer()
        }
    }
}

struct PermissionsPage: View {
    @Binding var hasRequestedMicPermission: Bool

    var body: some View {
        VStack(spacing: 40) {
            Text("Quick Setup")
                .font(.custom("DMSerifDisplay-Regular", size: 34))
                .foregroundColor(.white)
                .padding(.top, 60)

            VStack(spacing: 30) {
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone Access",
                    description: "Required to record coaching sessions",
                    isEnabled: hasRequestedMicPermission,
                    action: requestMicrophonePermission
                )
            }
            .padding(.horizontal, 30)

            Spacer()

            Text("You can change these anytime in Settings")
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))
                .padding(.bottom, 40)
        }
    }

    private func requestMicrophonePermission() {
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                hasRequestedMicPermission = granted
            }
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }

            Spacer()

            Button(action: action) {
                Text(isEnabled ? "Enabled" : "Enable")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isEnabled ? Color(red: 0.30, green: 0.56, blue: 0.54) : .white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(isEnabled ? Color.white : Color.white.opacity(0.3))
                    .cornerRadius(15)
            }
            .disabled(isEnabled)
        }
        .padding()
        .background(Color.white.opacity(0.1))
        .cornerRadius(15)
    }
}

struct VoiceProfilesPage: View {
    @Binding var profileCount: Int
    @State private var profiles: [SpeakerProfile] = SpeakerProfile.loadAll()
    @State private var isAddingProfile = false
    @State private var profileName = ""
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var recordingDone = false
    @State private var audioEngine: AVAudioEngine?
    @State private var recordedSamples: [Float] = []

    var body: some View {
        VStack(spacing: 25) {
            Text("Voice Profiles")
                .font(.custom("DMSerifDisplay-Regular", size: 34))
                .foregroundColor(.white)
                .padding(.top, 60)

            Text("Add a voice profile for speaker identification")
                .font(.body)
                .foregroundColor(.white.opacity(0.8))

            // Added profiles list
            if !profiles.isEmpty {
                VStack(spacing: 12) {
                    ForEach(profiles) { profile in
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text(profile.name)
                                .font(.headline)
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .padding()
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 30)
            }

            if isAddingProfile {
                // Inline recording flow
                VStack(spacing: 16) {
                    TextField("Name", text: $profileName)
                        .textFieldStyle(.plain)
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                        .accentColor(.white)

                    Text("Read aloud: \"The quick brown fox jumps over the lazy dog\"")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)

                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.2)
                            .padding()
                        Text("Extracting voice profile...")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    } else if recordingDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40))
                            .foregroundColor(.green)
                            .padding()
                    } else {
                        Button(action: toggleRecording) {
                            VStack(spacing: 8) {
                                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(isRecording ? .red : .white)
                                    .scaleEffect(isRecording ? 1.2 : 1.0)
                                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isRecording)
                                Text(isRecording ? "Tap to stop" : "Tap to record")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(profileName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                    }
                }
                .padding(.horizontal, 30)
            } else {
                Button(action: {
                    withAnimation {
                        isAddingProfile = true
                        profileName = ""
                        recordingDone = false
                    }
                }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Profile")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(20)
                }
            }

            Spacer()
        }
    }

    private func toggleRecording() {
        if isRecording {
            stopProfileRecording()
        } else {
            startProfileRecording()
        }
    }

    private func startProfileRecording() {
        recordedSamples.removeAll()
        let engine = AVAudioEngine()
        audioEngine = engine

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)

            let inputNode = engine.inputNode
            let hardwareFormat = inputNode.inputFormat(forBus: 0)

            let recordingFormat: AVAudioFormat
            if hardwareFormat.channelCount == 1 {
                recordingFormat = hardwareFormat
            } else {
                guard let monoFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: hardwareFormat.sampleRate,
                    channels: 1,
                    interleaved: false
                ) else { return }
                recordingFormat = monoFormat
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [self] buffer, _ in
                if let converted = AudioProcessing.convertToMono16kHz(buffer: buffer, from: buffer.format, targetSampleRate: 16000) {
                    DispatchQueue.main.async {
                        self.recordedSamples.append(contentsOf: converted)
                    }
                }
            }

            try engine.start()
            isRecording = true

            // Auto-stop after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
                if self.isRecording {
                    self.stopProfileRecording()
                }
            }
        } catch {
            #if DEBUG
            print("Failed to start profile recording: \(error)")
            #endif
        }
    }

    private func stopProfileRecording() {
        isRecording = false
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        try? AVAudioSession.sharedInstance().setActive(false)

        let samples = recordedSamples
        guard samples.count >= 16000 else {
            // Less than 1 second of audio — not enough
            #if DEBUG
            print("Voice profile recording too short: \(samples.count) samples")
            #endif
            return
        }

        isProcessing = true

        Task {
            do {
                let embedding = try await FluidAudioManager.shared.extractEmbedding(from: samples)
                let profile = SpeakerProfile(
                    name: profileName.trimmingCharacters(in: .whitespaces),
                    embedding: embedding
                )

                await MainActor.run {
                    profiles.append(profile)
                    SpeakerProfile.saveAll(profiles)
                    FluidAudioManager.shared.reloadProfiles()
                    profileCount = profiles.count
                    isProcessing = false
                    recordingDone = true

                    // Reset for next profile after a brief delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation {
                            isAddingProfile = false
                            profileName = ""
                            recordingDone = false
                        }
                    }
                }
            } catch {
                #if DEBUG
                print("Failed to extract voice embedding: \(error)")
                #endif
                await MainActor.run {
                    isProcessing = false
                }
            }
        }
    }
}

struct GetStartedPage: View {
    let isModelReady: Bool
    let isInitializing: Bool
    let onComplete: () -> Void
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            if isInitializing {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .frame(width: 100, height: 100)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.white)
                    .scaleEffect(isAnimating ? 1.0 : 0.0)
                    .onAppear {
                        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                            isAnimating = true
                        }
                    }
            }

            VStack(spacing: 20) {
                Text(isInitializing ? "Preparing AI Models..." : "You're All Set!")
                    .font(.custom("DMSerifDisplay-Regular", size: 34))
                    .foregroundColor(.white)

                Text(isInitializing
                     ? "This only happens once"
                     : "Start a session by tapping\nthe record button")
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button(action: onComplete) {
                Text("Start Using PocketCoach")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.29, green: 0.48, blue: 0.41))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isInitializing ? Color.white.opacity(0.5) : Color.white)
                    .cornerRadius(25)
                    .shadow(color: .black.opacity(0.1), radius: 10, y: 5)
            }
            .disabled(isInitializing)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }
}
