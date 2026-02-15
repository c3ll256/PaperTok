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
    @AppStorage("hasSeenSwipeGuide") private var hasSeenSwipeGuide = false
    @State private var currentIndex = 0
    @State private var rankedPapers: [Paper] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showBookmarks = false
    @State private var showSwipeGuide = false
    @State private var showMenu = false
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
                
                // Swipe gesture guide overlay
                if showSwipeGuide {
                    SwipeGestureGuideView {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showSwipeGuide = false
                        }
                        hasSeenSwipeGuide = true
                    }
                    .transition(.opacity)
                    .zIndex(10)
                }
                
                // Floating menu button — bottom-left corner
                VStack {
                    Spacer()
                    HStack {
                        FloatingMenuView(
                            isExpanded: $showMenu,
                            isLoading: isLoading,
                            onSettings: { showSettings = true },
                            onBookmarks: { showBookmarks = true },
                            onRefresh: { loadPapers() }
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
            .task {
                if hasConfiguredAPI && rankedPapers.isEmpty {
                    loadPapers()
                }
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
                guard let preference = preferences.first else {
                    await MainActor.run {
                        isLoading = false
                    }
                    return
                }
                
                let arxivService = ArxivService(modelContainer: modelContainer)
                let query = ArxivQuery(
                    categories: preference.selectedCategories,
                    maxResults: pageSize,
                    start: 0,
                    sortBy: "submittedDate",
                    sortOrder: "descending"
                )
                
                let fetchedArxivIds = try await arxivService.fetchPapers(query: query)
                
                let rankingEngine = RankingEngine(modelContainer: modelContainer)
                let rankedArxivIds = try await rankingEngine.rankPapers(fetchedArxivIds)
                
                await MainActor.run {
                    rankedPapers = rankedArxivIds.compactMap { arxivId in
                        let descriptor = FetchDescriptor<Paper>(
                            predicate: #Predicate { $0.arxivId == arxivId }
                        )
                        return try? modelContext.fetch(descriptor).first
                    }
                    currentOffset = pageSize
                    currentIndex = 0
                    isLoading = false
                    
                    // Show swipe guide on first successful load
                    if !hasSeenSwipeGuide && !rankedPapers.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            withAnimation(.easeIn(duration: 0.3)) {
                                showSwipeGuide = true
                            }
                        }
                    }
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
    private func loadMorePapers() {
        guard !isLoadingMore && !isLoading else { return }
        isLoadingMore = true
        
        Task {
            do {
                guard let preference = preferences.first else {
                    await MainActor.run {
                        isLoadingMore = false
                    }
                    return
                }
                
                let arxivService = ArxivService(modelContainer: modelContainer)
                let query = ArxivQuery(
                    categories: preference.selectedCategories,
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
                
                let rankingEngine = RankingEngine(modelContainer: modelContainer)
                let rankedArxivIds = try await rankingEngine.rankPapers(fetchedArxivIds)
                
                await MainActor.run {
                    let existingIds = Set(rankedPapers.map(\.arxivId))
                    let newPapers: [Paper] = rankedArxivIds.compactMap { arxivId in
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
}

// MARK: - Floating Menu

struct FloatingMenuView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var isExpanded: Bool
    let isLoading: Bool
    let onSettings: () -> Void
    let onBookmarks: () -> Void
    let onRefresh: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Menu items — shown when expanded
            if isExpanded {
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
                    label: "拉取论文",
                    isDisabled: isLoading
                ) {
                    withAnimation(.spring(duration: 0.35, bounce: 0.25)) {
                        isExpanded = false
                    }
                    onRefresh()
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
            
            Text("点击拉取按钮拉取最新论文")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
            
            Button(action: onRefresh) {
                Text("拉取论文")
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

// MARK: - Swipe Gesture Guide

struct SwipeGestureGuideView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onDismiss: () -> Void
    
    @State private var leftArrowOffset: CGFloat = 0
    @State private var rightArrowOffset: CGFloat = 0
    @State private var contentOpacity: Double = 0
    @State private var handOffset: CGFloat = 0
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }
            
            VStack(spacing: 48) {
                Spacer()
                
                // Swipe hints
                HStack(spacing: 0) {
                    // Right swipe → View original
                    swipeHint(
                        icon: "doc.text",
                        label: "右滑查看原文",
                        arrowDirection: .right,
                        color: Color(hex: "5DADE2"),
                        arrowOffset: rightArrowOffset
                    )
                    
                    Spacer()
                    
                    // Left swipe → Like
                    swipeHint(
                        icon: "heart.fill",
                        label: "左滑喜欢",
                        arrowDirection: .left,
                        color: Color(hex: "F1948A"),
                        arrowOffset: leftArrowOffset
                    )
                }
                .padding(.horizontal, 32)
                
                // Hand gesture illustration
                VStack(spacing: 16) {
                    Image(systemName: "hand.draw")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(0.8))
                        .offset(x: handOffset)
                    
                    Text("左右滑动卡片来操作")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                
                Spacer()
                
                // Dismiss hint
                VStack(spacing: 8) {
                    Text("点击任意位置继续")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .padding(.bottom, 100)
            }
            .opacity(contentOpacity)
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Fade in content
        withAnimation(.easeOut(duration: 0.5)) {
            contentOpacity = 1
        }
        
        // Looping arrow animations
        withAnimation(
            .easeInOut(duration: 1.0)
            .repeatForever(autoreverses: true)
        ) {
            leftArrowOffset = -12
            rightArrowOffset = 12
        }
        
        // Hand swipe animation
        withAnimation(
            .easeInOut(duration: 1.5)
            .repeatForever(autoreverses: true)
        ) {
            handOffset = 30
        }
    }
    
    enum ArrowDirection {
        case left, right
    }
    
    @ViewBuilder
    private func swipeHint(
        icon: String,
        label: String,
        arrowDirection: ArrowDirection,
        color: Color,
        arrowOffset: CGFloat
    ) -> some View {
        VStack(spacing: 12) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 64, height: 64)
                .background(color.opacity(0.15))
                .clipShape(.circle)
            
            // Arrow
            HStack(spacing: 4) {
                if arrowDirection == .left {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .opacity(0.5)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .opacity(0.5)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                }
            }
            .foregroundStyle(color)
            .offset(x: arrowOffset)
            
            // Label
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
        }
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
