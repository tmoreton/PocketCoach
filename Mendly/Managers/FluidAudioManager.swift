import Foundation
import FluidAudio
import Combine

enum FluidAudioError: LocalizedError {
    case modelNotLoaded
    case initializationFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "Model not loaded"
        case .initializationFailed:
            return "Failed to initialize audio manager"
        }
    }
}

@MainActor
class FluidAudioManager: ObservableObject {
    @Published var availableModels: [FluidModel] = []
    @Published var selectedModel: FluidModel?
    @Published var asrManager: AsrManager?
    @Published var vadManager: VadManager?
    @Published var models: AsrModels?
    @Published var isInitializing = false

    // Diarization (used for onboarding embedding extraction and profile matching)
    @Published var diarizerManager: DiarizerManager?

    // Offline diarization (post-recording — AHC + VBx for better speaker separation)
    @Published var offlineDiarizerManager: OfflineDiarizerManager?

    private var cancellables = Set<AnyCancellable>()

    // Singleton instance
    static let shared = FluidAudioManager()

    /// Returns true if the model is ready for transcription
    var isModelReady: Bool {
        return asrManager != nil && models != nil && !isInitializing
    }

    struct FluidModel: Identifiable, Codable {
        let id: String
        let displayName: String
        let size: String
        let description: String
        var isDownloaded: Bool = false

        static let availableModels = [
            FluidModel(id: "v2", displayName: "English v2", size: "150 MB", description: "English-only, fast and accurate"),
            FluidModel(id: "v3", displayName: "Multilingual v3", size: "350 MB", description: "Supports multiple European languages")
        ]
    }

    init() {
        BundledModelManager.installBundledModelsIfNeeded()
        loadAvailableModels()
        loadSelectedModel()
    }

    private func loadAvailableModels() {
        availableModels = FluidModel.availableModels

        // Check which models are already downloaded
        Task {
            for i in 0..<availableModels.count {
                let isDownloaded = await checkModelDownloaded(version: availableModels[i].id)
                availableModels[i].isDownloaded = isDownloaded
            }
        }
    }

    private func loadSelectedModel() {
        let savedModelId = UserDefaults.standard.string(forKey: "selectedFluidModel") ?? "v3"
        selectedModel = availableModels.first { $0.id == savedModelId }

        // Don't auto-load models on init - wait until user requests recording
        #if DEBUG
        print("Selected model: \(savedModelId) - will load on demand")
        #endif
    }

    func selectModel(_ model: FluidModel) async throws {
        selectedModel = model
        UserDefaults.standard.set(model.id, forKey: "selectedFluidModel")

        // Reset loaded state so loadFluidAudio will re-load the new model
        self.models = nil
        self.asrManager = nil

        try await loadFluidAudio(modelId: model.id)
    }

    private func loadFluidAudio(modelId: String) async throws {
        #if DEBUG
        print("FluidAudioManager: loadFluidAudio called for model: \(modelId)")
        #endif

        // If already loaded, return
        if models != nil && asrManager != nil {
            #if DEBUG
            print("FluidAudioManager: Models already loaded, returning")
            #endif
            return
        }

        let version: AsrModelVersion = modelId == "v2" ? .v2 : .v3

        #if DEBUG
        print("FluidAudioManager: Starting AsrModels.downloadAndLoad for version: \(version)")
        #endif

        // Models are pre-installed from bundle; this loads from cache
        let loadedModels = try await AsrModels.downloadAndLoad(version: version)

        #if DEBUG
        print("FluidAudioManager: AsrModels.downloadAndLoad completed successfully")
        #endif

        // Initialize ASR manager
        let manager = AsrManager(config: .default)

        #if DEBUG
        print("FluidAudioManager: Initializing AsrManager...")
        #endif

        try await manager.initialize(models: loadedModels)

        #if DEBUG
        print("FluidAudioManager: AsrManager initialized successfully")
        #endif

        // Update properties atomically
        await MainActor.run {
            self.models = loadedModels
            self.asrManager = manager
        }

        #if DEBUG
        print("FluidAudio loaded with model: \(modelId)")
        #endif

        // Update model as downloaded
        if let index = availableModels.firstIndex(where: { $0.id == modelId }) {
            availableModels[index].isDownloaded = true
        }
    }

