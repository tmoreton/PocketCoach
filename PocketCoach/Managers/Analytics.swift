import FirebaseAnalytics

enum Analytics {
    static func track(_ event: String, parameters: [String: String] = [:]) {
        guard !ScreenshotMockData.isScreenshotMode else { return }
        FirebaseAnalytics.Analytics.logEvent(event, parameters: parameters)
    }

    // MARK: - App Lifecycle

    static func appLaunched() {
        track("appLaunched")
    }

    // MARK: - Recording

    static func sessionStarted() {
        track("sessionStarted")
    }

    static func sessionCompleted(durationSeconds: Int) {
        track("sessionCompleted", parameters: ["duration": durationBucket(durationSeconds)])
    }

    // MARK: - Registration

    static func registrationCompleted() {
        track("registrationCompleted")
    }

    // MARK: - Analysis

    static func analysisViewed() {
        track("analysisViewed")
    }

    static func coachingOpportunityExpanded(foul: String) {
        track("coachingOpportunityExpanded", parameters: ["foul": foul])
    }

    // MARK: - V2 Pipeline

    static func pipelineValidationFailed(reason: String) {
        track("pipelineValidationFailed", parameters: ["reason": reason])
    }

    static func pipelineCompleted(vibeScore: Int, foulsCount: Int) {
        track("pipelineCompleted", parameters: ["vibeScore": "\(vibeScore)", "foulsCount": "\(foulsCount)"])
    }

    static func pipelinePartialFailure(failedPrompts: [String]) {
        track("pipelinePartialFailure", parameters: ["failed": failedPrompts.joined(separator: ",")])
    }

    // MARK: - History

    static func historyOpened() {
        track("historyOpened")
    }

    static func historySearched() {
        track("historySearched")
    }

    static func historyFiltered(option: String) {
        track("historyFiltered", parameters: ["filter": option])
    }

    static func historySorted(option: String) {
        track("historySorted", parameters: ["sort": option])
    }

    static func sessionExported() {
        track("sessionExported")
    }

    static func sessionDeleted() {
        track("sessionDeleted")
    }

    // MARK: - Settings

    static func appearanceChanged(to mode: String) {
        track("appearanceChanged", parameters: ["mode": mode])
    }

    static func conversationModeChanged(to mode: String) {
        track("conversationModeChanged", parameters: ["mode": mode])
    }

    // MARK: - Helpers

    private static func durationBucket(_ seconds: Int) -> String {
        switch seconds {
        case ..<60: return "under1min"
        case ..<300: return "1to5min"
        case ..<900: return "5to15min"
        case ..<1800: return "15to30min"
        default: return "over30min"
        }
    }
}
