import SwiftUI

public struct LiquidGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var glowColor: Color
    var strokeWidth: CGFloat
    
    public init(cornerRadius: CGFloat = 22, glowColor: Color = Color(red: 0.0, green: 0.94, blue: 1.0), strokeWidth: CGFloat = 1.0) {
        self.cornerRadius = cornerRadius
        self.glowColor = glowColor
        self.strokeWidth = strokeWidth
    }
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.white.opacity(0.02)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .allowsHitTesting(false)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.6),
                                glowColor.opacity(0.5),
                                Color.purple.opacity(0.3),
                                Color.white.opacity(0.1)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: strokeWidth
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: glowColor.opacity(0.2), radius: 14, x: 0, y: 6)
    }
}

public extension View {
    func liquidGlass(cornerRadius: CGFloat = 22, glowColor: Color = Color(red: 0.0, green: 0.94, blue: 1.0), strokeWidth: CGFloat = 1.0) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius, glowColor: glowColor, strokeWidth: strokeWidth))
    }
}

public struct ThemeColors {
    public static let cyanGlow = Color(red: 0.0, green: 0.94, blue: 1.0)
    public static let neonPurple = Color(red: 0.69, green: 0.15, blue: 1.0)
    public static let electricGreen = Color(red: 0.0, green: 1.0, blue: 0.53)
    public static let dangerRed = Color(red: 1.0, green: 0.23, blue: 0.36)
    public static let darkBackground = Color(red: 0.03, green: 0.04, blue: 0.07)
    public static let glassTextMuted = Color.white.opacity(0.65)
}
