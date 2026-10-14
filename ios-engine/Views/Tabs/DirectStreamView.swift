import SwiftUI

public struct DirectStreamView: View {
    @ObservedObject private var stream = DirectStreamDSPPlayer.shared
    @ObservedObject private var dspEngine = AudioDSPEngine.shared
    @State private var confirmsAuthorization = false

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                header

                VStack(alignment: .leading, spacing: 14) {
                    Label("AUTHORIZED DIRECT STREAM", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(0.6)
                        .foregroundColor(PioneerColors.amberOrange)

                    Text("Paste an HTTPS URL to an audio file hosted by a service that permits streaming. DSP is applied to decoded audio in real time; the app does not save a copy.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    TextField("https://example.com/track.mp3", text: $stream.urlText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        .onSubmit { stream.start(authorized: confirmsAuthorization) }
                        .padding(12)
                        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(PioneerColors.titaniumCardBorder.opacity(0.72), lineWidth: 1)
                        }

                    Toggle(isOn: $confirmsAuthorization) {
                        Text("I’m authorized to stream this audio URL.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .tint(PioneerColors.amberOrange)
                    .padding(.vertical, 2)

                    HStack(spacing: 10) {
                        Button {
                            stream.start(authorized: confirmsAuthorization)
                        } label: {
                            HStack(spacing: 8) {
                                if stream.isLoading {
                                    ProgressView().tint(.black).scaleEffect(0.82)
                                } else {
                                    Image(systemName: "waveform.path")
                                }
                                Text(stream.isLoading ? "CONNECTING" : "START DSP STREAM")
                            }
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(PioneerColors.amberOrange, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .disabled(stream.isLoading || !confirmsAuthorization)
                        .opacity(!confirmsAuthorization ? 0.54 : 1)
                        .buttonStyle(.plain)

                        Button {
                            stream.stop()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white.opacity(0.92))
                                .frame(width: 44, height: 42)
                                .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Stop direct stream")
                    }

                    if let error = stream.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color.orange.opacity(0.96))
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 2)
                    }
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18, highlight: PioneerColors.amberOrange.opacity(0.48))
                .padding(.horizontal, 16)

                if stream.isPlaying || stream.isLoading || stream.sourceLabel != nil {
                    playbackCard
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(PioneerColors.cyberCyan)
                    Text("Direct MP3, AAC/M4A, WAV, AIFF, and CAF audio URLs are supported when iOS can decode them. YouTube, Spotify, DRM/FairPlay, HLS playlists, video pages, and audio from other apps aren’t processed here.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(13)
                .pioneerCard(cornerRadius: 14)
                .padding(.horizontal, 16)

                VStack(spacing: 10) {
                    Text("STREAM DSP EFFECTS")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(PioneerColors.textMuted)
                    VStack(spacing: 2) {
                        Text("EQ: \(dspEngine.currentPreset.rawValue) • HALL: \(dspEngine.isConcertHallEnabled ? dspEngine.currentReverbRoom.rawValue.uppercased() : "OFF")")
                        Text("SEAT: \(dspEngine.listeningPosition.rawValue)")
                    }
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(PioneerColors.cyberCyan)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                    HStack(spacing: 12) {
                        PioneerDialKnob(
                            title: "BASS SHELF",
                            value: Binding(
                                get: { stream.bassGainDB },
                                set: { stream.setBassGain($0) }
                            ),
                            range: 0...12,
                            unit: "dB",
                            accentColor: PioneerColors.amberOrange
                        )
                        .frame(maxWidth: .infinity)

                        PioneerDialKnob(
                            title: "ROOM TAIL",
                            value: Binding(
                                get: { stream.roomMix * 100 },
                                set: { stream.setRoomMix($0 / 100) }
                            ),
                            range: 0...45,
                            unit: "%",
                            accentColor: PioneerColors.cyberCyan
                        )
                        .frame(maxWidth: .infinity)
                    }

                    Text("The 10-band EQ and seat balance follow shared DSP controls; Hall room/mix shapes the stream’s multi-tap room tail. Bass shelf is an extra stream control.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
                .pioneerCard(cornerRadius: 18, highlight: PioneerColors.cyberCyan.opacity(0.36))
                .padding(.horizontal, 16)

                Spacer(minLength: 24)
            }
            .padding(.top, 6)
            .padding(.bottom, 22)
        }
        .background(Color.clear)
    }

    private var header: some View {
        HStack(spacing: 12) {
            DSPLogoMark(compact: true)
            VStack(alignment: .leading, spacing: 3) {
                Text("STREAM DSP")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundColor(.white)
                Text("REAL-TIME • USER-SUPPLIED SOURCE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(PioneerColors.textMuted)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private var playbackCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 11) {
                Image(systemName: stream.isPlaying ? "waveform" : "music.note")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(PioneerColors.amberOrange)
                    .frame(width: 42, height: 42)
                    .background(PioneerColors.amberOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(stream.isLoading ? "BUFFERING DIRECT STREAM" : "AUTHORIZED AUDIO STREAM")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                    Text(stream.sourceLabel ?? "Connecting…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    stream.togglePlayback()
                } label: {
                    Image(systemName: stream.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 38, height: 38)
                        .background(PioneerColors.amberOrange, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(stream.sourceLabel == nil)
            }

            if stream.duration > 0 {
                Slider(
                    value: Binding(
                        get: { stream.currentTime / max(1, stream.duration) },
                        set: { stream.seek(toFraction: $0) }
                    ),
                    in: 0...1
                )
                .tint(PioneerColors.amberOrange)
                HStack {
                    Text(timeLabel(stream.currentTime))
                    Spacer()
                    Text(timeLabel(stream.duration))
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(PioneerColors.textMuted)
            } else if stream.isPlaying {
                Label("Streaming audio • no file is being saved", systemImage: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(PioneerColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .pioneerCard(cornerRadius: 16, highlight: PioneerColors.amberOrange.opacity(0.32))
        .padding(.horizontal, 16)
    }

    private func timeLabel(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        return String(format: "%d:%02d", Int(value) / 60, Int(value) % 60)
    }
}
