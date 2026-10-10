import SwiftUI

public struct ContentView: View {
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        ZStack(alignment: .bottom) {
            PioneerColors.carbonBg
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Tab Content
                TabView(selection: $selectedTab) {
                    MainDSPView()
                        .tag(0)
                    
                    EqualizerView()
                        .tag(1)
                    
                    AcousticsView()
                        .tag(2)
                    
                    TimeAlignmentView()
                        .tag(3)
                    
                    SpotifyView()
                        .tag(4)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Pioneer Custom Cockpit Bottom Navigation Bar
                HStack(spacing: 0) {
                    TabPill(icon: "slider.horizontal.3", title: "TUNER", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    TabPill(icon: "waveform", title: "EQ", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    TabPill(icon: "building.columns.fill", title: "ACOUSTICS", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                    TabPill(icon: "car.fill", title: "POSITION", isSelected: selectedTab == 3) {
                        selectedTab = 3
                    }
                    TabPill(icon: "music.note", title: "SPOTIFY", isSelected: selectedTab == 4) {
                        selectedTab = 4
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(
                    PioneerColors.titaniumCard
                        .overlay(
                            Rectangle()
                                .fill(PioneerColors.titaniumCardBorder)
                                .frame(height: 1),
                            alignment: .top
                        )
                )
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct TabPill: View {
    let icon: String
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impact = UIImpactFeedbackGenerator(style: .light)
            impact.impactOccurred()
            action()
        }) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: isSelected ? .bold : .regular))
                    .foregroundColor(isSelected ? PioneerColors.amberOrange : PioneerColors.textMuted)
                
                Text(title)
                    .font(.system(size: 9, weight: isSelected ? .black : .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : PioneerColors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }
}
