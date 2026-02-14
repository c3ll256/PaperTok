import SwiftUI
import SwiftData

struct FeedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query private var papers: [Paper]
    @Query private var preferences: [UserPreference]
    
    @AppStorage("hasConfiguredAPI") private var hasConfiguredAPI = false
    @State private var currentIndex = 0
    @State private var rankedPapers: [Paper] = []
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showBookmarks = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.Colors.background(for: colorScheme)
                    .ignoresSafeArea()
                
                if isLoading {
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
                        modelContext: modelContext
                    )
                }
                
                // 统一的底部工具栏
                if !rankedPapers.isEmpty && !isLoading {
                    VStack {
                        Spacer()
                        bottomToolbar
                    }
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
    
    // MARK: - Bottom Toolbar
    
    @ViewBuilder
    private var bottomToolbar: some View {
        GeometryReader { geo in
            let barWidth = geo.size.width * 0.55
            
            if #available(iOS 26, *) {
                HStack {
                    HStack(spacing: 0) {
                        // 设置
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        
                        // 收藏夹
                        Button {
                            showBookmarks = true
                        } label: {
                            Image(systemName: "archivebox")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        
                        // 拉取新内容
                        Button {
                            loadPapers()
                        } label: {
                            Image(systemName: "arrow.2.circlepath.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        .disabled(isLoading)
                    }
                    .frame(width: barWidth)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            } else {
                HStack {
                    HStack(spacing: 0) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        
                        Button {
                            showBookmarks = true
                        } label: {
                            Image(systemName: "archivebox")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        
                        Button {
                            loadPapers()
                        } label: {
                            Image(systemName: "arrow.2.circlepath.circle")
                                .font(.system(size: 20))
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                        }
                        .buttonStyle(ToolbarButtonStyle())
                        .disabled(isLoading)
                    }
                    .frame(width: barWidth)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(.capsule)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
            }
        }
        .frame(height: 48)
        .padding(.bottom, 12)
    }
    
    // MARK: - Actions
    
    private func loadPapers() {
        isLoading = true
        
        Task {
            do {
                guard let preference = preferences.first else {
                    await MainActor.run {
                        isLoading = false
                    }
                    return
                }
                
                let arxivService = ArxivService(modelContext: modelContext)
                let query = ArxivQuery(
                    categories: preference.selectedCategories,
                    maxResults: 50,
                    sortBy: "submittedDate",
                    sortOrder: "descending"
                )
                
                let fetchedPapers = try await arxivService.fetchPapers(query: query)
                
                let rankingEngine = RankingEngine(modelContext: modelContext)
                let ranked = try await rankingEngine.rankPapers(fetchedPapers)
                
                await MainActor.run {
                    rankedPapers = ranked
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
                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                .frame(width: 160, height: 50)
                .background(AppTheme.Colors.surfaceSecondary(for: colorScheme))
                .clipShape(.rect(cornerRadius: 25))
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
            
            Text("点击刷新按钮加载最新论文")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
            
            Button(action: onRefresh) {
                Text("刷新")
                    .font(AppTheme.Typography.headline)
                    .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                    .frame(width: 120, height: 44)
                    .background(AppTheme.Colors.surfaceSecondary(for: colorScheme))
                    .clipShape(.rect(cornerRadius: 22))
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

struct VerticalPagingView: View {
    let papers: [Paper]
    @Binding var currentIndex: Int
    let modelContext: ModelContext
    
    @State private var scrollPosition: Int?
    
    var body: some View {
        GeometryReader { geometry in
            let totalHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            ScrollView(.vertical) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(papers.enumerated()), id: \.element.arxivId) { index, paper in
                        PaperCardView(paper: paper, modelContext: modelContext)
                            .frame(width: geometry.size.width, height: totalHeight)
                            .clipped()
                            .id(index)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $scrollPosition)
            .onChange(of: scrollPosition) { oldValue, newValue in
                if let newValue = newValue {
                    currentIndex = newValue
                }
            }
            .onAppear {
                scrollPosition = currentIndex
            }
        }
        .ignoresSafeArea()
    }
}
