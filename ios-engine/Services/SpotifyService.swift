import Foundation
import UIKit
import Combine

public struct SpotifyStation: Identifiable {
    public let id: String
    public let name: String
    public let genre: String
    public let url: URL
    public let icon: String
}

/// Opens Spotify-owned Universal Links. Playback stays inside Spotify and is never
/// routed through the local AVAudioEngine DSP graph.
@MainActor
public final class SpotifyService: ObservableObject {
    public static let shared = SpotifyService()

    @Published public private(set) var lastOpenedStationID: String?

    public let stations: [SpotifyStation] = [
        SpotifyStation(id: "1", name: "Today’s Top Hits", genre: "Pop & trending", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")!, icon: "flame.fill"),
        SpotifyStation(id: "2", name: "Live Concert Hall", genre: "Acoustic & orchestral", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX0hWmn8726Rh")!, icon: "building.columns.fill"),
        SpotifyStation(id: "3", name: "Bass Heavy Drive", genre: "Hip-hop & electronic", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd")!, icon: "speaker.wave.3.fill"),
        SpotifyStation(id: "4", name: "Rock Classics", genre: "High-energy rock", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DWXRqgorJj26U")!, icon: "guitars.fill"),
        SpotifyStation(id: "5", name: "Chill Lo-Fi Vibes", genre: "Study & relax", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DXdLEN7aqioXM")!, icon: "headphones")
    ]

    public init() {}

    public func open(_ station: SpotifyStation) {
        lastOpenedStationID = station.id
        UIApplication.shared.open(station.url, options: [:])
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func openSpotifyHome() {
        guard let url = URL(string: "https://open.spotify.com") else { return }
        UIApplication.shared.open(url, options: [:])
    }
}
