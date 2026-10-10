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

@MainActor
public final class SpotifyService: ObservableObject {
    public static let shared = SpotifyService()
    
    @Published public var currentURL: URL = URL(string: "https://open.spotify.com")!
    @Published public var isPlayerExpanded: Bool = false
    @Published public var currentTrackTitle: String = "Spotify Connect Active"
    @Published public var currentArtist: String = "Pioneer DSP Studio Companion"
    @Published public var isPlaying: Bool = true
    @Published public var activeStationId: String = "1"
    
    public let stations: [SpotifyStation] = [
        SpotifyStation(id: "1", name: "Today's Top Hits", genre: "Pop & Trending", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M")!, icon: "flame.fill"),
        SpotifyStation(id: "2", name: "Live Concert Hall", genre: "Acoustic & Orchestral", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX0hWmn8726Rh")!, icon: "building.columns.fill"),
        SpotifyStation(id: "3", name: "Bass Heavy Drive", genre: "Hip-Hop & Electronic", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DX0XUsuxWHRQd")!, icon: "speaker.wave.3.fill"),
        SpotifyStation(id: "4", name: "Rock Classics", genre: "High Energy Rock", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DWXRqgorJj26U")!, icon: "guitars.fill"),
        SpotifyStation(id: "5", name: "Chill Lo-Fi Vibes", genre: "Study & Relax", url: URL(string: "https://open.spotify.com/playlist/37i9dQZF1DXdLEN7aqioXM")!, icon: "headphones")
    ]
    
    public init() {}
    
    public func selectStation(_ station: SpotifyStation) {
        self.activeStationId = station.id
        self.currentURL = station.url
        self.currentTrackTitle = station.name
        self.currentArtist = station.genre
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    public func openExternalSpotifyApp() {
        let spotifyURL = URL(string: "spotify:")!
        if UIApplication.shared.canOpenURL(spotifyURL) {
            UIApplication.shared.open(spotifyURL)
        } else {
            self.currentURL = URL(string: "https://open.spotify.com")!
        }
    }
}
