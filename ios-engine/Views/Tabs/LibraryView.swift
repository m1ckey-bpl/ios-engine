import SwiftUI
import UIKit

private enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "RECENT"
    case title = "TITLE"
    case artist = "ARTIST"
    var id: String { rawValue }
}

public struct LibraryView: View {
    @ObservedObject private var libraryManager = MusicLibraryManager.shared
    @ObservedObject private var dspEngine = AudioDSPEngine.shared
    @ObservedObject private var ytService = YouTubeMusicService.shared
    @ObservedObject private var downloadManager = AuthorizedAudioDownloadManager.shared

    @State private var showMultiPicker = false
    @State private var selectedSegment = 0
    @State private var ytSearchQuery = ""
    @State private var apiKeyDraft = ""
    @State private var libraryQuery = ""
    @State private var librarySort: LibrarySort = .recent
    @State private var selectedResult: YouTubeTrackResult?
    @State private var downloadURL = ""
    @State private var downloadTitle = ""
    @State private var downloadArtist = ""
    @State private var confirmsDownloadAuthorization = false
    @State private var pendingDeletionIndexes = IndexSet()
    @State private var showDeleteConfirmation = false

    public init() {
        _apiKeyDraft = State(initialValue: YouTubeMusicService.shared.customApiKey)
    }

    private var visibleSongEntries: [(offset: Int, element: SongItem)] {
        let query = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var entries = Array(libraryManager.songs.enumerated()).filter { _, song in
            query.isEmpty || song.title.lowercased().contains(query)
                || song.artist.lowercased().contains(query)
                || (song.album?.lowercased().contains(query) ?? false)
        }
        switch librarySort {
        case .recent:
            entries.sort { $0.element.dateAdded > $1.element.dateAdded }
        case .title:
            entries.sort { $0.element.title.localizedCaseInsensitiveCompare($1.element.title) == .orderedAscending }
        case .artist:
            entries.sort { $0.element.artist.localizedCaseInsensitiveCompare($1.element.artist) == .orderedAscending }
        }
        return entries
    }

