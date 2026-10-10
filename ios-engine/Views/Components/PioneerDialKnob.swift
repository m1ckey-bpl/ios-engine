import SwiftUI

public struct PioneerDialKnob: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let unit: String
    let accentColor: Color
    
    @State private var angle: Double = 0.0
    
    public init(title: String, value: Binding<Float>, range: ClosedRange<Float>, unit: String = "%", accentColor: Color = PioneerColors.amberOrange) {
        self.title = title
        self._value = value
        self.range = range
        self.unit = unit
        self.accentColor = accentColor
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(PioneerColors.textMuted)
            
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 80, height: 80)
                
                // Progress Arc
                Circle()
                    .trim(from: 0.0, to: CGFloat(normalizedValue))
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [accentColor.opacity(0.4), accentColor]),
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360)
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 80, height: 80)
                
                // Center Knob
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.22, green: 0.26, blue: 0.35), Color(red: 0.10, green: 0.12, blue: 0.17)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 3)
                
                // Value Text in Center
                VStack(spacing: 1) {
                    Text(String(format: "%.0f", value))
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text(unit)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor)
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let delta = Float(-gesture.translation.height * 0.5)
                        let span = range.upperBound - range.lowerBound
                        let newVal = min(range.upperBound, max(range.lowerBound, value + delta * (span / 100.0)))
                        value = newVal
                    }
            )
        }
    }
    
    private var normalizedValue: Float {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (value - range.lowerBound) / span
    }
}
