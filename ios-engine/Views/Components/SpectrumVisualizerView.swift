import SwiftUI

/// Lightweight neon equalizer animation. This is a visualizer, not a measured FFT meter.
public struct SpectrumVisualizerView: View {
    public let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let barCount = 18

    public init(isPlaying: Bool) {
        self.isPlaying = isPlaying
    }

    public var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.38))
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !isPlaying || reduceMotion)) { timeline in
                Canvas { context, size in
                    guard size.width > 0, size.height > 0 else { return }
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let spacing: CGFloat = 4
                    let barWidth = max(3, (size.width - spacing * CGFloat(barCount - 1) - 16) / CGFloat(barCount))
                    let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
                    let leading = (size.width - totalWidth) / 2
                    let baseline = size.height - 7

                    for index in 0..<barCount {
                        let indexValue = Double(index)
                        let envelope = 0.35 + 0.65 * sin(Double(index + 1) / Double(barCount + 1) * .pi)
                        let pulse = isPlaying ? (0.28 + 0.72 * (0.5 + 0.5 * sin(time * 2.6 + indexValue * 0.63))) : 0.10
                        let height = max(4, CGFloat(envelope * pulse) * (size.height - 17))
                        let x = leading + CGFloat(index) * (barWidth + spacing)
                        let rect = CGRect(x: x, y: baseline - height, width: barWidth, height: height)
                        let path = Path(roundedRect: rect, cornerRadius: min(3, barWidth / 2))
                        context.fill(
                            path,
                            with: .linearGradient(
                                Gradient(colors: [PioneerColors.amberOrange, PioneerColors.amberGlow, PioneerColors.cyberCyan]),
                                startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                endPoint: CGPoint(x: rect.midX, y: baseline)
                            )
                        )
                    }
                }
            }
        }
        .frame(height: 72)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PioneerColors.titaniumCardBorder, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityLabel(isPlaying ? "Animated audio visualizer, playback active" : "Audio visualizer, standby")
    }
}
