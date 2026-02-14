import SwiftUI

/// AppTheme provides a centralized design system inspired by OpenAI's visual language
/// with adaptive colors for light/dark mode, typography presets, and spacing constants.
enum AppTheme {
    
    // MARK: - Colors
    
    enum Colors {
        /// Page background - pure white/near-black
        static func background(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "0D0D0D") : Color(hex: "FFFFFF")
        }
        
        /// Card/surface background
        static func surfacePrimary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "1A1A1A") : Color(hex: "F7F7F8")
        }
        
        /// Nested surfaces, input fields
        static func surfaceSecondary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "2A2A2A") : Color(hex: "ECECF1")
        }
        
        /// Headings, body text
        static func textPrimary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "ECECF1") : Color(hex: "0D0D0D")
        }
        
        /// Subtitles, metadata
        static func textSecondary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "8E8EA0") : Color(hex: "6E6E80")
        }
        
        /// Hints, timestamps
        static func textTertiary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "6E6E80") : Color(hex: "8E8EA0")
        }
        
        /// Primary accent - ChatGPT green
        static let accent = Color(hex: "10A37F")
        
        /// Tag backgrounds, highlights
        static func accentSubtle(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark 
                ? Color(hex: "10A37F").opacity(0.15)
                : Color(hex: "10A37F").opacity(0.10)
        }
        
        /// Dividers, input borders
        static func border(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "2F2F2F") : Color(hex: "E5E5E5")
        }
        
        /// Error, remove actions
        static func destructive(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "F87171") : Color(hex: "EF4444")
        }
        
        /// Heart/favorite
        static func favorite(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "F87171") : Color(hex: "EF4444")
        }
    }
    
    // MARK: - Typography
    
    enum Typography {
        /// Title - 22pt semibold sans-serif
        static let title = Font.system(size: 22, weight: .semibold)
        
        /// Headline - 17pt semibold
        static let headline = Font.system(size: 17, weight: .semibold)
        
        /// Body - 15pt regular
        static let body = Font.system(size: 15, weight: .regular)
        
        /// Caption - 13pt regular
        static let caption = Font.system(size: 13, weight: .regular)
        
        /// Tag - 12pt medium
        static let tag = Font.system(size: 12, weight: .medium)
    }
    
    // MARK: - Spacing
    
    enum Spacing {
        /// Standard horizontal padding for content
        static let horizontalPadding: CGFloat = 20
        
        /// Padding inside cards
        static let cardPadding: CGFloat = 16
        
        /// Spacing between sections
        static let sectionSpacing: CGFloat = 24
    }
    
    // MARK: - Corner Radius
    
    enum CornerRadius {
        /// Cards
        static let card: CGFloat = 12
        
        /// Large buttons
        static let buttonLarge: CGFloat = 20
        
        /// Tags
        static let tag: CGFloat = 8
    }
}

// MARK: - Color Hex Extension

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
