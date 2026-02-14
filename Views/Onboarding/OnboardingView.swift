import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    @State private var selectedCategories: Set<String> = []
    
    let availableCategories = [
        ("cs.AI", "人工智能", "Artificial Intelligence"),
        ("cs.CL", "计算语言学", "Computation and Language"),
        ("cs.CV", "计算机视觉", "Computer Vision"),
        ("cs.LG", "机器学习", "Machine Learning"),
        ("cs.NE", "神经网络", "Neural and Evolutionary Computing"),
        ("stat.ML", "统计机器学习", "Machine Learning (Statistics)"),
        ("cs.CR", "密码学", "Cryptography and Security"),
        ("cs.DB", "数据库", "Databases"),
        ("cs.DC", "分布式计算", "Distributed Computing"),
        ("cs.IR", "信息检索", "Information Retrieval")
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 12) {
                    Text("欢迎使用 PaperTok")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(AppTheme.Colors.textPrimary(for: colorScheme))
                    
                    Text("像刷短视频一样刷论文")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                // Category selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择你感兴趣的领域")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textPrimary(for: colorScheme))
                        .padding(.horizontal, 24)
                    
                    Text("至少选择一个领域")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
                        .padding(.horizontal, 24)
                    
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(availableCategories, id: \.0) { category in
                                CategoryCard(
                                    code: category.0,
                                    chinese: category.1,
                                    english: category.2,
                                    isSelected: selectedCategories.contains(category.0)
                                ) {
                                    toggleCategory(category.0)
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 4)
                    }
                }
                
                Spacer()
                
                // Continue button
                Button(action: savePreferences) {
                    Text("继续")
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.textPrimary(for: colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(selectedCategories.isEmpty ? AppTheme.Colors.surfacePrimary(for: colorScheme) : AppTheme.Colors.surfaceSecondary(for: colorScheme))
                        .cornerRadius(AppTheme.CornerRadius.card)
                }
                .disabled(selectedCategories.isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(AppTheme.Colors.background(for: colorScheme))
        }
    }
    
    private func toggleCategory(_ code: String) {
        if selectedCategories.contains(code) {
            selectedCategories.remove(code)
        } else {
            selectedCategories.insert(code)
        }
    }
    
    private func savePreferences() {
        // Save to database
        let preference = UserPreference(selectedCategories: Array(selectedCategories))
        modelContext.insert(preference)
        try? modelContext.save()
        
        hasCompletedOnboarding = true
    }
}

struct CategoryCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let code: String
    let chinese: String
    let english: String
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(chinese)
                        .font(AppTheme.Typography.headline)
                        .foregroundColor(AppTheme.Colors.textPrimary(for: colorScheme))
                    
                    Text(english)
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
                    
                    Text(code)
                        .font(AppTheme.Typography.tag)
                        .foregroundColor(AppTheme.Colors.textTertiary(for: colorScheme))
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? AppTheme.Colors.textPrimary(for: colorScheme) : AppTheme.Colors.textTertiary(for: colorScheme))
            }
            .padding(16)
            .background(isSelected ? AppTheme.Colors.surfaceSecondary(for: colorScheme) : AppTheme.Colors.surfacePrimary(for: colorScheme))
            .cornerRadius(AppTheme.CornerRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card)
                    .stroke(isSelected ? AppTheme.Colors.border(for: colorScheme) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

