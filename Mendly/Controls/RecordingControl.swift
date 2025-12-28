import SwiftUI
import WidgetKit
import AppIntents

@available(iOS 18.0, *)
struct RecordingControl: ControlWidget {
    static let kind: String = "RecordingControl"
    
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind
        ) {
            ControlWidgetButton(action: RecordTranscriptionIntent()) {
                Label("Record", systemImage: "mic.fill")
            }
        }
        .displayName("Mendly Recording")
        .description("Quick toggle for audio transcription")
    }
}

// Control Center Toggle View (for iOS 17 and below fallback)
struct RecordingToggle: View {
    @State private var isRecording = false
    
    var body: some View {
        Button {
            toggleRecording()
        } label: {
            VStack {
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 24))
                    .foregroundColor(isRecording ? .red : .white)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(isRecording ? Color.red.opacity(0.2) : Color.gray.opacity(0.3))
                    )
                
                Text(isRecording ? "Recording" : "Record")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func toggleRecording() {
        isRecording.toggle()
        
        // Open app with deep link
        if let url = URL(string: "mendly://record") {
            UIApplication.shared.open(url)
        }
        
        // Reset state after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            isRecording = false
        }
    }
}