import SwiftUI
import UIKit

/// 渐进式模糊方向
enum VariableBlurDirection {
    case blurredTopClearBottom
    case blurredBottomClearTop
}

/// 使用 UIVisualEffectView + 渐变 mask 实现渐进式模糊效果
struct VariableBlurView: UIViewRepresentable {
    var maxBlurRadius: CGFloat
    var direction: VariableBlurDirection
    
    func makeUIView(context: Context) -> UIVisualEffectView {
        let blurEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        let blurView = UIVisualEffectView(effect: blurEffect)
        blurView.backgroundColor = .clear
        
        // 添加渐变 mask
        let maskLayer = CAGradientLayer()
        maskLayer.colors = gradientColors
        maskLayer.startPoint = CGPoint(x: 0.5, y: 0)
        maskLayer.endPoint = CGPoint(x: 0.5, y: 1)
        blurView.layer.mask = maskLayer
        
        return blurView
    }
    
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        // 更新 mask 的 frame
        DispatchQueue.main.async {
            uiView.layer.mask?.frame = uiView.bounds
        }
        
        if let gradientMask = uiView.layer.mask as? CAGradientLayer {
            gradientMask.colors = gradientColors
        }
    }
    
    private var gradientColors: [CGColor] {
        switch direction {
        case .blurredTopClearBottom:
            return [
                UIColor.black.withAlphaComponent(1.0).cgColor,
                UIColor.black.withAlphaComponent(0.8).cgColor,
                UIColor.black.withAlphaComponent(0.4).cgColor,
                UIColor.black.withAlphaComponent(0.0).cgColor
            ]
        case .blurredBottomClearTop:
            return [
                UIColor.black.withAlphaComponent(0.0).cgColor,
                UIColor.black.withAlphaComponent(0.4).cgColor,
                UIColor.black.withAlphaComponent(0.8).cgColor,
                UIColor.black.withAlphaComponent(1.0).cgColor
            ]
        }
    }
}
