import SwiftUI

public struct AcousticsView: View {
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    
    public init() {}
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 6)
                
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACOUSTIC REVERB ENVIRONMENT")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("SIMULATE REAL-WORLD ARCHITECTURAL ACOUSTICS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                
                // Reverb Type Selector
                VStack(alignment: .leading, spacing: 14) {
                    Text("SELECT ROOM ARCHITECTURE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.textMuted)
                    
                    VStack(spacing: 10) {
                        ForEach(ReverbRoomType.allCases) { room in
                            Button(action: {
                                dspEngine.setReverbRoom(room)
                            }) {
                                HStack {
                                    Image(systemName: room == .concertHall ? "building.columns.fill" : "speaker.wave.2.fill")
                                        .foregroundColor(dspEngine.currentReverbRoom == room ? PioneerColors.amberOrange : Color.white.opacity(0.4))
                                    
                                    Text(room.rawValue.uppercased())
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    
                                    Spacer()
                                    
                                    if dspEngine.currentReverbRoom == room {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(PioneerColors.amberOrange)
                                    }
                                }
                                .padding(14)
                                .background(dspEngine.currentReverbRoom == room ? PioneerColors.amberOrange.opacity(0.15) : Color.white.opacity(0.04))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(dspEngine.currentReverbRoom == room ? PioneerColors.amberOrange : Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(18)
                .pioneerCard(cornerRadius: 20)
                .padding(.horizontal, 20)
                
                // Wet / Dry Slider
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("WET / DRY REVERBERATION MIX")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                        Spacer()
                        Text(String(format: "%.0f%%", dspEngine.reverbWetDryMix))
                            .font(.system(size: 12, weight: .black, design: .monospaced))
                            .foregroundColor(PioneerColors.cyberCyan)
                    }
                    
                    Slider(
                        value: Binding(
                            get: { dspEngine.reverbWetDryMix },
                            set: { dspEngine.setReverbWetDry($0) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                    .accentColor(PioneerColors.cyberCyan)
                }
                .padding(18)
                .pioneerCard(cornerRadius: 20, highlight: PioneerColors.cyberCyan.opacity(0.4))
                .padding(.horizontal, 20)
                
                Spacer().frame(height: 30)
            }
        }
    }
}