    public var body: some View {
        VStack(spacing: 0) {
            header

            Picker("Library section", selection: $selectedSegment) {
                Text("LOCAL (\(libraryManager.songs.count))").tag(0)
                Text("SEARCH").tag(1)
                Text("DOWNLOADS (\(downloadManager.downloads.count))").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)

            Group {
                switch selectedSegment {
                case 0: localLibrary
                case 1: youtubeSearch
                default: downloadsView
                }
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
        .sheet(item: $selectedResult) { result in
            YouTubeSearchDetailView(track: result)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: ytService.customApiKey) { _, value in apiKeyDraft = value }
    }

    private var header: some View {
        HStack(spacing: 11) {
            DSPLogoMark(compact: true)
            VStack(alignment: .leading, spacing: 2) {
                Text("MUSIC LIBRARY")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(0.9)
                    .foregroundColor(.white)
                Text("LOCAL DSP • METADATA SEARCH • AUTHORIZED FILES")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(PioneerColors.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
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
                .accessibilityLabel("Import local audio")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial.opacity(0.42))
        .overlay(alignment: .bottom) {
            Rectangle().fill(PioneerColors.titaniumCardBorder.opacity(0.7)).frame(height: 1)
        }
    }

    private var localLibrary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundColor(PioneerColors.amberOrange)
                Text("Imported compatible files play through the live DSP chain. Lossy detail cannot be restored.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 8)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(PioneerColors.textMuted)
                TextField("Filter title, artist, album", text: $libraryQuery)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Sort", selection: $librarySort) {
                    ForEach(LibrarySort.allCases) { mode in Text(mode.rawValue).tag(mode) }
                }
                .pickerStyle(.menu)
                .tint(PioneerColors.cyberCyan)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial.opacity(0.43), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
            .padding(.horizontal, 13)
            .padding(.bottom, 7)

            if libraryManager.isImporting {
                HStack(spacing: 8) {
                    ProgressView().tint(PioneerColors.cyberCyan)
                    Text("Validating and importing audio…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            if let message = libraryManager.lastImportMessage {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(message.contains("could not") || message.contains("couldn’t") ? .orange : PioneerColors.cyberCyan)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }

            List {
                ForEach(visibleSongEntries, id: \.element.id) { index, song in
                    Button {
                        libraryManager.selectSong(at: index)
                    } label: {
                        HStack(spacing: 11) {
                            songArtwork(song)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(song.title)
                                    .font(.system(size: 12, weight: libraryManager.currentSongIndex == index ? .bold : .medium))
                                    .foregroundColor(libraryManager.currentSongIndex == index ? PioneerColors.amberOrange : .white)
                                    .lineLimit(1)
                                Text(song.album.map { "\(song.artist) • \($0)" } ?? song.artist)
                                    .font(.system(size: 9))
                                    .foregroundColor(PioneerColors.textMuted)
                                    .lineLimit(1)
                                Text("\(song.formattedDuration)  •  \(song.fileSize)")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundColor(PioneerColors.textMuted.opacity(0.9))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 2)
                            if libraryManager.currentSongIndex == index && dspEngine.isPlaying {
                                Image(systemName: "waveform").foregroundColor(PioneerColors.cyberCyan)
                            }
                        }
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.white.opacity(0.025))
                    .listRowSeparatorTint(Color.white.opacity(0.07))
                }
                .onDelete { offsets in
                    pendingDeletionIndexes = IndexSet(offsets.compactMap { visibleSongEntries.indices.contains($0) ? visibleSongEntries[$0].offset : nil })
                    showDeleteConfirmation = !pendingDeletionIndexes.isEmpty
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .confirmationDialog("Delete selected audio?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete from this device", role: .destructive) {
                    libraryManager.deleteSong(at: pendingDeletionIndexes)
                    pendingDeletionIndexes = []
                }
                Button("Cancel", role: .cancel) { pendingDeletionIndexes = [] }
            } message: {
                Text("The selected imported file will be removed from the app’s local library and storage.")
            }
        }
    }

    @ViewBuilder
    private func songArtwork(_ song: SongItem) -> some View {
        if let data = song.artworkData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.055))
                Image(systemName: "music.note")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(PioneerColors.amberOrange)
            }
            .frame(width: 42, height: 42)
        }
    }

    private var youtubeSearch: some View {
        VStack(spacing: 11) {
            VStack(spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill").foregroundColor(PioneerColors.amberOrange)
                    SecureField("YouTube Data API key", text: $apiKeyDraft)
                        .font(.system(size: 12, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundColor(.white)
                    Button("SAVE") { ytService.setApiKey(apiKeyDraft) }
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(PioneerColors.amberOrange)
                }
                .padding(10)
                .background(Color.black.opacity(0.19), in: RoundedRectangle(cornerRadius: 11, style: .continuous))

                Text("The key stays in iOS Keychain. Restrict it to YouTube Data API v3 and bundle ID com.pioneerdsp.app.")
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
            .padding(.top, 7)

            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundColor(PioneerColors.textMuted)
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
                    } label: { Image(systemName: "xmark.circle.fill").foregroundColor(PioneerColors.textMuted) }
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
            .background(.ultraThinMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PioneerColors.titaniumCardBorder.opacity(0.75), lineWidth: 1))
            .padding(.horizontal, 14)

            if ytService.isSearching {
                Spacer()
                ProgressView().tint(PioneerColors.amberOrange)
                Text("Searching official YouTube metadata…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                Spacer()
            } else if let error = ytService.errorMessage {
                ScrollView {
                    VStack(spacing: 9) {
                        Image(systemName: "info.circle.fill").font(.system(size: 24)).foregroundColor(PioneerColors.amberOrange)
                        Text(error).font(.system(size: 12, weight: .medium)).foregroundColor(PioneerColors.textMuted).multilineTextAlignment(.center)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity)
                    .pioneerCard(cornerRadius: 16)
                    .padding(18)
                }
            } else if ytService.searchResults.isEmpty {
                Spacer()
                VStack(spacing: 9) {
                    Image(systemName: "text.magnifyingglass").font(.system(size: 30)).foregroundColor(PioneerColors.amberOrange)
                    Text("Search official video metadata").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundColor(.white.opacity(0.9))
                    Text("Tap a result for its thumbnail, channel, and official source link. DSP playback and downloads are not available from search results.")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(PioneerColors.textMuted).multilineTextAlignment(.center).padding(.horizontal, 23)
                }
                Spacer()
            } else {
                List {
                    ForEach(ytService.searchResults) { track in
                        Button { selectedResult = track } label: {
                            HStack(spacing: 10) {
                                searchArtwork(track.artworkURL, size: 54)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title).font(.system(size: 12, weight: .bold)).foregroundColor(.white).lineLimit(2)
                                    Text(track.artist).font(.system(size: 10)).foregroundColor(PioneerColors.textMuted).lineLimit(1)
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "info.circle").font(.system(size: 13, weight: .semibold)).foregroundColor(PioneerColors.cyberCyan)
                            }
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
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

    private func searchArtwork(_ text: String, size: CGFloat) -> some View {
        AsyncImage(url: URL(string: text)) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.055))
                    Image(systemName: "play.rectangle").foregroundColor(PioneerColors.amberOrange)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var downloadsView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Label("AUTHORIZED DIRECT AUDIO DOWNLOAD", systemImage: "arrow.down.circle.fill")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundColor(PioneerColors.amberOrange)
                    Text("Enter a direct HTTPS audio-file URL only when the source expressly permits downloading. YouTube/Spotify URLs, video pages, HLS, and DRM are rejected. The completed original file is validated and added to the DSP library.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Permission is your confirmation; DSP ENGINE cannot independently verify a source’s license or terms.")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                    TextField("https://example.com/track.mp3", text: $downloadURL)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(.white)
                        .padding(10).background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    HStack(spacing: 8) {
                        TextField("Track title (optional)", text: $downloadTitle)
                            .textInputAutocapitalization(.words).font(.system(size: 11)).foregroundColor(.white)
                        TextField("Artist (optional)", text: $downloadArtist)
                            .textInputAutocapitalization(.words).font(.system(size: 11)).foregroundColor(.white)
                    }
                    Toggle(isOn: $confirmsDownloadAuthorization) {
                        Text("I have permission to download this audio.")
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(.white.opacity(0.9))
                    }
                    .tint(PioneerColors.amberOrange)
                    Button {
                        downloadManager.startAuthorizedDownload(
                            urlText: downloadURL,
                            title: downloadTitle,
                            artist: downloadArtist,
                            authorized: confirmsDownloadAuthorization
                        )
                        confirmsDownloadAuthorization = false
                    } label: {
                        Label("START AUTHORIZED DOWNLOAD", systemImage: "arrow.down.to.line")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(PioneerColors.amberOrange, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(!confirmsDownloadAuthorization || downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(!confirmsDownloadAuthorization || downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.58 : 1)
                    if let error = downloadManager.lastError {
                        Text(error).font(.system(size: 10)).foregroundColor(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("Original format is kept. iOS does not provide a native MP3 encoder; no audio is falsely converted or re-encoded.")
                        .font(.system(size: 9, weight: .medium)).foregroundColor(PioneerColors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .pioneerCard(cornerRadius: 16, highlight: PioneerColors.amberOrange.opacity(0.30))
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if downloadManager.downloads.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle").font(.system(size: 26)).foregroundColor(PioneerColors.textMuted)
                        Text("No downloads yet").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.85))
                    }
                    .padding(18)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(downloadManager.downloads) { item in
                            downloadRow(item)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 22)
                }
            }
        }
        .background(Color.clear)
    }

    private func downloadRow(_ item: AudioDownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: item.state == .completed ? "checkmark.circle.fill" : "waveform")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(item.state == .failed ? .orange : PioneerColors.cyberCyan)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.system(size: 11, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    Text("\(item.artist) • \(downloadHost(item)) • \(item.state.title)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(PioneerColors.textMuted).lineLimit(1)
                }
                Spacer(minLength: 3)
                downloadControls(item)
            }
            if let progress = item.progress {
                ProgressView(value: progress).tint(PioneerColors.amberOrange)
                HStack {
                    Text("\(Int(progress * 100))% • \(formatBytes(item.bytesWritten)) / \(formatBytes(item.expectedBytes ?? 0))")
                    Spacer()
                    if let speed = item.bytesPerSecond, speed > 0 { Text("\(formatBytes(Int64(speed)))/s") }
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(PioneerColors.textMuted)
                if let eta = item.estimatedRemaining {
                    Text("About \(formatDuration(eta)) remaining")
                        .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(PioneerColors.textMuted)
                }
            } else if item.state == .downloading || item.state == .pausing || item.state == .validating {
                if item.state == .validating { ProgressView().tint(PioneerColors.cyberCyan) }
                else { ProgressView().tint(PioneerColors.amberOrange) }
                Text(item.expectedBytes == nil ? "\(formatBytes(item.bytesWritten)) downloaded • total size unknown" : item.state.title)
                    .font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(PioneerColors.textMuted)
            }
            if let error = item.errorMessage {
                Text(error).font(.system(size: 9, weight: .medium)).foregroundColor(item.state == .completed ? PioneerColors.cyberCyan : .orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .pioneerCard(cornerRadius: 14)
    }

    @ViewBuilder
    private func downloadControls(_ item: AudioDownloadRecord) -> some View {
        HStack(spacing: 6) {
            if item.state == .downloading {
                Button { downloadManager.pause(item.id) } label: { Image(systemName: "pause.fill") }
                    .accessibilityLabel("Pause download")
                Button { downloadManager.cancel(item.id) } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel download")
            } else if item.state == .paused {
                Button { downloadManager.resume(item.id) } label: { Image(systemName: "play.fill") }
                    .accessibilityLabel("Resume download")
                Button { downloadManager.cancel(item.id) } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Cancel download")
            } else if item.state == .failed && downloadManager.canResume(item.id) {
                Button { downloadManager.resume(item.id) } label: { Image(systemName: "play.fill") }
                    .accessibilityLabel("Resume interrupted download")
                Button { downloadManager.retry(item.id) } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Restart download")
                Button { downloadManager.removeCompletedOrCancelled(item.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Remove download record")
            } else if item.state == .failed || item.state == .cancelled {
                Button { downloadManager.retry(item.id) } label: { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Retry download")
                Button { downloadManager.removeCompletedOrCancelled(item.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Remove download record")
            } else if item.state == .completed {
                Button { downloadManager.removeCompletedOrCancelled(item.id) } label: { Image(systemName: "trash") }
                    .accessibilityLabel("Remove completed download record")
            }
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(PioneerColors.cyberCyan)
        .buttonStyle(.plain)
    }

    private func downloadHost(_ item: AudioDownloadRecord) -> String {
        URL(string: item.sourceURL)?.host ?? "source"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        let whole = Int(seconds)
        return whole >= 3_600 ? String(format: "%d:%02d:%02d", whole / 3_600, (whole / 60) % 60, whole % 60)
            : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    private func performYouTubeSearch() {
        let query = ytSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        Task { await ytService.search(query: query) }
    }
}

private struct YouTubeSearchDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let track: YouTubeTrackResult

    private var officialURL: URL? {
        var components = URLComponents(string: "https://www.youtube.com/watch")
        components?.queryItems = [URLQueryItem(name: "v", value: track.videoId)]
        return components?.url
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.94).ignoresSafeArea()
            VStack(spacing: 15) {
                HStack {
                    Text("SEARCH RESULT • METADATA ONLY")
                        .font(.system(size: 9, weight: .black, design: .monospaced)).foregroundColor(PioneerColors.cyberCyan)
                    Spacer()
                    Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundColor(.white.opacity(0.65)) }
                }
                HStack(spacing: 13) {
                    AsyncImage(url: URL(string: track.artworkURL)) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { ZStack { Color.white.opacity(0.06); Image(systemName: "play.rectangle").foregroundColor(PioneerColors.amberOrange) } }
                    }
                    .frame(width: 92, height: 70).clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(track.title).font(.system(size: 14, weight: .bold)).foregroundColor(.white).lineLimit(3)
                        Text(track.artist).font(.system(size: 11)).foregroundColor(PioneerColors.textMuted).lineLimit(2)
                    }
                }
                Text("DSP ENGINE does not play, extract, or download audio from this result. Use only authorized audio files or direct URLs for DSP processing.")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(PioneerColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let officialURL {
                    Link(destination: officialURL) {
                        Label("OPEN OFFICIAL SOURCE", systemImage: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.black).frame(maxWidth: .infinity).padding(.vertical, 11)
                            .background(PioneerColors.cyberCyan, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(18)
        }
    }
}