    private func checkModelDownloaded(version: String) async -> Bool {
        // Check if model files exist
        let fileManager = FileManager.default

        // FluidAudio uses Application Support, not Documents
        let appSupportPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        // Match the path pattern from logs: /Library/Application Support/FluidAudio/Models/parakeet-tdt-0.6b-v2-coreml
        let modelName = version == "v2" ? "parakeet-tdt-0.6b-v2-coreml" : "parakeet-tdt-0.6b-v3-coreml"
        let modelPath = appSupportPath?.appendingPathComponent("FluidAudio/Models/\(modelName)")

        #if DEBUG
        print("FluidAudioManager: Checking for model at path: \(modelPath?.path ?? "nil")")
        #endif

        if let path = modelPath {
            let exists = fileManager.fileExists(atPath: path.path)
            #if DEBUG
            print("FluidAudioManager: Model exists: \(exists)")
            #endif
            return exists
        }

        return false
    }

    func deleteModel(_ model: FluidModel) async throws {
        // Remove model files
        let fileManager = FileManager.default
        let appSupportPath = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first

        let modelName = model.id == "v2" ? "parakeet-tdt-0.6b-v2-coreml" : "parakeet-tdt-0.6b-v3-coreml"

        if let modelPath = appSupportPath?.appendingPathComponent("FluidAudio/Models/\(modelName)") {
            try? fileManager.removeItem(at: modelPath)
        }

        // Update model status
        if let index = availableModels.firstIndex(where: { $0.id == model.id }) {
            availableModels[index].isDownloaded = false
        }

        // If this was the selected model, switch to v2
        if selectedModel?.id == model.id {
            if let v2Model = availableModels.first(where: { $0.id == "v2" }) {
                try await selectModel(v2Model)
            }
        }
    }

    func initializeASRIfNeeded() async throws {
        #if DEBUG
        print("FluidAudioManager: initializeASRIfNeeded called - asrManager: \(asrManager != nil), selectedModel: \(selectedModel?.id ?? "none")")
        #endif

        // If already initialized or already loading, return
        guard asrManager == nil, !isInitializing, let selectedModel = selectedModel else {
            #if DEBUG
            print("FluidAudioManager: Already initialized, already loading, or no model selected, returning")
            #endif
            return
        }

        // Set initializing state
        isInitializing = true

        do {
            try await loadFluidAudio(modelId: selectedModel.id)

            // Clear initializing state on success
            isInitializing = false

            #if DEBUG
            print("FluidAudioManager: Initialization complete - asrManager: \(asrManager != nil), isModelReady: \(isModelReady)")
            #endif
        } catch {
            // Clear initializing state on error
            isInitializing = false

            #if DEBUG
            print("FluidAudioManager: Initialization failed with error: \(error)")
            #endif

            // Clean up any partially loaded state
            await MainActor.run {
                self.models = nil
                self.asrManager = nil
            }

            throw error
        }
    }

    // Add a force reset method
    func forceResetModelState() async {
        #if DEBUG
        print("FluidAudioManager: Force resetting model state")
        #endif

        // Reset all state
        await MainActor.run {
            self.isInitializing = false
            self.models = nil
            self.asrManager = nil
            self.vadManager = nil
            self.offlineDiarizerManager = nil
        }
    }

    func initializeDiarizerIfNeeded() async throws {
        guard diarizerManager == nil else { return }

        #if DEBUG
        print("FluidAudioManager: Loading diarizer models...")
        #endif

        let diarizerModels = try await DiarizerModels.downloadIfNeeded()

        #if DEBUG
        print("FluidAudioManager: Diarizer models loaded, initializing...")
        #endif

        var config = DiarizerConfig.default
        config.debugMode = true
        config.chunkOverlap = 2.0  // 2s overlap between chunks to maintain speaker tracking across boundaries

        let manager = DiarizerManager(config: config)
        try await manager.initialize(models: diarizerModels)

        // Speaker matching threshold — balanced for accuracy and recall.
        manager.speakerManager.speakerThreshold = Constants.speakerMatchingThreshold

        // Lower minimum speech duration so short utterances from a second speaker
        // can still create a new speaker entry (default 1.0s rejects short turns).
        manager.speakerManager.minSpeechDuration = 0.5

        // Pre-load saved voice profiles.
        let savedProfiles = SpeakerProfile.loadAll()
        if !savedProfiles.isEmpty {
            let speakers = savedProfiles.map { profile in
                Speaker(
                    id: profile.name,
                    name: profile.name,
                    currentEmbedding: profile.embedding,
                    duration: 5.0,
                    isPermanent: true
                )
            }
            manager.speakerManager.initializeKnownSpeakers(speakers, mode: .reset)
            #if DEBUG
            print("FluidAudioManager: Pre-loaded \(speakers.count) speaker profile(s) into diarizer")
            #endif
        }

        diarizerManager = manager

        #if DEBUG
        print("FluidAudioManager: Diarizer initialized successfully")
        #endif
    }

