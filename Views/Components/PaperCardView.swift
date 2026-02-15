import SwiftUI
import SwiftData

struct PaperCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    let paper: Paper
    let modelContainer: ModelContainer
    
    @State private var summary: PaperSummary?
    @State private var terms: [TermGlossaryItem] = []
    @State private var isGeneratingSummary = false
    @State private var isTranslatingTitle = false
    @State private var showFullAbstract = false
    @State private var startTime = Date()
    @State private var isFavorited = false
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
                        .padding(.top, 60)
                    
                    // Title - bilingual (Chinese + English)
                    VStack(alignment: .leading, spacing: 6) {
                        if let chineseTitle = summary?.titleChinese, !chineseTitle.isEmpty {
                            Text(chineseTitle)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        Text(paper.title)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(summary?.titleChinese != nil ? AppTheme.Colors.textSecondary(for: colorScheme) : AppTheme.Colors.textPrimary(for: colorScheme))
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
                
                // Bottom actions + next article hint
                PaperBottomActionsView(
                    paper: paper,
                    isFavorited: $isFavorited,
                    hasSummary: summary != nil,
                    isRegenerating: isGeneratingSummary,
                    onToggleFavorite: toggleFavorite,
                    onOpenOriginal: openOriginalPaper,
                    onRegenerate: regenerateSummary
                )
                .padding(.bottom, 80) // Extra padding for bottom bar
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.top)
        .background(AppTheme.Colors.background(for: colorScheme))
        .task {
            feedbackGenerator.prepare()
            loadSummary()
            loadFavoriteStatus()
            startTime = Date()
            
            // Fast path: translate title first so it shows immediately
            if summary?.titleChinese == nil && !isTranslatingTitle {
                translateTitleFirst()
            }
            
            // Then generate full summary if needed
            let hasFullSummary = summary?.problem != nil
            if !hasFullSummary && !isGeneratingSummary {
                generateSummary()
            }
        }
        .onDisappear {
            recordDwellTime()
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
    }
    
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
    
    private func translateTitleFirst() {
        isTranslatingTitle = true
        
        Task {
            do {
                let summaryService = SummaryService(modelContainer: modelContainer)
                try await summaryService.translateTitle(for: paper)
                
                await MainActor.run {
                    loadSummary()
                    isTranslatingTitle = false
                }
            } catch {
                print("Error translating title: \(error)")
                await MainActor.run {
                    isTranslatingTitle = false
                }
            }
        }
    }
    
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
    
    private func recordDwellTime() {
        let dwellTime = Date().timeIntervalSince(startTime)
        
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<UserAction>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        if let action = try? modelContext.fetch(descriptor).first {
            action.dwellTimeSeconds += dwellTime
            action.isRead = true
            action.updatedAt = Date()
        } else {
            let newAction = UserAction(arxivId: paper.arxivId, isRead: true, dwellTimeSeconds: dwellTime)
            modelContext.insert(newAction)
        }
        
        try? modelContext.save()
    }
    
    private func loadFavoriteStatus() {
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<UserAction>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        if let action = try? modelContext.fetch(descriptor).first {
            isFavorited = action.isFavorited
        } else {
            isFavorited = false
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

struct SummaryContentView: View {
    @Environment(\.colorScheme) private var colorScheme
    let summary: PaperSummary
    let terms: [TermGlossaryItem]
    @State private var isTermsExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let problem = summary.problem {
                SectionView(title: "问题", content: problem, icon: "questionmark.circle")
            }
            
            if let method = summary.method {
                SectionView(title: "方法", content: method, icon: "gearshape")
            }
            
            if let result = summary.result {
                SectionView(title: "结果", content: result, icon: "chart.bar")
            }
            
            if let oneLiner = summary.oneLiner {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                        Text("一句话总结")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                    }
                    
                    MarkdownTextView(
                        content: oneLiner,
                        font: .system(size: 17, weight: .medium),
                        foregroundColor: AppTheme.Colors.textPrimary(for: colorScheme)
                    )
                    .italic()
                }
                .padding(16)
                .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
                .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
            }
            
            if !terms.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isTermsExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "book")
                                .font(.system(size: 16))
                                .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                            Text("核心术语")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                                .rotationEffect(.degrees(isTermsExpanded ? 90 : 0))
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if isTermsExpanded {
                        ForEach(terms.prefix(6), id: \.id) { term in
                            TermCardView(term: term)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }
        }
    }
}

