import SwiftUI
import SwiftData

struct PaperCardView: View {
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
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Color(hex: "1E3A5F"))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color(hex: "1E3A5F").opacity(0.1))
                                        .clipShape(.rect(cornerRadius: 12))
                                }
                            }
                        }
                        .scrollDisabled(true)
                        .scrollIndicators(.hidden)
                        .padding(.top, 60)
                    
                    // Title
                    Text(paper.title)
                        .font(.system(size: 24, weight: .bold, design: .serif))
                        .foregroundStyle(Color(hex: "111111"))
                        .lineLimit(3)
                    
                    // Authors and date
                    VStack(alignment: .leading, spacing: 4) {
                        Text(paper.authors.prefix(3).joined(separator: ", ") + (paper.authors.count > 3 ? " et al." : ""))
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "555555"))
                        
                        Text(formatDate(paper.publishedDate))
                            .font(.system(size: 13))
                            .foregroundStyle(Color(hex: "888888"))
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
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(Color(hex: "1E3A5F"))
                            .clipShape(.rect(cornerRadius: 12))
                        }
                    }
                }
                .padding(24)
                
                Divider()
                    .padding(.horizontal, 24)
                
                // Original abstract
                VStack(alignment: .leading, spacing: 12) {
                    Text("原始摘要")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color(hex: "111111"))
                    
                    Text(paper.abstractText)
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "555555"))
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
        .background(Color(hex: "F7F5F2"))
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
                            .foregroundStyle(Color(hex: "1E3A5F"))
                        Text("一句话总结")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "111111"))
                    }
                    
                    Text(oneLiner)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Color(hex: "1E3A5F"))
                        .italic()
                }
                .padding(16)
                .background(Color(hex: "1E3A5F").opacity(0.05))
                .clipShape(.rect(cornerRadius: 12))
            }
            
            if !terms.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "book")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: "1E3A5F"))
                        Text("核心术语")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color(hex: "111111"))
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
    let title: String
    let content: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "1E3A5F"))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "111111"))
            }
            
            Text(content)
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: "555555"))
                .lineSpacing(4)
        }
    }
}

struct TermCardView: View {
    let term: TermGlossaryItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(term.termChinese)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color(hex: "111111"))
                
                Text(term.termEnglish)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "1E3A5F"))
            }
            
            Text(term.explanation)
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "555555"))
            
            if !term.contextMeaning.isEmpty {
                Text("本文中：\(term.contextMeaning)")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(hex: "888888"))
                    .italic()
            }
        }
        .padding(12)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 8))
    }
}

struct PaperBottomActionsView: View {
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
                    .foregroundStyle(isFavorited ? Color.red : Color(hex: "555555"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        isFavorited
                            ? Color.red.opacity(0.08)
                            : Color(hex: "1E3A5F").opacity(0.05)
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
                    .foregroundStyle(Color(hex: "555555"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Color(hex: "1E3A5F").opacity(0.05))
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
                    .foregroundStyle(Color(hex: "CCCCCC"))
                
                Text("继续下滑，阅读下一篇")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(hex: "CCCCCC"))
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }
}

