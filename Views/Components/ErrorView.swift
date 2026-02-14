import SwiftUI

enum AppError: Identifiable {
    case networkError(String)
    case apiError(String)
    case authenticationError
    case rateLimitError
    case insufficientBalance
    case parseError
    case cloudSyncError(String)
    
    var id: String {
        switch self {
        case .networkError(let msg): return "network_\(msg)"
        case .apiError(let msg): return "api_\(msg)"
        case .authenticationError: return "auth"
        case .rateLimitError: return "rate_limit"
        case .insufficientBalance: return "balance"
        case .parseError: return "parse"
        case .cloudSyncError(let msg): return "cloud_\(msg)"
        }
    }
    
    var title: String {
        switch self {
        case .networkError:
            return "网络错误"
        case .apiError:
            return "API 错误"
        case .authenticationError:
            return "认证失败"
        case .rateLimitError:
            return "请求频率超限"
        case .insufficientBalance:
            return "余额不足"
        case .parseError:
            return "数据解析错误"
        case .cloudSyncError:
            return "同步失败"
        }
    }
    
    var message: String {
        switch self {
        case .networkError(let msg):
            return "网络连接失败：\(msg)\n请检查网络设置后重试"
        case .apiError(let msg):
            return "API 调用失败：\(msg)\n请检查配置或稍后重试"
        case .authenticationError:
            return "API 密钥认证失败\n请在设置中检查你的密钥是否正确"
        case .rateLimitError:
            return "API 请求频率超过限制\n请稍后再试"
        case .insufficientBalance:
            return "API 账户余额不足\n请前往提供商充值后继续使用"
        case .parseError:
            return "数据解析失败\n这可能是临时问题，请重试"
        case .cloudSyncError(let msg):
            return "iCloud 同步失败：\(msg)\n请检查 iCloud 登录状态"
        }
    }
    
    var icon: String {
        switch self {
        case .networkError:
            return "wifi.exclamationmark"
        case .apiError, .parseError:
            return "exclamationmark.triangle"
        case .authenticationError:
            return "key.slash"
        case .rateLimitError:
            return "clock.badge.exclamationmark"
        case .insufficientBalance:
            return "creditcard.trianglebadge.exclamationmark"
        case .cloudSyncError:
            return "icloud.slash"
        }
    }
    
    var actionTitle: String? {
        switch self {
        case .authenticationError, .insufficientBalance:
            return "前往设置"
        case .cloudSyncError:
            return "检查 iCloud"
        default:
            return nil
        }
    }
}

struct ErrorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let error: AppError
    let onRetry: (() -> Void)?
    let onAction: (() -> Void)?
    
    init(error: AppError, onRetry: (() -> Void)? = nil, onAction: (() -> Void)? = nil) {
        self.error = error
        self.onRetry = onRetry
        self.onAction = onAction
    }
    
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: error.icon)
                .font(.system(size: 60))
                .foregroundColor(AppTheme.Colors.destructive(for: colorScheme))
            
            VStack(spacing: 8) {
                Text(error.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(AppTheme.Colors.textPrimary(for: colorScheme))
                
                Text(error.message)
                    .font(AppTheme.Typography.body)
                    .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            VStack(spacing: 12) {
                if let actionTitle = error.actionTitle, let action = onAction {
                    Button(action: action) {
                        Text(actionTitle)
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.textPrimary(for: colorScheme))
                            .frame(width: 200, height: 44)
                            .background(AppTheme.Colors.surfaceSecondary(for: colorScheme))
                            .cornerRadius(22)
                    }
                }
                
                if let retry = onRetry {
                    Button(action: retry) {
                        Text("重试")
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(AppTheme.Colors.accent(for: colorScheme))
                            .frame(width: 200, height: 44)
                            .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
                            .cornerRadius(22)
                            .overlay(
                                RoundedRectangle(cornerRadius: 22)
                                    .stroke(AppTheme.Colors.accent(for: colorScheme), lineWidth: 2)
                            )
                    }
                }
            }
        }
        .padding(32)
    }
}

struct ErrorBanner: View {
    @Environment(\.colorScheme) private var colorScheme
    let error: AppError
    @Binding var isPresented: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: error.icon)
                .font(.system(size: 20))
                .foregroundColor(.white)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(error.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(error.message.components(separatedBy: "\n").first ?? "")
                    .font(AppTheme.Typography.caption)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(2)
            }
            
            Spacer()
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .padding(16)
        .background(AppTheme.Colors.destructive(for: colorScheme))
        .cornerRadius(AppTheme.CornerRadius.card)
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
