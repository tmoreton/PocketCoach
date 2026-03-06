#if DEBUG
import SwiftUI
import FluidAudio

struct DiarizationComparisonView: View {
    let audio: [Float]
    let sampleRate: Double

    @Environment(\.dismiss) var dismiss
    @State private var isRunning = false
    @State private var cloudSegments: [TimedSpeakerSegment]?
    @State private var deviceSegments: [TimedSpeakerSegment]?
    @State private var cloudError: String?
    @State private var deviceError: String?
    @State private var cloudDuration: TimeInterval?
    @State private var deviceDuration: TimeInterval?

    private var audioDuration: Double {
        Double(audio.count) / sampleRate
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Audio info
                    HStack {
                        Label("\(String(format: "%.1f", audioDuration))s", systemImage: "waveform")
                        Spacer()
                        Label("\(audio.count) samples", systemImage: "number")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 20)

                    if isRunning {
                        ProgressView("Running both diarization pipelines...")
                            .padding(40)
                    } else if cloudSegments != nil || deviceSegments != nil {
                        // Results
                        HStack(alignment: .top, spacing: 12) {
                            // Cloud column
                            resultColumn(
                                title: "Cloud (PyAnnote)",
                                icon: "cloud",
                                color: .blue,
                                segments: cloudSegments,
                                error: cloudError,
                                duration: cloudDuration
                            )

                            // Device column
                            resultColumn(
                                title: "On-Device",
                                icon: "cpu",
                                color: .green,
                                segments: deviceSegments,
                                error: deviceError,
                                duration: deviceDuration
                            )
                        }
                        .padding(.horizontal, 16)

                        // Timeline comparison
                        if let cloud = cloudSegments, let device = deviceSegments {
                            timelineComparison(cloud: cloud, device: device)
                                .padding(.horizontal, 16)
                        }
                    } else {
                        Button(action: { Task { await runComparison() } }) {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text("Run Comparison")
                                    .font(.system(size: 15, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(16)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                    }
                }
                .padding(.bottom, 40)
            }
            .background(Constants.adaptiveBackgroundColor.ignoresSafeArea())
            .navigationTitle("Diarization Debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Result Column

    private func resultColumn(
        title: String,
        icon: String,
        color: Color,
        segments: [TimedSpeakerSegment]?,
        error: String?,
        duration: TimeInterval?
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(.system(size: 12, weight: .black))
                    .kerning(0.5)
            }
            .foregroundColor(color)

            if let duration = duration {
                Text(String(format: "%.1fs", duration))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if let error = error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let segments = segments {
                let speakers = Set(segments.map { $0.speakerId }).sorted()
                Text("\(segments.count) segments, \(speakers.count) speakers")
                    .font(.system(size: 12, weight: .semibold))

                ForEach(speakers, id: \.self) { speaker in
                    let speakerSegs = segments.filter { $0.speakerId == speaker }
                    let totalTime = speakerSegs.reduce(0.0) { $0 + Double($1.endTimeSeconds - $1.startTimeSeconds) }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(speaker == speakers.first ? Color.blue : Color.purple)
                            .frame(width: 6, height: 6)
                        Text("\(SpeakerTextAligner.labelFor(speaker)): \(String(format: "%.1fs", totalTime))")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                // Show segment details
                ForEach(Array(segments.enumerated()), id: \.offset) { idx, seg in
                    Text("\(idx + 1). \(SpeakerTextAligner.labelFor(seg.speakerId)) [\(String(format: "%.1f", seg.startTimeSeconds))-\(String(format: "%.1f", seg.endTimeSeconds))s]")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Constants.coachingCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Timeline Comparison

    private func timelineComparison(cloud: [TimedSpeakerSegment], device: [TimedSpeakerSegment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TIMELINE")
                .font(.system(size: 11, weight: .black))
                .kerning(0.8)
                .foregroundColor(.secondary)

            // Cloud timeline
            timelineRow(label: "Cloud", segments: cloud, color: .blue)

            // Device timeline
            timelineRow(label: "Device", segments: device, color: .green)

            // Time markers
            HStack {
                Text("0s")
                Spacer()
                Text(String(format: "%.0fs", audioDuration))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Constants.coachingCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }

    private func timelineRow(label: String, segments: [TimedSpeakerSegment], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(color)

            GeometryReader { geo in
                let totalWidth = geo.size.width
                let speakers = Set(segments.map { $0.speakerId }).sorted()

                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.08))

                    // Segments
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                        let startFrac = CGFloat(seg.startTimeSeconds) / CGFloat(audioDuration)
                        let endFrac = CGFloat(seg.endTimeSeconds) / CGFloat(audioDuration)
                        let width = max((endFrac - startFrac) * totalWidth, 2)
                        let speakerIdx = speakers.firstIndex(of: seg.speakerId) ?? 0
                        let segColor: Color = speakerIdx == 0 ? color : color.opacity(0.5)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(segColor)
                            .frame(width: width, height: 14)
                            .offset(x: startFrac * totalWidth)
                    }
                }
            }
            .frame(height: 14)
        }
    }

    // MARK: - Run Comparison

    private func runComparison() async {
        isRunning = true

        // Run both in parallel
        async let cloudResult = runCloud()
        async let deviceResult = runDevice()

        let (cloud, device) = await (cloudResult, deviceResult)

        cloudSegments = cloud.segments
        cloudError = cloud.error
        cloudDuration = cloud.duration
        deviceSegments = device.segments
        deviceError = device.error
        deviceDuration = device.duration

        isRunning = false
    }

    private func runCloud() async -> (segments: [TimedSpeakerSegment]?, error: String?, duration: TimeInterval) {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let segments = try await PyAnnoteCloudService.shared.diarize(
                audio: audio,
                sampleRate: sampleRate,
                numSpeakers: 2
            )
            let duration = CFAbsoluteTimeGetCurrent() - start
            return (segments, nil, duration)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - start
            return (nil, error.localizedDescription, duration)
        }
    }

    private func runDevice() async -> (segments: [TimedSpeakerSegment]?, error: String?, duration: TimeInterval) {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let manager = FluidAudioManager.shared
            try await manager.initializeOfflineDiarizerIfNeeded(speakerCount: 2)

            guard let offlineDiarizer = manager.offlineDiarizerManager else {
                let duration = CFAbsoluteTimeGetCurrent() - start
                return (nil, "Offline diarizer not available", duration)
            }

            let diarization = try await offlineDiarizer.process(audio: audio)
            let duration = CFAbsoluteTimeGetCurrent() - start
            return (diarization.segments, nil, duration)
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - start
            return (nil, error.localizedDescription, duration)
        }
    }
}
#endif
