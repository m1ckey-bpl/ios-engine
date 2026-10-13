import Foundation
import AVFoundation
import UIKit
import Combine

@MainActor
public final class MusicLibraryManager: ObservableObject {
    public static let shared = MusicLibraryManager()

    @Published public var songs: [SongItem] = []
    @Published public var currentSongIndex: Int = 0
    @Published public var isShuffleEnabled: Bool = false
    @Published public var isRepeatEnabled: Bool = true
    @Published public private(set) var isImporting = false

    public var currentSong: SongItem? {
        guard !songs.isEmpty, songs.indices.contains(currentSongIndex) else { return nil }
        return songs[currentSongIndex]
    }

    public init() {
        loadDefaultLibrary()
        restoreImportedSongs()
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

    public func selectSong(at index: Int) {
        guard songs.indices.contains(index) else { return }
        currentSongIndex = index
        let song = songs[index]
        if let fileURL = song.fileURL {
            AudioDSPEngine.shared.loadAudioFile(url: fileURL, title: song.title, artist: song.artist, duration: song.duration)
        } else {
            AudioDSPEngine.shared.loadBuiltInDemo(title: song.title, artist: song.artist, duration: song.duration)
        }
    }

    public func playNext() {
        guard !songs.isEmpty else { return }
        currentSongIndex = isShuffleEnabled
            ? Int.random(in: songs.indices)
            : (currentSongIndex + 1) % songs.count
        selectSong(at: currentSongIndex)
    }

    public func playPrevious() {
        guard !songs.isEmpty else { return }
        currentSongIndex = (currentSongIndex - 1 + songs.count) % songs.count
        selectSong(at: currentSongIndex)
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
            selectSong(at: currentSongIndex)
        } else {
            currentSongIndex = max(0, currentSongIndex - removedBeforeCurrent)
        }
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
