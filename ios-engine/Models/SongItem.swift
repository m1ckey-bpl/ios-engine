import Foundation
import AVFoundation

/// A local file or a generated in-app test signal. Streaming catalog results use
/// their provider's official player and are not represented as DSP library items.
public struct SongItem: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let fileURL: URL?
    public let fileSize: String
    public let isBuiltIn: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        duration: TimeInterval,
        fileURL: URL? = nil,
        fileSize: String = "Demo",
        isBuiltIn: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileURL = fileURL
        self.fileSize = fileSize
        self.isBuiltIn = isBuiltIn
    }

    public var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        return String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}
