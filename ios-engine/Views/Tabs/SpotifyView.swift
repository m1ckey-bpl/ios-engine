import SwiftUI

public struct SpotifyView: View {
    @ObservedObject private var spotifyService = SpotifyService.shared

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.11, green: 0.84, blue: 0.38))
                            .frame(width: 42, height: 42)
                        Image(systemName: "music.note")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SPOTIFY")
                            .font(.system(size: 17, weight: .black, design: .rounded))
                            .tracking(1.3)
                            .foregroundColor(.white)
                        Text("OFFICIAL PLAYER • SEPARATE FROM DSP")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Open and play in Spotify", systemImage: "arrow.up.right.square")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("Spotify keeps control of its own playback. DSP ENGINE applies EQ and effects to local, non-DRM audio imported into your library—not to Spotify streams.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        spotifyService.openSpotifyHome()
                    } label: {
                        Label("OPEN SPOTIFY", systemImage: "play.fill")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .tracking(0.6)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(red: 0.11, green: 0.84, blue: 0.38), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18, highlight: Color(red: 0.11, green: 0.84, blue: 0.38).opacity(0.65))
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 12) {
                    Text("QUICK PICKS")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.2)
                        .foregroundColor(PioneerColors.amberOrange)

                    ForEach(spotifyService.stations) { station in
                        Button {
                            spotifyService.open(station)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: station.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(Color(red: 0.11, green: 0.84, blue: 0.38))
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(station.name)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundColor(.white)
                                    Text(station.genre.uppercased())
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(PioneerColors.textMuted)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(red: 0.11, green: 0.84, blue: 0.38))
                            }
                            .padding(11)
                            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18, highlight: Color(red: 0.11, green: 0.84, blue: 0.38).opacity(0.38))
                .padding(.horizontal, 20)

                Text("DSP is active when you play audio from the Local Library tab.")
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .foregroundColor(PioneerColors.textMuted)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 26)
            }
        }
        .background(Color.clear)
    }
}
