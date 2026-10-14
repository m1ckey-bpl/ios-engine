import Foundation
import AVFoundation

/// A local, app-owned audio file or the in-app DSP test signal. Search-provider
/// results remain discovery metadata and are never used as playback assets.
public struct SongItem: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var artist: String
    public var album: String?
    public var duration: TimeInterval
    public let fileURL: URL?
    public var fileSize: String
    public let isBuiltIn: Bool
    public var artworkData: Data?
    public var fileFingerprint: String?
    public var dateAdded: Date

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String? = nil,
        duration: TimeInterval,
        fileURL: URL? = nil,
        fileSize: String = "Demo",
        isBuiltIn: Bool = false,
        artworkData: Data? = nil,
        fileFingerprint: String? = nil,
        dateAdded: Date = .now
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.isBuiltIn = isBuiltIn
        self.artworkData = artworkData
        self.fileFingerprint = fileFingerprint
        self.dateAdded = dateAdded
    }

    public var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}
