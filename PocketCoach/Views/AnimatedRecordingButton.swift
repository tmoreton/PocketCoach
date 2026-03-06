import SwiftUI

// MARK: - Audio Level Visualizer

struct AudioLevelVisualizer: View {
    let audioLevel: Float
    @State private var bars: [CGFloat] = Array(repeating: 0.2, count: 5)
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Constants.coachingPrimaryColor)
                    .frame(width: 4, height: 30 * bars[index])
                    .animation(.spring(response: 0.1), value: bars[index])
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            updateBars()
        }
    }
    
    private func updateBars() {
        for i in 0..<bars.count {
            let randomVariation = CGFloat.random(in: -0.1...0.1)
            let targetHeight = CGFloat(audioLevel) + randomVariation
            bars[i] = max(0.2, min(1.0, targetHeight + CGFloat(i) * 0.05))
        }
    }
}

// MARK: - Shimmer Effect

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    let duration: Double
    
    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .rotationEffect(.degrees(30))
                .offset(x: phase * 200 - 100)
                .mask(content)
            )
            .onAppear {
                withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer(duration: Double = 2.0) -> some View {
        modifier(ShimmerEffect(duration: duration))
    }
}

struct AnimatedRecordingButton: View {
    @Binding var isRecording: Bool
    let action: () -> Void
    var isDisabled: Bool = false
    var loadingText: String? = nil
    
    @State private var scale: CGFloat = 1.0
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0.0
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        ZStack {
            // Ripple effect
            Circle()
                .stroke(isRecording ? Color.red : Constants.coachingPrimaryColor, lineWidth: 2)
                .scaleEffect(rippleScale)
                .opacity(rippleOpacity)
            
            // Main button
            Button(action: {
                guard !isDisabled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    action()
                }
                
                // Trigger ripple
                withAnimation(.easeOut(duration: 0.6)) {
                    rippleScale = 2.0
                    rippleOpacity = 0.0
                }
                
                // Reset ripple
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    rippleScale = 1.0
                    rippleOpacity = isRecording ? 0.3 : 0.0
                }
            }) {
                ZStack {
                    // Background circle
                    Circle()
                        .fill(buttonBackgroundColor)
                        .shadow(color: buttonShadowColor, radius: isRecording ? 15 : 10)
                    
                    if let loadingText = loadingText {
                        // Loading state
                        VStack(spacing: 12) {
                            ZStack {
                                // Outer ring
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 3)
                                    .frame(width: 40, height: 40)
                                
                                // Animated progress ring
                                Circle()
                                    .trim(from: 0, to: 0.7)
                                    .stroke(
                                        AngularGradient(
                                            colors: [Color.white, Color.white.opacity(0.3)],
                                            center: .center,
                                            startAngle: .degrees(0),
                                            endAngle: .degrees(360)
                                        ),
                                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                                    )
                                    .frame(width: 40, height: 40)
                                    .rotationEffect(.degrees(rotationAngle))
                            }
                            
                            Text(loadingText)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .opacity(0.95)
                        }
                    } else {
                        // Normal mic/stop icon
                        Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 44, weight: .semibold))
                            .foregroundColor(.white)
                            .scaleEffect(scale)
                            .rotationEffect(.degrees(isRecording ? 90 : 0))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
                    }
                }
                .frame(width: 120, height: 120)
            }
            .scaleEffect(scale)
            .onAppear {
                if isRecording {
                    startPulsingAnimation()
                }
                if loadingText != nil {
                    startLoadingAnimation()
                }
            }
            .onChange(of: isRecording) { newValue in
                if newValue {
                    startPulsingAnimation()
                } else {
                    stopPulsingAnimation()
                }
            }
            .onChange(of: loadingText) { newValue in
                if newValue != nil {
                    startLoadingAnimation()
                } else {
                    stopLoadingAnimation()
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var buttonBackgroundColor: Color {
        if isDisabled {
            return Color.gray
        } else if isRecording {
            return Color.red
        } else {
            return Constants.coachingPrimaryColor
        }
    }
    
    private var buttonShadowColor: Color {
        if isDisabled {
            return Color.gray.opacity(0.3)
        } else if isRecording {
            return Color.red.opacity(0.3)
        } else {
            return Constants.coachingPrimaryColor.opacity(0.3)
        }
    }
    
    // MARK: - Animation Methods
    
    private func startPulsingAnimation() {
        withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
            rippleOpacity = 0.3
        }
        
        withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
            scale = 1.05
        }
    }
    
    private func stopPulsingAnimation() {
        withAnimation(.spring()) {
            scale = 1.0
            rippleOpacity = 0.0
        }
    }
    
    private func startLoadingAnimation() {
        withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
    
    private func stopLoadingAnimation() {
        withAnimation(.spring()) {
            rotationAngle = 0
        }
    }
}