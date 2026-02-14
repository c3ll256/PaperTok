import SwiftUI
import SwiftData

struct BookmarksView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<UserAction> { $0.isFavorited == true },
           sort: \UserAction.updatedAt,
           order: .reverse)
    private var favoriteActions: [UserAction]
    @Query private var papers: [Paper]
    
    private var favoritePapers: [Paper] {
        let favoritedIds = Set(favoriteActions.map(\.arxivId))
        return papers.filter { favoritedIds.contains($0.arxivId) }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if favoritePapers.isEmpty {
                    emptyState
                } else {
                    paperList
                }
            }
            .background(Color(hex: "F7F5F2"))
            .navigationTitle("收藏夹")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Color(hex: "888888"))
                    }
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "heart.slash")
                .font(.system(size: 48))
                .foregroundStyle(Color(hex: "CCCCCC"))
            
            Text("暂无收藏")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color(hex: "111111"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Paper List
    
    private var paperList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(favoritePapers, id: \.arxivId) { paper in
                    BookmarkCardView(paper: paper) {
                        removeFavorite(arxivId: paper.arxivId)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
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

// MARK: - Bookmark Card

struct BookmarkCardView: View {
    let paper: Paper
    let onRemove: () -> Void
    
    @State private var showRemoveConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Categories
            if !paper.categories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(paper.categories.prefix(3), id: \.self) { category in
                            Text(category)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(hex: "1E3A5F"))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color(hex: "1E3A5F").opacity(0.1))
                                .clipShape(.rect(cornerRadius: 6))
                        }
                    }
                }
            }
            
            // Title
            Text(paper.title)
                .font(.system(size: 16, weight: .semibold, design: .serif))
                .foregroundStyle(Color(hex: "111111"))
                .lineLimit(3)
            
            // Authors
            Text(paper.authors.prefix(3).joined(separator: ", ") + (paper.authors.count > 3 ? " et al." : ""))
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "888888"))
                .lineLimit(1)
            
            // Bottom row: date + actions
            HStack {
                Text(formatDate(paper.publishedDate))
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "AAAAAA"))
                
                Spacer()
                
                // Open PDF
                Button {
                    if let url = URL(string: paper.pdfURL) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Image(systemName: "doc.text")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "1E3A5F"))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Remove from favorites
                Button {
                    showRemoveConfirmation = true
                } label: {
                    Image(systemName: "heart.slash")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: "FF6B6B"))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
        .confirmationDialog("取消收藏", isPresented: $showRemoveConfirmation) {
            Button("取消收藏", role: .destructive) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    onRemove()
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("确定要取消收藏这篇论文吗？")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
