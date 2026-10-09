import SwiftUI

public struct GlowingButton: View {
    public let title: String
    public let icon: String
    public let primaryColor: Color
    public let isPulsing: Bool
    public let action: () -> Void
    
    @State private var pulseScale: CGFloat = 1.0
    
    public init(title: String, icon: String = "bolt.fill", primaryColor: Color = ThemeColors.cyanGlow, isPulsing: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.primaryColor = primaryColor
        self.isPulsing = isPulsing
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            let impactMed = UIImpactFeedbackGenerator(style: .medium)
            impactMed.impactOccurred()
            action()
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .tracking(1.2)
            }
            .foregroundColor(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [primaryColor.opacity(0.8), primaryColor.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.5), lineWidth: 1)
                }
            )
            .shadow(color: primaryColor.opacity(0.6), radius: isPulsing ? 18 : 8, x: 0, y: 4)
            .scaleEffect(isPulsing ? pulseScale : 1.0)
        }
        .onAppear {
            if isPulsing {
                withAnimation(Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulseScale = 1.03
                }
            }
        }
    }
}
