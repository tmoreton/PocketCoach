import Foundation
import Combine

@MainActor
class SharedHistoryManager: ObservableObject {
    @Published var items: [HistoryItem] = []
    @Published var isSyncing = false

    private let storageKey = "MendlyHistory"
    private let cloudKitManager: CloudKitSyncManager?
    private var cancellables = Set<AnyCancellable>()
    private var isClearing = false

    init() {
        self.cloudKitManager = CloudKitSyncManager()
        loadLocalHistory()
        setupCloudKitSync()
    }

    // MARK: - Local Storage

    private func loadLocalHistory() {
        guard let sharedDefaults = UserDefaults(suiteName: Constants.appGroupIdentifier) else { return }

        if let data = sharedDefaults.data(forKey: storageKey) {
            do {
                let decoded = try JSONDecoder().decode([HistoryItem].self, from: data)
                items = decoded
            } catch {
                #if DEBUG
                print("SharedHistoryManager: Error decoding items: \(error)")
                #endif
            }
        }
    }

    private func saveLocalHistory() {
        guard !isSyncingFromCloud else { return }

        guard let sharedDefaults = UserDefaults(suiteName: Constants.appGroupIdentifier) else { return }

        do {
            let encoded = try JSONEncoder().encode(items)
            sharedDefaults.set(encoded, forKey: storageKey)
            sharedDefaults.synchronize()
        } catch {
            #if DEBUG
            print("SharedHistoryManager: Error encoding items: \(error)")
            #endif
        }
    }

    // MARK: - History Management

    func add(_ text: String, analysisV2: SessionAnalysisV2, durationSeconds: Int? = nil, utterances: [SpeakerUtterance]? = nil) {
        let trimmedText = String(text.prefix(Constants.historyTextTruncationLimit))

        let fiveSecondsAgo = Date().addingTimeInterval(-5)
        let isDuplicate = items.contains { $0.text == trimmedText && $0.timestamp > fiveSecondsAgo }
        guard !isDuplicate else { return }

        let newItem = HistoryItem(text: trimmedText, analysisV2: analysisV2, durationSeconds: durationSeconds, utterances: utterances)
        items.insert(newItem, at: 0)

        if items.count > Constants.historyMaxItems {
            items = Array(items.prefix(Constants.historyMaxItems))
        }

        saveLocalHistory()

        Task {
            await cloudKitManager?.syncHistoryItems([newItem])
        }
    }

    func delete(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        saveLocalHistory()

        Task {
            await cloudKitManager?.deleteHistoryItem(item)
        }
    }

    func deleteAll() {
        isClearing = true
        items.removeAll()
        saveLocalHistory()

        Task {
            await cloudKitManager?.deleteAllHistoryItems()
            try? await Task.sleep(nanoseconds: 5_000_000_000)

            await MainActor.run { isClearing = false }

            for _ in 0..<3 {
                await performFullSync()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func clearAll() {
        deleteAll()
    }

    func exportAsText() -> String {
        items.map { item in
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            let dateString = formatter.string(from: item.timestamp)
            return "[\(dateString)]\n\(item.text)\n"
        }.joined(separator: "\n---\n\n")
    }

    // MARK: - CloudKit Sync

    private func setupCloudKitSync() {
        if let cloudKitManager = cloudKitManager {
            cloudKitManager.$isSyncing
                .assign(to: &$isSyncing)
        }

        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !isClearing && !isSyncingFromCloud {
                await performFullSync()
            }
        }

        Timer.publish(every: 120, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                if !self.isSyncingFromCloud && !self.isClearing {
                    Task { await self.performFullSync() }
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("CKDatabaseSubscriptionNotification"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                if !self.isSyncingFromCloud && !self.isClearing {
                    Task { await self.performFullSync() }
                }
            }
            .store(in: &cancellables)
    }

    private var isSyncingFromCloud = false

    private func performFullSync() async {
        guard !isClearing && !isSyncingFromCloud else { return }

        isSyncingFromCloud = true
        defer { isSyncingFromCloud = false }

        let remoteItems = await cloudKitManager?.fetchHistoryItems() ?? []
        let remoteIDs = Set(remoteItems.map { $0.id })
        let localOnlyItems = items.filter { !remoteIDs.contains($0.id) }

        // Build a lookup of local items so we can preserve analysis/duration
        // data that CloudKit doesn't store
        let localItemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        // Merge remote items with locally-stored analysis data
        var finalItems = remoteItems.map { remoteItem -> HistoryItem in
            if let localItem = localItemsByID[remoteItem.id] {
                var merged = remoteItem
                merged.analysisV2 = localItem.analysisV2
                merged.durationSeconds = localItem.durationSeconds
                merged.utterances = localItem.utterances
                return merged
            }
            return remoteItem
        }

        // Preserve all local-only items (CloudKit doesn't store analysis data,
        // so local is the source of truth)
        for localItem in localOnlyItems {
            if !finalItems.contains(where: { $0.id == localItem.id }) {
                finalItems.append(localItem)
            }
        }

        finalItems.sort { $0.timestamp > $1.timestamp }

        if finalItems != items {
            items = finalItems
            guard let sharedDefaults = UserDefaults(suiteName: Constants.appGroupIdentifier) else { return }
            do {
                let encoded = try JSONEncoder().encode(items)
                sharedDefaults.set(encoded, forKey: storageKey)
                sharedDefaults.synchronize()
            } catch {
                #if DEBUG
                print("Failed to save synced history: \(error)")
                #endif
            }
        }

        if !localOnlyItems.isEmpty {
            await cloudKitManager?.syncHistoryItems(localOnlyItems)
        }
    }

    // MARK: - Notification Handling

    func handleRemoteNotification() {
        Task { await performFullSync() }
    }

    func syncNow() {
        Task { await performFullSync() }
    }
}
