import Foundation
import AVFoundation

public struct SongItem: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let fileURL: URL?
    public let fileSize: String
    public let isBuiltIn: Bool
    
    public init(id: UUID = UUID(), title: String, artist: String, duration: TimeInterval, fileURL: URL? = nil, fileSize: String = "Demo", isBuiltIn: Bool = false) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.isBuiltIn = isBuiltIn
    }
    
    public var formattedDuration: String {
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
