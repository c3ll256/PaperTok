import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
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
                        .font(.system(size: 32, weight: .bold, design: .serif))
                        .foregroundColor(Color(hex: "111111"))
                    
                    Text("像刷短视频一样刷论文")
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: "555555"))
                }
                .padding(.top, 60)
                .padding(.bottom, 40)
                
                // Category selection
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择你感兴趣的领域")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Color(hex: "111111"))
                        .padding(.horizontal, 24)
                    
                    Text("至少选择一个领域")
                        .font(.system(size: 15))
                        .foregroundColor(Color(hex: "555555"))
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
                    }
                }
                
                Spacer()
                
                // Continue button
                Button(action: savePreferences) {
                    Text("继续")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(selectedCategories.isEmpty ? Color(hex: "CCCCCC") : Color(hex: "1E3A5F"))
                        .cornerRadius(12)
                }
                .disabled(selectedCategories.isEmpty)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .background(Color(hex: "F7F5F2"))
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
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "111111"))
                    
                    Text(english)
                        .font(.system(size: 14))
                        .foregroundColor(Color(hex: "555555"))
                    
                    Text(code)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "1E3A5F"))
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? Color(hex: "1E3A5F") : Color(hex: "CCCCCC"))
            }
            .padding(16)
            .background(Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(hex: "1E3A5F") : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Helper for hex colors
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
