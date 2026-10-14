import SwiftUI

public struct EqualizerView: View {
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 6)
                
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("10-BAND GRAPHIC EQUALIZER")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("PARAMETRIC PRECISION FREQUENCY SHAPING")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        dspEngine.resetEQToZero()
                    }) {
                        Text("RESET FLAT")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.amberOrange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
                
                // Frequency Curve Preview Line
                GeometryReader { geo in
                    Path { path in
                        let step = geo.size.width / CGFloat(max(1, dspEngine.eqBands.count - 1))
                        let midY = geo.size.height / 2.0
                        
                        for (idx, band) in dspEngine.eqBands.enumerated() {
                            let x = CGFloat(idx) * step
                            // -12 to +12 dB mapped to Y
                            let norm = CGFloat(band.gain / 12.0)
                            let y = midY - (norm * (geo.size.height * 0.4))
                            
                            if idx == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        LinearGradient(
                            colors: [PioneerColors.amberOrange, PioneerColors.cyberCyan],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2.5
                    )
                }
                .frame(height: 50)
                .padding(.horizontal, 24)
                
                // Vertical Faders Container
                VStack(spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(0..<dspEngine.eqBands.count, id: \.self) { idx in
                                SmoothEQFader(
                                    label: dspEngine.eqBands[idx].label,
                                    gain: Binding(
                                        get: { dspEngine.eqBands[idx].gain },
                                        set: { dspEngine.setEQBandGain(index: idx, gain: $0) }
                                    )
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 12)
                    }
                }
                .pioneerCard(cornerRadius: 20, highlight: PioneerColors.cyberCyan.opacity(0.4))
                .padding(.horizontal, 20)
                
                // Curve Description Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE CURVE: \(dspEngine.currentPreset.rawValue)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.amberOrange)
                    
                    Text(dspEngine.currentPreset.subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(PioneerColors.textMuted)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pioneerCard(cornerRadius: 16)
                .padding(.horizontal, 20)
                
                Spacer().frame(height: 30)
            }
        }
    }
}

struct SmoothEQFader: View {
    let label: String
    @Binding var gain: Float // -12 to +12 dB
    
    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%+.0f", gain))
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(gain > 0 ? PioneerColors.amberOrange : (gain < 0 ? PioneerColors.cyberCyan : .white.opacity(0.5)))
            
            // Interactive Slider Track
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.34))
                    .frame(width: 8, height: 150)
                
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 14, height: 1.5)
                    .offset(y: -75)
                
                // Animated Handle
                Circle()
                    .fill(PioneerColors.amberOrange)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: PioneerColors.amberOrange.opacity(0.5), radius: 5)
                    .offset(y: -CGFloat((gain + 12.0) / 24.0) * 130)
            }
            .frame(width: 28, height: 150)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let locationY = 150 - g.location.y
                        let clamped = max(0, min(150, locationY))
                        let normalized = Float(clamped / 150.0)
                        gain = -12.0 + normalized * 24.0
                    }
            )
            
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PioneerColors.textMuted)
        }
        .frame(width: 44)
    }
}
