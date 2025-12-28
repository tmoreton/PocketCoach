import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var historyManager: SharedHistoryManager
    @State private var searchText = ""
    @State private var filterOption: FilterOption = .all
    @State private var sortOption: SortOption = .newest
    @State private var selectedItems: Set<UUID> = []
    @State private var isSelectionMode = false
    @State private var selectedHistoryItem: HistoryItem?
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case today = "Today"
        case week = "Week"
        case month = "Month"
        
        var displayName: String { rawValue }
    }
    
    enum SortOption: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case hottest = "Most Heated"
        case calmest = "Calmest"

        var displayName: String { rawValue }
    }
    
    var filteredAndSortedItems: [HistoryItem] {
        let filtered = historyManager.items.filter { item in
            let searchableText = item.analysisV2?.coaching?.gameSummary ?? item.text
            let topicMatch = item.analysisV2?.analyst?.topicAnalysis.primaryCategory.localizedCaseInsensitiveContains(searchText) ?? false
            let matchesSearch = searchText.isEmpty || searchableText.localizedCaseInsensitiveContains(searchText) || topicMatch

            let matchesDate: Bool
            switch filterOption {
            case .all:
                matchesDate = true
            case .today:
                matchesDate = Calendar.current.isDateInToday(item.timestamp)
            case .week:
                matchesDate = Calendar.current.isDate(item.timestamp, equalTo: Date(), toGranularity: .weekOfYear)
            case .month:
                matchesDate = Calendar.current.isDate(item.timestamp, equalTo: Date(), toGranularity: .month)
            }

            return matchesSearch && matchesDate
        }

        return filtered.sorted { item1, item2 in
            switch sortOption {
            case .newest:
                return item1.timestamp > item2.timestamp
            case .oldest:
                return item1.timestamp < item2.timestamp
            case .hottest:
                let heat1 = item1.analysisV2?.maxGottmanSeverity ?? 0
                let heat2 = item2.analysisV2?.maxGottmanSeverity ?? 0
                return heat1 > heat2
            case .calmest:
                let vibe1 = item1.analysisV2?.vibeCard?.vibeScore ?? 50
                let vibe2 = item2.analysisV2?.vibeCard?.vibeScore ?? 50
                return vibe1 > vibe2
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Constants.adaptiveBackgroundColor.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Minimalist Header Bar
                    ZStack {
                        // Perfectly Centered Title
                        Text("History")
                            .font(.custom("DMSerifDisplay-Regular", size: 20))
                        
                        // Buttons on sides
                        HStack {
                            Button(action: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isSelectionMode.toggle()
                                    if !isSelectionMode {
                                        selectedItems.removeAll()
                                    }
                                }
                            }) {
                                Text(isSelectionMode ? "Done" : "Select")
                                    .font(.system(.caption, weight: .bold))
                                    .foregroundColor(isSelectionMode ? Constants.therapyPrimaryColor : .secondary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            
                            Spacer()

                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(8)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(Circle())
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 12)
                    
                    // Filter bar - ultra clean
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(FilterOption.allCases, id: \.self) { option in
                                FilterChip(
                                    title: option.displayName,
                                    isSelected: filterOption == option
                                ) {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        filterOption = option
                                        Analytics.historyFiltered(option: option.rawValue)
                                    }
                                }
                            }
                            
                            Divider().frame(height: 16)
                            
                            Menu {
                                ForEach(SortOption.allCases, id: \.self) { option in
                                    Button(action: {
                                        sortOption = option
                                        Analytics.historySorted(option: option.rawValue)
                                    }) {
                                        HStack {
                                            Text(option.displayName)
                                            if sortOption == option { Image(systemName: "checkmark") }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "line.3.horizontal.decrease")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(sortOption.displayName)
                                        .font(.system(size: 12, weight: .bold))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.secondary.opacity(0.05))
                                .cornerRadius(12)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    }
                    
                    // Search bar
                    SearchBar(text: $searchText)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                    
                    // Content
                    if historyManager.items.isEmpty {
                        emptyStateView
                    } else if filteredAndSortedItems.isEmpty {
                        noResultsView
                    } else {
                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredAndSortedItems) { item in
                                    HistoryItemRow(
                                        item: item,
                                        isSelected: selectedItems.contains(item.id),
                                        isSelectionMode: isSelectionMode
                                    ) {
                                        if isSelectionMode {
                                            toggleSelection(item.id)
                                        } else if item.analysisV2 != nil {
                                            selectedHistoryItem = item
                                        }
                                    }
                                    .environmentObject(historyManager)
                                }
                            }
                            .padding(.top, 8)
                            .padding(.bottom, isSelectionMode ? 100 : 20) // Dynamic padding based on selection mode
                        }
                        .scrollContentBackground(.hidden)
                        .frame(maxHeight: .infinity)
                    }
                }
                
                // Selection toolbar - overlay
                if isSelectionMode {
                    VStack {
                        Spacer()
                        selectionToolbar
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    .ignoresSafeArea(.keyboard)
                }
            }
            .navigationBarHidden(true)
            .sheet(item: $selectedHistoryItem) { item in
                if let analysisV2 = item.analysisV2, analysisV2.isValid {
                    AnalysisViewV2(analysisV2: analysisV2, utterances: item.utterances ?? [])
                        .presentationDetents([.large])
                        .presentationDragIndicator(.visible)
                        .presentationCornerRadius(32)
                }
            }
            .onAppear { Analytics.historyOpened() }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 40))
                .foregroundColor(.secondary.opacity(0.3))
            
            Text("No sessions yet")
                .font(.custom("DMSerifDisplay-Regular", size: 17))
                .foregroundColor(.secondary)
            
            Spacer()
            Spacer()
        }
    }
    
    private var noResultsView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No results for \"\(searchText)\"")
                .font(.system(.subheadline))
                .foregroundColor(.secondary)
            
            Button("Clear Search") {
                searchText = ""
            }
            .font(.system(.caption, weight: .bold))
            .foregroundColor(Constants.therapyPrimaryColor)
            
            Spacer()
            Spacer()
        }
    }
    
    private var selectionToolbar: some View {
        HStack(spacing: 24) {
            Text("\(selectedItems.count) selected")
                .font(.system(.caption, weight: .bold))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Button(action: copySelected) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(selectedItems.isEmpty)
            
            Button(action: shareSelected) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(selectedItems.isEmpty)
            
            Button(role: .destructive, action: deleteSelected) {
                Image(systemName: "trash")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.red)
            }
            .disabled(selectedItems.isEmpty)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .shadow(color: Color.black.opacity(0.1), radius: 20, y: 10)
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedItems.contains(id) {
            selectedItems.remove(id)
        } else {
            selectedItems.insert(id)
        }
    }
    
    private func copySelected() {
        let selectedTexts = historyManager.items
            .filter { selectedItems.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
            .map { item in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let dateString = formatter.string(from: item.timestamp)
                return "[\(dateString)]\n\(item.text)"
            }
            .joined(separator: "\n\n---\n\n")
        
        UIPasteboard.general.string = selectedTexts
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isSelectionMode = false
        selectedItems.removeAll()
    }
    
    private func shareSelected() {
        let selectedTexts = historyManager.items
            .filter { selectedItems.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
            .map { item in
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                let dateString = formatter.string(from: item.timestamp)
                return "[\(dateString)]\n\(item.text)"
            }
            .joined(separator: "\n\n---\n\n")
        
        let activityVC = UIActivityViewController(
            activityItems: [selectedTexts],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
    
    private func deleteSelected() {
        Analytics.sessionDeleted()
        for id in selectedItems {
            if let item = historyManager.items.first(where: { $0.id == id }) {
                historyManager.delete(item)
            }
        }
        isSelectionMode = false
        selectedItems.removeAll()
    }
    
}

struct SearchBar: View {
    @Binding var text: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 14, weight: .bold))
            
            TextField("Search sessions", text: $text)
                .font(.system(.body))
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(14)
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(isSelected ? Constants.therapyPrimaryColor : Color.secondary.opacity(0.05))
                .foregroundColor(isSelected ? .white : .secondary)
                .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct HistoryItemRow: View {
    let item: HistoryItem
    let isSelected: Bool
    let isSelectionMode: Bool
    let onTap: () -> Void
    @State private var offset: CGFloat = 0
    @State private var isSwiped = false
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var historyManager: SharedHistoryManager

    private var hasAnalysis: Bool { item.analysisV2 != nil }

    private var vibeScoreColor: Color {
        switch item.analysisV2?.vibeCard?.vibeScore ?? 50 {
        case 0..<30: return .red
        case 30..<50: return .orange
        case 50..<70: return .yellow
        case 70..<90: return .green
        default: return .green
        }
    }


    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if isSelectionMode {
                Button(action: onTap) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? Constants.therapyPrimaryColor : .secondary.opacity(0.3))
                        .font(.system(size: 20))
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.top, 12)
            }

            ZStack(alignment: .trailing) {
                // Swipe actions
                HStack(spacing: 0) {
                    Button(action: {
                        let shareText = item.analysisV2?.coaching?.gameSummary ?? item.text
                        let activityVC = UIActivityViewController(
                            activityItems: [shareText],
                            applicationActivities: nil
                        )
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first {
                            var topController = window.rootViewController
                            while let presented = topController?.presentedViewController {
                                topController = presented
                            }
                            topController?.present(activityVC, animated: true)
                        }
                        withAnimation(.spring()) {
                            offset = 0
                            isSwiped = false
                        }
                    }) {
                        VStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                            Text("Share")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .frame(width: 80)
                        .frame(maxHeight: .infinity)
                    }
                    .background(Constants.therapyPrimaryColor)

                    Button(action: {
                        withAnimation { historyManager.delete(item) }
                    }) {
                        VStack(spacing: 4) {
                            Spacer()
                            Image(systemName: "trash")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                            Text("Delete")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                            Spacer()
                        }
                        .frame(width: 80)
                        .frame(maxHeight: .infinity)
                    }
                    .background(Color.red)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                // Card content
                VStack(alignment: .leading, spacing: 12) {
                    // Date + duration header
                    HStack {
                        Text(item.timestamp, style: .date)
                            .font(.system(size: 10, weight: .black))
                            .kerning(1.0)
                        Text("•")
                            .font(.system(size: 10, weight: .black))
                        Text(item.timestamp, style: .time)
                            .font(.system(size: 10, weight: .black))
                            .kerning(1.0)

                        if let duration = item.durationSeconds {
                            Text("•")
                                .font(.system(size: 10, weight: .black))
                            Text("\(duration / 60):\(String(format: "%02d", duration % 60))")
                                .font(.system(size: 10, weight: .black))
                                .kerning(1.0)
                        }

                        Spacer()
                    }
                    .foregroundColor(Constants.therapyCardForeground.opacity(0.6))

                    if let v2 = item.analysisV2, v2.isValid {
                        // V2: Vibe score + archetype
                        if let vibe = v2.vibeCard {
                            HStack(spacing: 10) {
                                Text("\(vibe.vibeScore)/100")
                                    .font(.system(size: 18, weight: .black))
                                    .foregroundColor(vibeScoreColor)
                                Text(vibe.headlineArchetype)
                                    .font(.system(.caption, weight: .bold))
                                    .foregroundColor(vibeScoreColor)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(vibeScoreColor.opacity(0.12))
                                    .clipShape(Capsule())
                                    .lineLimit(1)
                                Spacer()
                            }
                        }

                        // Game summary
                        if let coaching = v2.coaching {
                            Text(coaching.gameSummary)
                                .font(.system(.subheadline))
                                .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                                .lineSpacing(4)
                                .lineLimit(3)
                        }

                        // Topic from analyst
                        if let analyst = v2.analyst {
                            HStack(spacing: 6) {
                                Text(analyst.topicAnalysis.primaryCategory)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Constants.therapyPrimaryColor.opacity(0.12))
                                    .foregroundColor(Constants.therapyPrimaryColor)
                                    .clipShape(Capsule())
                                Text(analyst.topicAnalysis.outcomeTag)
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.08))
                                    .foregroundColor(.secondary)
                                    .clipShape(Capsule())
                            }
                        }

                        // Foul count
                        let foulCount = v2.foulCount
                        if foulCount > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(foulCount) foul\(foulCount == 1 ? "" : "s")")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.red.opacity(0.7))
                        }
                    } else {
                        // Fallback: show raw text for old items without analysis
                        Text(item.text)
                            .font(.system(.subheadline))
                            .foregroundColor(colorScheme == .dark ? .white.opacity(0.9) : .black.opacity(0.85))
                            .lineLimit(4)
                            .lineSpacing(4)
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Constants.therapyCardBackground)
                        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.06), radius: 10, x: 0, y: 4)
                )
                .offset(x: offset)
                .gesture(
                    DragGesture(minimumDistance: 30, coordinateSpace: .local)
                        .onChanged { value in
                            if !isSelectionMode {
                                if abs(value.translation.width) > abs(value.translation.height) * 2 {
                                    if value.translation.width < 0 {
                                        offset = max(value.translation.width, -160)
                                    } else if isSwiped {
                                        offset = min(-160 + value.translation.width, 0)
                                    }
                                }
                            }
                        }
                        .onEnded { value in
                            if !isSelectionMode {
                                if abs(value.translation.width) > abs(value.translation.height) {
                                    withAnimation(.spring()) {
                                        if offset < -80 {
                                            offset = -160
                                            isSwiped = true
                                        } else {
                                            offset = 0
                                            isSwiped = false
                                        }
                                    }
                                }
                            }
                        }
                )
                .onTapGesture {
                    if isSwiped {
                        withAnimation(.spring()) {
                            offset = 0
                            isSwiped = false
                        }
                    } else {
                        onTap()
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

// MARK: - Export View

struct ExportView: View {
    let text: String
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                TextEditor(text: .constant(text))
                    .font(.system(.body, design: .monospaced))
                    .padding()
            }
            .navigationTitle("Export History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: shareText) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private func shareText() {
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}