struct SectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let content: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
            }
            
            MarkdownTextView(content: content)
        }
    }
}

/// Renders Markdown content as styled `Text` using `AttributedString`.
/// Supports **bold**, *italic*, and list markers while applying the app's
/// color scheme and typography consistently.
struct MarkdownTextView: View {
    @Environment(\.colorScheme) private var colorScheme
    let content: String
    var font: Font = AppTheme.Typography.body
    var foregroundColor: Color?
    
    var body: some View {
        Text(styledMarkdown)
            .font(font)
            .foregroundStyle(foregroundColor ?? AppTheme.Colors.textSecondary(for: colorScheme))
            .lineSpacing(4)
    }
    
    private var styledMarkdown: AttributedString {
        // Try parsing as Markdown; fall back to plain text on failure
        guard var attributed = try? AttributedString(markdown: content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return AttributedString(content)
        }
        
        // Walk through runs and apply theme-consistent styling
        for run in attributed.runs {
            let range = run.range
            
            // Preserve inline bold/italic traits from Markdown parsing
            // but ensure colors stay within the theme
            if let inlinePresentationIntent = run.inlinePresentationIntent {
                if inlinePresentationIntent.contains(.stronglyEmphasized) {
                    attributed[range].foregroundColor = UIColor(AppTheme.Colors.textPrimary(for: colorScheme))
                }
            }
        }
        
        return attributed
    }
}

struct TermCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let term: TermGlossaryItem
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row — always visible, tappable
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(term.termEnglish)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                        
                        Text(term.termChinese)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            .padding(16)
            
            // Detail — collapsed by default
            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    Text(term.explanation)
                        .font(.system(size: 14))
                        .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if !term.contextMeaning.isEmpty {
                        Text("本文中：\(term.contextMeaning)")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                            .italic()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
        .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
    }
}

struct PaperBottomActionsView: View {
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
            
            // Action buttons
            if #available(iOS 26, *) {
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        // 喜欢按钮
                        Button(action: onToggleFavorite) {
                            HStack(spacing: 6) {
                                Image(systemName: isFavorited ? "heart.fill" : "heart")
                                    .font(.system(size: 16))
                                    .symbolEffect(.bounce, value: isFavorited)
                                Text(isFavorited ? "已喜欢" : "喜欢")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundStyle(isFavorited ? AppTheme.Colors.favorite(for: colorScheme) : AppTheme.Colors.textSecondary(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(.capsule)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                        
                        // 重新分析按钮
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
                                .glassEffect(.regular.interactive(), in: .capsule)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRegenerating)
                            .opacity(isRegenerating ? 0.5 : 1)
                        }
                        
                        // 查看原文按钮
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
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            } else {
                HStack(spacing: 12) {
                    // 喜欢按钮
                    Button(action: onToggleFavorite) {
                        HStack(spacing: 6) {
                            Image(systemName: isFavorited ? "heart.fill" : "heart")
                                .font(.system(size: 16))
                                .symbolEffect(.bounce, value: isFavorited)
                            Text(isFavorited ? "已喜欢" : "喜欢")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(isFavorited ? AppTheme.Colors.favorite(for: colorScheme) : AppTheme.Colors.textSecondary(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(.capsule)
                        .background(.ultraThinMaterial)
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    
                    // 重新分析按钮
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
                            .background(.ultraThinMaterial)
                            .clipShape(.capsule)
                        }
                        .buttonStyle(.plain)
                        .disabled(isRegenerating)
                        .opacity(isRegenerating ? 0.5 : 1)
                    }
                    
                    // 查看原文按钮
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
                        .background(.ultraThinMaterial)
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            
            // Next article hint
            VStack(spacing: 6) {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                
                Text("继续下滑，阅读下一篇")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}

