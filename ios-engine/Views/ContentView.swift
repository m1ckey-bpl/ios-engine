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
                    
                    LibraryView()
                        .tag(1)
                    
                    SpotifyView()
                        .tag(2)
                    
                    EqualizerView()
                        .tag(3)
                    
                    AcousticsView()
                        .tag(4)
                    
                    TimeAlignmentView()
                        .tag(5)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                
                // Pioneer Custom Cockpit Bottom Navigation Bar
                HStack(spacing: 0) {
                    TabPill(icon: "slider.horizontal.3", title: "TUNER", isSelected: selectedTab == 0) {
                        selectedTab = 0
                    }
                    TabPill(icon: "music.note.list", title: "LIBRARY", isSelected: selectedTab == 1) {
                        selectedTab = 1
                    }
                    TabPill(icon: "music.note", title: "SPOTIFY", isSelected: selectedTab == 2) {
                        selectedTab = 2
                    }
                    TabPill(icon: "waveform", title: "EQ", isSelected: selectedTab == 3) {
                        selectedTab = 3
                    }
                    TabPill(icon: "building.columns.fill", title: "HALL", isSelected: selectedTab == 4) {
                        selectedTab = 4
                    }
                    TabPill(icon: "car.fill", title: "CABIN", isSelected: selectedTab == 5) {
                        selectedTab = 5
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
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
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: isSelected ? .black : .regular))
                    .foregroundColor(isSelected ? PioneerColors.amberOrange : PioneerColors.textMuted)
                
                Text(title)
                    .font(.system(size: 8, weight: isSelected ? .black : .bold, design: .monospaced))
                    .foregroundColor(isSelected ? .white : PioneerColors.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }
}
