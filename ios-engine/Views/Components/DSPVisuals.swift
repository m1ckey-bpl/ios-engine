import SwiftUI

/// Shared night-sky art, a restrained drifting-snow effect, and the DSP ENGINE wordmark.
/// The snowfall is drawn in one Canvas layer so it stays lightweight during scrolling.
public struct DSPNightBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    public init() {}

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image("NightAnimeBackground")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.015, green: 0.02, blue: 0.07).opacity(0.12), location: 0),
                        .init(color: Color(red: 0.015, green: 0.02, blue: 0.07).opacity(0.30), location: 0.42),
                        .init(color: Color(red: 0.015, green: 0.02, blue: 0.07).opacity(0.86), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                SnowfallCanvas(isPaused: reduceMotion || scenePhase != .active)
                    .accessibilityHidden(true)

                VStack {
                    HStack {
                        Spacer()
                        Text("AVX")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(Color.white.opacity(0.86))
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(Capsule().stroke(Color.cyan.opacity(0.55), lineWidth: 1))
                            .shadow(color: Color.cyan.opacity(0.45), radius: 12)
                    }
                    .padding(.top, 10)
                    .padding(.trailing, 17)
                    Spacer()
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

private struct SnowParticle {
    let x: Double
    let y: Double
    let radius: Double
    let speed: Double
    let phase: Double
    let opacity: Double
}

private struct SnowfallCanvas: View {
    let isPaused: Bool

    private static let particles: [SnowParticle] = (0..<34).map { index in
        let seed = Double(index + 1)
        return SnowParticle(
            x: (seed * 0.61803398875).truncatingRemainder(dividingBy: 1),
            y: (seed * 0.38196601125).truncatingRemainder(dividingBy: 1),
            radius: 0.8 + (seed.truncatingRemainder(dividingBy: 4)) * 0.32,
            speed: 5.0 + seed.truncatingRemainder(dividingBy: 7) * 1.65,
            phase: seed * 1.91,
            opacity: 0.22 + seed.truncatingRemainder(dividingBy: 5) * 0.10
        )
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: isPaused)) { timeline in
            Canvas { context, size in
                guard size.width > 0, size.height > 0 else { return }
                let time = timeline.date.timeIntervalSinceReferenceDate
                let width = Double(size.width)
                let height = Double(size.height)
                for particle in Self.particles {
                    let drift = sin(time * 0.32 + particle.phase) * 13.0
                    let rawX = particle.x * width + drift
                    let x = (rawX.truncatingRemainder(dividingBy: width) + width)
                        .truncatingRemainder(dividingBy: width)
                    let y = (particle.y * height + time * particle.speed)
                        .truncatingRemainder(dividingBy: height)
                    let radius = CGFloat(particle.radius)
                    let rect = CGRect(x: CGFloat(x), y: CGFloat(y), width: radius * 2, height: radius * 2)
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color.white.opacity(particle.opacity))
                    )
                }
            }
        }
    }
}

public struct DSPLogoMark: View {
    public var compact: Bool

    public init(compact: Bool = false) {
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 8 : 11) {
            ZStack {
                RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous)
                    .fill(Color.black.opacity(0.34))
                RoundedRectangle(cornerRadius: compact ? 11 : 14, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.cyan, Color(red: 0.72, green: 0.38, blue: 1.0), Color(red: 1.0, green: 0.30, blue: 0.76)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.4
                    )
                Image(systemName: "waveform.path")
                    .font(.system(size: compact ? 20 : 24, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(colors: [.cyan, Color(red: 0.75, green: 0.48, blue: 1.0)], startPoint: .leading, endPoint: .trailing)
                    )
                    .shadow(color: Color.cyan.opacity(0.72), radius: 9)
            }
            .frame(width: compact ? 40 : 48, height: compact ? 40 : 48)
            .shadow(color: Color.cyan.opacity(0.18), radius: 10)

            if !compact {
                VStack(alignment: .leading, spacing: 2) {
                    Text("DSP ENGINE")
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .tracking(1.15)
                        .foregroundStyle(.white)
                    Text("MADE BY AVX")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(2.3)
                        .foregroundStyle(Color.cyan.opacity(0.95))
                }
                .shadow(color: Color.black.opacity(0.7), radius: 8, y: 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("DSP ENGINE, made by AVX")
    }
}
