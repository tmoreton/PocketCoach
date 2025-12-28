//
//  MendlyApp.swift
//  Mendly
//
//  Created by Tim Moreton on 12/20/25.
//

import SwiftUI
import AppIntents
import FBSDKCoreKit

@main
struct MendlyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var historyManager = SharedHistoryManager()
    @StateObject private var transcriptionManager = AudioTranscriptionManager_iOS()
    @StateObject private var liveActivityManager = LiveActivityManager()
    @AppStorage("appearanceMode") private var appearanceMode = "light"
    @State private var showingOnboarding = false

    init() {
        configureAppearance()
        Analytics.configure()
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
                    checkOnboardingStatus()
                    // Pre-load model in background so it's ready when user taps record
                    Task {
                        try? await transcriptionManager.initializeModelIfNeeded()
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
        if url.scheme == "mendly" {
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
        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: launchOptions)
        application.registerForRemoteNotifications()

        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            if shortcutItem.type == "com.reactnativenerd.record" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let url = URL(string: "mendly://record") {
                        UIApplication.shared.open(url)
                    }
                }
                return false
            }
        }

        return true
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        ApplicationDelegate.shared.application(app, open: url, sourceApplication: options[UIApplication.OpenURLOptionsKey.sourceApplication] as? String, annotation: options[UIApplication.OpenURLOptionsKey.annotation])
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
            if let url = URL(string: "mendly://record") {
                UIApplication.shared.open(url)
            }
        }

        completionHandler(true)
        return true
    }
}
