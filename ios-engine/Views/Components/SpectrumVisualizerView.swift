import SwiftUI

public struct SpectrumVisualizerView: View {
    let isPlaying: Bool
    let barCount: Int = 18
    
    @State private var animatedHeights: [CGFloat] = Array(repeating: 0.15, count: 18)
    @State private var timer: Timer?
    
    public init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }
    
    public var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<barCount, id: \.self) { idx in
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(
                            LinearGradient(
                                colors: [
                                    PioneerColors.amberOrange,
                                    PioneerColors.amberGlow,
                                    PioneerColors.cyberCyan
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: max(6, animatedHeights[idx] * 58))
                }
            }
        }
        .frame(height: 64)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PioneerColors.titaniumCardBorder, lineWidth: 1)
                .allowsHitTesting(false)
        )
        .onAppear {
            startAnimation()
        }
        .onDisappear {
            stopAnimation()
        }
        .onChange(of: isPlaying) { playing in
            if playing {
                startAnimation()
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    animatedHeights = Array(repeating: 0.1, count: barCount)
                }
            }
        }
    }
    
    private func startAnimation() {
        stopAnimation()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            if isPlaying {
                withAnimation(.linear(duration: 0.09)) {
                    animatedHeights = (0..<barCount).map { i in
                        let curve = sin(Double(i) / Double(barCount) * .pi)
                        let base = CGFloat.random(in: 0.25...0.9)
                        return CGFloat(base * (0.5 + 0.5 * curve))
                    }
                }
            }
        }
    }
    
    private func stopAnimation() {
        timer?.invalidate()
        timer = nil
    }
}
