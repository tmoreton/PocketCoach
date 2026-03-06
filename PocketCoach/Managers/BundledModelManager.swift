import Foundation

/// Copies bundled ML models from the app bundle to the FluidAudio cache directory
/// so they're available without downloading on first launch.
enum BundledModelManager {

    /// Current version of bundled models. Bump this when shipping updated models
    /// to force a re-copy on app update.
    /// v2: Added offline diarizer models (Segmentation, Embedding, FBank, PldaRho, plda-parameters.json)
    private static let currentVersion = 2
    private static let versionKey = "bundledModelsVersion"

    /// The model folders to copy from the bundle to Application Support.
    private static let modelFolders = [
        "parakeet-tdt-0.6b-v3-coreml",
        "speaker-diarization-coreml",
        "silero-vad-coreml"
    ]

    /// Copies bundled models to the FluidAudio cache directory if not already done
    /// for the current version. Safe to call multiple times.
    static func installBundledModelsIfNeeded() {
        let installedVersion = UserDefaults.standard.integer(forKey: versionKey)
        guard installedVersion < currentVersion else {
            #if DEBUG
            print("BundledModelManager: Models already installed (version \(installedVersion))")
            #endif
            return
        }

        let fileManager = FileManager.default

        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            #if DEBUG
            print("BundledModelManager: Could not find Application Support directory")
            #endif
            return
        }

        let cacheBase = appSupport
            .appendingPathComponent("FluidAudio", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)

        // Ensure the base cache directory exists
        try? fileManager.createDirectory(at: cacheBase, withIntermediateDirectories: true)

        guard let bundleBase = Bundle.main.url(forResource: "BundledModels", withExtension: nil) else {
            #if DEBUG
            print("BundledModelManager: BundledModels folder not found in app bundle")
            #endif
            return
        }

        var allSucceeded = true

        for folder in modelFolders {
            let source = bundleBase.appendingPathComponent(folder)
            let destination = cacheBase.appendingPathComponent(folder)

            // On version bump, remove existing folder so updated models replace them
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
                #if DEBUG
                print("BundledModelManager: Removed existing \(folder) for version upgrade")
                #endif
            }

            guard fileManager.fileExists(atPath: source.path) else {
                #if DEBUG
                print("BundledModelManager: \(folder) not found in bundle, skipping")
                #endif
                allSucceeded = false
                continue
            }

            do {
                try fileManager.copyItem(at: source, to: destination)
                #if DEBUG
                print("BundledModelManager: Copied \(folder) to cache")
                #endif
            } catch {
                #if DEBUG
                print("BundledModelManager: Failed to copy \(folder): \(error)")
                #endif
                allSucceeded = false
            }
        }

        if allSucceeded {
            UserDefaults.standard.set(currentVersion, forKey: versionKey)
            #if DEBUG
            print("BundledModelManager: All bundled models installed (version \(currentVersion))")
            #endif
        }
    }
}
