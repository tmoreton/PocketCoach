import ActivityKit
import SwiftUI
import WidgetKit

// Audio Level View Component
struct AudioLevelView: View {
    let level: Float
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green)
                    .frame(width: geometry.size.width * CGFloat(min(level, 1.0)))
                    .animation(.linear(duration: 0.1), value: level)
            }
        }
    }
}

// Live Activity Attributes
struct RecordingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var transcriptionLength: Int
        var duration: Int
        var isProcessing: Bool
        var transcriptionPreview: String?
        var audioLevel: Float
    }
    
    var startTime: Date
}

// Live Activity Views
struct RecordingActivityView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    
    var body: some View {
        HStack {
            // Recording indicator
            HStack(spacing: 4) {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                
                if !context.state.isProcessing {
                    Text(formatDuration(context.state.duration))
                        .font(.caption)
                        .monospacedDigit()
                } else {
                    Text("Processing...")
                        .font(.caption)
                }
            }
            
            Spacer()
            
            // Character count
            Text("\(context.state.transcriptionLength) chars")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.clear)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Dynamic Island Expanded View
struct RecordingActivityExpandedView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    
    var body: some View {
        VStack(spacing: 12) {
            // Header with controls
            HStack {
                Label("Recording", systemImage: "mic.fill")
                    .font(.headline)
                    .foregroundColor(.red)
                
                Spacer()
                
                HStack(spacing: 16) {
                    // Pause/Resume button
                    Link(destination: URL(string: "pocketcoach://toggle-recording")!) {
                        Image(systemName: "pause.circle.fill")
                            .font(.title2)
                            .foregroundColor(.orange)
                    }
                    
                    // Stop button
                    Link(destination: URL(string: "pocketcoach://stop-recording")!) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Audio level indicator
            if context.state.audioLevel > 0 {
                AudioLevelView(level: context.state.audioLevel)
                    .frame(height: 4)
            }
            
            // Transcription preview
            if let preview = context.state.transcriptionPreview {
                Text(preview)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // Stats row
            HStack {
                VStack(alignment: .leading) {
                    Text(formatDuration(context.state.duration))
                        .font(.subheadline)
                        .monospacedDigit()
                    
                    Text("\(context.state.transcriptionLength) characters")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Link(destination: URL(string: "pocketcoach://recording")!) {
                    HStack {
                        Text("Open")
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(15)
                }
            }
        }
        .padding()
        .background(Color.clear)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// Dynamic Island Compact Views
struct RecordingActivityCompactLeading: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
                .foregroundColor(.red)
            if !context.state.isProcessing {
                Text(formatDuration(context.state.duration))
                    .monospacedDigit()
            }
        }
        .font(.caption2)
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let seconds = seconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct RecordingActivityCompactTrailing: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    
    var body: some View {
        Image(systemName: "waveform")
            .font(.caption2)
            .foregroundColor(.secondary)
    }
}

// Dynamic Island Minimal View
struct RecordingActivityMinimal: View {
    let context: ActivityViewContext<RecordingActivityAttributes>
    
    var body: some View {
        Image(systemName: "mic.fill")
            .foregroundColor(Color(red: 0.36, green: 0.62, blue: 0.60))
            .font(.system(size: 10))
    }
}

// Live Activity Manager
class LiveActivityManager: ObservableObject {
    private var currentActivity: Activity<RecordingActivityAttributes>?
    private var updateTimer: Timer?
    
    func startRecordingActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let attributes = RecordingActivityAttributes(startTime: Date())
        let initialState = RecordingActivityAttributes.ContentState(
            transcriptionLength: 0,
            duration: 0,
            isProcessing: false,
            transcriptionPreview: nil,
            audioLevel: 0.0
        )
        
        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
            
            // Start timer to update duration
            startDurationTimer()
        } catch {
            #if DEBUG
            print("Failed to start Live Activity: \(error)")
            #endif
        }
    }
    
    func updateTranscriptionLength(_ length: Int, preview: String? = nil) {
        Task {
            guard let activity = currentActivity else { return }
            
            let elapsed = Int(Date().timeIntervalSince(activity.attributes.startTime))
            let currentState = await activity.contentState
            let updatedState = RecordingActivityAttributes.ContentState(
                transcriptionLength: length,
                duration: elapsed,
                isProcessing: false,
                transcriptionPreview: preview ?? currentState.transcriptionPreview,
                audioLevel: currentState.audioLevel
            )
            
            await activity.update(using: updatedState)
        }
    }
    
    func updateAudioLevel(_ level: Float) {
        Task {
            guard let activity = currentActivity else { return }
            
            let currentState = await activity.contentState
            let updatedState = RecordingActivityAttributes.ContentState(
                transcriptionLength: currentState.transcriptionLength,
                duration: currentState.duration,
                isProcessing: currentState.isProcessing,
                transcriptionPreview: currentState.transcriptionPreview,
                audioLevel: level
            )
            
            await activity.update(using: updatedState)
        }
    }
    
    func stopRecordingActivity(finalLength: Int) {
        Task {
            guard let activity = currentActivity else { return }
            
            // Show processing state briefly
            let processingState = RecordingActivityAttributes.ContentState(
                transcriptionLength: finalLength,
                duration: Int(Date().timeIntervalSince(activity.attributes.startTime)),
                isProcessing: true,
                transcriptionPreview: nil,
                audioLevel: 0.0
            )
            
            await activity.update(using: processingState)
            
            // End activity after a short delay
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            await activity.end(dismissalPolicy: .immediate)
            
            currentActivity = nil
            stopDurationTimer()
        }
    }
    
    private func startDurationTimer() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateDuration()
        }
    }
    
    private func stopDurationTimer() {
        updateTimer?.invalidate()
        updateTimer = nil
    }
    
    private func updateDuration() {
        Task {
            guard let activity = currentActivity else { return }
            
            let elapsed = Int(Date().timeIntervalSince(activity.attributes.startTime))
            let currentState = await activity.contentState
            
            let updatedState = RecordingActivityAttributes.ContentState(
                transcriptionLength: currentState.transcriptionLength,
                duration: elapsed,
                isProcessing: currentState.isProcessing,
                transcriptionPreview: currentState.transcriptionPreview,
                audioLevel: currentState.audioLevel
            )
            
            await activity.update(using: updatedState)
        }
    }
}