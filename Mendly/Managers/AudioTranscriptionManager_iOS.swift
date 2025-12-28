import Foundation
import AVFoundation
import FluidAudio
import SwiftUI
import Combine

@MainActor
class AudioTranscriptionManager_iOS: ObservableObject {
    @AppStorage("conversationMode") private var conversationMode = "couple"
    @AppStorage("diarizationMode") private var diarizationMode = "cloud"
    @Published var isTranscribing = false
    @Published var currentTranscription = ""
    @Published var audioLevel: Float = 0.0
    @Published var useVAD = true // Always on for better experience
    @Published var isModelLoading = false
    @Published var isModelReady = false
    @Published var currentSession: TherapySession?
    @Published var isDiarizing = false
    @Published var isAnalyzing = false
    @Published var analysisError: String?
    @Published var analysisPhase: AnalysisPhase = .idle
    @Published var validationMessage: String?

    enum AnalysisPhase { case idle, validating, analyzing, complete, invalidConversation }

    weak var historyManager: SharedHistoryManager?
    weak var liveActivityManager: LiveActivityManager?

    let fluidAudioManager = FluidAudioManager.shared
    private var audioEngine: AVAudioEngine?
    private var speechBuffer: [Float] = []         // VAD-gated speech for real-time transcription (drained as chunks are processed)
    private var diarizationBuffer: [Float] = []    // Full audio for post-recording diarization (append-only)
    private let bufferQueue = DispatchQueue(label: "com.reactnativenerd.mendly.bufferQueue", attributes: .concurrent)
    private var transcriptionTask: Task<Void, Never>?
    private var vadTranscriptionTask: Task<Void, Never>?

    // VAD
    private var vadManager: VADManager_iOS?
    private var isSpeechActive = false
    private var speechStartTime: TimeInterval?
    private var accumulatedVADText = ""
    private var lastProcessedSampleCount = 0

    // Audio settings
    #if DEBUG
    /// Raw audio retained after diarization for debug comparison (cloud vs on-device)
    var debugLastAudio: [Float]?
    #endif
    private let sampleRate: Double = Constants.sampleRate
    private let maxBufferSamples = Constants.maxBufferSamples
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.useVAD = true // Enable VAD for better transcription accuracy
        // Don't request permission on init - wait until user tries to record

        // Initialize model state
        self.isModelReady = fluidAudioManager.isModelReady
        self.isModelLoading = fluidAudioManager.isInitializing

