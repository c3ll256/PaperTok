import SwiftUI

struct LoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    
    init(message: String = "加载中...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(AppTheme.Colors.textSecondary(for: colorScheme))
            
            Text(message)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
        }
    }
}

struct PulsingLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    
    init(message: String = "处理中...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.regular)
                .tint(AppTheme.Colors.textSecondary(for: colorScheme))
            
            Text(message)
                .font(AppTheme.Typography.body)
                .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
        }
    }
}
