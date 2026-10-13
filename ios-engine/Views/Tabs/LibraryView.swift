import SwiftUI

public struct LibraryView: View {
    @ObservedObject var libraryManager = MusicLibraryManager.shared
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    @ObservedObject var ytService = YouTubeMusicService.shared
    
    @State private var showMultiPicker: Bool = false
    @State private var selectedSegment: Int = 0 // 0: Local Library, 1: YouTube Music
    @State private var ytSearchQuery: String = ""
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(PioneerColors.amberOrange.opacity(0.2))
                        .frame(width: 36, height: 36)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(PioneerColors.amberOrange)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("MUSIC DISCOVERY & LIBRARY")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("32-BIT DSP PLAYBACK ARCHITECTURE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.textMuted)
                }
                
                Spacer()
                
                if selectedSegment == 0 {
                    Button(action: {
                        showMultiPicker = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle.fill")
                            Text("ADD SONGS")
                        }
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(PioneerColors.amberOrange)
                        .cornerRadius(8)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PioneerColors.titaniumCard)
            
            // Segmented Picker
            Picker("Source", selection: $selectedSegment) {
                Text("Local Library (\(libraryManager.songs.count))").tag(0)
                Text("YouTube Music Search").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(PioneerColors.titaniumCard)
            
            if selectedSegment == 0 {
                // Local Songs List
                List {
                    ForEach(Array(libraryManager.songs.enumerated()), id: \.element.id) { index, song in
                        Button(action: {
                            libraryManager.selectSong(at: index)
                        }) {
                            HStack(spacing: 12) {
                                let isCurrent = libraryManager.currentSongIndex == index
                                ZStack {
                                    Circle()
                                        .fill(isCurrent ? PioneerColors.amberOrange.opacity(0.25) : Color.white.opacity(0.06))
                                        .frame(width: 32, height: 32)
                                    if isCurrent && dspEngine.isPlaying {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 14))
                                            .foregroundColor(PioneerColors.amberOrange)
                                    } else {
                                        Text("\(index + 1)")
                                            .font(.system(size: 11, weight: .black, design: .monospaced))
                                            .foregroundColor(isCurrent ? PioneerColors.amberOrange : PioneerColors.textMuted)
                                    }
                                }
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(song.title)
                                        .font(.system(size: 14, weight: isCurrent ? .bold : .medium))
                                        .foregroundColor(isCurrent ? PioneerColors.amberOrange : .white)
                                        .lineLimit(1)
                                    
                                    HStack(spacing: 6) {
                                        Text(song.artist)
                                            .font(.system(size: 11))
                                            .foregroundColor(PioneerColors.textMuted)
                                        Text("•")
                                            .font(.system(size: 9))
                                            .foregroundColor(Color.white.opacity(0.2))
                                        Text(song.fileSize)
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(PioneerColors.cyberCyan.opacity(0.8))
                                    }
                                }
                                
                                Spacer()
                                
                                Text(song.formattedDuration)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(PioneerColors.textMuted)
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(Color.white.opacity(0.08))
                    }
                    .onDelete { indexSet in
                        libraryManager.removeSong(at: indexSet)
                    }
                }
                .listStyle(.plain)
                .background(Color.clear)
            } else {
                // YouTube Music Search Section
                VStack(spacing: 12) {
                    // Search Bar
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(PioneerColors.textMuted)
                        TextField("Search YouTube Music...", text: $ytSearchQuery)
                            .foregroundColor(.white)
                            .font(.system(size: 14))
                            .onSubmit {
                                performYouTubeSearch()
                            }
                        if !ytSearchQuery.isEmpty {
                            Button(action: { ytSearchQuery = ""; ytService.searchResults = [] }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(PioneerColors.textMuted)
                            }
                        }
                        Button(action: { performYouTubeSearch() }) {
                            Text("SEARCH")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(PioneerColors.amberOrange)
                                .cornerRadius(6)
                        }
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    
                    if ytService.isSearching {
                        Spacer()
                        ProgressView()
                            .tint(PioneerColors.amberOrange)
                        Text("Searching YouTube Data API & Music Gateway...")
                            .font(.system(size: 12))
                            .foregroundColor(PioneerColors.textMuted)
                        Spacer()
                    } else if ytService.searchResults.isEmpty {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "play.tv.fill")
                                .font(.system(size: 36))
                                .foregroundColor(Color.white.opacity(0.2))
                            Text("Search Millions of Tracks on YouTube")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white.opacity(0.7))
                            Text("Audio streams through Pioneer 10-Band EQ & Reverb")
                                .font(.system(size: 11))
                                .foregroundColor(PioneerColors.textMuted)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(ytService.searchResults) { track in
                                Button(action: {
                                    playYouTubeTrack(track)
                                }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 6)
                                                .fill(Color.red.opacity(0.2))
                                                .frame(width: 40, height: 40)
                                            Image(systemName: "play.circle.fill")
                                                .font(.system(size: 18))
                                                .foregroundColor(.red)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(track.title)
                                                .font(.system(size: 13, weight: .bold))
                                                .foregroundColor(.white)
                                                .lineLimit(1)
                                            
                                            HStack(spacing: 6) {
                                                Text(track.artist)
                                                    .font(.system(size: 11))
                                                    .foregroundColor(PioneerColors.textMuted)
                                                Text("•")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(Color.white.opacity(0.2))
                                                Text("YouTube")
                                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                    .foregroundColor(.red.opacity(0.8))
                                            }
                                        }
                                        
                                        Spacer()
                                        
                                        Text(track.formattedDuration)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundColor(PioneerColors.textMuted)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Color.white.opacity(0.08))
                            }
                        }
                        .listStyle(.plain)
                        .background(Color.clear)
                    }
                }
            }
        }
        .background(PioneerColors.carbonBg.ignoresSafeArea())
        .sheet(isPresented: $showMultiPicker) {
            DocumentPickerView { urls in
                libraryManager.addSongs(from: urls)
            }
        }
    }
    
    private func performYouTubeSearch() {
        guard !ytSearchQuery.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        Task {
            await ytService.search(query: ytSearchQuery)
        }
    }
    
    private func playYouTubeTrack(_ track: YouTubeTrackResult) {
        let newSong = SongItem(
            title: track.title,
            artist: track.artist,
            duration: track.duration,
            fileSize: "YouTube Stream",
            isBuiltIn: false,
            isYouTube: true,
            thumbnailURL: track.artworkURL
        )
        libraryManager.songs.insert(newSong, at: 0)
        libraryManager.selectSong(at: 0)
        
        Task {
            await LRCLibService.shared.fetchLyrics(title: track.title, artist: track.artist, duration: track.duration)
        }
    }
}