        // Reactively sync state from FluidAudioManager so pre-loading during onboarding is reflected
        // Use $published properties (fires after change) instead of objectWillChange (fires before)
        Publishers.CombineLatest3(
            fluidAudioManager.$asrManager,
            fluidAudioManager.$models,
            fluidAudioManager.$isInitializing
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] asrManager, models, isInitializing in
            guard let self else { return }
            self.isModelReady = asrManager != nil && models != nil && !isInitializing
            self.isModelLoading = isInitializing
        }
        .store(in: &cancellables)

        #if DEBUG
        print("AudioTranscriptionManager_iOS initialized, VAD: \(useVAD), ModelReady: \(isModelReady), ModelLoading: \(isModelLoading)")
        #endif
    }
    
    var selectedModel: String {
        get {
            fluidAudioManager.selectedModel?.id ?? "v2"
        }
        set {
            Task {
                let model = fluidAudioManager.availableModels.first { $0.id == newValue }
                if let model = model {
                    try? await fluidAudioManager.selectModel(model)
                }
            }
        }
    }
    
    
    func initializeModelIfNeeded() async throws {
        // Check if already ready
        if fluidAudioManager.isModelReady {
            isModelReady = true
            isModelLoading = false
            return
        }
        
        // Start loading
        isModelLoading = true
        isModelReady = false
        
        do {
            try await fluidAudioManager.initializeASRIfNeeded()
            
            // Update our state based on FluidAudioManager state
            isModelReady = fluidAudioManager.isModelReady
            isModelLoading = false
            
            print("Model initialization completed - ModelReady: \(isModelReady)")
        } catch {
            // Failed to load
            isModelLoading = false
            isModelReady = false
            print("Model initialization failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Permissions

    private func checkMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        #if DEBUG
        print("Current microphone permission status: \(status)")
        #endif
        
        switch status {
        case .notDetermined:
            #if DEBUG
            print("Requesting microphone permission...")
            #endif
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            #if DEBUG
            print("Permission granted: \(granted)")
            #endif
            return granted
        case .authorized:
            #if DEBUG
            print("Microphone permission already authorized")
            #endif
            return true
        case .denied:
            #if DEBUG
            print("Microphone permission denied")
            #endif
            return false
        case .restricted:
            #if DEBUG
            print("Microphone permission restricted")
            #endif
            return false
        @unknown default:
            #if DEBUG
            print("Unknown microphone permission status")
            #endif
            return false
        }
    }
    
    
    // MARK: - Recording Control
    
    func startRecording() {
        guard !isTranscribing else { return }
        
        #if DEBUG
        print("Starting recording...")
        #endif
        
        // First ensure model is ready, then check microphone permission
        Task {
            // Initialize model if needed
            if !isModelReady {
                #if DEBUG
                print("Model not ready, initializing...")
                #endif
                do {
                    try await initializeModelIfNeeded()
                } catch {
                    #if DEBUG
                    print("Failed to initialize model: \(error)")
                    #endif
                    return
                }
            }
            
            let hasPermission = await checkMicrophonePermission()
            
            // Initialize offline diarizer in parallel (non-blocking for recording start)
            // Reset if already initialized (mode may have changed since last recording)
            let speakerCount = self.conversationMode == "solo" ? 1 : 2
            self.fluidAudioManager.resetOfflineDiarizer()
            Task {
                do {
                    try await self.fluidAudioManager.initializeOfflineDiarizerIfNeeded(speakerCount: speakerCount)
                } catch {
                    #if DEBUG
                    print("Failed to initialize offline diarizer: \(error) — will fall back to plain transcription")
                    #endif
                }
            }

            await MainActor.run {
                if hasPermission {
                    #if DEBUG
                    print("Microphone permission granted - starting actual recording")
                    #endif

                    // Haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()

                    isTranscribing = true

                    // Clear previous transcription and buffers for new session
                    currentTranscription = ""
                    accumulatedVADText = ""
                    lastProcessedSampleCount = 0
                    isSpeechActive = false
                    currentSession = TherapySession(startedAt: Date())
                    bufferQueue.async(flags: .barrier) {
                        self.speechBuffer.removeAll()
                        self.diarizationBuffer.removeAll()
                    }

                    // Enable background recording
                    enableBackgroundTranscription()

                    // Start Live Activity
                    liveActivityManager?.startRecordingActivity()

                    // Initialize VAD if needed
                    if useVAD {
                        vadManager = VADManager_iOS()
                        vadManager?.delegate = self
                    }

                    // Start audio capture
                    startAudioCapture()

                    // Start transcription loop only if VAD is disabled
                    if !useVAD {
                        startTranscriptionLoop()
                    }
                } else {
                    #if DEBUG
                    print("Microphone permission denied - cannot record")
                    #endif
                    ErrorHandler.shared.handle(MendlyError.microphonePermissionDenied)
                }
            }
        }
    }
    
    func stopRecording() {
        guard isTranscribing else { return }
        
        // Haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()
        
        isTranscribing = false

        // Cancel all in-flight transcription/VAD tasks FIRST to avoid racing with diarization
        transcriptionTask?.cancel()
        vadTranscriptionTask?.cancel()
        isSpeechActive = false

        // Reset VAD without processing its final chunk (diarization replaces everything)
        vadManager?.reset()
        vadManager = nil

        stopAudioCapture()

        // Save the live transcription as fallback in case diarization fails
        let liveTranscript = currentTranscription

        // Process remaining audio and run diarization
        Task {
            // Brief pause to let any in-flight ASR calls finish/cancel
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Run full-recording diarization (replaces session utterances)
            await runPostRecordingDiarization()

            // Finalize session
            currentSession?.endedAt = Date()

            // Update currentTranscription from session for clipboard/history
            if let session = currentSession, !session.utterances.isEmpty {
                currentTranscription = session.formattedTranscript
            } else {
                // Diarization produced nothing — restore live transcript
                currentTranscription = liveTranscript
            }

            // Save to history if V2 analysis completed (valid conversation)
            let sessionDuration: Int? = currentSession.map { Int(Date().timeIntervalSince($0.startedAt)) }
            if let analysisV2 = currentSession?.analysisV2, analysisV2.isValid {
                if let duration = sessionDuration {
                    Analytics.sessionCompleted(durationSeconds: duration)
                }
                historyManager?.add(currentTranscription, analysisV2: analysisV2, durationSeconds: sessionDuration, utterances: currentSession?.utterances)
            }

            if !currentTranscription.isEmpty {
                liveActivityManager?.stopRecordingActivity(finalLength: currentTranscription.count)
            }
        }
    }
    
    // MARK: - Audio Capture
    
    private func convertToMono16kHz(buffer: AVAudioPCMBuffer, from format: AVAudioFormat) -> [Float]? {
        return AudioProcessing.convertToMono16kHz(buffer: buffer, from: format, targetSampleRate: sampleRate)
    }
    
    private func startAudioCapture() {
        // Clean up any existing engine
        stopAudioCapture()
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        // Configure audio session first
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            #if DEBUG
            print("Audio session configured: \(audioSession.sampleRate) Hz")
            #endif
        } catch {
            #if DEBUG
            print("Failed to set up audio session: \(error)")
            #endif
            return
        }
        
        let inputNode = audioEngine.inputNode
        
        // Use the hardware's native format instead of forcing a specific sample rate
        let hardwareFormat = inputNode.inputFormat(forBus: 0)
        #if DEBUG
        print("Hardware input format: \(hardwareFormat)")
        #endif
        
        // Create a recording format that matches the hardware but ensures mono output
        let recordingFormat: AVAudioFormat
        if hardwareFormat.channelCount == 1 {
            // Already mono, use hardware format directly
            recordingFormat = hardwareFormat
        } else {
            // Convert to mono but keep the same sample rate
            guard let monoFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hardwareFormat.sampleRate,
                channels: 1,
                interleaved: false
            ) else {
                #if DEBUG
                print("Failed to create mono recording format")
                #endif
                return
            }
            recordingFormat = monoFormat
        }
        
        #if DEBUG
        print("Using recording format: \(recordingFormat)")
        #endif
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        
        do {
            try audioEngine.start()
            #if DEBUG
            print("Audio engine started successfully")
            #endif
        } catch {
            #if DEBUG
            print("Failed to start audio engine: \(error)")
            #endif
        }
    }
    
    private func stopAudioCapture() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        
        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            #if DEBUG
            print("Failed to deactivate audio session: \(error)")
            #endif
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let floatData = buffer.floatChannelData else { return }
        
        let channelCount = Int(buffer.format.channelCount)
        let frameCount = Int(buffer.frameLength)
        
        // Calculate audio level for visualization
        let normalizedLevel = AudioProcessing.calculateNormalizedAudioLevel(from: buffer)
        
        DispatchQueue.main.async {
            self.audioLevel = normalizedLevel
        }
        
        // Convert to mono 16kHz for FluidAudio
        if let convertedSamples = self.convertToMono16kHz(buffer: buffer, from: buffer.format) {
            #if DEBUG
            let maxAmplitude = convertedSamples.map { abs($0) }.max() ?? 0
            if buffer.frameLength > 0 && Int(buffer.frameLength) % 1000 == 0 {
                print("Audio buffer: \(buffer.frameLength) frames, converted: \(convertedSamples.count) samples, max amplitude: \(maxAmplitude)")
            }
            #endif

            // Accumulate into diarization buffer (always, regardless of VAD)
            bufferQueue.async(flags: .barrier) {
                self.diarizationBuffer.append(contentsOf: convertedSamples)
            }

            // Process with VAD if enabled
            if let vadManager = vadManager {
                // Create a buffer from the converted samples
                guard let format = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: self.sampleRate,
                    channels: 1,
                    interleaved: false
                ) else { return }
                
                guard let vadBuffer = AVAudioPCMBuffer(
                    pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(convertedSamples.count)
                ) else { return }
                
                vadBuffer.frameLength = AVAudioFrameCount(convertedSamples.count)
                
                // Copy samples to buffer
                if let channelData = vadBuffer.floatChannelData {
                    convertedSamples.withUnsafeBufferPointer { sourcePtr in
                        guard let baseAddress = sourcePtr.baseAddress else { return }
                        channelData[0].update(from: baseAddress, count: convertedSamples.count)
                    }
                }
                
                // Process with VAD
                let isSpeech = vadManager.processAudioBuffer(vadBuffer, at: CACurrentMediaTime())
                
                #if DEBUG
                if convertedSamples.count > 0 && Int(convertedSamples.count) % 16000 == 0 {
                    print("VAD processing: \(convertedSamples.count) samples, speech detected: \(isSpeech)")
                }
                #endif
                
                if isSpeech {
                    bufferQueue.async(flags: .barrier) {
                        self.speechBuffer.append(contentsOf: convertedSamples)
                        // Prevent speech buffer overflow
                        if self.speechBuffer.count > self.maxBufferSamples {
                            let excess = self.speechBuffer.count - self.maxBufferSamples
                            self.speechBuffer.removeFirst(excess)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Transcription
    
    private func startTranscriptionLoop() {
        transcriptionTask = Task {
            // Initial delay to accumulate audio
            try? await Task.sleep(nanoseconds: Constants.transcriptionInitialDelay)
            
            while !Task.isCancelled && isTranscribing {
                await processAudioChunk()
                try? await Task.sleep(nanoseconds: Constants.transcriptionInterval)
            }
        }
    }
    
    private func processAudioChunk() async {
        // Thread-safe buffer access — uses diarizationBuffer as fallback (non-VAD mode)
        let (shouldProcess, samplesToProcess) = bufferQueue.sync {
            if let chunk = AudioProcessing.extractOptimalChunk(from: &diarizationBuffer, sampleRate: sampleRate) {
                #if DEBUG
                print("Processing audio chunk with \(chunk.count) samples")
                #endif
                return (true, chunk)
            } else {
                #if DEBUG
                print("Not enough samples yet: \(diarizationBuffer.count)")
                #endif
                return (false, [Float]())
            }
        }

        if shouldProcess {
            await transcribe(samples: samplesToProcess)
        }
    }

    private func transcribe(samples: [Float], isPartial: Bool = false) async {
        #if DEBUG
        print("Transcribing \(samples.count) samples...")
        #endif
        
        // Initialize ASR on demand
        do {
            // Check if model is already being loaded
            if isModelLoading {
                #if DEBUG
                print("Model is still downloading, skipping transcription")
                #endif
                return
            }
            
            try await initializeModelIfNeeded()
        } catch {
            #if DEBUG
            print("Failed to initialize ASR: \(error)")
            #endif
            return
        }
        
        guard let asrManager = fluidAudioManager.asrManager else {
            #if DEBUG
            print("FluidAudio ASR Manager not available")
            #endif
            return
        }
        
        do {
            // Direct transcription - VAD is already handled in processAudioBuffer
            let result = try await asrManager.transcribe(samples)
            
            if isPartial {
                // For partial transcriptions during VAD
                await MainActor.run {
                    self.currentTranscription = self.accumulatedVADText + (self.accumulatedVADText.isEmpty ? "" : " ") + result.text + "..."
                }
            } else {
                updateTranscription(with: result.text)
            }
        } catch {
            #if DEBUG
            print("Transcription error: \(error)")
            #endif
        }
    }
    
    private func cleanTranscriptionText(_ text: String) -> String {
        return TranscriptionTextProcessor.cleanTranscriptionText(text)
    }
    
    private func updateTranscription(with text: String) {
        guard !text.isEmpty else { 
            #if DEBUG
            print("Received empty transcription text")
            #endif
            return 
        }
        
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedText = cleanTranscriptionText(trimmedText)
        
        // Skip if cleaned text is empty or just punctuation
        guard TranscriptionTextProcessor.isValidTranscriptionText(cleanedText) else {
            return
        }
        
        #if DEBUG
        print("Updating transcription with cleaned text: \(cleanedText)")
        #endif
        
        currentTranscription = (currentTranscription + " " + cleanedText).trimmingCharacters(in: .whitespaces)
        
        // Trim if too long
        currentTranscription = TranscriptionTextProcessor.truncateTranscription(
            currentTranscription,
            maxLength: Constants.maxTranscriptionLength
        )
        
        // Update Live Activity
        liveActivityManager?.updateTranscriptionLength(currentTranscription.count)
    }
    
    // MARK: - Post-Recording Diarization

    /// Run diarization on the full recording after the user stops.
    /// Uses a single-pass diarization with pre-loaded speaker profiles so the diarizer's
    /// SpeakerManager assigns matching profile names as speaker IDs automatically.
    /// Unknown speakers get auto-generated IDs → labeled "Other".
    private func runPostRecordingDiarization() async {
        let fullAudio: [Float] = bufferQueue.sync {
            let buf = diarizationBuffer
            diarizationBuffer.removeAll()
            return buf
        }

        #if DEBUG
        debugLastAudio = fullAudio
        #endif

        let totalSeconds = Double(fullAudio.count) / sampleRate
        guard fullAudio.count >= Int(sampleRate * 2) else {
            #if DEBUG
            print("Diarization skipped: only \(String(format: "%.1f", totalSeconds))s of audio")
            #endif
            return
        }

        guard let asrManager = fluidAudioManager.asrManager else {
            #if DEBUG
            print("ASR not available for post-recording diarization")
            #endif
            return
        }

        isDiarizing = true

        #if DEBUG
        print("=== POST-RECORDING DIARIZATION ===")
        print("Diarization mode: \(diarizationMode)")
        print("Full audio: \(String(format: "%.1f", totalSeconds))s (\(fullAudio.count) samples)")
        #endif

        do {
            let isSoloMode = conversationMode == "solo"
            let savedProfiles = SpeakerProfile.loadAll()
            let savedProfileNames = Set(savedProfiles.map { $0.name })

            let speakerSegments: [TimedSpeakerSegment]

            if diarizationMode == "cloud" {
                // Cloud diarization via pyannote.ai Precision-2
                do {
                    let numSpeakers = isSoloMode ? 1 : 2
                    var cloudSegments = try await PyAnnoteCloudService.shared.diarize(
                        audio: fullAudio,
                        sampleRate: sampleRate,
                        numSpeakers: numSpeakers
                    )

                    // Merge to 2 speakers if cloud over-segmented in couple mode
                    if !isSoloMode {
                        let cloudSpeakerCount = Set(cloudSegments.map { $0.speakerId }).count
                        if cloudSpeakerCount > 2 {
                            let diarization = Self.mergeToTwoSpeakers(DiarizationResult(segments: cloudSegments))
                            cloudSegments = diarization.segments
                            #if DEBUG
                            let postMergeSpeakers = Set(cloudSegments.map { $0.speakerId })
                            print("[PyAnnote] Cluster merge: \(cloudSpeakerCount) → \(postMergeSpeakers.count) speakers")
                            #endif
                        }
                    }

                    speakerSegments = cloudSegments

                    #if DEBUG
                    let finalSpeakers = Set(speakerSegments.map { $0.speakerId })
                    print("[PyAnnote] ✅ CLOUD diarization used. Final speakers: \(finalSpeakers.sorted())")
                    #endif
                } catch {
                    // Cloud failed — fall back to on-device
                    #if DEBUG
                    print("[PyAnnote] ⚠️ Cloud diarization FAILED: \(error). Falling back to on-device.")
                    #endif
                    speakerSegments = try await runOnDeviceDiarizationPipeline(
                        audio: fullAudio,
                        isSoloMode: isSoloMode,
                        savedProfiles: savedProfiles,
                        savedProfileNames: savedProfileNames
                    )
                }
            } else {
                // On-device diarization (default)
                #if DEBUG
                print("[Diarization] Using ON-DEVICE diarization (mode=\(diarizationMode))")
                #endif
                speakerSegments = try await runOnDeviceDiarizationPipeline(
                    audio: fullAudio,
                    isSoloMode: isSoloMode,
                    savedProfiles: savedProfiles,
                    savedProfileNames: savedProfileNames
                )
            }

            // Step 1: Run ASR in 30s chunks to get token timings, then align with speaker segments
            let chunkSize = Int(sampleRate * Constants.diarizationChunkSeconds)
            var allUtterances: [SpeakerUtterance] = []
            var offset = 0

            while offset < fullAudio.count {
                let end = min(offset + chunkSize, fullAudio.count)
                let chunk = Array(fullAudio[offset..<end])
                let chunkTimeOffset = Double(offset) / sampleRate

                // Skip very short trailing chunks
                guard chunk.count >= Int(sampleRate * 0.5) else { break }

                do {
                    let asrResult = try await asrManager.transcribe(chunk)

                    #if DEBUG
                    print("ASR chunk \(offset/chunkSize): offset=\(String(format: "%.1f", chunkTimeOffset))s, tokens=\(asrResult.tokenTimings?.count ?? 0), text=\(asrResult.text.prefix(50))...")
                    #endif

                    let utterances = SpeakerTextAligner.align(
                        tokenTimings: asrResult.tokenTimings,
                        text: asrResult.text,
                        speakerSegments: speakerSegments,
                        chunkTimeOffset: chunkTimeOffset
                    )

                    allUtterances.append(contentsOf: utterances)
                } catch {
                    #if DEBUG
                    print("ASR chunk at \(String(format: "%.1f", chunkTimeOffset))s failed: \(error) — skipping")
                    #endif
                }

                offset = end
            }

            // Step 2: Merge consecutive utterances from the same speaker
            // (ASR chunk boundaries can split a speaker's turn into two adjacent utterances)
            var mergedUtterances: [SpeakerUtterance] = []
            for u in allUtterances {
                if let last = mergedUtterances.last, last.speakerId == u.speakerId {
                    mergedUtterances[mergedUtterances.count - 1] = SpeakerUtterance(
                        speakerId: last.speakerId,
                        speakerLabel: last.speakerLabel,
                        text: last.text + " " + u.text,
                        startTime: last.startTime,
                        endTime: u.endTime
                    )
                } else {
                    mergedUtterances.append(u)
                }
            }

            // Validation: if diarization found 2+ speakers but alignment collapsed to 1,
            // log diagnostic info (the midpoint offset bug was the typical root cause).
            let alignedSpeakerCount = Set(mergedUtterances.map { $0.speakerId }).count
            let diarizationSpeakerCount = Set(speakerSegments.map { $0.speakerId }).count
            #if DEBUG
            if diarizationSpeakerCount >= 2 && alignedSpeakerCount < 2 {
                print("WARNING: Alignment collapsed \(diarizationSpeakerCount) diarized speakers → \(alignedSpeakerCount) in transcript")
                print("  This suggests a time alignment mismatch between ASR tokens and diarization segments")
            }
            #endif

            // Map speaker IDs to display labels.
            // Profile-matched speakers keep their profile name.
            // Unknown speakers get distinct emoji labels (🔵, 🟠)
            // so they remain distinguishable in the transcript.
            var unknownSpeakerLabels: [String: String] = [:]
            let speakerEmojis = ["🔵", "🟠"]
            var nextUnknownIndex = 0
            mergedUtterances = mergedUtterances.map { u in
                if savedProfileNames.contains(u.speakerId) {
                    return SpeakerUtterance(
                        speakerId: u.speakerId,
                        speakerLabel: u.speakerId,
                        text: u.text,
                        startTime: u.startTime,
                        endTime: u.endTime
                    )
                }
                // Assign a stable label per unknown speaker ID
                if unknownSpeakerLabels[u.speakerId] == nil {
                    unknownSpeakerLabels[u.speakerId] = nextUnknownIndex < speakerEmojis.count ? speakerEmojis[nextUnknownIndex] : "🟠"
                    nextUnknownIndex += 1
                }
                return SpeakerUtterance(
                    speakerId: u.speakerId,
                    speakerLabel: unknownSpeakerLabels[u.speakerId]!,
                    text: u.text,
                    startTime: u.startTime,
                    endTime: u.endTime
                )
            }

            #if DEBUG
            print("Total aligned utterances: \(mergedUtterances.count) (before merge: \(allUtterances.count))")
            print("")
            print("=== FULL CONVERSATION ===")
            for (i, u) in mergedUtterances.enumerated() {
                print("[\(i)] \(u.speakerLabel) [\(String(format: "%.1f", u.startTime))-\(String(format: "%.1f", u.endTime))s]:")
                print("    \(u.text)")
                print("")
            }
            print("=== END POST-RECORDING DIARIZATION ===")
            #endif

            // Show diarized results immediately
            await MainActor.run {
                currentSession?.utterances = mergedUtterances
                if let session = currentSession {
                    currentTranscription = session.formattedTranscript
                }
                isDiarizing = false
            }

            // Step 3: LLM speaker correction + Conversation analysis
            if OpenAIService.shared.isConfigured {
                await MainActor.run {
                    isAnalyzing = true
                    analysisError = nil
                    analysisPhase = .validating
                    validationMessage = nil
                }

                let sessionId = UUID().uuidString

                // Compute diarization quality — skip LLM correction if high confidence
                let speakerIds = Set(mergedUtterances.map { $0.speakerId })
                let hasTwoSpeakers = speakerIds.count >= 2
                let totalDuration = mergedUtterances.reduce(0.0) { $0 + ($1.endTime - $1.startTime) }
                let speakerDurations = Dictionary(grouping: mergedUtterances, by: { $0.speakerId })
                    .mapValues { $0.reduce(0.0) { $0 + ($1.endTime - $1.startTime) } }
                let dominantRatio = totalDuration > 0 ? (speakerDurations.values.max() ?? 0) / totalDuration : 1.0
                let isHighQuality = hasTwoSpeakers && dominantRatio < 0.85 && mergedUtterances.count >= 4

                #if DEBUG
                print("Diarization quality: speakers=\(speakerIds.count), dominantRatio=\(String(format: "%.0f%%", dominantRatio * 100)), utterances=\(mergedUtterances.count), highQuality=\(isHighQuality)")
                #endif

                // LLM speaker correction: skip in solo mode and when diarization is high confidence
                if !isSoloMode && !isHighQuality, let corrected = await SpeakerCorrectionService.shared.correctSpeakerAttribution(
                    utterances: mergedUtterances,
                    sessionId: sessionId
                ) {
                    mergedUtterances = corrected
                    await MainActor.run {
                        currentSession?.utterances = corrected
                        if let session = currentSession {
                            currentTranscription = session.formattedTranscript
                        }
                    }
                    #if DEBUG
                    print("Speaker correction applied: \(corrected.count) utterances")
                    #endif
                }

                await MainActor.run { analysisPhase = .analyzing }

                if let result = await ConversationAnalysisService.shared.analyzeConversationV2(
                    utterances: mergedUtterances,
                    sessionId: sessionId,
                    conversationMode: isSoloMode ? "solo" : "couple"
                ) {
                    await MainActor.run {
                        currentSession?.analysisV2 = result

                        if result.isValid {
                            analysisPhase = .complete

                            // Track analytics
                            let failedPrompts = [
                                result.vibeCard == nil ? "vibe" : nil,
                                result.coaching == nil ? "coach" : nil,
                                result.analyst == nil ? "analyst" : nil
                            ].compactMap { $0 }

                            if failedPrompts.isEmpty {
                                Analytics.pipelineCompleted(
                                    vibeScore: result.vibeCard?.vibeScore ?? 0,
                                    foulsCount: result.foulCount
                                )
                            } else {
                                Analytics.pipelinePartialFailure(failedPrompts: failedPrompts)
                            }
                        } else {
                            analysisPhase = .invalidConversation
                            validationMessage = result.validation.userMessage
                            Analytics.pipelineValidationFailed(reason: result.validation.failReason ?? "unknown")
                        }
                    }
                } else {
                    await MainActor.run {
                        analysisError = "Analysis failed. You may have hit your daily limit — try again later."
                        analysisPhase = .idle
                    }
                }

                await MainActor.run { isAnalyzing = false }
            } else {
                await MainActor.run {
                    analysisError = "Analysis is currently unavailable."
                }
            }

        } catch {
            #if DEBUG
            print("Post-recording diarization error: \(error)")
            #endif
            await MainActor.run {
                isDiarizing = false
            }
        }
    }

    // MARK: - On-Device Diarization Pipeline

    /// Extracted on-device diarization: offline diarizer → merge to 2 speakers → profile matching → remap
    private func runOnDeviceDiarizationPipeline(
        audio: [Float],
        isSoloMode: Bool,
        savedProfiles: [SpeakerProfile],
        savedProfileNames: Set<String>
    ) async throws -> [TimedSpeakerSegment] {
        guard let offlineDiarizer = fluidAudioManager.offlineDiarizerManager else {
            #if DEBUG
            print("No offline diarizer available, skipping post-recording diarization")
            #endif
            return []
        }

        #if DEBUG
        print("Running offline diarizer...")
        #endif
        var diarization = try await offlineDiarizer.process(audio: audio)

        #if DEBUG
        let offlineSpeakerCounts = Dictionary(grouping: diarization.segments, by: { $0.speakerId })
            .mapValues { $0.count }
        print("Offline diarizer found \(offlineSpeakerCounts.count) speaker(s), segments per speaker: \(offlineSpeakerCounts.sorted(by: { $0.key < $1.key }).map { "\($0.key):\($0.value)" }.joined(separator: ", "))")
        #endif

        #if DEBUG
        print("Diarization segments: \(diarization.segments.count)")
        for (i, seg) in diarization.segments.enumerated() {
            print("  Seg \(i): \(seg.speakerId) [\(String(format: "%.2f", seg.startTimeSeconds))-\(String(format: "%.2f", seg.endTimeSeconds))s] emb=\(seg.embedding.count)d quality=\(String(format: "%.2f", seg.qualityScore))")
        }
        let uniqueSpeakers = Set(diarization.segments.map { $0.speakerId })
        print("Unique speakers (raw): \(uniqueSpeakers.sorted())")
        #endif

        // Couple mode: merge to 2 speakers if over-segmented
        if !isSoloMode {
            let preMergeSpeakerCount = Set(diarization.segments.map { $0.speakerId }).count
            if preMergeSpeakerCount > 2 {
                diarization = Self.mergeToTwoSpeakers(diarization)
                #if DEBUG
                let postMergeSpeakers = Set(diarization.segments.map { $0.speakerId })
                print("Cluster merge: \(preMergeSpeakerCount) → \(postMergeSpeakers.count) speakers (\(postMergeSpeakers.sorted()))")
                #endif
            }
        }

        // Profile matching
        #if DEBUG
        print("Saved profiles: \(savedProfileNames.sorted())")
        #endif

        var speakerIdRemap: [String: String] = [:]
        if !savedProfiles.isEmpty {
            try? await fluidAudioManager.initializeDiarizerIfNeeded()

            if let speakerManager = fluidAudioManager.diarizerManager?.speakerManager {
                speakerManager.reset(keepIfPermanent: true)

                var clusterEmbeddings: [String: [[Float]]] = [:]
                for seg in diarization.segments where !seg.embedding.isEmpty {
                    clusterEmbeddings[seg.speakerId, default: []].append(seg.embedding)
                }

                var assignedProfiles = Set<String>()
                let sortedClusters = clusterEmbeddings.keys.sorted()

                for clusterId in sortedClusters {
                    guard let embeddings = clusterEmbeddings[clusterId],
                          let avgEmb = SpeakerUtilities.averageEmbeddings(embeddings) else { continue }

                    let match = speakerManager.findSpeaker(with: avgEmb, speakerThreshold: Constants.speakerMatchingThreshold)

                    #if DEBUG
                    print("  Cluster '\(clusterId)' → match: \(match.id ?? "none") (dist=\(String(format: "%.4f", match.distance)))")
                    #endif

                    if let matchedId = match.id,
                       savedProfileNames.contains(matchedId),
                       !assignedProfiles.contains(matchedId) {
                        speakerIdRemap[clusterId] = matchedId
                        assignedProfiles.insert(matchedId)
                    }
                }
            }
        }

        // Apply remap
        let speakerSegments: [TimedSpeakerSegment] = diarization.segments.map { seg in
            if let newId = speakerIdRemap[seg.speakerId] {
                return TimedSpeakerSegment(
                    speakerId: newId,
                    embedding: seg.embedding,
                    startTimeSeconds: seg.startTimeSeconds,
                    endTimeSeconds: seg.endTimeSeconds,
                    qualityScore: seg.qualityScore
                )
            }
            return seg
        }

        #if DEBUG
        let finalSpeakers = Set(speakerSegments.map { $0.speakerId })
        print("Final speakers: \(finalSpeakers.sorted())")
        #endif

        return speakerSegments
    }

    // MARK: - Cluster Merging

    /// Merge excess speaker clusters down to exactly 2 by folding the shortest-duration
    /// cluster into its closest neighbor (embedding cosine distance). Falls back to
    /// merging into the longest cluster when embeddings are unavailable.
    private static func mergeToTwoSpeakers(_ result: DiarizationResult) -> DiarizationResult {
        let clusters = Dictionary(grouping: result.segments, by: { $0.speakerId })
        guard clusters.count > 2 else { return result }

        var clusterDur: [String: Float] = [:]
        var clusterEmb: [String: [Float]?] = [:]
        for (id, segs) in clusters {
            clusterDur[id] = segs.reduce(0) { $0 + $1.durationSeconds }
            let embs = segs.compactMap { $0.embedding.isEmpty ? nil : $0.embedding }
            clusterEmb[id] = SpeakerUtilities.averageEmbeddings(embs)
        }

        var active = Set(clusters.keys)
        var mergeMap: [String: String] = [:]

        while active.count > 2 {
            guard let smallest = active.min(by: { (clusterDur[$0] ?? 0) < (clusterDur[$1] ?? 0) }) else { break }
            let others = active.subtracting([smallest])

            // Try embedding-based nearest neighbor
            var target: String?
            if let sEmb = clusterEmb[smallest] ?? nil {
                var bestDist: Float = .greatestFiniteMagnitude
                for other in others {
                    if let oEmb = clusterEmb[other] ?? nil {
                        let d = SpeakerUtilities.cosineDistance(sEmb, oEmb)
                        if d < bestDist { bestDist = d; target = other }
                    }
                }
            }

            // Fallback: merge into the longest remaining cluster
            if target == nil {
                target = others.max(by: { (clusterDur[$0] ?? 0) < (clusterDur[$1] ?? 0) })
            }

            guard let finalTarget = target else { break }

            #if DEBUG
            print("Merging cluster '\(smallest)' (\(String(format: "%.1f", clusterDur[smallest] ?? 0))s) → '\(finalTarget)' (\(String(format: "%.1f", clusterDur[finalTarget] ?? 0))s)")
            #endif

            mergeMap[smallest] = finalTarget
            clusterDur[finalTarget] = (clusterDur[finalTarget] ?? 0) + (clusterDur[smallest] ?? 0)
            active.remove(smallest)
        }

        guard !mergeMap.isEmpty else { return result }

        return DiarizationResult(segments: result.segments.map { seg in
            guard let newId = mergeMap[seg.speakerId] else { return seg }
            return TimedSpeakerSegment(
                speakerId: newId, embedding: seg.embedding,
                startTimeSeconds: seg.startTimeSeconds, endTimeSeconds: seg.endTimeSeconds,
                qualityScore: seg.qualityScore
            )
        })
    }

    // MARK: - Quick Actions

    func quickRecord() {
        if isTranscribing {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func clearTranscription() {
        currentTranscription = ""
        accumulatedVADText = ""
        lastProcessedSampleCount = 0
        isSpeechActive = false
        analysisError = nil
    }
    
    // MARK: - Background Transcription
    
    func enableBackgroundTranscription() {
        // Configure audio session for background recording
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            #if DEBUG
            print("Background audio session configured for continuous recording")
            #endif
        } catch {
            #if DEBUG
            print("Failed to configure background audio: \(error)")
            #endif
        }
    }
    
    private func processVADChunk(_ audioData: [Float], isFinal: Bool) async {
        #if DEBUG
        print("Processing VAD chunk: \(audioData.count) samples, final: \(isFinal)")
        #endif
        
        do {
            try await initializeModelIfNeeded()
            
            guard let asrManager = fluidAudioManager.asrManager else {
                #if DEBUG
                print("ASR Manager not available")
                #endif
                return
            }
            
            let result = try await asrManager.transcribe(audioData)
            
            if !result.text.isEmpty {
                let cleanedText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                
                guard !cleanedText.isEmpty else { return }
                
                #if DEBUG
                print("VAD Chunk Transcribed: \(cleanedText)")
                #endif
                
                await MainActor.run {
                    // Add to accumulated text with a space
                    if !self.accumulatedVADText.isEmpty {
                        self.accumulatedVADText += " "
                    }
                    self.accumulatedVADText += cleanedText
                    
                    // Update display with accumulated text
                    self.currentTranscription = self.accumulatedVADText
                    
                    // Trim if too long
                    if self.currentTranscription.count > Constants.maxTranscriptionLength {
                        // Keep the last 80% when trimming
                        let keepLength = Int(Double(Constants.maxTranscriptionLength) * 0.8)
                        if let index = self.currentTranscription.index(
                            self.currentTranscription.endIndex,
                            offsetBy: -keepLength,
                            limitedBy: self.currentTranscription.startIndex
                        ) {
                            self.currentTranscription = "..." + String(self.currentTranscription[index...])
                            self.accumulatedVADText = self.currentTranscription
                        }
                    }
                }
                
                if isFinal {
                    await finalizeVADTranscription()
                }
            }
        } catch {
            #if DEBUG
            print("VAD chunk transcription error: \(error)")
            #endif
        }
    }
    
    @MainActor
    private func finalizeVADTranscription() {
        // No-op: history is saved only after analysis completes in stopRecording()
    }
}

// MARK: - VAD Delegate

extension AudioTranscriptionManager_iOS: VADManagerDelegate_iOS {
    func vadManager(_ manager: VADManager_iOS, didStartSpeechAt timestamp: TimeInterval) {
        #if DEBUG
        print("Speech started at \(timestamp)")
        #endif
        speechStartTime = timestamp
        isSpeechActive = true
        
        // Only clear if this is a new speech segment
        if accumulatedVADText.isEmpty {
            bufferQueue.async(flags: .barrier) {
                self.speechBuffer.removeAll()
            }
            accumulatedVADText = ""
            lastProcessedSampleCount = 0
        }
        
        // Start continuous chunk processing
        vadTranscriptionTask = Task {
            // Initial delay to accumulate some audio
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            while !Task.isCancelled && isSpeechActive {
                // Process chunks of 30 seconds at a time
                let chunkSize = Int(sampleRate * 30) // 30 seconds

                let (shouldProcessChunk, chunk, shouldShowPartial, bufferCopy) = bufferQueue.sync {
                    if speechBuffer.count >= chunkSize {
                        // Extract chunk from the beginning
                        let chunk = Array(speechBuffer.prefix(chunkSize))
                        speechBuffer.removeFirst(chunkSize)
                        return (true, chunk, false, [Float]())
                    } else if speechBuffer.count >= Int(sampleRate * 2) {
                        // Show partial transcription if we have at least 2 seconds
                        let bufferCopy = speechBuffer
                        return (false, [Float](), true, bufferCopy)
                    }
                    return (false, [Float](), false, [Float]())
                }

                if shouldProcessChunk {
                    await processVADChunk(chunk, isFinal: false)
                } else if shouldShowPartial {
                    await transcribe(samples: bufferCopy, isPartial: true)
                }

                // Check every 5 seconds (reduces redundant ASR calls on overlapping windows)
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
    
    func vadManager(_ manager: VADManager_iOS, didEndSpeechAt timestamp: TimeInterval, duration: TimeInterval) {
        #if DEBUG
        print("Speech ended at \(timestamp), duration: \(duration)s")
        #endif
        isSpeechActive = false

        // Cancel partial updates
        vadTranscriptionTask?.cancel()
        vadTranscriptionTask = nil

        // Process any remaining audio
        Task {
            let (shouldProcessFinal, finalBuffer) = bufferQueue.sync {
                if !speechBuffer.isEmpty && speechBuffer.count >= Int(sampleRate * 0.5) {
                    let buffer = speechBuffer
                    return (true, buffer)
                }
                return (false, [Float]())
            }
            
            if shouldProcessFinal {
                // Process the remaining chunk
                await processVADChunk(finalBuffer, isFinal: true)
            } else if !accumulatedVADText.isEmpty {
                // Just finalize with accumulated text
                await finalizeVADTranscription()
            }
            
            // Reset for next speech segment
            bufferQueue.async(flags: .barrier) {
                self.speechBuffer.removeAll()
            }
            accumulatedVADText = ""
            lastProcessedSampleCount = 0
        }
    }
    
    func vadManager(_ manager: VADManager_iOS, didUpdateVoiceProbability probability: Float) {
        // Could use this for UI feedback if needed
    }
}

