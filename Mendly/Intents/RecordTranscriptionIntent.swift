import AppIntents
import SwiftUI
import UIKit

struct RecordTranscriptionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Begin a new therapy session recording")

    static var openAppWhenRun: Bool = true
    static var isDiscoverable: Bool = true

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            if let url = URL(string: "mendly://record") {
                UIApplication.shared.open(url)
            }
        }

        return .result()
    }
}

struct MendlyShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RecordTranscriptionIntent(),
            phrases: [
                "Start recording with ${applicationName}",
                "Record session in ${applicationName}",
                "New therapy session in ${applicationName}"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
    }
}
