import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var transcriptionManager: AudioTranscriptionManager_iOS
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @AppStorage("conversationMode") private var conversationMode = "couple"
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme

    @State private var viewState: SettingsViewState = .main
    enum SettingsViewState {
        case main
        case voiceProfiles
    }
    
    var body: some View {
        ZStack {
            Constants.adaptiveBackgroundColor
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    if viewState != .main {
                        Button(action: { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                viewState = .main
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Settings")
                                    .font(.system(.subheadline, weight: .bold))
                            }
                            .foregroundColor(Constants.therapyPrimaryColor)
                        }
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Settings")
                                .font(.custom("DMSerifDisplay-Regular", size: 20))
                        }
                        .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: { 
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .frame(height: 60)
                
                ZStack {
                    Color.clear // ensures ZStack fills available space
                    if viewState == .main {
                        mainSettingsView
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    } else if viewState == .voiceProfiles {
                        VoiceProfilesSettingsView()
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                }
            }
        }
    }

    private var mainSettingsView: some View {
            VStack(spacing: 32) {
                VStack(spacing: 24) {
                    // Appearance Row — tap to toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            appearanceMode = nextAppearanceMode(after: appearanceMode)
                        }
                    }) {
                        SettingsNoteRow(
                            title: "Appearance",
                            value: appearanceName(for: appearanceMode),
                            icon: appearanceIcon(for: appearanceMode)
                        )
                    }

                    // Conversation Mode Row — simple toggle
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            conversationMode = conversationMode == "solo" ? "couple" : "solo"
                        }
                    }) {
                        SettingsNoteRow(
                            title: "Mode",
                            value: conversationMode == "solo" ? "Solo" : "Couple",
                            icon: conversationMode == "solo" ? "person" : "person.2"
                        )
                    }

                    // Shortcuts Row
                    Link(destination: URL(string: "shortcuts://")!) {
                        SettingsNoteRow(
                            title: "Shortcuts",
                            value: "Create Shortcuts",
                            icon: "square.on.square"
                        )
                    }

                    // Voice Profiles Row
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            viewState = .voiceProfiles
                        }
                    }) {
                        SettingsNoteRow(
                            title: "Voice Profiles",
                            value: voiceProfilesSummary,
                            icon: "person.wave.2"
                        )
                    }

                }
                .padding(.top, 24)

                // Footer
                VStack(spacing: 8) {
                    Link(destination: URL(string: "https://mend.ly")!) {
                        Text("Privacy & Support")
                            .font(.system(.caption, weight: .bold))
                            .foregroundColor(.secondary)
                    }

                    Text("v2.0.0")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.secondary.opacity(0.3))
                }
                .padding(.top, 20)
                .padding(.bottom, 28)
            }
            .padding(.horizontal, 32)
    }
    
    private func nextAppearanceMode(after current: String) -> String {
        return current == "light" ? "dark" : "light"
    }

    private func appearanceIcon(for mode: String) -> String {
        return mode == "dark" ? "moon" : "sun.max"
    }

    private var voiceProfilesSummary: String {
        let count = SpeakerProfile.loadAll().count
        if count == 0 { return "None" }
        return "\(count) profile\(count == 1 ? "" : "s")"
    }

    private func appearanceName(for mode: String) -> String {
        return mode == "dark" ? "Dark" : "Light"
    }
}

struct SettingsNoteRow: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack {
            Label {
                Text(title)
                    .font(.system(.body, weight: .medium))
            } icon: {
                Image(systemName: icon)
                    .font(.system(size: 16))
            }
            
            Spacer()
            
            Text(value)
                .font(.system(.subheadline, weight: .bold))
                .foregroundColor(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .black))
                .foregroundColor(.secondary.opacity(0.3))
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Voice Profiles Settings

struct VoiceProfilesSettingsView: View {
    @State private var profiles: [SpeakerProfile] = SpeakerProfile.loadAll()
    @State private var isAddingProfile = false
    @State private var profileName = ""
    @State private var isRecording = false
    @State private var isProcessing = false
    @State private var recordingDone = false
    @State private var audioEngine: AVAudioEngine?
    @State private var recordedSamples: [Float] = []
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: SpeakerProfile?

    var body: some View {
        VStack(spacing: 20) {
            if profiles.isEmpty && !isAddingProfile {
                VStack(spacing: 12) {
                    Image(systemName: "person.wave.2")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No voice profiles yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
            }

            // Existing profiles
            ForEach(profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.system(.body, weight: .medium))
                        Text(profile.date, style: .date)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        profileToDelete = profile
                        showDeleteConfirmation = true
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                            .foregroundColor(.red.opacity(0.8))
                            .padding(8)
                            .background(Color.red.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(12)
            }

            // Add profile inline flow
            if isAddingProfile {
                VStack(spacing: 14) {
                    TextField("Name", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)

                    Text("Read aloud: \"The quick brown fox jumps over the lazy dog\"")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    if isProcessing {
                        ProgressView("Extracting voice profile...")
                            .font(.caption)
                            .padding()
                    } else if recordingDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                            .padding()
                    } else {
                        Button(action: toggleRecording) {
                            HStack(spacing: 8) {
                                Image(systemName: isRecording ? "stop.circle.fill" : "mic.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(isRecording ? .red : Constants.therapyPrimaryColor)
                                Text(isRecording ? "Tap to stop" : "Tap to record")
                                    .font(.subheadline)
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(20)
                        }
                        .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                        .opacity(profileName.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1.0)
                    }

                    if !isRecording && !isProcessing && !recordingDone {
                        Button("Cancel") {
                            withAnimation {
                                isAddingProfile = false
                                profileName = ""
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
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
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundColor(Constants.therapyPrimaryColor)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Constants.therapyPrimaryColor.opacity(0.1))
                    .cornerRadius(20)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    withAnimation {
                        profiles.removeAll { $0.id == profile.id }
                        SpeakerProfile.saveAll(profiles)
                        FluidAudioManager.shared.reloadProfiles()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let profile = profileToDelete {
                Text("Remove \(profile.name)'s voice profile?")
            }
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
                    isProcessing = false
                    recordingDone = true

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

