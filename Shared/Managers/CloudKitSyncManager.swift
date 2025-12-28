import Foundation
import CloudKit
import Combine

@MainActor
class CloudKitSyncManager: ObservableObject {
    @Published var isSyncing = false
    @Published var lastSyncDate: Date?
    @Published var syncError: Error?
    
    private let container: CKContainer
    private let database: CKDatabase
    private var syncSubscription: CKDatabaseSubscription?
    private var cancellables = Set<AnyCancellable>()
    
    private var isSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
    }
    
    init() {
        self.container = CKContainer(identifier: Constants.cloudKitContainerIdentifier)
        self.database = container.privateCloudDatabase
        
        // Set default value for iCloudSyncEnabled if not set - default to true for automatic sync
        if UserDefaults.standard.object(forKey: "iCloudSyncEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
        }
        
        // Setup CloudKit asynchronously without blocking initialization
        Task {
            if isSyncEnabled {
                await checkAccountStatus()
                if isSyncEnabled { // Check again after account status check
                    await setupSubscriptions()
                }
            }
        }
        
        // Listen for changes to sync setting
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(syncSettingChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    // Track previous sync-enabled state to avoid redundant work
    private var lastKnownSyncEnabled: Bool?

    // MARK: - Account Status

    private func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                break
            case .noAccount:
                #if DEBUG
                print("No CloudKit account - CloudKit features will be disabled")
                #endif
                syncError = SyncError.noAccount
                // Disable sync if no account
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
            case .restricted:
                #if DEBUG
                print("CloudKit account restricted - CloudKit features will be disabled")
                #endif
                syncError = SyncError.restricted
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
            case .couldNotDetermine:
                #if DEBUG
                print("Could not determine CloudKit account status - CloudKit features will be disabled")
                #endif
                syncError = SyncError.unknown
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
            case .temporarilyUnavailable:
                #if DEBUG
                print("CloudKit account temporarily unavailable - CloudKit features will be disabled")
                #endif
                syncError = SyncError.unknown
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
            @unknown default:
                UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
                break
            }
        } catch {
            #if DEBUG
            print("Error checking CloudKit account status: \(error) - CloudKit features will be disabled")
            #endif
            syncError = error
            UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
        }
    }
    
    // MARK: - Subscriptions
    
    private func setupSubscriptions() async {
        // Only setup subscriptions if we have an authenticated account
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                #if DEBUG
                print("Skipping CloudKit subscription setup - account not available")
                #endif
                return
            }
            
            let existingSubscriptions = try await database.allSubscriptions()
            if !existingSubscriptions.contains(where: { $0.subscriptionID == "history-changes" }) {
                // Create query subscription for HistoryItem changes
                let predicate = NSPredicate(value: true)
                let subscription = CKQuerySubscription(
                    recordType: HistoryItem.recordType,
                    predicate: predicate,
                    subscriptionID: "history-changes",
                    options: [.firesOnRecordCreation, .firesOnRecordUpdate, .firesOnRecordDeletion]
                )
                
                let notificationInfo = CKSubscription.NotificationInfo()
                notificationInfo.shouldSendContentAvailable = true
                subscription.notificationInfo = notificationInfo
                
                try await database.save(subscription)
                #if DEBUG
                print("Created CloudKit subscription")
                #endif
            }
        } catch {
            #if DEBUG
            print("Error setting up CloudKit subscription: \(error) - continuing without CloudKit")
            #endif
            // Don't throw error, just log and continue
        }
    }
    
    // MARK: - Settings
    
    @objc private func syncSettingChanged() {
        let current = isSyncEnabled
        guard current != lastKnownSyncEnabled else { return }
        lastKnownSyncEnabled = current

        Task {
            if current {
                // Re-enable sync if it was turned on
                await setupSubscriptions()
                await checkAccountStatus()
            } else {
                // Clean up if sync was turned off
                syncSubscription = nil
                syncError = nil
            }
        }
    }
    
    // MARK: - Syncing
    
    func syncHistoryItems(_ items: [HistoryItem]) async {
        guard isSyncEnabled else { return }
        
        isSyncing = true
        defer { isSyncing = false }
        
        do {
            // Check account status first
            let status = try await container.accountStatus()
            guard status == .available else {
                #if DEBUG
                print("Cannot sync to CloudKit - account not available")
                #endif
                return
            }
            
            // Convert items to CloudKit records
            let records = items.map { $0.toCKRecord() }
            
            // Save in batches
            let batchSize = 400 // CloudKit limit
            for batch in stride(from: 0, to: records.count, by: batchSize) {
                let endIndex = min(batch + batchSize, records.count)
                let batchRecords = Array(records[batch..<endIndex])
                
                let (_, _) = try await database.modifyRecords(
                    saving: batchRecords,
                    deleting: []
                )
            }
            
            lastSyncDate = Date()
            syncError = nil
        } catch {
            #if DEBUG
            print("Error syncing to CloudKit: \(error) - continuing without CloudKit")
            #endif
            syncError = error
            // Don't fail the operation, just log the error
        }
    }
    
    func fetchHistoryItems() async -> [HistoryItem] {
        guard isSyncEnabled else { return [] }
        
        isSyncing = true
        defer { isSyncing = false }
        
        var allItems: [HistoryItem] = []
        
        do {
            // Check account status first
            let status = try await container.accountStatus()
            guard status == .available else {
                #if DEBUG
                print("Cannot fetch from CloudKit - account not available")
                #endif
                return []
            }
            
            let query = CKQuery(recordType: HistoryItem.recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: HistoryItem.CloudKitFields.timestamp, ascending: false)]
            
            // Fetch in batches
            var cursor: CKQueryOperation.Cursor?
            
            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                
                if let cursor = cursor {
                    results = try await database.records(continuingMatchFrom: cursor, resultsLimit: 100)
                } else {
                    results = try await database.records(matching: query, resultsLimit: 100)
                }
                
                for (_, result) in results.matchResults {
                    switch result {
                    case .success(let record):
                        if let item = HistoryItem(from: record) {
                            allItems.append(item)
                        }
                    case .failure(let error):
                        #if DEBUG
                        print("Error fetching record: \(error)")
                        #endif
                    }
                }

                cursor = results.queryCursor
            } while cursor != nil

            lastSyncDate = Date()
            syncError = nil
        } catch {
            #if DEBUG
            print("Error fetching from CloudKit: \(error) - continuing without CloudKit")
            #endif
            syncError = error
            // Return empty array instead of failing
        }
        
        return allItems
    }
    
    func deleteHistoryItem(_ item: HistoryItem) async {
        guard isSyncEnabled else { return }
        
        do {
            let recordID = CKRecord.ID(recordName: item.id.uuidString)
            try await database.deleteRecord(withID: recordID)
            #if DEBUG
            print("Deleted record from CloudKit: \(item.id)")
            #endif
        } catch {
            #if DEBUG
            if let ckError = error as? CKError, ckError.code == .unknownItem {
                print("Record already deleted from CloudKit")
            } else {
                print("Error deleting from CloudKit: \(error)")
            }
            #endif
        }
    }
    
    func deleteAllHistoryItems() async {
        guard isSyncEnabled else { return }
        
        do {
            // Fetch all record IDs
            let query = CKQuery(recordType: HistoryItem.recordType, predicate: NSPredicate(value: true))
            var allRecordIDs: [CKRecord.ID] = []
            
            // Fetch in batches
            var cursor: CKQueryOperation.Cursor?
            
            repeat {
                let results: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
                
                if let cursor = cursor {
                    results = try await database.records(continuingMatchFrom: cursor, resultsLimit: 400)
                } else {
                    results = try await database.records(matching: query, resultsLimit: 400)
                }
                
                for (recordID, result) in results.matchResults {
                    switch result {
                    case .success:
                        allRecordIDs.append(recordID)
                    case .failure(let error):
                        #if DEBUG
                        print("Error fetching record ID: \(error)")
                        #endif
                    }
                }
                
                cursor = results.queryCursor
            } while cursor != nil
            
            // Delete in batches (CloudKit has a limit of 400 per batch)
            for batch in stride(from: 0, to: allRecordIDs.count, by: 400) {
                let endIndex = min(batch + 400, allRecordIDs.count)
                let batchIDs = Array(allRecordIDs[batch..<endIndex])
                
                let (_, _) = try await database.modifyRecords(
                    saving: [],
                    deleting: batchIDs
                )
            }
            
            #if DEBUG
            print("Successfully deleted all CloudKit records")
            #endif
        } catch {
            #if DEBUG
            print("Error bulk deleting from CloudKit: \(error)")
            #endif
            syncError = error
        }
    }
    
    // MARK: - Conflict Resolution
    
    func mergeHistoryItems(local: [HistoryItem], remote: [HistoryItem]) -> [HistoryItem] {
        var merged: [HistoryItem] = []
        var seen = Set<UUID>()
        
        // Combine both lists, removing duplicates
        let combined = (local + remote).sorted { $0.timestamp > $1.timestamp }
        
        for item in combined {
            if !seen.contains(item.id) {
                seen.insert(item.id)
                merged.append(item)
            }
        }
        
        // Apply max items limit
        return Array(merged.prefix(Constants.historyMaxItems))
    }
}

// MARK: - Error Types

enum SyncError: LocalizedError {
    case noAccount
    case restricted
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .noAccount:
            return "No iCloud account configured. Please sign in to iCloud in Settings."
        case .restricted:
            return "iCloud access is restricted on this device."
        case .unknown:
            return "Could not determine iCloud account status."
        }
    }
}