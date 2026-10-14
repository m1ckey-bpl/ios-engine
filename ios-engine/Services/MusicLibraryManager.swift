import Foundation
import AVFoundation
import UIKit
import Combine

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
        loadDefaultLibrary()
        restoreImportedSongs()
        rebuildShuffleDeck(keepingCurrent: true)
    }

    private func loadDefaultLibrary() {
        songs = [
            SongItem(title: "DSP ENGINE Test Signal", artist: "Built-in audio demo", duration: 30, fileSize: "Demo", isBuiltIn: true)
        ]
    }

    /// Copies Files-picker selections into the app sandbox and adds them to the local library.
    /// A false security-scope return does not automatically mean access is denied; ordinary
    /// sandbox URLs can be copied without starting a security-scoped session.
    public func addSongs(from urls: [URL]) {
        guard !urls.isEmpty, !isImporting else { return }
        Task { await importSongs(from: urls) }
    }

    private func importSongs(from urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }

        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let libraryDirectory = documents.appendingPathComponent("MusicLibrary", isDirectory: true)
        do {
            try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        } catch {
            AudioDSPEngine.shared.reportPlaybackError("Could not create the local music folder.")
            return
        }

        var addedSongs: [SongItem] = []
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useMB, .useKB]
        byteFormatter.countStyle = .file

        for sourceURL in urls {
            let didStartAccess = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccess { sourceURL.stopAccessingSecurityScopedResource() }
            }

            guard sourceURL.isFileURL, fileManager.fileExists(atPath: sourceURL.path) else { continue }
            let destinationURL = uniqueDestinationURL(for: sourceURL, in: libraryDirectory)

            do {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                let probe = try AVAudioFile(forReading: destinationURL)
                let sampleRate = probe.processingFormat.sampleRate
                let duration = sampleRate > 0 ? Double(probe.length) / sampleRate : 0
                let attributes = try? fileManager.attributesOfItem(atPath: destinationURL.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                let title = sourceURL.deletingPathExtension().lastPathComponent

                addedSongs.append(
                    SongItem(
                        title: title,
                        artist: "Imported audio",
                        duration: duration.isFinite && duration > 0 ? duration : 0,
                        fileURL: destinationURL,
                        fileSize: byteFormatter.string(fromByteCount: size),
                        isBuiltIn: false
                    )
                )
            } catch {
                try? fileManager.removeItem(at: destinationURL)
            }
        }

        guard !addedSongs.isEmpty else { return }
        songs.append(contentsOf: addedSongs)
        saveImportedSongsList()
        if isShuffleEnabled {
            let alreadyQueued = Set(shuffleBag + shuffleHistory)
            shuffleBag.append(contentsOf: addedSongs.map(\.id).filter { !alreadyQueued.contains($0) }.shuffled())
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func uniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension
        var candidate = directory.appendingPathComponent(sourceURL.lastPathComponent)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) (\(suffix))" : "\(base) (\(suffix)).\(ext)"
            candidate = directory.appendingPathComponent(name)
            suffix += 1
        }
        return candidate
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
        let importedPaths = songs.compactMap { song -> String? in
            guard !song.isBuiltIn, let path = song.fileURL?.path else { return nil }
            return path
        }
        UserDefaults.standard.set(importedPaths, forKey: "saved_library_paths")
    }

    private func restoreImportedSongs() {
        guard let paths = UserDefaults.standard.stringArray(forKey: "saved_library_paths") else { return }
        let byteFormatter = ByteCountFormatter()
        byteFormatter.allowedUnits = [.useMB, .useKB]
        byteFormatter.countStyle = .file

        for path in paths where FileManager.default.fileExists(atPath: path) {
            let url = URL(fileURLWithPath: path)
            guard let file = try? AVAudioFile(forReading: url) else { continue }
            let sampleRate = file.processingFormat.sampleRate
            let duration = sampleRate > 0 ? Double(file.length) / sampleRate : 0
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            songs.append(
                SongItem(
                    title: url.deletingPathExtension().lastPathComponent,
                    artist: "Imported audio",
                    duration: duration.isFinite && duration > 0 ? duration : 0,
                    fileURL: url,
                    fileSize: byteFormatter.string(fromByteCount: size),
                    isBuiltIn: false
                )
            )
        }
    }
}
