import SwiftUI

public struct BackgroundMeshView: View {
    @State private var animateGlow: Bool = false
    
    public init() {}
    
    public var body: some View {
        ZStack {
            ThemeColors.darkBackground
                .ignoresSafeArea()
            
            // Neon Cyan Floating Orb
            Circle()
                .fill(ThemeColors.cyanGlow.opacity(0.28))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: animateGlow ? -100 : 120, y: animateGlow ? -180 : -60)
            
            // Neon Purple Floating Orb
            Circle()
                .fill(ThemeColors.neonPurple.opacity(0.32))
                .frame(width: 360, height: 360)
                .blur(radius: 100)
                .offset(x: animateGlow ? 120 : -90, y: animateGlow ? 220 : 120)
            
            // Deep Cyber Blue Accent Orb
            Circle()
                .fill(Color(red: 0.05, green: 0.3, blue: 0.9).opacity(0.25))
                .frame(width: 280, height: 280)
                .blur(radius: 80)
                .offset(x: animateGlow ? -60 : 70, y: animateGlow ? 60 : -140)
            
            // Subtle Cyber Grid Mesh Overlay
            GeometryReader { proxy in
                Path { path in
                    let step: CGFloat = 40
                    for x in stride(from: 0, through: proxy.size.width, by: step) {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                    }
                    for y in stride(from: 0, through: proxy.size.height, by: step) {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.03), lineWidth: 0.6)
            }
            .ignoresSafeArea()
        }
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                animateGlow.toggle()
            }
        }
    }
}
