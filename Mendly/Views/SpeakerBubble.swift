import SwiftUI

struct SpeakerBubble: View {
    let utterance: SpeakerUtterance
    @Environment(\.colorScheme) var colorScheme

    /// 🔵 is left-aligned (blue), 🟠 is right-aligned (orange)
    private var isPerson1: Bool {
        utterance.speakerId.contains("0") || utterance.speakerId == "unknown"
    }

    private var displayLabel: String {
        utterance.speakerLabel
    }

    private var bubbleColor: Color {
        if isPerson1 {
            return colorScheme == .dark
                ? Color.blue.opacity(0.25)
                : Color.blue.opacity(0.12)
        } else {
            return colorScheme == .dark
                ? Color.orange.opacity(0.25)
                : Color.orange.opacity(0.12)
        }
    }

    private var labelColor: Color {
        isPerson1 ? .blue : .orange
    }

    var body: some View {
        HStack {
            if !isPerson1 { Spacer(minLength: 40) }

            VStack(alignment: isPerson1 ? .leading : .trailing, spacing: 4) {
                Text(displayLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(labelColor)

                Text(utterance.text)
                    .font(.system(.body))
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                    .lineSpacing(4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bubbleColor)
            )

            if isPerson1 { Spacer(minLength: 40) }
        }
    }
}

struct ConversationView: View {
    let utterances: [SpeakerUtterance]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(utterances) { utterance in
                        SpeakerBubble(utterance: utterance)
                            .id(utterance.id)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .scrollIndicators(.hidden)
            .onChange(of: utterances.count) { _ in
                if let last = utterances.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
}
