import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var papers: [Paper]
    @Query private var preferences: [UserPreference]
    
    private var modelContainer: ModelContainer { modelContext.container }
    
    @AppStorage("hasConfiguredAPI") private var hasConfiguredAPI = false
    @AppStorage("preloadCount") private var preloadCount = 3
    @AppStorage("feedSource") private var feedSource = FeedSource.arxiv.rawValue
    @AppStorage("hfTimePeriod") private var hfTimePeriod = HFTimePeriod.daily.rawValue
    @AppStorage("arxivSearchKeyword") private var legacyArxivSearchKeyword = ""
    @State private var currentIndex = 0
    @State private var rankedPapers: [Paper] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showBookmarks = false
    @State private var showMenu = false
    @State private var showArxivFilterSheet = false
    @State private var currentOffset = 0
    @State private var feedVersion = 0
    private let pageSize = 10
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background(for: colorScheme)
                    .ignoresSafeArea()
                
                if isLoading && rankedPapers.isEmpty {
                    LoadingView(message: "加载论文中...")
                } else if !hasConfiguredAPI {
                    SetupPromptView {
                        showSettings = true
                    }
                } else if rankedPapers.isEmpty {
                    EmptyStateView {
                        loadPapers()
                    }
                } else {
                    VerticalPagingView(
                        papers: rankedPapers,
                        currentIndex: $currentIndex,
                        modelContainer: modelContainer,
                        preloadCount: preloadCount,
                        isLoadingMore: isLoadingMore,
                        onLoadMore: loadMorePapers
                    )
                    .id(feedVersion)
                }
                
                // Floating menu button — bottom-left corner
                VStack {
                    Spacer()
                    HStack {
                        FloatingMenuView(
                            isExpanded: $showMenu,
                            isLoading: isLoading,
                            feedSource: $feedSource,
                            filterSummary: arxivFilterSummary(),
                            onSettings: { showSettings = true },
                            onBookmarks: { showBookmarks = true },
                            onRefreshLatest: { loadPapers() },
                            onTapArxivFilter: {
                                showArxivFilterSheet = true
                            }
                        )
                        Spacer()
                    }
                }
            }
            // 顶部渐变模糊
            .overlay(alignment: .top) {
                if !rankedPapers.isEmpty && !isLoading {
                    GeometryReader { geom in
                        VariableBlurView(maxBlurRadius: 10)
                            .frame(height: geom.safeAreaInsets.top)
                            .ignoresSafeArea()
                    }
                    .allowsHitTesting(false)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                SettingsView(onDismiss: {
                    if hasConfiguredAPI {
                        resetFeedAndLoad()
                    }
                })
            }
            .alert("加载失败", isPresented: $showError) {
                Button("确定", role: .cancel) { }
                Button("重试") {
                    loadPapers()
                }
            } message: {
                Text(errorMessage ?? "未知错误")
            }
            .sheet(isPresented: $showBookmarks) {
                BookmarksView()
            }
            .sheet(isPresented: $showArxivFilterSheet) {
                ArxivFeedFilterSheet(
                    selectedCategories: Set(selectedArxivCategories()),
                    keywords: selectedArxivKeywords()
                ) { categories, keywords in
                    updateArxivFilter(categories: categories, keywords: keywords)
                    resetFeedAndLoad()
                }
            }
            .task {
                migrateLegacyKeywordIfNeeded()
                ensureUserPreferenceExists()
                if hasConfiguredAPI && rankedPapers.isEmpty {
                    loadPapers()
                }
            }
            .onChange(of: feedSource) { _, _ in
                guard hasConfiguredAPI else { return }
                resetFeedAndLoad()
            }
            .onChange(of: hfTimePeriod) { _, _ in
                guard feedSource == FeedSource.huggingFace.rawValue, hasConfiguredAPI else { return }
                resetFeedAndLoad()
            }
            .onReceive(NotificationCenter.default.publisher(for: .arxivCategoriesDidChange)) { _ in
                guard feedSource == FeedSource.arxiv.rawValue, hasConfiguredAPI else { return }
                resetFeedAndLoad()
            }
            
        }
    }
    
    // MARK: - Actions
    
    /// Initial load: fetches the first page and replaces the current list.
    private func loadPapers() {
        feedVersion += 1
        let requestVersion = feedVersion
        isLoading = true
        currentOffset = 0

        Task {
            do {
                let fetchedIds: [String]

                if feedSource == FeedSource.huggingFace.rawValue {
                    // Hugging Face Papers: community-curated, already ranked by upvotes
                    let period = HFTimePeriod(rawValue: hfTimePeriod) ?? .daily
                    let hfService = HuggingFaceService(modelContainer: modelContainer)
                    fetchedIds = try await hfService.fetchPapers(period: period)
                } else {
                    // arXiv: fetch latest papers with optional keyword filter
                    let queryCategories = selectedArxivCategories()
                    let arxivService = ArxivService(modelContainer: modelContainer)
                    let query = ArxivQuery(
                        categories: queryCategories,
                        keywords: selectedArxivKeywords(),
                        maxResults: pageSize,
                        start: 0,
                        sortBy: "submittedDate",
                        sortOrder: "descending"
                    )
                    fetchedIds = try await arxivService.fetchPapers(query: query)
                }

                await MainActor.run {
                    guard requestVersion == feedVersion else { return }
                    rankedPapers = fetchedIds.compactMap { arxivId in
                        let descriptor = FetchDescriptor<Paper>(
                            predicate: #Predicate { $0.arxivId == arxivId }
                        )
                        return try? modelContext.fetch(descriptor).first
                    }
                    currentOffset = pageSize
                    currentIndex = 0
                    isLoading = false
                }
            } catch {
                print("Error loading papers: \(error)")
                await MainActor.run {
                    guard requestVersion == feedVersion else { return }
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func resetFeedAndLoad() {
        feedVersion += 1
        rankedPapers = []
        currentIndex = 0
        currentOffset = 0
        isLoadingMore = false
        showError = false
        loadPapers()
    }
    
    /// Loads the next page and appends to the current list.
    /// HuggingFace Papers is a finite curated list per period — no pagination needed.
    private func loadMorePapers() {
        guard feedSource != FeedSource.huggingFace.rawValue else { return }
        guard !isLoadingMore && !isLoading else { return }
        isLoadingMore = true
        
        Task {
            do {
                let queryCategories = selectedArxivCategories()
                let arxivService = ArxivService(modelContainer: modelContainer)
                let query = ArxivQuery(
                    categories: queryCategories,
                    keywords: selectedArxivKeywords(),
                    maxResults: pageSize,
                    start: currentOffset,
                    sortBy: "submittedDate",
                    sortOrder: "descending"
                )
                
                let fetchedArxivIds = try await arxivService.fetchPapers(query: query)
                
                guard !fetchedArxivIds.isEmpty else {
                    await MainActor.run {
                        isLoadingMore = false
                    }
                    return
                }
                
                await MainActor.run {
                    let existingIds = Set(rankedPapers.map(\.arxivId))
                    let newPapers: [Paper] = fetchedArxivIds.compactMap { arxivId in
                        guard !existingIds.contains(arxivId) else { return nil }
                        let descriptor = FetchDescriptor<Paper>(
                            predicate: #Predicate { $0.arxivId == arxivId }
                        )
                        return try? modelContext.fetch(descriptor).first
                    }
                    rankedPapers.append(contentsOf: newPapers)
                    currentOffset += pageSize
                    isLoadingMore = false
                }
            } catch {
                print("Error loading more papers: \(error)")
                await MainActor.run {
                    isLoadingMore = false
                }
            }
        }
    }

    private func selectedArxivCategories() -> [String] {
        let selected = preferences.first?.selectedCategories ?? []
        if !selected.isEmpty {
            return selected
        }
        return CategorySelectionView.allCategories.map(\.code)
    }

    private func selectedArxivKeywords() -> [String] {
        preferences.first?.filterKeywords ?? []
    }

    private func arxivFilterSummary() -> String {
        let categories = selectedArxivCategories()
        let keywords = selectedArxivKeywords()
        let allCategoryCodes = CategorySelectionView.allCategories.map(\.code)
        let categoryCount = categories.count
        let isAllCategories = Set(categories) == Set(allCategoryCodes)

        var parts: [String] = []
        if !isAllCategories {
            parts.append("\(categoryCount) 个板块")
        }
        if !keywords.isEmpty {
            if keywords.count == 1 {
                parts.append(keywords[0])
            } else {
                parts.append("\(keywords.count) 个关键词")
            }
        }

        if parts.isEmpty {
            return "筛选条件"
        }
        return "筛选：" + parts.joined(separator: " · ")
    }

    private func migrateLegacyKeywordIfNeeded() {
        let trimmed = legacyArxivSearchKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let descriptor = FetchDescriptor<UserPreference>()
        let preference: UserPreference
        if let existing = try? modelContext.fetch(descriptor).first {
            preference = existing
        } else {
            let created = UserPreference(
                selectedCategories: CategorySelectionView.allCategories.map(\.code)
            )
            modelContext.insert(created)
            preference = created
        }

        if preference.filterKeywords.isEmpty {
            preference.filterKeywords = [trimmed]
            preference.updatedAt = Date()
            try? modelContext.save()
        }

        legacyArxivSearchKeyword = ""
    }

    private func ensureUserPreferenceExists() {
        guard preferences.isEmpty else { return }
        let defaultCategories = CategorySelectionView.allCategories.map(\.code)
        let preference = UserPreference(selectedCategories: defaultCategories)
        modelContext.insert(preference)
        try? modelContext.save()
    }

    private func updateArxivFilter(categories: Set<String>, keywords: [String]) {
        let descriptor = FetchDescriptor<UserPreference>()
        let preference: UserPreference
        if let existing = try? modelContext.fetch(descriptor).first {
            preference = existing
        } else {
            let created = UserPreference(selectedCategories: CategorySelectionView.allCategories.map(\.code))
            modelContext.insert(created)
            preference = created
        }

        let finalCategories: [String]
        if categories.isEmpty {
            finalCategories = CategorySelectionView.allCategories.map(\.code)
        } else {
            finalCategories = Array(categories).sorted()
        }

        preference.selectedCategories = finalCategories
        preference.filterKeywords = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        preference.updatedAt = Date()
        try? modelContext.save()
    }
}

extension Notification.Name {
    static let arxivCategoriesDidChange = Notification.Name("arxivCategoriesDidChange")
}

// MARK: - Floating Menu

struct FloatingMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isExpanded: Bool
    let isLoading: Bool
    @Binding var feedSource: String
    let filterSummary: String
    let onSettings: () -> Void
    let onBookmarks: () -> Void
    let onRefreshLatest: () -> Void
    let onTapArxivFilter: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Menu items — shown when expanded
            if isExpanded {
                if feedSource == FeedSource.arxiv.rawValue {
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                            isExpanded = false
                        }
                        onTapArxivFilter()
                    } label: {
                        FloatingMenuLabel(
                            icon: "line.3.horizontal.decrease.circle",
                            label: filterSummary
                        )
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity)
                    ))
                }

                FloatingMenuItem(
                    icon: "gearshape",
                    label: "设置"
                ) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                        isExpanded = false
                    }
                    onSettings()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity)
                ))
                
                FloatingMenuItem(
                    icon: "archivebox",
                    label: "收藏夹"
                ) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                        isExpanded = false
                    }
                    onBookmarks()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity)
                ))
                
                FloatingMenuItem(
                    icon: "arrow.2.circlepath.circle",
                    label: "拉取最新论文",
                    isDisabled: isLoading
                ) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                        isExpanded = false
                    }
                    onRefreshLatest()
                }
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity)
                ))
            }
            
            // FAB trigger button
            Button {
                withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                fabLabel
            }
            .buttonStyle(FABButtonStyle())
        }
        .padding(.leading, 20)
        .padding(.bottom, 16)
    }
    
    @ViewBuilder
    private var fabLabel: some View {
        if #available(iOS 26, *) {
            Image(systemName: isExpanded ? "xmark" : "ellipsis")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                .frame(width: 52, height: 52)
                .contentShape(.circle)
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            Image(systemName: isExpanded ? "xmark" : "ellipsis")
                .contentTransition(.symbolEffect(.replace))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                .frame(width: 52, height: 52)
                .background(.thickMaterial)
                .clipShape(.circle)
        }
    }
}