    /// Reload saved voice profiles into the existing diarizer's SpeakerManager.
    /// Call this after onboarding saves a new profile so the diarizer recognizes the new speaker.
    func reloadProfiles() {
        guard let diarizerManager = diarizerManager else { return }

        let savedProfiles = SpeakerProfile.loadAll()
        let speakers = savedProfiles.map { profile in
            Speaker(
                id: profile.name,
                name: profile.name,
                currentEmbedding: profile.embedding,
                duration: 5.0,
                isPermanent: true
            )
        }
        diarizerManager.speakerManager.initializeKnownSpeakers(speakers, mode: .reset)

        #if DEBUG
        print("FluidAudioManager: Reloaded \(speakers.count) speaker profile(s) into diarizer")
        #endif
    }

    func initializeOfflineDiarizerIfNeeded(speakerCount: Int = 2) async throws {
        guard offlineDiarizerManager == nil else { return }

        #if DEBUG
        print("FluidAudioManager: Loading offline diarizer models (exactly \(speakerCount) speaker(s))...")
        #endif

        // withSpeakers(exactly:) sets numSpeakers which triggers K-Means re-clustering,
        // forcing exactly N clusters even when AHC initially under-segments.
        var config = OfflineDiarizerConfig.default.withSpeakers(exactly: speakerCount)
        config.embedding.minSegmentDurationSeconds = 0.5  // default 1.0 — capture shorter speech segments for more embeddings
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()

        offlineDiarizerManager = manager

        #if DEBUG
        print("FluidAudioManager: Offline diarizer initialized successfully")
        #endif
    }

    /// Force-reinitialize the offline diarizer with a new speaker count.
    /// Call when the user switches conversation mode (couple ↔ solo).
    func resetOfflineDiarizer() {
        offlineDiarizerManager = nil
    }

    func initializeVADIfNeeded() async throws {
        guard vadManager == nil else { return }

        vadManager = try await VadManager(config: VadConfig(defaultThreshold: 0.75))
        #if DEBUG
        print("VAD Manager initialized on demand")
        #endif
    }

    /// Extract a single voice embedding from audio samples by picking the dominant (longest) speaker's embedding.
    /// This avoids averaging embeddings from multiple speakers, which would reduce profile quality.
    func extractEmbedding(from audioSamples: [Float]) async throws -> [Float] {
        try await initializeDiarizerIfNeeded()

        guard let diarizerManager = diarizerManager else {
            throw FluidAudioError.modelNotLoaded
        }

        let diarization = try await diarizerManager.performCompleteDiarization(
            audioSamples, sampleRate: 16000, atTime: 0
        )

        // Pick the longest segment's embedding — it's the dominant speaker in the onboarding clip
        let dominantSegment = diarization.segments
            .filter { !$0.embedding.isEmpty }
            .max { $0.durationSeconds < $1.durationSeconds }

        guard let segment = dominantSegment else {
            throw FluidAudioError.initializationFailed
        }

        return segment.embedding  // Already L2-normalized by the diarizer
    }

    func getModelStorageSize() -> String {
        var totalSize: Int64 = 0

        // Calculate total size of downloaded models
        let fileManager = FileManager.default
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first

        if let path = documentsPath?.appendingPathComponent("FluidAudio/Models") {
            if let size = try? fileManager.allocatedSizeOfDirectory(at: path) {
                totalSize += Int64(size)
            }
        }

        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }
}

// Extension for directory size calculation
extension FileManager {
    func allocatedSizeOfDirectory(at directoryURL: URL) throws -> UInt64 {
        var size: UInt64 = 0
        let allocatedSizeResourceKeys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
        ]

        guard let enumerator = self.enumerator(at: directoryURL,
                                               includingPropertiesForKeys: Array(allocatedSizeResourceKeys)) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        for case let fileURL as URL in enumerator {
            let resourceValues = try fileURL.resourceValues(forKeys: allocatedSizeResourceKeys)

            if resourceValues.isRegularFile == true {
                size += UInt64(resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize ?? 0)
            }
        }

        return size
    }
}
