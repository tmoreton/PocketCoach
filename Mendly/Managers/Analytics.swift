import TelemetryDeck
import FBSDKCoreKit

enum Analytics {
    static func configure() {
        let config = TelemetryDeck.Config(appID: "5930BC19-3EFB-4D11-9F9E-93936251D1F7")
        TelemetryDeck.initialize(config: config)
    }

    static func track(_ event: String, parameters: [String: String] = [:]) {
        TelemetryDeck.signal(event, parameters: parameters)
    }

    // MARK: - Recording

    static func sessionStarted() {
        track("sessionStarted")
        AppEvents.shared.logEvent(.completedTutorial)
    }

    static func sessionCompleted(durationSeconds: Int) {
        track("sessionCompleted", parameters: ["duration": durationBucket(durationSeconds)])
        AppEvents.shared.logEvent(.achievedLevel, valueToSum: Double(durationSeconds))
    }

    // MARK: - Analysis

    static func analysisGenerated(temperature: Int) {
        track("analysisGenerated", parameters: ["temperature": "\(temperature)"])
        AppEvents.shared.logEvent(.unlockedAchievement)
    }

    // MARK: - Registration

    static func registrationCompleted() {
        track("registrationCompleted")
        AppEvents.shared.logEvent(.completedRegistration)
    }

    // MARK: - Rating

    static func rated(value: Double, contentId: String) {
        track("rated", parameters: ["value": "\(value)", "contentId": contentId])
        AppEvents.shared.logEvent(.rated, valueToSum: value, parameters: [.contentID: contentId])
    }

    static func analysisViewed() {
        track("analysisViewed")
    }

    static func speakerFeedbackExpanded() {
        track("speakerFeedbackExpanded")
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

    static func languageChanged(to language: String) {
        track("languageChanged", parameters: ["language": language])
    }

    static func appearanceChanged(to mode: String) {
        track("appearanceChanged", parameters: ["mode": mode])
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
