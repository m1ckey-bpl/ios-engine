import Foundation
import UIKit

@MainActor
public final class SpotifyService: ObservableObject {
    public static let shared = SpotifyService()
    
    @Published public var isConnected: Bool = false
    @Published public var currentSpotifyTrack: String = "Starboy"
    @Published public var currentSpotifyArtist: String = "The Weeknd, Daft Punk"
    @Published public var spotifyAlbumArt: String = "music.note"
    @Published public var playbackProgress: Double = 0.45
    
    public init() {}
    
    public func openSpotifyApp() {
        let spotifyURL = URL(string: "spotify:")!
        if UIApplication.shared.canOpenURL(spotifyURL) {
            UIApplication.shared.open(spotifyURL)
        } else {
            // Open Spotify Web
            if let webURL = URL(string: "https://open.spotify.com") {
                UIApplication.shared.open(webURL)
            }
        }
        self.isConnected = true
    }
    
    public func searchSpotify(query: String) {
        let clean = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "spotify:search:\(clean)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
        }
    }
    
    public func toggleSpotifyConnection() {
        isConnected.toggle()
    }
}
