import SwiftUI

public struct LibraryView: View {
    @ObservedObject var libraryManager = MusicLibraryManager.shared
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    @State private var showMultiPicker: Bool = false
    
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
                    Text("MUSIC LIBRARY")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(libraryManager.songs.count) TRACKS READY FOR DSP TUNING")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.textMuted)
                }
                
                Spacer()
                
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
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(PioneerColors.titaniumCard)
            
            // Songs List
            List {
                ForEach(Array(libraryManager.songs.enumerated()), id: \.element.id) { index, song in
                    Button(action: {
                        libraryManager.selectSong(at: index)
                    }) {
                        HStack(spacing: 12) {
                            // Track Number / Animated Equalizer Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(libraryManager.currentSongIndex == index ? PioneerColors.amberOrange.opacity(0.2) : Color.white.opacity(0.05))
                                    .frame(width: 34, height: 34)
                                
                                if libraryManager.currentSongIndex == index && dspEngine.isPlaying {
                                    Image(systemName: "waveform")
                                        .foregroundColor(PioneerColors.amberOrange)
                                        .font(.system(size: 14))
                                } else {
                                    Text(String(format: "%02d", index + 1))
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(libraryManager.currentSongIndex == index ? PioneerColors.amberOrange : PioneerColors.textMuted)
                                }
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title)
                                    .font(.system(size: 13, weight: .bold, design: .rounded))
                                    .foregroundColor(libraryManager.currentSongIndex == index ? PioneerColors.amberOrange : .white)
                                    .lineLimit(1)
                                
                                HStack(spacing: 8) {
                                    Text(song.artist)
                                        .font(.system(size: 11))
                                        .foregroundColor(PioneerColors.textMuted)
                                    
                                    Text("•")
                                        .foregroundColor(Color.white.opacity(0.2))
                                    
                                    Text(song.fileSize)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(song.isBuiltIn ? PioneerColors.cyberCyan : Color.white.opacity(0.6))
                                }
                            }
                            
                            Spacer()
                            
                            Text(song.formattedDuration)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(PioneerColors.textMuted)
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(PioneerColors.carbonBg)
                    .listRowSeparatorTint(Color.white.opacity(0.08))
                }
                .onDelete { indexSet in
                    libraryManager.deleteSong(at: indexSet)
                }
            }
            .listStyle(PlainListStyle())
            
            // Bottom Player Dock with Scrubber & Controls
            VStack(spacing: 10) {
                // Time Scrubber Slider
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { dspEngine.totalDuration > 0 ? (dspEngine.currentTime / dspEngine.totalDuration) : 0 },
                            set: { dspEngine.seek(to: $0) }
                        ),
                        in: 0...1
                    )
                    .accentColor(PioneerColors.amberOrange)
                    
                    HStack {
                        Text(formatTime(dspEngine.currentTime))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                        Spacer()
                        Text(formatTime(dspEngine.totalDuration))
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                    }
                }
                .padding(.horizontal, 20)
                
                // Transport Buttons
                HStack(spacing: 28) {
                    // Shuffle
                    Button(action: {
                        libraryManager.isShuffleEnabled.toggle()
                    }) {
                        Image(systemName: "shuffle")
                            .font(.system(size: 15))
                            .foregroundColor(libraryManager.isShuffleEnabled ? PioneerColors.amberOrange : PioneerColors.textMuted)
                    }
                    
                    // Previous Track
                    Button(action: {
                        libraryManager.playPrevious()
                    }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                    
                    // Play / Pause
                    Button(action: {
                        dspEngine.togglePlayPause()
                    }) {
                        ZStack {
                            Circle()
                                .fill(PioneerColors.amberOrange)
                                .frame(width: 52, height: 52)
                            Image(systemName: dspEngine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 22))
                                .foregroundColor(.black)
                        }
                        .shadow(color: PioneerColors.amberOrange.opacity(0.5), radius: 8)
                    }
                    
                    // Next Track
                    Button(action: {
                        libraryManager.playNext()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white)
                    }
                    
                    // Repeat
                    Button(action: {
                        libraryManager.isRepeatEnabled.toggle()
                    }) {
                        Image(systemName: "repeat")
                            .font(.system(size: 15))
                            .foregroundColor(libraryManager.isRepeatEnabled ? PioneerColors.cyberCyan : PioneerColors.textMuted)
                    }
                }
                .padding(.bottom, 6)
            }
            .padding(.vertical, 10)
            .background(PioneerColors.titaniumCard)
            .overlay(
                Rectangle()
                    .fill(PioneerColors.titaniumCardBorder)
                    .frame(height: 1),
                alignment: .top
            )
        }
        .background(PioneerColors.carbonBg)
        .sheet(isPresented: $showMultiPicker) {
            DocumentPickerView(allowsMultipleSelection: true, onPick: { urls in
                libraryManager.addSongs(from: urls)
                showMultiPicker = false
            }, onCancel: {
                showMultiPicker = false
            })
            .ignoresSafeArea()
        }
    }
    
    private func formatTime(_ secs: TimeInterval) -> String {
        let m = Int(secs) / 60
        let s = Int(secs) % 60
        return String(format: "%02d:%02d", m, s)
    }
}
