import SwiftUI

public struct CarCabinVisualizer: View {
    @Binding var currentPosition: ListeningPosition
    let onSelect: (ListeningPosition) -> Void
    
    public init(currentPosition: Binding<ListeningPosition>, onSelect: @escaping (ListeningPosition) -> Void) {
        self._currentPosition = currentPosition
        self.onSelect = onSelect
    }
    
    public var body: some View {
        VStack(spacing: 14) {
            ZStack {
                // Car Outline
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(PioneerColors.titaniumCardBorder, lineWidth: 2)
                    .frame(width: 190, height: 230)
                    .background(
                        RoundedRectangle(cornerRadius: 32)
                            .fill(Color.black.opacity(0.4))
                    )
                
                // Windshield Curve
                Path { path in
                    path.move(to: CGPoint(x: 30, y: 65))
                    path.addQuadCurve(to: CGPoint(x: 160, y: 65), control: CGPoint(x: 95, y: 85))
                }
                .stroke(Color.white.opacity(0.15), lineWidth: 1.5)
                .frame(width: 190, height: 230)
                
                // 4 Car Seats
                VStack(spacing: 36) {
                    // Front Row
                    HStack(spacing: 44) {
                        SeatPill(title: "DRIVER", isSelected: currentPosition == .frontLeft) {
                            onSelect(.frontLeft)
                        }
                        SeatPill(title: "PASSENGER", isSelected: currentPosition == .frontRight) {
                            onSelect(.frontRight)
                        }
                    }
                    
                    // Rear Row
                    HStack(spacing: 44) {
                        SeatPill(title: "REAR L", isSelected: false) {
                            onSelect(.all)
                        }
                        SeatPill(title: "REAR R", isSelected: false) {
                            onSelect(.all)
                        }
                    }
                }
            }
            
            // Mode Selectors
            HStack(spacing: 10) {
                Button(action: { onSelect(.all) }) {
                    Text("ALL SEATS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(currentPosition == .all ? .black : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(currentPosition == .all ? PioneerColors.amberOrange : Color.white.opacity(0.08))
                        .cornerRadius(10)
                }
                
                Button(action: { onSelect(.frontLeft) }) {
                    Text("DRIVER FOCUS")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(currentPosition == .frontLeft ? .black : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(currentPosition == .frontLeft ? PioneerColors.cyberCyan : Color.white.opacity(0.08))
                        .cornerRadius(10)
                }
            }
        }
    }
}

struct SeatPill: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: isSelected ? "person.fill" : "person")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? PioneerColors.amberOrange : Color.white.opacity(0.4))
                
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : PioneerColors.textMuted)
            }
            .frame(width: 58, height: 60)
            .background(isSelected ? PioneerColors.amberOrange.opacity(0.2) : Color.white.opacity(0.05))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? PioneerColors.amberOrange : Color.white.opacity(0.1), lineWidth: 1.5)
            )
        }
    }
}
