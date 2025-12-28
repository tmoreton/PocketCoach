import SwiftUI
import os.log

// MARK: - Error Types

enum MendlyError: LocalizedError, Equatable {
    case microphonePermissionDenied
    case modelDownloadFailed(String)
    case transcriptionFailed(String)
    case networkUnavailable
    case syncFailed(String)
    case audioProcessingError
    
    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone Access Required"
        case .modelDownloadFailed:
            return "Model Download Failed"
        case .transcriptionFailed:
            return "Transcription Failed"
        case .networkUnavailable:
            return "Network Unavailable"
        case .syncFailed:
            return "Sync Failed"
        case .audioProcessingError:
            return "Audio Processing Error"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Mendly needs microphone access to record sessions."
        case .modelDownloadFailed(let model):
            return "Failed to download \(model) model. Please check your connection."
        case .transcriptionFailed(let reason):
            return "Could not transcribe audio: \(reason)"
        case .networkUnavailable:
            return "Please check your internet connection and try again."
        case .syncFailed(let reason):
            return "Could not sync with iCloud: \(reason)"
        case .audioProcessingError:
            return "There was an error processing the audio."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Go to Settings > Mendly > Microphone to enable access."
        case .modelDownloadFailed:
            return "Try downloading a smaller model or free up storage space."
        case .transcriptionFailed:
            return "Try recording again with less background noise."
        case .networkUnavailable:
            return "Transcription will work offline with downloaded models."
        case .syncFailed:
            return "Your transcriptions are saved locally and will sync when available."
        case .audioProcessingError:
            return "Try recording again or restart the app."
        }
    }
}

// MARK: - Error Handler

@MainActor
class ErrorHandler: ObservableObject {
    static let shared = ErrorHandler()
    
    @Published var currentError: MendlyError?
    @Published var showingError = false
    @Published var isRecovering = false
    
    private let logger = Logger(subsystem: "com.reactnativenerd.Mendly", category: "ErrorHandler")
    private var errorQueue: [MendlyError] = []
    
    func handle(_ error: Error) {
        logger.error("Error occurred: \(error.localizedDescription)")
        
        if let therapyError = error as? MendlyError {
            handleMendlyError(therapyError)
        } else {
            // Convert to MendlyError
            let therapyError = mapToMendlyError(error)
            handleMendlyError(therapyError)
        }
    }
    
    private func handleMendlyError(_ error: MendlyError) {
        // Add to queue
        errorQueue.append(error)
        
        // Show if no error is currently displayed
        if !showingError {
            showNextError()
        }
        
        // Attempt automatic recovery for certain errors
        Task {
            await attemptAutomaticRecovery(for: error)
        }
    }
    
    private func showNextError() {
        guard !errorQueue.isEmpty else { return }
        
        currentError = errorQueue.removeFirst()
        showingError = true
    }
    
    func dismissError() {
        showingError = false
        currentError = nil
        
        // Show next error if any
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.showNextError()
        }
    }
    
    private func mapToMendlyError(_ error: Error) -> MendlyError {
        switch error {
        case let nsError as NSError:
            switch nsError.domain {
            case NSURLErrorDomain:
                return .networkUnavailable
            case "FluidAudio":
                return .transcriptionFailed(nsError.localizedDescription)
            default:
                return .transcriptionFailed(error.localizedDescription)
            }
        default:
            return .transcriptionFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Automatic Recovery
    
    private func attemptAutomaticRecovery(for error: MendlyError) async {
        isRecovering = true
        defer { isRecovering = false }
        
        switch error {
        case .networkUnavailable:
            // Wait and retry
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            // Check network again
            
        case .modelDownloadFailed:
            // Try alternative model
            logger.info("Attempting to use alternative model")
            
        case .syncFailed:
            // Queue for later sync
            logger.info("Queuing data for later sync")
            
        default:
            break
        }
    }
    
    // MARK: - Recovery Actions
    
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
    
    func retry() {
        // Implement retry logic based on last error
        guard let error = currentError else { return }
        
        dismissError()
        
        // Notify relevant managers to retry
        NotificationCenter.default.post(
            name: .retryFailedOperation,
            object: nil,
            userInfo: ["error": error]
        )
    }
}

// MARK: - Error View

struct ErrorView: View {
    let error: MendlyError
    let onDismiss: () -> Void
    let onRetry: () -> Void
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: iconName)
                .font(.system(size: 50))
                .foregroundColor(.red)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isAnimating = true
                    }
                }
            
            // Error title
            Text(error.errorDescription ?? "Error")
                .font(.title2)
                .fontWeight(.semibold)
            
            // Error details
            VStack(spacing: 12) {
                if let reason = error.failureReason {
                    Text(reason)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            // Actions
            HStack(spacing: 20) {
                Button("Dismiss") {
                    onDismiss()
                }
                .foregroundColor(.secondary)
                
                if canRetry {
                    Button("Retry") {
                        onRetry()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                }
                
                if error == .microphonePermissionDenied {
                    Button("Open Settings") {
                        ErrorHandler.shared.openSettings()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                }
            }
        }
        .padding(30)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 20)
        .padding(40)
    }
    
    private var iconName: String {
        switch error {
        case .microphonePermissionDenied:
            return "mic.slash.fill"
        case .networkUnavailable:
            return "wifi.slash"
        case .syncFailed:
            return "icloud.slash.fill"
        default:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var canRetry: Bool {
        switch error {
        case .microphonePermissionDenied:
            return false
        default:
            return true
        }
    }
}

// MARK: - Error Alert Modifier

struct ErrorAlert: ViewModifier {
    @StateObject private var errorHandler = ErrorHandler.shared
    
    func body(content: Content) -> some View {
        ZStack {
            content
            
            if errorHandler.showingError, let error = errorHandler.currentError {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .onTapGesture {
                        errorHandler.dismissError()
                    }
                
                ErrorView(
                    error: error,
                    onDismiss: {
                        errorHandler.dismissError()
                    },
                    onRetry: {
                        errorHandler.retry()
                    }
                )
                .transition(.asymmetric(
                    insertion: .scale.combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
            }
        }
        .animation(.spring(), value: errorHandler.showingError)
    }
}

extension View {
    func handlesErrors() -> some View {
        modifier(ErrorAlert())
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let retryFailedOperation = Notification.Name("com.reactnativenerd.mendly.retryFailedOperation")
}