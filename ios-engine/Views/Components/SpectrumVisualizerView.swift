import SwiftUI

public struct SpectrumVisualizerView: View {
    let levels: [CGFloat]
    
    public init(levels: [CGFloat]) {
        self.levels = levels
    }
    
    public var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<levels.count, id: \.self) { idx in
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 3)
                        .fill(
                            LinearGradient(
                                colors: [
                                    PioneerColors.amberOrange,
                                    PioneerColors.cyberCyan
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: max(6, levels[idx] * 64))
                        .animation(.spring(response: 0.15, dampingFraction: 0.6), value: levels[idx])
                }
            }
        }
        .frame(height: 70)
        .padding(12)
        .background(Color.black.opacity(0.5))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PioneerColors.titaniumCardBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
    }
}
