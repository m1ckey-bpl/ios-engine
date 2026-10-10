import Foundation
import AVFoundation
import UIKit

@MainActor
public final class MusicLibraryManager: ObservableObject {
    public static let shared = MusicLibraryManager()
    
    @Published public var songs: [SongItem] = []
    @Published public var currentSongIndex: Int = 0
    @Published public var isShuffleEnabled: Bool = false
    @Published public var isRepeatEnabled: Bool = true
    
    public var currentSong: SongItem? {
        guard !songs.isEmpty, currentSongIndex >= 0 && currentSongIndex < songs.count else { return nil }
        return songs[currentSongIndex]
    }
    
    public init() {
        loadDefaultLibrary()
        restoreImportedSongs()
    }
    
    private func loadDefaultLibrary() {
        let defaults: [SongItem] = [
            SongItem(
                title: "Concert Hall Acoustic Master",
                artist: "Pioneer Philharmonic Studio",
                duration: 180,
                fileSize: "Hi-Res Master",
                isBuiltIn: true
            ),
            SongItem(
                title: "Todoroki 808 Sub-Bass Groove",
                artist: "Pioneer Bass Engineering",
                duration: 165,
                fileSize: "Hi-Res Master",
                isBuiltIn: true
            ),
            SongItem(
                title: "Tokyo Highway Synth Drive",
                artist: "Cyber Audio Collective",
                duration: 210,
                fileSize: "Hi-Res Master",
                isBuiltIn: true
            ),
            SongItem(
                title: "Midnight Lo-Fi Piano Lounge",
                artist: "Acoustic Stage Project",
                duration: 195,
                fileSize: "Hi-Res Master",
                isBuiltIn: true
            )
        ]
        self.songs = defaults
    }
    
    public func addSongs(from urls: [URL]) {
        let fileManager = FileManager.default
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let libraryDir = docs.appendingPathComponent("MusicLibrary", isDirectory: true)
        try? fileManager.createDirectory(at: libraryDir, withIntermediateDirectories: true)
        
        var addedSongs: [SongItem] = []
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB, .useKB]
        bcf.countStyle = .file
        
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            
            let destURL = libraryDir.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: destURL)
            
            do {
                try fileManager.copyItem(at: url, to: destURL)
                
                let asset = AVURLAsset(url: destURL)
                let durationSecs = CMTimeGetSeconds(asset.duration)
                let finalDuration = durationSecs.isNormal && durationSecs > 0 ? durationSecs : 180.0
                
                let fileAttributes = try? fileManager.attributesOfItem(atPath: destURL.path)
                let sizeBytes = (fileAttributes?[.size] as? Int64) ?? 0
                let formattedSize = bcf.string(fromByteCount: sizeBytes)
                
                let title = destURL.deletingPathExtension().lastPathComponent
                let song = SongItem(
                    title: title,
                    artist: "Imported Track",
                    duration: finalDuration,
                    fileURL: destURL,
                    fileSize: formattedSize,
                    isBuiltIn: false
                )
                addedSongs.append(song)
            } catch {
                print("Failed to import song: \(error)")
            }
        }
        
        if !addedSongs.isEmpty {
            self.songs.append(contentsOf: addedSongs)
            saveImportedSongsList()
            let impact = UINotificationFeedbackGenerator()
            impact.notificationOccurred(.success)
        }
    }
    
    public func selectSong(at index: Int) {
        guard index >= 0 && index < songs.count else { return }
        self.currentSongIndex = index
        let song = songs[index]
        
        if let fileURL = song.fileURL {
            AudioDSPEngine.shared.loadAudioFile(url: fileURL, title: song.title, artist: song.artist, duration: song.duration)
        } else {
            AudioDSPEngine.shared.loadBuiltInDemo(title: song.title, artist: song.artist, duration: song.duration)
        }
    }
    
    public func playNext() {
        guard !songs.isEmpty else { return }
        if isShuffleEnabled {
            currentSongIndex = Int.random(in: 0..<songs.count)
        } else {
            currentSongIndex = (currentSongIndex + 1) % songs.count
        }
        selectSong(at: currentSongIndex)
    }
    
    public func playPrevious() {
        guard !songs.isEmpty else { return }
        currentSongIndex = (currentSongIndex - 1 + songs.count) % songs.count
        selectSong(at: currentSongIndex)
    }
    
    public func deleteSong(at indexSet: IndexSet) {
        let fileManager = FileManager.default
        for index in indexSet {
            let song = songs[index]
            if let url = song.fileURL {
                try? fileManager.removeItem(at: url)
            }
        }
        songs.remove(atOffsets: indexSet)
        saveImportedSongsList()
        if currentSongIndex >= songs.count {
            currentSongIndex = max(0, songs.count - 1)
        }
    }
    
    private func saveImportedSongsList() {
        let imported = songs.compactMap { song -> String? in
            if !song.isBuiltIn, let path = song.fileURL?.path {
                return path
            }
            return nil
        }
        UserDefaults.standard.set(imported, forKey: "saved_library_paths")
    }
    
    private func restoreImportedSongs() {
        guard let paths = UserDefaults.standard.stringArray(forKey: "saved_library_paths") else { return }
        let bcf = ByteCountFormatter()
        bcf.allowedUnits = [.useMB, .useKB]
        
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: path) {
                let asset = AVURLAsset(url: url)
                let dur = CMTimeGetSeconds(asset.duration)
                let title = url.deletingPathExtension().lastPathComponent
                let attrs = try? FileManager.default.attributesOfItem(atPath: path)
                let size = (attrs?[.size] as? Int64) ?? 0
                
                let song = SongItem(
                    title: title,
                    artist: "Imported Track",
                    duration: dur > 0 ? dur : 180,
                    fileURL: url,
                    fileSize: bcf.string(fromByteCount: size),
                    isBuiltIn: false
                )
                self.songs.append(song)
            }
        }
    }
}