private struct FloatingMenuLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let label: String

    var body: some View {
        Group {
            if #available(iOS 26, *) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .contentShape(.capsule)
                .glassEffect(.regular.interactive(), in: .capsule)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                    Text(label)
                        .font(.system(size: 15, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                .padding(.horizontal, 16)
                .frame(height: 44)
                .background(.thickMaterial)
                .clipShape(.capsule)
            }
        }
    }
}

struct FloatingMenuItem: View {
    @Environment(\.colorScheme) private var colorScheme
    let icon: String
    let label: String
    var isDisabled: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            menuContent
        }
        .buttonStyle(ToolbarButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1)
    }
    
    @ViewBuilder
    private var menuContent: some View {
        if #available(iOS 26, *) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .contentShape(.capsule)
            .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
            .padding(.horizontal, 16)
            .frame(height: 44)
            .background(.thickMaterial)
            .clipShape(.capsule)
        }
    }
}

struct ArxivFeedFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedCategories: Set<String>
    @State private var keywords: [String]
    @State private var keywordInput = ""
    @FocusState private var isKeywordFieldFocused: Bool

    let onApply: (Set<String>, [String]) -> Void

    init(
        selectedCategories: Set<String>,
        keywords: [String],
        onApply: @escaping (Set<String>, [String]) -> Void
    ) {
        _selectedCategories = State(initialValue: selectedCategories)
        _keywords = State(initialValue: keywords)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    keywordSection
                    categorySection
                }
                .padding(20)
                .padding(.bottom, 24)
            }
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("筛选条件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(selectedCategories, keywords)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var keywordSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("关键词")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))

            Text("匹配标题、摘要等任意字段；多个关键词为「或」关系")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))

            HStack(spacing: 8) {
                TextField("例如：diffusion model", text: $keywordInput)
                    .textFieldStyle(CustomTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isKeywordFieldFocused)
                    .onSubmit(addKeyword)

                Button(action: addKeyword) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(
                            keywordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? AppTheme.Colors.textTertiary(for: colorScheme)
                                : AppTheme.Colors.textPrimary(for: colorScheme)
                        )
                }
                .disabled(keywordInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !keywords.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(keywords, id: \.self) { keyword in
                        KeywordChip(keyword: keyword) {
                            keywords.removeAll { $0 == keyword }
                        }
                    }
                }

                Button("清空全部关键词") {
                    keywords = []
                }
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
            }
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("板块")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))

            Text("至少选择一个 arXiv 分类")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))

            LazyVStack(spacing: 10) {
                ForEach(CategorySelectionView.allCategories, id: \.code) { category in
                    Button {
                        toggleCategory(category.code)
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.chinese)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                                Text(category.code)
                                    .font(.system(size: 13))
                                    .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                            }
                            Spacer()
                            Image(systemName: selectedCategories.contains(category.code) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(
                                    selectedCategories.contains(category.code)
                                        ? AppTheme.Colors.textPrimary(for: colorScheme)
                                        : AppTheme.Colors.textTertiary(for: colorScheme)
                                )
                        }
                        .padding(12)
                        .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
                        .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card)
                                .stroke(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func addKeyword() {
        let trimmed = keywordInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !keywords.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            keywordInput = ""
            return
        }
        keywords.append(trimmed)
        keywordInput = ""
        isKeywordFieldFocused = true
    }

    private func toggleCategory(_ code: String) {
        if selectedCategories.contains(code) {
            if selectedCategories.count > 1 {
                selectedCategories.remove(code)
            }
        } else {
            selectedCategories.insert(code)
        }
    }
}

