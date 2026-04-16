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
    @AppStorage("arxivSearchKeyword") private var arxivSearchKeyword = ""
    @State private var currentIndex = 0
    @State private var rankedPapers: [Paper] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showBookmarks = false
    @State private var showMenu = false
    @State private var showArxivSearchSheet = false
    @State private var showDataSourceSheet = false
    @State private var showCategorySheet = false
    @State private var currentOffset = 0
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
                }
                
                // Floating menu button — bottom-left corner
                VStack {
                    Spacer()
                    HStack {
                        FloatingMenuView(
                            isExpanded: $showMenu,
                            isLoading: isLoading,
                            feedSource: $feedSource,
                            arxivSearchKeyword: arxivSearchKeyword,
                            onSettings: { showSettings = true },
                            onBookmarks: { showBookmarks = true },
                            onRefreshLatest: { loadPapers() },
                            onTapArxivSearch: {
                                showArxivSearchSheet = true
                            },
                            onTapDataSource: {
                                showDataSourceSheet = true
                            },
                            onTapArxivCategories: {
                                showCategorySheet = true
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
                    if hasConfiguredAPI && rankedPapers.isEmpty {
                        loadPapers()
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
            .sheet(isPresented: $showArxivSearchSheet) {
                ArxivSearchSheet(initialKeyword: arxivSearchKeyword) { keyword in
                    arxivSearchKeyword = keyword
                    rankedPapers = []
                    loadPapers()
                }
            }
            .sheet(isPresented: $showDataSourceSheet) {
                DataSourcePickerSheet(selectedSource: feedSource) { source in
                    feedSource = source
                }
            }
            .sheet(isPresented: $showCategorySheet) {
                ArxivCategoryMultiSelectSheet(
                    selectedCategories: Set(selectedArxivCategories())
                ) { categories in
                    updateArxivCategories(categories)
                    rankedPapers = []
                    loadPapers()
                }
            }
            .task {
                ensureUserPreferenceExists()
                if hasConfiguredAPI && rankedPapers.isEmpty {
                    loadPapers()
                }
            }
            .onChange(of: feedSource) { _, _ in
                guard hasConfiguredAPI else { return }
                rankedPapers = []
                loadPapers()
            }
            .onChange(of: hfTimePeriod) { _, _ in
                guard feedSource == FeedSource.huggingFace.rawValue, hasConfiguredAPI else { return }
                rankedPapers = []
                loadPapers()
            }
            
        }
    }
    
    // MARK: - Actions
    
    /// Initial load: fetches the first page and replaces the current list.
    private func loadPapers() {
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
                        keyword: arxivSearchKeyword,
                        maxResults: pageSize,
                        start: 0,
                        sortBy: "submittedDate",
                        sortOrder: "descending"
                    )
                    fetchedIds = try await arxivService.fetchPapers(query: query)
                }

                await MainActor.run {
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
                    isLoading = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
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
                    keyword: arxivSearchKeyword,
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

    private func ensureUserPreferenceExists() {
        guard preferences.isEmpty else { return }
        let defaultCategories = CategorySelectionView.allCategories.map(\.code)
        let preference = UserPreference(selectedCategories: defaultCategories)
        modelContext.insert(preference)
        try? modelContext.save()
    }

    private func updateArxivCategories(_ categories: Set<String>) {
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
        preference.updatedAt = Date()
        try? modelContext.save()
    }
}

// MARK: - Floating Menu

struct FloatingMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isExpanded: Bool
    let isLoading: Bool
    @Binding var feedSource: String
    let arxivSearchKeyword: String
    let onSettings: () -> Void
    let onBookmarks: () -> Void
    let onRefreshLatest: () -> Void
    let onTapArxivSearch: () -> Void
    let onTapDataSource: () -> Void
    let onTapArxivCategories: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Menu items — shown when expanded
            if isExpanded {
                Button {
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                        isExpanded = false
                    }
                    onTapDataSource()
                } label: {
                    FloatingMenuLabel(icon: "square.2.layers.3d", label: dataSourceLabel)
                }
                .buttonStyle(ToolbarButtonStyle())
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity),
                    removal: .scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity)
                ))

                if feedSource == FeedSource.arxiv.rawValue {
                    Button {
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                            isExpanded = false
                        }
                        onTapArxivCategories()
                    } label: {
                        FloatingMenuLabel(
                            icon: "line.3.horizontal.decrease.circle",
                            label: "分类筛选（多选）"
                        )
                    }
                    .buttonStyle(ToolbarButtonStyle())
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.5, anchor: .bottomLeading).combined(with: .opacity),
                        removal: .scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity)
                    ))

                    FloatingMenuItem(
                        icon: "magnifyingglass",
                        label: arxivSearchKeyword.isEmpty ? "搜索论文" : "搜索：\(arxivSearchKeyword)"
                    ) {
                        withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                            isExpanded = false
                        }
                        onTapArxivSearch()
                    }
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

    private var dataSourceLabel: String {
        feedSource == FeedSource.arxiv.rawValue ? "数据源：arXiv" : "数据源：Hugging Face"
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

struct ArxivSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var keyword: String
    let onSearch: (String) -> Void

    init(initialKeyword: String, onSearch: @escaping (String) -> Void) {
        _keyword = State(initialValue: initialKeyword)
        self.onSearch = onSearch
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("输入关键词后，将在 arXiv 中拉取匹配的最新论文")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextField("例如：diffusion model", text: $keyword)
                    .textFieldStyle(CustomTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    onSearch(keyword.trimmingCharacters(in: .whitespacesAndNewlines))
                    dismiss()
                } label: {
                    Text("搜索")
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textInverted(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(AppTheme.Colors.textPrimary(for: colorScheme))
                        .clipShape(.capsule)
                }
                .modifier(GlassEffectModifier())

                Button("清空关键词并查看全部") {
                    onSearch("")
                    dismiss()
                }
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))

                Spacer()
            }
            .padding(24)
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("arXiv 搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DataSourcePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedSource: String
    let onSelect: (String) -> Void

    init(selectedSource: String, onSelect: @escaping (String) -> Void) {
        _selectedSource = State(initialValue: selectedSource)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                dataSourceRow(
                    title: "arXiv",
                    subtitle: "按最新提交时间拉取论文",
                    value: FeedSource.arxiv.rawValue
                )

                dataSourceRow(
                    title: "Hugging Face Papers",
                    subtitle: "社区聚合与热度排序",
                    value: FeedSource.huggingFace.rawValue
                )

                Spacer()
            }
            .padding(24)
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("选择数据源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onSelect(selectedSource)
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

    private func dataSourceRow(title: String, subtitle: String, value: String) -> some View {
        Button {
            selectedSource = value
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                }
                Spacer()
                Image(systemName: selectedSource == value ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(selectedSource == value ? AppTheme.Colors.textPrimary(for: colorScheme) : AppTheme.Colors.textTertiary(for: colorScheme))
            }
            .padding(14)
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

struct ArxivCategoryMultiSelectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedCategories: Set<String>
    let onApply: (Set<String>) -> Void

    init(selectedCategories: Set<String>, onApply: @escaping (Set<String>) -> Void) {
        _selectedCategories = State(initialValue: selectedCategories)
        self.onApply = onApply
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(CategorySelectionView.allCategories, id: \.code) { category in
                            Button {
                                toggle(category.code)
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
                                        .foregroundStyle(selectedCategories.contains(category.code) ? AppTheme.Colors.textPrimary(for: colorScheme) : AppTheme.Colors.textTertiary(for: colorScheme))
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
                    .padding(16)
                    .padding(.bottom, 20)
                }
            }
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("分类筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("应用") {
                        onApply(selectedCategories)
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

    private func toggle(_ code: String) {
        if selectedCategories.contains(code) {
            if selectedCategories.count > 1 {
                selectedCategories.remove(code)
            }
        } else {
            selectedCategories.insert(code)
        }
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
        VStack(spacing: 20) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 60))
                .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
            
            Text("暂无论文")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
            
            Text("点击按钮拉取最新论文")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
            
            Button(action: onRefresh) {
                Text("拉取最新论文")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textInverted(for: colorScheme))
                    .frame(width: 120, height: 44)
                    .background(AppTheme.Colors.textPrimary(for: colorScheme))
                    .clipShape(.capsule)
                    .modifier(GlassEffectModifier())
            }
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
