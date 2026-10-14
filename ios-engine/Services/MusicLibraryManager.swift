import Foundation
import AVFoundation
import UIKit
import Combine
import CryptoKit

public enum AudioImportOutcome: Equatable {
    case imported
    case alreadyInLibrary
    case rejected(String)
}

private struct ImportedAudioSummary: Sendable {
    let duration: TimeInterval
    let size: Int64
    let fingerprint: String
}

private struct ImportMetadata: Sendable {
    let title: String?
    let artist: String?
}

private struct AudioFileMetadata: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let artwork: Data?
}

private func audioFileFingerprint(at url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

@MainActor
public final class MusicLibraryManager: ObservableObject {
    public static let shared = MusicLibraryManager()

    @Published public var songs: [SongItem] = []
    @Published public var currentSongIndex: Int = 0
    @Published public var isShuffleEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(isShuffleEnabled, forKey: "music_shuffle_enabled")
            if oldValue != isShuffleEnabled {
                rebuildShuffleDeck(keepingCurrent: true)
            }
        }
    }
    @Published public var repeatMode: RepeatMode = .off {
        didSet {
            UserDefaults.standard.set(repeatMode.rawValue, forKey: "music_repeat_mode")
        }
    }
    @Published public private(set) var isImporting = false
    @Published public var lastImportMessage: String?

    private var activeImportCount = 0
    private var importPipelineLocked = false
    private var importWaiters: [CheckedContinuation<Void, Never>] = []

    /// Compatibility for older call sites; repeat-one and repeat-all are both enabled modes.
    public var isRepeatEnabled: Bool { repeatMode != .off }

    private var shuffleBag: [UUID] = []
    private var shuffleHistory: [UUID] = []
    private var shuffleHistoryCursor = -1

    public var currentSong: SongItem? {
        guard !songs.isEmpty, songs.indices.contains(currentSongIndex) else { return nil }
        return songs[currentSongIndex]
    }

    public init() {
        let defaults = UserDefaults.standard
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: "music_repeat_mode") ?? "") ?? .off
        isShuffleEnabled = defaults.bool(forKey: "music_shuffle_enabled")
        cleanStaleImportFiles()
        loadDefaultLibrary()
        restoreImportedSongs()
        rebuildShuffleDeck(keepingCurrent: true)
    }

    private func cleanStaleImportFiles() {
        let libraryDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MusicLibrary", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: libraryDirectory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.lastPathComponent.hasPrefix(".import-") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func loadDefaultLibrary() {
        songs = [
            SongItem(title: "DSP ENGINE Test Signal", artist: "Built-in audio demo", duration: 30, fileSize: "Demo", isBuiltIn: true, dateAdded: .distantPast)
        ]
    }

    /// Imports user-selected audio into the app sandbox. File copies, decoding probes,
    /// and content hashing run on a utility task so large files do not stall the UI.
    public func addSongs(from urls: [URL]) {
        guard !urls.isEmpty else { return }
        Task { _ = await importSongs(from: urls, overrides: [:]) }
    }

    private func acquireImportPipeline() async {
        if !importPipelineLocked {
            importPipelineLocked = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            importWaiters.append(continuation)
        }
    }

    private func releaseImportPipeline() {
        if importWaiters.isEmpty {
            importPipelineLocked = false
        } else {
            importWaiters.removeFirst().resume()
        }
    }

    /// Completes a download by validating it, atomically moving it into the library,
    /// and adding it to the same AVAudioEngine-backed local queue.
    public func importDownloadedFile(from stagedURL: URL, title: String, artist: String) async -> AudioImportOutcome {
        defer { try? FileManager.default.removeItem(at: stagedURL) }
        let outcomes = await importSongs(
            from: [stagedURL],
            overrides: [stagedURL: ImportMetadata(title: title, artist: artist)]
        )
        return outcomes.first ?? .rejected("The downloaded file could not be added to the library.")
    }

    private func importSongs(from urls: [URL], overrides: [URL: ImportMetadata]) async -> [AudioImportOutcome] {
        guard !urls.isEmpty else { return [] }
        await acquireImportPipeline()
        activeImportCount += 1
        isImporting = true
        defer {
            activeImportCount = max(0, activeImportCount - 1)
            isImporting = activeImportCount > 0 || !importWaiters.isEmpty
            releaseImportPipeline()
        }

        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let libraryDirectory = documents.appendingPathComponent("MusicLibrary", isDirectory: true)
        do {
            try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        } catch {
            lastImportMessage = "Could not create the local music folder."
            return urls.map { _ in .rejected("Could not create the local music folder.") }
        }

        await ensureRestoredFingerprints()
        var addedSongs: [SongItem] = []
        var outcomes: [AudioImportOutcome] = []
        var fingerprintsSeen = Set(songs.compactMap(\.fileFingerprint))
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useMB, .useKB]
        byteFormatter.countStyle = .file

        for sourceURL in urls {
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }

            guard sourceURL.isFileURL, fileManager.fileExists(atPath: sourceURL.path) else {
                outcomes.append(.rejected("The selected audio file is no longer available."))
                continue
            }

            let sourceExtension = sourceURL.pathExtension.lowercased()
            let fileExtension = sourceExtension.isEmpty ? "audio" : sourceExtension
            let stagingURL = libraryDirectory.appendingPathComponent(".import-\(UUID().uuidString).\(fileExtension)")
            do {
                let summary = try await Task.detached(priority: .utility) { () throws -> ImportedAudioSummary in
                    let manager = FileManager.default
                    try manager.copyItem(at: sourceURL, to: stagingURL)
                    do {
                        let probe = try AVAudioFile(forReading: stagingURL)
                        let format = probe.processingFormat
                        guard format.sampleRate.isFinite, format.sampleRate >= 8_000, format.sampleRate <= 192_000,
                              format.channelCount >= 1, format.channelCount <= 2 else {
                            throw NSError(domain: "DSPAudioImport", code: 1)
                        }
                        let probeFrameCount = AVAudioFrameCount(min(Int64(8_192), probe.length))
                        guard probeFrameCount > 0,
                              let probeBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: probeFrameCount) else {
                            throw NSError(domain: "DSPAudioImport", code: 2)
                        }
                        try probe.read(into: probeBuffer, frameCount: probeFrameCount)
                        guard probeBuffer.frameLength > 0 else { throw NSError(domain: "DSPAudioImport", code: 3) }
                        let attributes = try manager.attributesOfItem(atPath: stagingURL.path)
                        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                        let fingerprint = try audioFileFingerprint(at: stagingURL)
                        let duration = probe.length > 0 ? Double(probe.length) / format.sampleRate : 0
                        guard duration.isFinite, duration > 0, size > 0 else {
                            throw NSError(domain: "DSPAudioImport", code: 2)
                        }
                        return ImportedAudioSummary(duration: duration, size: size, fingerprint: fingerprint)
                    } catch {
                        try? manager.removeItem(at: stagingURL)
                        throw error
                    }
                }.value

                if fingerprintsSeen.contains(summary.fingerprint) {
                    try? fileManager.removeItem(at: stagingURL)
                    outcomes.append(.alreadyInLibrary)
                    continue
                }

                let metadata = await readAudioMetadata(from: stagingURL)
                let override = overrides[sourceURL]
                let suggestedTitle = nonEmpty(override?.title) ?? nonEmpty(metadata.title)
                    ?? sourceURL.deletingPathExtension().lastPathComponent
                let title = suggestedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let artist = nonEmpty(override?.artist) ?? nonEmpty(metadata.artist) ?? "Imported audio"
                let destinationURL = uniqueDestinationURL(
                    title: title,
                    fileExtension: fileExtension,
                    in: libraryDirectory
                )
                try fileManager.moveItem(at: stagingURL, to: destinationURL)
                fingerprintsSeen.insert(summary.fingerprint)
                addedSongs.append(
                    SongItem(
                        title: title,
                        artist: artist,
                        album: nonEmpty(metadata.album),
                        duration: summary.duration,
                        fileURL: destinationURL,
                        fileSize: byteFormatter.string(fromByteCount: summary.size),
                        isBuiltIn: false,
                        artworkData: metadata.artwork,
                        fileFingerprint: summary.fingerprint,
                        dateAdded: Date()
                    )
                )
                outcomes.append(.imported)
            } catch {
                try? fileManager.removeItem(at: stagingURL)
                outcomes.append(.rejected("This file could not be decoded as supported audio. It may be damaged, DRM-protected, or unsupported."))
            }
        }

        if !addedSongs.isEmpty {
            songs.append(contentsOf: addedSongs)
            saveImportedSongsList()
            if isShuffleEnabled {
                let alreadyQueued = Set(shuffleBag + shuffleHistory)
                shuffleBag.append(contentsOf: addedSongs.map(\.id).filter { !alreadyQueued.contains($0) }.shuffled())
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }

        let importedCount = outcomes.filter { $0 == .imported }.count
        let duplicateCount = outcomes.filter { $0 == .alreadyInLibrary }.count
        let failures = outcomes.compactMap { outcome -> String? in
            if case .rejected(let message) = outcome { return message }
            return nil
        }
        var messages: [String] = []
        if importedCount > 0 { messages.append("Added \(importedCount) track\(importedCount == 1 ? "" : "s") to your library.") }
        if duplicateCount > 0 { messages.append("\(duplicateCount) duplicate track\(duplicateCount == 1 ? " was" : "s were") already in the library.") }
        messages.append(contentsOf: failures)
        lastImportMessage = messages.isEmpty ? nil : messages.joined(separator: " ")
        return outcomes
    }

    private func uniqueDestinationURL(title: String, fileExtension: String, in directory: URL) -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " _-()."))
        let safeBase = title.unicodeScalars
            .map { allowed.contains($0) ? String($0) : "-" }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
        let base = safeBase.isEmpty ? "Audio" : String(safeBase.prefix(100))
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(fileExtension)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(suffix))").appendingPathExtension(fileExtension)
            suffix += 1
        }
        return candidate
    }

    private func nonEmpty(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func readAudioMetadata(from url: URL) async -> AudioFileMetadata {
        do {
            let metadata = try await AVURLAsset(url: url).load(.commonMetadata)
            let title = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierTitle).first?.stringValue
            let artist = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtist).first?.stringValue
            let album = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierAlbumName).first?.stringValue
            let rawArtwork = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first?.dataValue
            let artwork = rawArtwork.flatMap { $0.count <= 8 * 1_024 * 1_024 ? $0 : nil }
            return AudioFileMetadata(title: title, artist: artist, album: album, artwork: artwork)
        } catch {
            return AudioFileMetadata(title: nil, artist: nil, album: nil, artwork: nil)
        }
    }

    /// Select a track. Tapping a library row starts it immediately; callers may pass
    /// autoplay: false when they only want to load metadata without starting playback.
    public func selectSong(at index: Int, autoplay: Bool = true) {
        guard songs.indices.contains(index) else { return }
        _ = startSong(at: index, autoplay: autoplay, resetShuffleHistory: true)
    }

    /// Manual Next always loads and starts the next available song, even if playback was paused.
    public func playNext() {
        guard !songs.isEmpty, let nextIndex = nextTrackIndex() else { return }
        _ = startSong(at: nextIndex, autoplay: true, resetShuffleHistory: false)
    }

    /// Called once when the active source reaches its end. Returns false when no next item
    /// can be started, allowing the audio engine to stop cleanly.
    @discardableResult
    public func advanceAfterTrackFinished() -> Bool {
        guard !songs.isEmpty else { return false }
        if repeatMode == .one {
            return startSong(at: currentSongIndex, autoplay: true, resetShuffleHistory: false)
        }
        guard let nextIndex = nextTrackIndex() else { return false }
        return startSong(at: nextIndex, autoplay: true, resetShuffleHistory: false)
    }

    public func playPrevious() {
        guard !songs.isEmpty else { return }

        if isShuffleEnabled {
            if shuffleHistoryCursor > 0 {
                shuffleHistoryCursor -= 1
                if let index = songs.firstIndex(where: { $0.id == shuffleHistory[shuffleHistoryCursor] }) {
                    _ = startSong(at: index, autoplay: true, resetShuffleHistory: false)
                    return
                }
            }
            // With no earlier shuffled item, Previous restarts the current song.
            _ = startSong(at: currentSongIndex, autoplay: true, resetShuffleHistory: false)
            return
        }

        let previousIndex: Int
        if currentSongIndex > 0 {
            previousIndex = currentSongIndex - 1
        } else if repeatMode == .all {
            previousIndex = songs.count - 1
        } else {
            previousIndex = currentSongIndex
        }
        _ = startSong(at: previousIndex, autoplay: true, resetShuffleHistory: false)
    }

    public func toggleShuffle() {
        UISelectionFeedbackGenerator().selectionChanged()
        isShuffleEnabled.toggle()
    }

    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func nextTrackIndex() -> Int? {
        guard !songs.isEmpty else { return nil }
        if isShuffleEnabled { return nextShuffledIndex() }

        if currentSongIndex + 1 < songs.count { return currentSongIndex + 1 }
        return repeatMode == .all ? 0 : nil
    }

    private func nextShuffledIndex() -> Int? {
        if shuffleHistoryCursor + 1 < shuffleHistory.count {
            let nextID = shuffleHistory[shuffleHistoryCursor + 1]
            guard let index = songs.firstIndex(where: { $0.id == nextID }) else { return nil }
            shuffleHistoryCursor += 1
            return index
        }

        if shuffleBag.isEmpty {
            guard repeatMode == .all else { return nil }
            let currentID = currentSong?.id
            shuffleBag = songs.map(\.id).filter { $0 != currentID }.shuffled()
            if shuffleBag.isEmpty, let currentID {
                // A one-song queue in Repeat All must still be able to repeat that song.
                shuffleBag = [currentID]
            }
        }

        guard !shuffleBag.isEmpty else { return nil }
        let nextID = shuffleBag.removeFirst()
        if shuffleHistoryCursor + 1 < shuffleHistory.count {
            shuffleHistory.removeSubrange((shuffleHistoryCursor + 1)..<shuffleHistory.count)
        }
        shuffleHistory.append(nextID)
        shuffleHistoryCursor = shuffleHistory.count - 1
        return songs.firstIndex(where: { $0.id == nextID })
    }

    private func startSong(at index: Int, autoplay: Bool, resetShuffleHistory: Bool) -> Bool {
        guard songs.indices.contains(index) else { return false }
        DirectStreamDSPPlayer.shared.stop()
        currentSongIndex = index
        let song = songs[index]

        if resetShuffleHistory && isShuffleEnabled {
            rebuildShuffleDeck(keepingCurrent: true)
        }

        if let fileURL = song.fileURL {
            return AudioDSPEngine.shared.loadAudioFile(
                url: fileURL,
                title: song.title,
                artist: song.artist,
                duration: song.duration,
                autoplay: autoplay
            )
        }
        return AudioDSPEngine.shared.loadBuiltInDemo(
            title: song.title,
            artist: song.artist,
            duration: song.duration,
            autoplay: autoplay
        )
    }

    private func rebuildShuffleDeck(keepingCurrent: Bool) {
        guard isShuffleEnabled else {
            shuffleBag.removeAll()
            shuffleHistory.removeAll()
            shuffleHistoryCursor = -1
            return
        }

        let currentID = keepingCurrent ? currentSong?.id : nil
        if let currentID {
            shuffleHistory = [currentID]
            shuffleHistoryCursor = 0
            shuffleBag = songs.map(\.id).filter { $0 != currentID }.shuffled()
        } else {
            shuffleHistory = []
            shuffleHistoryCursor = -1
            shuffleBag = songs.map(\.id).shuffled()
        }
    }

    public func removeSong(at indexSet: IndexSet) {
        deleteSong(at: indexSet)
    }

    public func deleteSong(at indexSet: IndexSet) {
        let validIndices = indexSet.filter { songs.indices.contains($0) }
        guard !validIndices.isEmpty else { return }

        let removedCurrent = validIndices.contains(currentSongIndex)
        let removedBeforeCurrent = validIndices.filter { $0 < currentSongIndex }.count
        let fileManager = FileManager.default
        for index in validIndices.sorted(by: >) {
            if let url = songs[index].fileURL { try? fileManager.removeItem(at: url) }
            songs.remove(at: index)
        }
        saveImportedSongsList()

        if songs.isEmpty {
            currentSongIndex = 0
            AudioDSPEngine.shared.stop()
        } else if removedCurrent {
            AudioDSPEngine.shared.stop()
            currentSongIndex = min(currentSongIndex, songs.count - 1)
            selectSong(at: currentSongIndex, autoplay: false)
        } else {
            currentSongIndex = max(0, currentSongIndex - removedBeforeCurrent)
        }
        rebuildShuffleDeck(keepingCurrent: true)
    }

    private func saveImportedSongsList() {
        let imported = songs.filter { !$0.isBuiltIn && $0.fileURL != nil }
        let entries: [[String: Any]] = imported.compactMap { song in
            guard let path = song.fileURL?.path else { return nil }
            return [
                "path": path,
                "title": song.title,
                "artist": song.artist,
                "album": song.album ?? "",
                "fingerprint": song.fileFingerprint ?? "",
                "dateAdded": song.dateAdded.timeIntervalSince1970
            ]
        }
        UserDefaults.standard.set(entries, forKey: "saved_library_entries")
        UserDefaults.standard.set(imported.compactMap { $0.fileURL?.path }, forKey: "saved_library_paths")
    }

    private func restoreImportedSongs() {
        let defaults = UserDefaults.standard
        let storedEntries = defaults.array(forKey: "saved_library_entries") as? [[String: Any]]
        let entries: [[String: Any]]
        if let storedEntries {
            entries = storedEntries
        } else {
            entries = (defaults.stringArray(forKey: "saved_library_paths") ?? []).map { ["path": $0] }
        }
        guard !entries.isEmpty else { return }

        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useMB, .useKB]
        byteFormatter.countStyle = .file

        for entry in entries {
            guard let path = entry["path"] as? String,
                  FileManager.default.fileExists(atPath: path),
                  let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { continue }
            let url = URL(fileURLWithPath: path)
            let sampleRate = file.processingFormat.sampleRate
            let duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            let filename = url.deletingPathExtension().lastPathComponent
            let fingerprint = (entry["fingerprint"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let dateAdded = (entry["dateAdded"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) } ?? .distantPast
            let song = SongItem(
                title: (entry["title"] as? String) ?? filename,
                artist: (entry["artist"] as? String) ?? "Imported audio",
                album: (entry["album"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                duration: duration.isFinite && duration > 0 ? duration : 0,
                fileURL: url,
                fileSize: byteFormatter.string(fromByteCount: size),
                isBuiltIn: false,
                fileFingerprint: fingerprint,
                dateAdded: dateAdded
            )
            songs.append(song)
            Task { await enrichRestoredSong(id: song.id, url: url) }
        }
    }

    private func ensureRestoredFingerprints() async {
        let missing = songs.filter { !$0.isBuiltIn && $0.fileURL != nil && $0.fileFingerprint == nil }
        var didUpdate = false
        for song in missing {
            guard let url = song.fileURL else { continue }
            let fingerprint = try? await Task.detached(priority: .utility) {
                try audioFileFingerprint(at: url)
            }.value
            guard let fingerprint, let index = songs.firstIndex(where: { $0.id == song.id }) else { continue }
            songs[index].fileFingerprint = fingerprint
            didUpdate = true
        }
        if didUpdate { saveImportedSongsList() }
    }

    private func enrichRestoredSong(id: UUID, url: URL) async {
        let metadata = await readAudioMetadata(from: url)
        let fingerprint = try? await Task.detached(priority: .utility) {
            try audioFileFingerprint(at: url)
        }.value
        guard let index = songs.firstIndex(where: { $0.id == id }) else { return }
        let originalFilename = url.deletingPathExtension().lastPathComponent
        if songs[index].title == originalFilename, let title = nonEmpty(metadata.title) {
            songs[index].title = title
        }
        if songs[index].artist == "Imported audio", let artist = nonEmpty(metadata.artist) {
            songs[index].artist = artist
        }
        if songs[index].album == nil { songs[index].album = nonEmpty(metadata.album) }
        if songs[index].artworkData == nil { songs[index].artworkData = metadata.artwork }
        if songs[index].fileFingerprint == nil, let fingerprint { songs[index].fileFingerprint = fingerprint }
        saveImportedSongsList()
    }
}
