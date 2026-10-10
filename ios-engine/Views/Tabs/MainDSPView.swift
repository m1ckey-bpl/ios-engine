import SwiftUI

public struct MainDSPView: View {
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    @State private var showDocPicker: Bool = false
    
    public init() {}
    
    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer().frame(height: 6)
                
                // Top Header Bar
                HStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(PioneerColors.amberOrange, lineWidth: 1.5)
                        )
                        .shadow(color: PioneerColors.amberOrange.opacity(0.4), radius: 8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIONEER DSP")
                            .font(.system(size: 19, weight: .black, design: .rounded))
                            .tracking(1.5)
                            .foregroundColor(.white)
                        
                        Text("SOUND TUNE ACOUSTIC ENGINE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.amberOrange)
                    }
                    
                    Spacer()
                    
                    // Hi-Res Audio Badge
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("HI-RES")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .foregroundColor(PioneerColors.hiFiGold)
                        Text("96kHz/24b")
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
                
                // Giant Real-Time Concert Hall Toggle Button
                Button(action: {
                    dspEngine.toggleConcertHall()
                }) {
                    VStack(spacing: 8) {
                        HStack {
                            ZStack {
                                Circle()
                                    .fill(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange.opacity(0.25) : Color.white.opacity(0.06))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "building.columns.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : Color.white.opacity(0.4))
                            }
                            
                            VStack(alignment: .leading, spacing: 3) {
                                Text("CONCERT HALL ACOUSTICS")
                                    .font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundColor(.white)
                                
                                Text(dspEngine.isConcertHallEnabled ? "3D Spatial Reverb Active (Medium Hall)" : "Tap to Engage Concert Hall Acoustics")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(dspEngine.isConcertHallEnabled ? PioneerColors.cyberCyan : PioneerColors.textMuted)
                            }
                            
                            Spacer()
                            
                            // On / Off LED indicator
                            Text(dspEngine.isConcertHallEnabled ? "ON" : "OFF")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundColor(dspEngine.isConcertHallEnabled ? .black : .white.opacity(0.4))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : Color.white.opacity(0.08))
                                .cornerRadius(12)
                        }
                    }
                    .padding(16)
                    .pioneerCard(cornerRadius: 18, highlight: dspEngine.isConcertHallEnabled ? PioneerColors.amberOrange : PioneerColors.titaniumCardBorder)
                }
                .padding(.horizontal, 20)
                
                // Real-Time Audio Spectrum Screen
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(PioneerColors.cyberCyan)
                        Text("REAL-TIME SPECTRUM ANALYZER")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(PioneerColors.textMuted)
                        Spacer()
                        Text(dspEngine.isPlaying ? "SIGNAL ACTIVE" : "IDLE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(dspEngine.isPlaying ? PioneerColors.amberOrange : Color.white.opacity(0.3))
                    }
                    
                    SpectrumVisualizerView(levels: dspEngine.spectrumLevels)
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18, highlight: PioneerColors.cyberCyan.opacity(0.4))
                .padding(.horizontal, 20)
                
                // Dual Rotary Dials: Super Bass (Todoroki) & Reverb Wet/Dry
                HStack(spacing: 20) {
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
                    Text("PIONEER SOUND TUNE PRESETS")
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
                
                // Now Playing Audio Transport Bar
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.08))
                                .frame(width: 44, height: 44)
                            Image(systemName: dspEngine.hasCustomFileLoaded ? "music.note" : "waveform.path")
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
                        
                        // Play / Pause Button
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
                    }
                    
                    Divider().background(Color.white.opacity(0.1))
                    
                    // Import Audio File Button
                    Button(action: {
                        showDocPicker = true
                    }) {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                                .foregroundColor(PioneerColors.cyberCyan)
                            Text("IMPORT AUDIO FILE (MP3 / WAV / FLAC)")
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
        .sheet(isPresented: $showDocPicker) {
            DocumentPickerView(onPick: { url in
                dspEngine.loadAudioFile(url: url)
                showDocPicker = false
            }, onCancel: {
                showDocPicker = false
            })
            .ignoresSafeArea()
        }
    }
}
