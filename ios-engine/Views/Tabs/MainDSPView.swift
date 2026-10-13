import SwiftUI

public struct MainDSPView: View {
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    @ObservedObject var libraryManager = MusicLibraryManager.shared
    @State private var showMultiPicker: Bool = false
    @State private var showLyricsSheet: Bool = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                Spacer().frame(height: 6)

                // Top Header Bar
                HStack(spacing: 12) {
                    DSPLogoMark()

                    Spacer()

                    // Hi-Res Audio Badge
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("LOCAL")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(PioneerColors.hiFiGold)
                        Text("DSP AUDIO")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.4))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(PioneerColors.hiFiGold.opacity(0.4), lineWidth: 1)
                    )
                }
                .padding(.horizontal, 20)

                // Animated Concert Hall Toggle Button
                Button(action: {
                    dspEngine.toggleConcertHall()
                }) {
                    VStack(spacing: 8) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange.opacity(0.25) : Color.white.opacity(0.06))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "building.columns.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : Color.white.opacity(0.4))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text("CONCERT HALL ACOUSTICS")
                                        .font(.system(size: 15, weight: .black, design: .rounded))
                                        .foregroundColor(.white)
                                    if dspEngine.isConcertHallEnabled {
                                        Circle()
                                            .fill(PioneerColors.amberOrange)
                                            .frame(width: 7, height: 7)
                                    }
                                }

                                Text(dspEngine.isConcertHallEnabled ? "3D Spatial Reverb Active • Live Stage Acoustics" : "Tap to Engage Real-Time Concert Hall Reverb")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(dspEngine.isConcertHallEnabled ? PioneerColors.cyberCyan : PioneerColors.textMuted)
                            }

                            Spacer()

                            Text(dspEngine.isConcertHallEnabled ? "ACTIVE" : "ENGAGE")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(dspEngine.isConcertHallEnabled ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : Color.white.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }
                    .padding(16)
                    .pioneerCard(cornerRadius: 18, highlight: dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : PioneerColors.titaniumCardBorder)
                    .scaleEffect(dspEngine.isConcertHallEnabled ? 1.01 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.65), value: dspEngine.isConcertHallEnabled)
                }
                .padding(.horizontal, 20)

                // Real-Time Audio Spectrum Screen
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(PioneerColors.cyberCyan)
                        Text("DSP SIGNAL VISUALIZER")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                        Spacer()
                        Text(dspEngine.isPlaying ? "PLAYBACK ACTIVE" : "STANDBY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(dspEngine.isPlaying ? PioneerColors.amberOrange : Color.white.opacity(0.3))
                    }

                    SpectrumVisualizerView(isPlaying: dspEngine.isPlaying)
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18, highlight: PioneerColors.cyberCyan.opacity(0.4))
                .padding(.horizontal, 20)

                // Dual Rotary Dials: Super Bass (Todoroki) & Reverb Wet/Dry
                HStack(spacing: 16) {
                    VStack {
                        PioneerDialKnob(
                            title: "SUPER BASS",
                            value: Binding(
                                get: { dspEngine.superBassGain },
                                set: { dspEngine.setSuperBass($0) }
                            ),
                            range: 0...12,
                            unit: "dB",
                            accentColor: PioneerColors.amberOrange
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .pioneerCard(cornerRadius: 18)

                    VStack {
                        PioneerDialKnob(
                            title: "REVERB MIX",
                            value: Binding(
                                get: { dspEngine.reverbWetDryMix },
                                set: { dspEngine.setReverbWetDry($0) }
                            ),
                            range: 0...100,
                            unit: "%",
                            accentColor: PioneerColors.cyberCyan
                        )
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .pioneerCard(cornerRadius: 18)
                }
                .padding(.horizontal, 20)

                // Sound Tune Preset Selectors
                VStack(alignment: .leading, spacing: 12) {
                    Text("DSP ENGINE PRESETS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(PioneerColors.textMuted)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(DSPPreset.allCases) { preset in
                                Button(action: {
                                    dspEngine.applyPreset(preset)
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: preset.icon)
                                            .font(.system(size: 12))
                                        Text(preset.rawValue)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    }
                                    .foregroundColor(dspEngine.currentPreset == preset ? .black : .white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(dspEngine.currentPreset == preset ? PioneerColors.amberOrange : Color.white.opacity(0.06))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(dspEngine.currentPreset == preset ? PioneerColors.amberOrange : PioneerColors.titaniumCardBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18)
                .padding(.horizontal, 20)

                // Local-file playback dock
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 44, height: 44)
                            Image(systemName: "music.note")
                                .foregroundColor(PioneerColors.amberOrange)
                        }

                        VStack(alignment: .leading, spacing: 3) {
                            Text(dspEngine.trackTitle)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(dspEngine.trackArtist)
                                .font(.system(size: 11))
                                .foregroundColor(PioneerColors.textMuted)
                        }

                        Spacer()

                        // Lyrics & Previous, Play/Pause, Next Controls
                        HStack(spacing: 12) {
                            Button(action: {
                                showLyricsSheet = true
                                Task {
                                    await LRCLibService.shared.fetchLyrics(title: dspEngine.trackTitle, artist: dspEngine.trackArtist, duration: dspEngine.totalDuration)
                                }
                            }) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(width: 32, height: 32)
                                    Image(systemName: "quote.bubble.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(PioneerColors.amberOrange)
                                }
                            }

                            Button(action: {
                                libraryManager.playPrevious()
                            }) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color.white.opacity(0.7))
                            }

                            Button(action: {
                                dspEngine.togglePlayPause()
                            }) {
                                ZStack {
                                    Circle()
                                        .fill(PioneerColors.amberOrange)
                                        .frame(width: 42, height: 42)
                                    Image(systemName: dspEngine.isPlaying ? "pause.fill" : "play.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(.black)
                                }
                                .shadow(color: PioneerColors.amberOrange.opacity(0.4), radius: 6)
                            }

                            Button(action: {
                                libraryManager.playNext()
                            }) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 15))
                                    .foregroundColor(Color.white.opacity(0.7))
                            }
                        }
                    }

                    Divider().background(Color.white.opacity(0.1))

                    // Import Multi-Song Library Button
                    Button(action: {
                        showMultiPicker = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(PioneerColors.cyberCyan)
                            Text("IMPORT LOCAL AUDIO FILES")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(PioneerColors.cyberCyan)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.04))
                        .cornerRadius(10)
                    }
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18, highlight: PioneerColors.amberOrange.opacity(0.3))
                .padding(.horizontal, 20)

                Spacer().frame(height: 30)
            }
        }
        .sheet(isPresented: $showMultiPicker) {
            DocumentPickerView(allowsMultipleSelection: true, onPick: { urls in
                libraryManager.addSongs(from: urls)
                showMultiPicker = false
            }, onCancel: {
                showMultiPicker = false
            })
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLyricsSheet) {
            LRCLyricsSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}
