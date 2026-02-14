import SwiftUI
import SwiftData

struct PaperCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let paper: Paper
    let modelContext: ModelContext
    
    @State private var summary: PaperSummary?
    @State private var terms: [TermGlossaryItem] = []
    @State private var isGeneratingSummary = false
    @State private var showFullAbstract = false
    @State private var startTime = Date()
    @State private var isFavorited = false
    
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
                                        .foregroundStyle(AppTheme.Colors.accent(for: colorScheme))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(AppTheme.Colors.accentSubtle(for: colorScheme))
                                        .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.tag))
                                }
                            }
                        }
                        .scrollDisabled(true)
                        .scrollIndicators(.hidden)
                        .padding(.top, 60)
                    
                    // Title
                    Text(paper.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                        .lineLimit(3)
                    
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
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(AppTheme.Colors.surfaceSecondary(for: colorScheme))
                            .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
                        }
                    }
                }
                .padding(24)
                
                Divider()
                    .padding(.horizontal, 24)
                
                // Original abstract
                VStack(alignment: .leading, spacing: 12) {
                    Text("原始摘要")
                        .font(AppTheme.Typography.headline)
                        .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                    
                    Text(paper.abstractText)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                }
                .padding(24)
                
                // Bottom actions + next article hint
                PaperBottomActionsView(
                    paper: paper,
                    isFavorited: $isFavorited,
                    onToggleFavorite: toggleFavorite,
                    onOpenOriginal: openOriginalPaper
                )
                .padding(.bottom, 80) // Extra padding for bottom bar
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaPadding(.top)
        .background(AppTheme.Colors.background(for: colorScheme))
        .task {
            loadSummary()
            loadFavoriteStatus()
            startTime = Date()
            
            // Auto-generate summary if it doesn't exist
            if summary == nil && !isGeneratingSummary {
                generateSummary()
            }
        }
        .onDisappear {
            recordDwellTime()
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
    
    private func generateSummary() {
        isGeneratingSummary = true
        
        Task {
            do {
                let summaryService = SummaryService(modelContext: modelContext)
                let generatedSummary = try await summaryService.generateSummary(for: paper)
                
                await MainActor.run {
                    summary = generatedSummary
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
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<UserAction>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
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
            UIApplication.shared.open(url)
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
            
            if let whyItMatters = summary.whyItMatters {
                SectionView(title: "意义", content: whyItMatters, icon: "star")
            }
            
            if let oneLiner = summary.oneLiner {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.Colors.accent(for: colorScheme))
                        Text("一句话总结")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                    }
                    
                    Text(oneLiner)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(AppTheme.Colors.accent(for: colorScheme))
                        .italic()
                }
                .padding(16)
                .background(AppTheme.Colors.accentSubtle(for: colorScheme))
                .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
            }
            
            if !terms.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "book")
                            .font(.system(size: 16))
                            .foregroundStyle(AppTheme.Colors.accent(for: colorScheme))
                        Text("核心术语")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                    }
                    
                    ForEach(terms.prefix(6), id: \.id) { term in
                        TermCardView(term: term)
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
                    .foregroundStyle(AppTheme.Colors.accent(for: colorScheme))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
            }
            
            Text(content)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                .lineSpacing(4)
        }
    }
}

struct TermCardView: View {
    @Environment(\.colorScheme) private var colorScheme
    let term: TermGlossaryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(term.termChinese)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                
                Text(term.termEnglish)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.accent(for: colorScheme))
            }
            
            Text(term.explanation)
                .font(.system(size: 14))
                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
            
            if !term.contextMeaning.isEmpty {
                Text("本文中：\(term.contextMeaning)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                    .italic()
            }
        }
        .padding(12)
        .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
        .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.tag))
    }
}

struct PaperBottomActionsView: View {
    @Environment(\.colorScheme) private var colorScheme
    let paper: Paper
    @Binding var isFavorited: Bool
    let onToggleFavorite: () -> Void
    let onOpenOriginal: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 24)
            
            // Action buttons
            HStack(spacing: 16) {
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
                    .background(
                        isFavorited
                            ? AppTheme.Colors.favorite(for: colorScheme).opacity(0.08)
                            : AppTheme.Colors.accentSubtle(for: colorScheme)
                    )
                    .clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                
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
                    .background(AppTheme.Colors.accentSubtle(for: colorScheme))
                    .clipShape(.rect(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            // Next article hint
            VStack(spacing: 6) {
                Image(systemName: "chevron.compact.down")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                
                Text("继续下滑，阅读下一篇")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
    }
}