private struct KeywordChip: View {
    @Environment(\.colorScheme) private var colorScheme
    let keyword: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Text(keyword)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppTheme.Colors.surfaceSecondary(for: colorScheme))
        .clipShape(.capsule)
    }
}

/// Simple wrapping layout for keyword chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

struct SetupPromptView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onSetup: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            Button(action: onSetup) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                    Text("配置模型")
                }
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.textInverted(for: colorScheme))
                .frame(width: 160, height: 50)
                .background(AppTheme.Colors.textPrimary(for: colorScheme))
                .clipShape(.capsule)
                .modifier(GlassEffectModifier())
            }
        }
    }
}

struct EmptyStateView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onRefresh: () -> Void
    
    var body: some View {
        Button(action: onRefresh) {
            Text("重新加载")
                .font(AppTheme.Typography.headline)
                .foregroundStyle(AppTheme.Colors.textInverted(for: colorScheme))
                .frame(width: 132, height: 44)
                .background(AppTheme.Colors.textPrimary(for: colorScheme))
                .clipShape(.capsule)
                .modifier(GlassEffectModifier())
        }
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.75 : 1.0)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct FABButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Vertical Paging

struct VerticalPagingView: View {
    let papers: [Paper]
    @Binding var currentIndex: Int
    let modelContainer: ModelContainer
    let preloadCount: Int
    let isLoadingMore: Bool
    let onLoadMore: () -> Void
    
