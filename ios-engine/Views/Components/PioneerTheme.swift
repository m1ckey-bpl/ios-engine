import SwiftUI

public struct PioneerColors {
    public static let carbonBg = Color(red: 0.04, green: 0.06, blue: 0.09)
    public static let titaniumCard = Color(red: 0.08, green: 0.11, blue: 0.16)
    public static let titaniumCardBorder = Color(red: 0.16, green: 0.22, blue: 0.31)
    
    // Pioneer Signature Brand Colors
    public static let amberOrange = Color(red: 1.0, green: 0.42, blue: 0.0) // Pioneer Sound Tune signature
    public static let amberGlow = Color(red: 1.0, green: 0.55, blue: 0.1)
    public static let cyberCyan = Color(red: 0.0, green: 0.90, blue: 1.0)
    public static let hiFiGold = Color(red: 0.95, green: 0.77, blue: 0.25)
    public static let textMuted = Color.white.opacity(0.55)
}

public struct PioneerCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var borderHighlight: Color
    
    public func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(PioneerColors.titaniumCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                borderHighlight.opacity(0.6),
                                PioneerColors.titaniumCardBorder,
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
                    .allowsHitTesting(false)
            )
            .shadow(color: borderHighlight.opacity(0.12), radius: 10, x: 0, y: 4)
    }
}

public extension View {
    func pioneerCard(cornerRadius: CGFloat = 18, highlight: Color = PioneerColors.titaniumCardBorder) -> some View {
        modifier(PioneerCardModifier(cornerRadius: cornerRadius, borderHighlight: highlight))
    }
}
