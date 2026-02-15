import SwiftUI
import SwiftData

struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(filter: #Predicate<UserAction> { $0.isFavorited == true },
           sort: \UserAction.updatedAt,
           order: .reverse)
    private var favoriteActions: [UserAction]
    @Query private var papers: [Paper]
    @Query private var summaries: [PaperSummary]
    
    @State private var searchText = ""
    @State private var selectedCategory: String?
    
    private var modelContainer: ModelContainer { modelContext.container }
    
    // MARK: - Computed Properties
    
    private var favoritePapers: [Paper] {
        let favoritedIds = Set(favoriteActions.map(\.arxivId))
        return papers.filter { favoritedIds.contains($0.arxivId) }
    }
    
    /// All unique categories across favorited papers, sorted alphabetically
    private var allCategories: [String] {
        let categories = favoritePapers.flatMap(\.categories)
        return Array(Set(categories)).sorted()
    }
    
    /// Build a lookup from arxivId -> PaperSummary for search
    private var summaryLookup: [String: PaperSummary] {
        Dictionary(summaries.map { ($0.arxivId, $0) }, uniquingKeysWith: { _, last in last })
    }
    
    /// Papers filtered by search text and selected category
    private var filteredPapers: [Paper] {
        var result = favoritePapers
        
        // Filter by category
        if let category = selectedCategory {
            result = result.filter { $0.categories.contains(category) }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            result = result.filter { paper in
                let summary = summaryLookup[paper.arxivId]
                
                // Search in title (English)
                if paper.title.localizedStandardContains(searchText) { return true }
                // Search in Chinese title
                if let chineseTitle = summary?.titleChinese,
                   chineseTitle.localizedStandardContains(searchText) { return true }
                // Search in authors
                if paper.authors.contains(where: { $0.localizedStandardContains(searchText) }) { return true }
                // Search in categories
                if paper.categories.contains(where: { $0.localizedStandardContains(searchText) }) { return true }
                // Search in summary content
                if let problem = summary?.problem, problem.localizedStandardContains(searchText) { return true }
                if let method = summary?.method, method.localizedStandardContains(searchText) { return true }
                if let resultText = summary?.result, resultText.localizedStandardContains(searchText) { return true }
                if let oneLiner = summary?.oneLiner, oneLiner.localizedStandardContains(searchText) { return true }
                
                return false
            }
        }
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if favoritePapers.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        // Category filter chips
                        if !allCategories.isEmpty {
                            categoryFilter
                        }
                        
                        if filteredPapers.isEmpty {
                            noResultsState
                        } else {
                            paperList
                        }
                    }
                }
            }
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("收藏夹")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "搜索论文标题、作者、内容…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                    }
                }
            }
        }
    }
    
    // MARK: - Category Filter
    
    private var categoryFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                // "All" chip
                CategoryChipView(
                    label: "全部",
                    isSelected: selectedCategory == nil
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedCategory = nil
                    }
                }
                
                ForEach(allCategories, id: \.self) { category in
                    CategoryChipView(
                        label: category,
                        isSelected: selectedCategory == category
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .scrollIndicators(.hidden)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
            
            Text("暂无收藏")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
            
            Text("在浏览论文时点击喜欢按钮来收藏")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - No Results State
    
    private var noResultsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
            
            Text("未找到匹配的论文")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
            
            Text("尝试更换搜索词或筛选条件")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Paper List
    
    private var paperList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(filteredPapers, id: \.arxivId) { paper in
                    NavigationLink(value: paper.arxivId) {
                        BookmarkCardView(
                            paper: paper,
                            summary: summaryLookup[paper.arxivId],
                            onRemove: { removeFavorite(arxivId: paper.arxivId) }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationDestination(for: String.self) { arxivId in
            if let paper = favoritePapers.first(where: { $0.arxivId == arxivId }) {
                BookmarkDetailView(paper: paper, modelContainer: modelContainer)
            }
        }
    }
    
    // MARK: - Actions
    
    private func removeFavorite(arxivId: String) {
        let descriptor = FetchDescriptor<UserAction>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        if let action = try? modelContext.fetch(descriptor).first {
            action.isFavorited = false
            action.updatedAt = Date()
            try? modelContext.save()
        }
    }
}

// MARK: - Category Chip

private struct CategoryChipView: View {
    @Environment(\.colorScheme) private var colorScheme
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(
                    isSelected
                        ? AppTheme.Colors.textInverted(for: colorScheme)
                        : AppTheme.Colors.textSecondary(for: colorScheme)
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? AppTheme.Colors.textPrimary(for: colorScheme)
                        : AppTheme.Colors.surfacePrimary(for: colorScheme)
                )
                .clipShape(.capsule)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Bookmark Card

struct BookmarkCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let paper: Paper
    let summary: PaperSummary?
    let onRemove: () -> Void
    
    @State private var showRemoveConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Categories
            if !paper.categories.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(paper.categories.prefix(3), id: \.self) { category in
                            Text(category)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(AppTheme.Colors.surfaceSecondary(for: colorScheme))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            
            // Title — show Chinese title if available, otherwise English
            VStack(alignment: .leading, spacing: 4) {
                if let chineseTitle = summary?.titleChinese, !chineseTitle.isEmpty {
                    Text(chineseTitle)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                        .lineLimit(2)
                    
                    Text(paper.title)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                        .lineLimit(2)
                } else {
                    Text(paper.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                        .lineLimit(3)
                }
            }
            
            // One-liner summary preview
            if let oneLiner = summary?.oneLiner, !oneLiner.isEmpty {
                Text(oneLiner)
                    .font(.system(size: 13))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                    .lineLimit(2)
                    .italic()
            }
            
            // Authors
            Text(paper.authors.prefix(3).joined(separator: ", ") + (paper.authors.count > 3 ? " et al." : ""))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                .lineLimit(1)
            
            // Bottom row: date + remove action
            HStack {
                Text(formatDate(paper.publishedDate))
                    .font(.system(size: 12))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                
                Spacer()
                
                // Chevron indicator for navigation
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
        .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .contextMenu {
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    onRemove()
                }
            } label: {
                Label("取消收藏", systemImage: "heart.slash")
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Bookmark Detail View

/// Full detail view for a bookmarked paper — mirrors the content shown in the main feed's PaperCardView.
struct BookmarkDetailView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    let paper: Paper
    let modelContainer: ModelContainer
    
    @State private var summary: PaperSummary?
    @State private var terms: [TermGlossaryItem] = []
    @State private var isFavorited = true
    @State private var isGeneratingSummary = false
    @State private var safariURL: URL?
    
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 12) {
                    // Categories
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(paper.categories, id: \.self) { category in
                                Text(category)
                                    .font(AppTheme.Typography.tag)
                                    .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
                                    .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.tag))
                            }
                        }
                    }
                    .scrollDisabled(true)
                    .scrollIndicators(.hidden)
                    
                    // Title — bilingual (Chinese + English)
                    VStack(alignment: .leading, spacing: 6) {
                        if let chineseTitle = summary?.titleChinese, !chineseTitle.isEmpty {
                            Text(chineseTitle)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Text(paper.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(
                                summary?.titleChinese != nil
                                    ? AppTheme.Colors.textSecondary(for: colorScheme)
                                    : AppTheme.Colors.textPrimary(for: colorScheme)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    
                    // Institutions
                    if let institutions = summary?.institutions, !institutions.isEmpty, institutions != "未明确标注" {
                        HStack(spacing: 6) {
                            Image(systemName: "building.columns")
                                .font(.system(size: 13))
                                .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                            Text(institutions)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    // Authors and date
                    VStack(alignment: .leading, spacing: 4) {
                        Text(paper.authors.prefix(3).joined(separator: ", ") + (paper.authors.count > 3 ? " et al." : ""))
                            .font(.system(size: 14))
                            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                        
                        Text(formatDate(paper.publishedDate))
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                
                Divider()
                    .padding(.horizontal, 24)
                
                // Summary section
                VStack(alignment: .leading, spacing: 20) {
                    if isGeneratingSummary {
                        PulsingLoadingView(message: "AI 正在生成摘要...")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 40)
                    } else if let summary = summary {
                        SummaryContentView(summary: summary, terms: terms)
                    } else {
                        Button(action: generateSummary) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("生成 AI 摘要")
                            }
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(AppTheme.Colors.textInverted(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(AppTheme.Colors.textPrimary(for: colorScheme))
                            .clipShape(.capsule)
                            .modifier(GlassEffectModifier())
                        }
                    }
                }
                .padding(24)
                
                // Bottom actions
                BookmarkDetailActionsView(
                    paper: paper,
                    isFavorited: $isFavorited,
                    hasSummary: summary != nil,
                    isRegenerating: isGeneratingSummary,
                    onToggleFavorite: toggleFavorite,
                    onOpenOriginal: openOriginalPaper,
                    onRegenerate: regenerateSummary
                )
                .padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .background(AppTheme.Colors.background(for: colorScheme))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            feedbackGenerator.prepare()
            loadSummary()
            loadFavoriteStatus()
            
            // Generate summary if not available
            let hasFullSummary = summary?.problem != nil
            if !hasFullSummary && !isGeneratingSummary {
                generateSummary()
            }
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }
    
    // MARK: - Data Loading
    
    private func loadSummary() {
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<PaperSummary>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        if let existingSummary = try? modelContext.fetch(descriptor).first {
            summary = existingSummary
            loadTerms()
        }
    }
    
    private func loadTerms() {
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<TermGlossaryItem>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        if let fetchedTerms = try? modelContext.fetch(descriptor) {
            terms = fetchedTerms.sorted { $0.weight > $1.weight }
        }
    }
    
    private func loadFavoriteStatus() {
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<UserAction>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        if let action = try? modelContext.fetch(descriptor).first {
            isFavorited = action.isFavorited
        }
    }
    
    // MARK: - Actions
    
    private func generateSummary() {
        isGeneratingSummary = true
        
        Task {
            do {
                let summaryService = SummaryService(modelContainer: modelContainer)
                try await summaryService.generateSummary(for: paper)
                
                await MainActor.run {
                    loadSummary()
                    loadTerms()
                    isGeneratingSummary = false
                }
            } catch {
                print("Error generating summary: \(error)")
                await MainActor.run {
                    isGeneratingSummary = false
                }
            }
        }
    }
    
    private func regenerateSummary() {
        isGeneratingSummary = true
        summary = nil
        terms = []
        
        Task {
            do {
                let summaryService = SummaryService(modelContainer: modelContainer)
                try await summaryService.regenerateSummary(for: paper)
                
                await MainActor.run {
                    loadSummary()
                    loadTerms()
                    isGeneratingSummary = false
                }
            } catch {
                print("Error regenerating summary: \(error)")
                await MainActor.run {
                    isGeneratingSummary = false
                }
            }
        }
    }
    
    private func toggleFavorite() {
        feedbackGenerator.impactOccurred()
        
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<UserAction>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        if let action = try? modelContext.fetch(descriptor).first {
            action.isFavorited.toggle()
            isFavorited = action.isFavorited
            action.updatedAt = Date()
        } else {
            let newAction = UserAction(arxivId: paper.arxivId, isFavorited: true)
            modelContext.insert(newAction)
            isFavorited = true
        }
        try? modelContext.save()
    }
    
    private func openOriginalPaper() {
        if let url = URL(string: paper.pdfURL) {
            safariURL = url
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}

// MARK: - Bookmark Detail Actions

/// Action bar for the detail view — mirrors PaperBottomActionsView but without the "next article" hint.
private struct BookmarkDetailActionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let paper: Paper
    @Binding var isFavorited: Bool
    let hasSummary: Bool
    let isRegenerating: Bool
    let onToggleFavorite: () -> Void
    let onOpenOriginal: () -> Void
    let onRegenerate: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 24)
            
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 12) {
                    actionButtons
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            } else {
                actionButtons
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 12) {
            // Favorite toggle
            Button(action: onToggleFavorite) {
                HStack(spacing: 6) {
                    Image(systemName: isFavorited ? "heart.fill" : "heart")
                        .font(.system(size: 16))
                        .symbolEffect(.bounce, value: isFavorited)
                    Text(isFavorited ? "已喜欢" : "喜欢")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(
                    isFavorited
                        ? AppTheme.Colors.favorite(for: colorScheme)
                        : AppTheme.Colors.textSecondary(for: colorScheme)
                )
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(.capsule)
                .modifier(ActionButtonBackground())
            }
            .buttonStyle(.plain)
            
            // Regenerate
            if hasSummary {
                Button(action: onRegenerate) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 16))
                        Text("重新分析")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .contentShape(.capsule)
                    .modifier(ActionButtonBackground())
                }
                .buttonStyle(.plain)
                .disabled(isRegenerating)
                .opacity(isRegenerating ? 0.5 : 1)
            }
            
            // Open original
            Button(action: onOpenOriginal) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                    Text("查看原文")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(.capsule)
                .modifier(ActionButtonBackground())
            }
            .buttonStyle(.plain)
        }
    }
}

/// Applies glass effect on iOS 26+, ultraThinMaterial capsule on older versions.
private struct ActionButtonBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content
                .background(.ultraThinMaterial)
                .clipShape(.capsule)
        }
    }
}
