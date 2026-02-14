import SwiftUI

struct LoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    @State private var isAnimating = false
    
    init(message: String = "加载中...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(AppTheme.Colors.border(for: colorScheme), lineWidth: 3)
                    .frame(width: 60, height: 60)
                
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(AppTheme.Colors.accent, lineWidth: 3)
                    .frame(width: 60, height: 60)
                    .rotationEffect(Angle(degrees: isAnimating ? 360 : 0))
                    .animation(
                        Animation.linear(duration: 1)
                            .repeatForever(autoreverses: false),
                        value: isAnimating
                    )
            }
            
            Text(message)
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
        }
        .onAppear {
            isAnimating = true
        }
    }
}

struct PulsingLoadingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let message: String
    @State private var scale: CGFloat = 1.0
    
    init(message: String = "处理中...") {
        self.message = message
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundColor(AppTheme.Colors.accent)
                .scaleEffect(scale)
                .animation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: true),
                    value: scale
                )
            
            Text(message)
                .font(AppTheme.Typography.headline)
                .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
        }
        .onAppear {
            scale = 1.2
        }
    }
}
