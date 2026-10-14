import SwiftUI

public struct LibraryView: View {
    @ObservedObject private var libraryManager = MusicLibraryManager.shared
    @ObservedObject private var dspEngine = AudioDSPEngine.shared
    @ObservedObject private var ytService = YouTubeMusicService.shared

    @State private var showMultiPicker = false
    @State private var selectedSegment = 0
    @State private var ytSearchQuery = ""
    @State private var apiKeyDraft = ""

    public init() {
        _apiKeyDraft = State(initialValue: YouTubeMusicService.shared.customApiKey)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Source", selection: $selectedSegment) {
                Text("LOCAL (\(libraryManager.songs.count))").tag(0)
                Text("YOUTUBE SEARCH").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)

            if selectedSegment == 0 {
                localLibrary
            } else {
                youtubeSearch
            }
        }
        .background(Color.clear)
        .sheet(isPresented: $showMultiPicker) {
            DocumentPickerView(
                allowsMultipleSelection: true,
                onPick: { urls in
                    libraryManager.addSongs(from: urls)
                    showMultiPicker = false
                },
                onCancel: { showMultiPicker = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: ytService.customApiKey) { _, value in
            apiKeyDraft = value
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            DSPLogoMark(compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("MUSIC LIBRARY")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundColor(.white)
                Text("LOCAL AUDIO • YOUTUBE METADATA SEARCH")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(PioneerColors.textMuted)
            }
            Spacer(minLength: 3)
            if selectedSegment == 0 {
                Button { showMultiPicker = true } label: {
                    Label("ADD", systemImage: "plus")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(PioneerColors.amberOrange, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial.opacity(0.56))
        .overlay(alignment: .bottom) {
            Rectangle().fill(PioneerColors.titaniumCardBorder.opacity(0.7)).frame(height: 1)
        }
    }

    private var localLibrary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .foregroundColor(PioneerColors.amberOrange)
                Text("Real-time DSP on compatible local audio. Lossless input keeps its source data; lossy detail can’t be restored.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 9)

            List {
                ForEach(Array(libraryManager.songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        libraryManager.selectSong(at: index)
                    } label: {
                        HStack(spacing: 12) {
                            let isCurrent = libraryManager.currentSongIndex == index
                            ZStack {
                                Circle()
                                    .fill(isCurrent ? PioneerColors.amberOrange.opacity(0.20) : Color.white.opacity(0.055))
                                    .frame(width: 38, height: 38)
                                Image(systemName: isCurrent && dspEngine.isPlaying ? "waveform" : "music.note")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(isCurrent ? PioneerColors.amberOrange : PioneerColors.textMuted)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.title)
                                    .font(.system(size: 13, weight: isCurrent ? .bold : .medium))
                                    .foregroundColor(isCurrent ? PioneerColors.amberOrange : .white)
                                    .lineLimit(1)
                                HStack(spacing: 6) {
                                    Text(song.artist)
                                    Text("•")
                                    Text(song.fileSize)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                .font(.system(size: 10))
                                .foregroundColor(PioneerColors.textMuted)
                                .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text(song.formattedDuration)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(PioneerColors.textMuted)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.white.opacity(0.025))
                    .listRowSeparatorTint(Color.white.opacity(0.07))
                }
                .onDelete { indexSet in libraryManager.deleteSong(at: indexSet) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
    }

    private var youtubeSearch: some View {
        VStack(spacing: 12) {
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .foregroundColor(PioneerColors.amberOrange)
                    SecureField("YouTube Data API key", text: $apiKeyDraft)
                        .font(.system(size: 12, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                    Button("SAVE") {
                        ytService.setApiKey(apiKeyDraft)
                    }
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(PioneerColors.amberOrange)
                }
                .padding(10)
                .background(Color.black.opacity(0.19), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text("Key stays in iOS Keychain. Restrict it to YouTube Data API v3 and bundle ID com.pioneerdsp.app.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Label("METADATA ONLY — no in-app playback, audio extraction, downloads, or MP3 conversion.", systemImage: "info.circle.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(PioneerColors.cyberCyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .pioneerCard(cornerRadius: 14, highlight: PioneerColors.amberOrange.opacity(0.28))
            .padding(.horizontal, 14)
            .padding(.top, 10)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(PioneerColors.textMuted)
                TextField("Search YouTube music metadata", text: $ytSearchQuery)
                    .foregroundColor(.white)
                    .font(.system(size: 13))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(performYouTubeSearch)
                if !ytSearchQuery.isEmpty {
                    Button {
                        ytSearchQuery = ""
                        ytService.searchResults = []
                        ytService.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(PioneerColors.textMuted)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: performYouTubeSearch) {
                    Text(ytService.isSearching ? "…" : "SEARCH")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(PioneerColors.amberOrange, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .disabled(ytService.isSearching)
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(.ultraThinMaterial.opacity(0.50), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PioneerColors.titaniumCardBorder.opacity(0.75), lineWidth: 1))
            .padding(.horizontal, 14)

            if ytService.isSearching {
                Spacer()
                ProgressView().tint(PioneerColors.amberOrange)
                Text("Searching YouTube’s official Data API…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                Spacer()
            } else if let error = ytService.errorMessage {
                ScrollView {
                    VStack(spacing: 9) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(PioneerColors.amberOrange)
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(PioneerColors.textMuted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .pioneerCard(cornerRadius: 16)
                    .padding(18)
                }
            } else if ytService.searchResults.isEmpty {
                Spacer()
                VStack(spacing: 9) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.system(size: 30))
                        .foregroundColor(PioneerColors.amberOrange)
                    Text("Search official video metadata")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Results show titles and channels only. For DSP playback, import audio you own or are licensed to use, or paste an authorized direct audio URL in Stream DSP.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 23)
                }
                Spacer()
            } else {
                List {
                    ForEach(ytService.searchResults) { track in
                        HStack(spacing: 11) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.045))
                                    .frame(width: 42, height: 42)
                                Image(systemName: "play.rectangle")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(PioneerColors.amberOrange)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(track.title)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(2)
                                Text(track.artist)
                                    .font(.system(size: 10))
                                    .foregroundColor(PioneerColors.textMuted)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            Text("INFO")
                                .font(.system(size: 8, weight: .black, design: .monospaced))
                                .foregroundColor(PioneerColors.cyberCyan)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Color.white.opacity(0.025))
                        .listRowSeparatorTint(Color.white.opacity(0.07))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color.clear)
            }
        }
    }

    private func performYouTubeSearch() {
        let query = ytSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task { await ytService.search(query: query) }
    }
}
