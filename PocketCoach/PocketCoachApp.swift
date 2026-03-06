//
//  PocketCoachApp.swift
//  PocketCoach
//
//  Created by Tim Moreton on 12/20/25.
//

import SwiftUI
import AppIntents
import FirebaseCore

@main
struct PocketCoachApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var historyManager = SharedHistoryManager()
    @StateObject private var transcriptionManager = AudioTranscriptionManager_iOS()
    @StateObject private var liveActivityManager = LiveActivityManager()
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @State private var showingOnboarding = false

    init() {
        FirebaseApp.configure()
        configureAppearance()
        Analytics.appLaunched()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(historyManager)
                .environmentObject(transcriptionManager)
                .environmentObject(liveActivityManager)
                .preferredColorScheme(colorSchemeFromMode(appearanceMode))
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .sheet(isPresented: $showingOnboarding) {
                    OnboardingView(isPresented: $showingOnboarding)
                        .interactiveDismissDisabled()
                }
                .onAppear {
                    appDelegate.historyManager = historyManager
                    transcriptionManager.historyManager = historyManager

                    if ScreenshotMockData.isScreenshotMode {
                        setupScreenshotMode()
                    } else {
                        checkOnboardingStatus()
                        // Pre-load model in background so it's ready when user taps record
                        Task {
                            try? await transcriptionManager.initializeModelIfNeeded()
                        }
                    }
                }
        }
    }

    private func colorSchemeFromMode(_ mode: String) -> ColorScheme? {
        switch mode {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func configureAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    private func setupScreenshotMode() {
        // Skip onboarding by default in screenshot mode
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")

        if ScreenshotMockData.shouldForceDarkMode {
            appearanceMode = "dark"
        } else {
            appearanceMode = "light"
        }

        if ScreenshotMockData.shouldShowOnboarding {
            // Force onboarding to show for that specific screenshot
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
            showingOnboarding = true
            return
        }

        // Mark model as ready so button shows "Tap to start a session"
        transcriptionManager.isModelReady = true

        // Inject mock session with analysis data
        if !ScreenshotMockData.isRecordingScreenshot {
            transcriptionManager.currentSession = ScreenshotMockData.mockSession
            // Set phase directly without triggering the auto-show sheet
            // The onChange in ContentView only fires on *changes*, so setting
            // this before the view observes prevents auto-presentation
            transcriptionManager.analysisPhase = .complete
        }

        // Populate history with mock items
        if historyManager.items.isEmpty {
            for item in ScreenshotMockData.mockHistoryItems {
                if let analysis = item.analysisV2 {
                    historyManager.add(
                        item.text,
                        analysisV2: analysis,
                        durationSeconds: item.durationSeconds,
                        utterances: item.utterances
                    )
                }
            }
        }

        // Video mode: auto-walkthrough for app preview recording
        if ScreenshotMockData.isVideoMode {
            startVideoModeWalkthrough()
        }
    }

    private func startVideoModeWalkthrough() {
        // Simulate the recording -> analysis flow with timed transitions
        transcriptionManager.currentSession = nil
        transcriptionManager.analysisPhase = .idle

        // 3s: Start "recording"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            transcriptionManager.isTranscribing = true
        }

        // 8s: Show some transcription text
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
            transcriptionManager.currentTranscription = "I feel like we haven't really talked about how the move is affecting us. I've been stressed and I don't think I've been showing up the way I want to."
        }

        // 13s: Stop recording, start "processing"
        DispatchQueue.main.asyncAfter(deadline: .now() + 13.0) {
            transcriptionManager.isTranscribing = false
            transcriptionManager.isDiarizing = true
        }

        // 17s: Move to analysis phase
        DispatchQueue.main.asyncAfter(deadline: .now() + 17.0) {
            transcriptionManager.isDiarizing = false
            transcriptionManager.isAnalyzing = true
            transcriptionManager.analysisPhase = .analyzing
        }

        // 22s: Show completed analysis
        DispatchQueue.main.asyncAfter(deadline: .now() + 22.0) {
            transcriptionManager.isAnalyzing = false
            transcriptionManager.currentSession = ScreenshotMockData.mockSession
            transcriptionManager.analysisPhase = .complete
        }
    }

    private func checkOnboardingStatus() {
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !hasCompletedOnboarding {
            showingOnboarding = true
            // Pre-load models during onboarding so they're ready when user finishes
            Task {
                try? await FluidAudioManager.shared.initializeASRIfNeeded()
            }
        }
    }

    private func handleDeepLink(_ url: URL) {
        if url.scheme == "pocketcoach" {
            if url.host == "record" {
                transcriptionManager.quickRecord()
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {
    var historyManager: SharedHistoryManager?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()

        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            if shortcutItem.type == "com.reactnativenerd.record" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let url = URL(string: "pocketcoach://record") {
                        UIApplication.shared.open(url)
                    }
                }
                return false
            }
        }

        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let historyManager = historyManager {
            historyManager.handleRemoteNotification()
            completionHandler(.newData)
        } else {
            completionHandler(.noData)
        }
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) -> Bool {
        if shortcutItem.type == "com.reactnativenerd.record" {
            if let url = URL(string: "pocketcoach://record") {
                UIApplication.shared.open(url)
            }
        }

        completionHandler(true)
        return true
    }
}
