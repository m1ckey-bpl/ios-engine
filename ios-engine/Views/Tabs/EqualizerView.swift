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
                
                // Sliders Container
                VStack(spacing: 14) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(0..<dspEngine.eqBands.count, id: \.self) { idx in
                                EQVerticalFader(
                                    label: dspEngine.eqBands[idx].label,
                                    gain: Binding(
                                        get: { dspEngine.eqBands[idx].gain },
                                        set: { dspEngine.setEQBandGain(index: idx, gain: $0) }
                                    )
                                )
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
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

struct EQVerticalFader: View {
    let label: String
    @Binding var gain: Float // -12 to +12 dB
    
    var body: some View {
        VStack(spacing: 8) {
            Text(String(format: "%+.0fdB", gain))
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundColor(gain > 0 ? PioneerColors.amberOrange : (gain < 0 ? PioneerColors.cyberCyan : .white.opacity(0.5)))
            
            // Vertical Slider Bar
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.6))
                    .frame(width: 8, height: 160)
                
                // Zero center line
                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 14, height: 1.5)
                    .offset(y: -80)
                
                // Slider Handle
                Circle()
                    .fill(PioneerColors.amberOrange)
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: PioneerColors.amberOrange.opacity(0.6), radius: 6)
                    .offset(y: -CGFloat(normalizeGain(gain)) * 140)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { g in
                                let val = Float(-g.translation.height / 140.0) * 24.0
                                gain = max(-12.0, min(12.0, val))
                            }
                    )
            }
            .frame(width: 26, height: 160)
            
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(PioneerColors.textMuted)
        }
        .frame(width: 44)
    }
    
    private func normalizeGain(_ g: Float) -> Float {
        // -12 -> 0.0, 0 -> 0.5, +12 -> 1.0
        return (g + 12.0) / 24.0
    }
}
