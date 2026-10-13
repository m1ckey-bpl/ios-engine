import SwiftUI

public struct TimeAlignmentView: View {
    @ObservedObject var dspEngine = AudioDSPEngine.shared

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 6)

                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STEREO LISTENING POSITION")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("LOCAL AUDIO PAN CONTROL")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)

                // Car Cabin Diagram Container
                VStack(spacing: 16) {
                    CarCabinVisualizer(
                        currentPosition: Binding(
                            get: { dspEngine.listeningPosition },
                            set: { dspEngine.setPosition($0) }
                        ),
                        onSelect: { pos in
                            dspEngine.setPosition(pos)
                        }
                    )
                }
                .padding(22)
                .pioneerCard(cornerRadius: 20, highlight: PioneerColors.amberOrange.opacity(0.4))
                .padding(.horizontal, 20)

                // Explanation Card
                VStack(alignment: .leading, spacing: 8) {
                    Text("ACTIVE FOCUS: \(dspEngine.listeningPosition.rawValue)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.amberOrange)

                    Text("Stereo balance shifts local playback toward the selected seating position. This is simple left/right panning—not per-speaker delay or vehicle-specific acoustic calibration.")
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
