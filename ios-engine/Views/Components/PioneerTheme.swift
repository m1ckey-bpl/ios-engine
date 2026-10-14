import SwiftUI

/// Retained as `PioneerColors` internally to avoid churn in the existing DSP controls;
/// the shipped product branding and palette are DSP ENGINE / AVX.
public struct PioneerColors {
    public static let carbonBg = Color(red: 0.012, green: 0.018, blue: 0.055)
    // A low-opacity tint keeps the rotating anime wallpaper visible through cards.
    public static let titaniumCard = Color(red: 0.035, green: 0.045, blue: 0.105).opacity(0.09)
    public static let titaniumCardBorder = Color(red: 0.24, green: 0.34, blue: 0.57).opacity(0.48)

    // Existing property names are kept for source compatibility; the values are now neon cyan / violet.
    public static let amberOrange = Color(red: 0.20, green: 0.91, blue: 1.0)
    public static let amberGlow = Color(red: 0.64, green: 0.43, blue: 1.0)
    public static let cyberCyan = Color(red: 1.0, green: 0.32, blue: 0.79)
    public static let hiFiGold = Color(red: 0.78, green: 0.78, blue: 1.0)
    public static let textMuted = Color.white.opacity(0.62)
}

public struct PioneerCardModifier: ViewModifier {
    var cornerRadius: CGFloat
    var borderHighlight: Color

    public func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.54))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(PioneerColors.titaniumCard)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.055), Color.white.opacity(0.012), .clear],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                borderHighlight.opacity(0.68),
                                PioneerColors.titaniumCardBorder,
                                Color.white.opacity(0.045)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: borderHighlight.opacity(0.14), radius: 12, x: 0, y: 5)
    }
}

public extension View {
    func pioneerCard(cornerRadius: CGFloat = 18, highlight: Color = PioneerColors.titaniumCardBorder) -> some View {
        modifier(PioneerCardModifier(cornerRadius: cornerRadius, borderHighlight: highlight))
    }
}