    @State private var scrollPosition: Int?
    @State private var preloadedIndices: Set<Int> = []
    
    /// Trigger loading more when the user is within this many papers of the end.
    private let loadMoreThreshold = 3
    
    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(papers.enumerated()), id: \.element.arxivId) { index, paper in
                        PaperCardView(paper: paper, modelContainer: modelContainer)
                            .frame(width: geometry.size.width, height: totalHeight)
                            .clipped()
                            .id(index)
                    }
                    
                    // Loading indicator at the bottom
                    if isLoadingMore {
                        LoadingMoreIndicator()
                            .frame(width: geometry.size.width, height: totalHeight)
                            .id(-1)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollPosition)
            .onChange(of: scrollPosition) { oldValue, newValue in
                if let newValue = newValue, newValue >= 0 {
                    currentIndex = newValue
                    preloadUpcoming(from: newValue)
                    checkAndLoadMore(currentIndex: newValue)
                }
            }
            .onAppear {
                scrollPosition = currentIndex
                preloadUpcoming(from: currentIndex)
            }
        }
        .ignoresSafeArea()
    }
    
    /// Preload title translations and summaries for the next N papers
    private func preloadUpcoming(from index: Int) {
        guard preloadCount > 0 else { return }
        
        let start = index + 1
        let end = min(index + preloadCount, papers.count - 1)
        guard start <= end else { return }
        
        for i in start...end {
            guard !preloadedIndices.contains(i) else { continue }
            preloadedIndices.insert(i)
            
            let paper = papers[i]
            Task {
                let summaryService = SummaryService(modelContainer: modelContainer)
                
                // 1. Fast title translation
                _ = try? await summaryService.translateTitle(for: paper)
                
                // 2. Full summary
                _ = try? await summaryService.generateSummary(for: paper)
            }
        }
    }
    
    /// Triggers loading more papers when approaching the end of the list.
    private func checkAndLoadMore(currentIndex: Int) {
        let remaining = papers.count - 1 - currentIndex
        if remaining <= loadMoreThreshold {
            onLoadMore()
        }
    }
}

// MARK: - Loading More Indicator

struct LoadingMoreIndicator: View {
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(AppTheme.Colors.textSecondary(for: colorScheme))
            
            Text("加载更多论文...")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
        }
    }
}
