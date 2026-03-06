import XCTest

@MainActor
class PocketCoachScreenshots: XCTestCase {

    let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments += ["-SCREENSHOT_MODE"]
        setupSnapshot(app)
    }

    // MARK: - 1. Onboarding Welcome

    func test01_OnboardingWelcome() {
        app.launchArguments += ["-SHOW_ONBOARDING"]
        app.launch()

        // Dismiss ATT dialog if it appears
        let alertButton = app.alerts.firstMatch.buttons["Allow"]
        if alertButton.waitForExistence(timeout: 3) {
            alertButton.tap()
        }

        // Wait for onboarding to appear
        let welcomeText = app.staticTexts["Welcome to"]
        _ = welcomeText.waitForExistence(timeout: 5)

        snapshot("01_Onboarding_Welcome")
    }

    // MARK: - 2. Onboarding Features

    func test02_OnboardingFeatures() {
        app.launchArguments += ["-SHOW_ONBOARDING"]
        app.launch()

        // Dismiss ATT dialog if it appears
        let alertButton = app.alerts.firstMatch.buttons["Allow"]
        if alertButton.waitForExistence(timeout: 3) {
            alertButton.tap()
        }

        sleep(1)

        // Swipe to features page
        app.swipeLeft()
        sleep(1)

        snapshot("02_Onboarding_Features")
    }

    // MARK: - 3. Record Screen (idle)

    func test03_RecordScreen() {
        app.launchArguments += ["-SCREENSHOT_RECORD"]
        app.launch()

        // Wait for onAppear to set isModelReady
        let tapText = app.staticTexts["Tap to start a session"]
        if !tapText.waitForExistence(timeout: 5) {
            // Fallback: wait a bit more for state to propagate
            sleep(3)
        }
        sleep(1)

        snapshot("03_Record_Screen")
    }

    // MARK: - 4. Analysis Results (vibe score + summary on main screen)

    func test04_AnalysisResults() {
        app.launch()

        // Mock session with analysis should be injected, auto-show sheet prevented
        sleep(3)
        snapshot("04_Analysis_Results")
    }

    // MARK: - 5. Full Analysis (AnalysisViewV2)

    func test05_FullAnalysis() {
        app.launch()
        sleep(3)

        // Tap "View Full Analysis" button
        let viewFullAnalysis = app.buttons["View Full Analysis"]
        if viewFullAnalysis.waitForExistence(timeout: 5) {
            viewFullAnalysis.tap()
            sleep(2)
            snapshot("05_Full_Analysis")
        }
    }

    // MARK: - 6. Conversation View (speaker bubbles)

    func test06_ConversationView() {
        app.launchArguments += ["-SHOW_CONVERSATION"]
        app.launch()
        sleep(3)

        // Scroll down to show expanded conversation bubbles
        app.swipeUp()
        sleep(1)
        snapshot("06_Conversation_View")
    }

    // MARK: - 7. History View

    func test07_HistoryView() {
        app.launch()
        sleep(3)

        // Tap history button via accessibility identifier
        let historyButton = app.buttons["historyButton"]
        if historyButton.waitForExistence(timeout: 5) {
            historyButton.tap()
            sleep(2)
            snapshot("07_History_View")
        }
    }

    // MARK: - 8. Settings View

    func test08_SettingsView() {
        app.launch()
        sleep(3)

        // Tap settings button via accessibility identifier
        let settingsButton = app.buttons["settingsButton"]
        if settingsButton.waitForExistence(timeout: 5) {
            settingsButton.tap()
            sleep(1)
            snapshot("08_Settings_View")
        }
    }

    // MARK: - 9. Dark Mode Analysis

    func test09_DarkModeAnalysis() {
        app.launchArguments += ["-FORCE_DARK_MODE"]
        app.launch()

        sleep(3)
        snapshot("09_Dark_Mode_Analysis")
    }
}
