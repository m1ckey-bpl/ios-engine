import SwiftUI

public struct SpotifyView: View {
    @ObservedObject var spotifyService = SpotifyService.shared
    @State private var searchQuery: String = ""
    
    public init() {}
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 6)
                
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SPOTIFY COMPANION")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                        Text("CONNECT & TUNE YOUR SPOTIFY AUDIO")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                
                // Spotify Launch Card
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Color(red: 0.11, green: 0.84, blue: 0.38))
                                .frame(width: 50, height: 50)
                            Image(systemName: "music.note")
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.black)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("SPOTIFY CONNECT")
                                .font(.system(size: 14, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                            
                            Text("Launch Spotify directly with Pioneer DSP active")
                                .font(.system(size: 11))
                                .foregroundColor(PioneerColors.textMuted)
                        }
                        
                        Spacer()
                    }
                    
                    Button(action: {
                        spotifyService.openSpotifyApp()
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right.square.fill")
                            Text("OPEN SPOTIFY APP")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.black)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Color(red: 0.11, green: 0.84, blue: 0.38))
                        .cornerRadius(14)
                    }
                }
                .padding(20)
                .pioneerCard(cornerRadius: 20, highlight: Color(red: 0.11, green: 0.84, blue: 0.38).opacity(0.5))
                .padding(.horizontal, 20)
                
                // Spotify Track Search / Launcher
                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK SPOTIFY SEARCH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.textMuted)
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(PioneerColors.textMuted)
                        
                        TextField("Search track, artist, or playlist...", text: $searchQuery)
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                        
                        if !searchQuery.isEmpty {
                            Button(action: {
                                spotifyService.searchSpotify(query: searchQuery)
                            }) {
                                Text("GO")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.black)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(PioneerColors.cyberCyan)
                                    .cornerRadius(6)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(PioneerColors.titaniumCardBorder, lineWidth: 1)
                    )
                }
                .padding(18)
                .pioneerCard(cornerRadius: 20)
                .padding(.horizontal, 20)
                
                // How to use guide
                VStack(alignment: .leading, spacing: 10) {
                    Text("HOW TO ENJOY SPOTIFY WITH PIONEER DSP:")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.amberOrange)
                    
                    Text("1. Play your favorite music in Spotify.\n2. Pioneer DSP stays running persistently in the background.\n3. Use Pioneer DSP to tune Concert Hall spatial reverberation, 10-band equalizer, and Todoroki Super Bass in real time!")
                        .font(.system(size: 12))
                        .foregroundColor(PioneerColors.textMuted)
                        .lineSpacing(4)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .pioneerCard(cornerRadius: 18)
                .padding(.horizontal, 20)
                
                Spacer().frame(height: 30)
            }
        }
    }
}
