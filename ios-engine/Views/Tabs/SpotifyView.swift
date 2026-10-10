import SwiftUI

public struct SpotifyView: View {
    @ObservedObject var spotifyService = SpotifyService.shared
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    @State private var showFullScreenWeb: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.11, green: 0.84, blue: 0.38))
                        .frame(width: 36, height: 36)
                    Image(systemName: "music.note")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("SPOTIFY PLAYER & DSP")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("STREAM DIRECTLY WITH REAL-TIME ACOUSTICS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.textMuted)
                }
                
                Spacer()
                
                Button(action: {
                    showFullScreenWeb.toggle()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showFullScreenWeb ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        Text(showFullScreenWeb ? "COMPACT" : "EXPAND")
                    }
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 0.11, green: 0.84, blue: 0.38))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(red: 0.11, green: 0.84, blue: 0.38).opacity(0.4), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PioneerColors.titaniumCard)
            
            // Quick Stations Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(spotifyService.stations) { station in
                        Button(action: {
                            spotifyService.selectStation(station)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: station.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(spotifyService.activeStationId == station.id ? .black : Color(red: 0.11, green: 0.84, blue: 0.38))
                                
                                Text(station.name)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(spotifyService.activeStationId == station.id ? .black : .white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(spotifyService.activeStationId == station.id ? Color(red: 0.11, green: 0.84, blue: 0.38) : Color.white.opacity(0.06))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(spotifyService.activeStationId == station.id ? Color(red: 0.11, green: 0.84, blue: 0.38) : PioneerColors.titaniumCardBorder, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color.black.opacity(0.3))
            
            // In-App Spotify Web Player
            ZStack {
                SpotifyWebView(currentURL: $spotifyService.currentURL)
                    .cornerRadius(showFullScreenWeb ? 0 : 14)
                    .padding(.horizontal, showFullScreenWeb ? 0 : 12)
                    .padding(.top, showFullScreenWeb ? 0 : 8)
            }
            .frame(maxHeight: .infinity)
            
            // Floating DSP Quick Tuning Bar on Spotify Screen
            if !showFullScreenWeb {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        // Quick Concert Hall Toggle
                        Button(action: {
                            dspEngine.toggleConcertHall()
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "building.columns.fill")
                                    .foregroundColor(dspEngine.isConcertHallEnabled ? .black : PioneerColors.amberOrange)
                                Text("CONCERT HALL")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundColor(dspEngine.isConcertHallEnabled ? .black : .white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : PioneerColors.titaniumCardBorder, lineWidth: 1)
                            )
                            .shadow(color: dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange.opacity(0.5) : .clear, radius: 8)
                        }
                        
                        // Quick Super Bass Toggle
                        Button(action: {
                            if dspEngine.superBassGain > 0 {
                                dspEngine.setSuperBass(0)
                            } else {
                                dspEngine.setSuperBass(9.0)
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundColor(dspEngine.superBassGain > 0 ? .black : PioneerColors.cyberCyan)
                                Text("SUPER BASS")
                                    .font(.system(size: 11, weight: .black, design: .rounded))
                                    .foregroundColor(dspEngine.superBassGain > 0 ? .black : .white)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(dspEngine.superBassGain > 0 ? PioneerColors.cyberCyan : Color.white.opacity(0.08))
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(dspEngine.superBassGain > 0 ? PioneerColors.cyberCyan : PioneerColors.titaniumCardBorder, lineWidth: 1)
                            )
                        }
                        
                        Spacer()
                        
                        // Launch Native Spotify App Button
                        Button(action: {
                            spotifyService.openExternalSpotifyApp()
                        }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(red: 0.11, green: 0.84, blue: 0.38))
                                .padding(10)
                                .background(Color.white.opacity(0.08))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(PioneerColors.titaniumCard)
                .overlay(
                    Rectangle()
                        .fill(PioneerColors.titaniumCardBorder)
                        .frame(height: 1),
                    alignment: .top
                )
            }
        }
        .background(PioneerColors.carbonBg)
    }
}
