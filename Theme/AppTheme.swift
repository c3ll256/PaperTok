import SwiftUI

/// AppTheme provides a centralized design system inspired by OpenAI's visual language
/// with adaptive colors for light/dark mode, typography presets, and spacing constants.
enum AppTheme {
    
    // MARK: - Colors
    // Based on ChatGPT Apps SDK Design System
    
    enum Colors {
        // MARK: - Background Colors
        
        /// Primary background - pure white in light mode, #171717 in dark mode
        static func background(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "171717") : Color(hex: "FFFFFF")
        }
        
        /// Secondary background - #F0F0F0 in light mode, #212121 in dark mode
        static func surfacePrimary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "212121") : Color(hex: "F0F0F0")
        }
        
        /// Tertiary background - #E8E8E8 in light mode, #2C2C2C in dark mode
        static func surfaceSecondary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "2C2C2C") : Color(hex: "E8E8E8")
        }
        
        // MARK: - Text Colors
        
        /// Primary text - #0D0D0D in light mode, #FFFFFF in dark mode
        static func textPrimary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "FFFFFF") : Color(hex: "0D0D0D")
        }
        
        /// Secondary text - #676767 in light mode, #B4B4B4 in dark mode
        static func textSecondary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "B4B4B4") : Color(hex: "676767")
        }
        
        /// Tertiary text - #ACACAC in light mode, #676767 in dark mode
        static func textTertiary(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "676767") : Color(hex: "ACACAC")
        }
        
        /// Inverted text - always white in light mode, always black in dark mode
        static func textInverted(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "0D0D0D") : Color(hex: "FFFFFF")
        }
        
        // MARK: - Icon Colors
        
        /// Primary icon color - matches text primary
        static func iconPrimary(for colorScheme: ColorScheme) -> Color {
            textPrimary(for: colorScheme)
        }
        
        /// Secondary icon color - matches text secondary
        static func iconSecondary(for colorScheme: ColorScheme) -> Color {
            textSecondary(for: colorScheme)
        }
        
        /// Tertiary icon color - matches text tertiary
        static func iconTertiary(for colorScheme: ColorScheme) -> Color {
            textTertiary(for: colorScheme)
        }
        
        /// Inverted icon color - matches text inverted
        static func iconInverted(for colorScheme: ColorScheme) -> Color {
            textInverted(for: colorScheme)
        }
        
        // MARK: - Accent Colors
        
        /// Blue accent - #1E88E5 in light mode, #5DADE2 in dark mode
        static func accentBlue(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "5DADE2") : Color(hex: "1E88E5")
        }
        
        /// Red accent - #E53935 in light mode, #F1948A in dark mode
        static func accentRed(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "F1948A") : Color(hex: "E53935")
        }
        
        /// Orange accent - #F57C00 in light mode, #F8B88B in dark mode
        static func accentOrange(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "F8B88B") : Color(hex: "F57C00")
        }
        
        /// Green accent - #00A67E in light mode, #66D9B5 in dark mode
        static func accentGreen(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "66D9B5") : Color(hex: "00A67E")
        }
        
        /// Primary accent - defaults to blue (more suitable for academic app)
        static func accent(for colorScheme: ColorScheme) -> Color {
            accentBlue(for: colorScheme)
        }
        
        /// Tag backgrounds, highlights
        static func accentSubtle(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark 
                ? Color(hex: "5DADE2").opacity(0.15)
                : Color(hex: "1E88E5").opacity(0.10)
        }
        
        // MARK: - Utility Colors
        
        /// Dividers, input borders
        static func border(for colorScheme: ColorScheme) -> Color {
            colorScheme == .dark ? Color(hex: "2C2C2C") : Color(hex: "E8E8E8")
        }
        
        /// Error, remove actions - uses red accent
        static func destructive(for colorScheme: ColorScheme) -> Color {
            accentRed(for: colorScheme)
        }
        
        /// Heart/favorite - uses red accent
        static func favorite(for colorScheme: ColorScheme) -> Color {
            accentRed(for: colorScheme)
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
