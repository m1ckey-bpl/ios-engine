import SwiftUI

struct OpenAudioSearchView: View {
    @ObservedObject private var catalog = InternetArchiveAudioCatalog.shared
    @State private var query = ""
    @State private var selectedItem: ArchiveAudioItem?

    var body: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                Label("OPEN-LICENSE MUSIC SEARCH", systemImage: "music.note.list")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundColor(PioneerColors.cyberCyan)
                Text("Search selected Internet Archive music collections. Results must carry a recognized CC BY, CC BY-SA, CC0, or Public Domain Mark record; the item is checked again before streaming. The catalog record is not a legal guarantee—review the source and confirm you’re authorized.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .pioneerCard(cornerRadius: 14, highlight: PioneerColors.cyberCyan.opacity(0.26))
            .padding(.horizontal, 13)
            .padding(.top, 7)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(PioneerColors.textMuted)
                TextField("Search title, artist, or genre", text: $query)
                    .foregroundColor(.white)
                    .font(.system(size: 12))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit(performSearch)
                if !query.isEmpty {
                    Button {
                        query = ""
                        Task { await catalog.search(query: " ") }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(PioneerColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear open-audio search")
                }
                Button(action: performSearch) {
                    Text(catalog.isSearching ? "…" : "SEARCH")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(PioneerColors.cyberCyan, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .disabled(catalog.isSearching || query.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(.ultraThinMaterial.opacity(0.45), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(PioneerColors.titaniumCardBorder.opacity(0.75), lineWidth: 1))
            .padding(.horizontal, 13)

            if catalog.isSearching {
                Spacer()
                ProgressView().tint(PioneerColors.cyberCyan)
                Text("Searching permitted open-audio records…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                Spacer()
            } else if let message = catalog.errorMessage {
                ScrollView {
                    VStack(spacing: 9) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(PioneerColors.amberOrange)
                        Text(message)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PioneerColors.textMuted)
                            .multilineTextAlignment(.center)
                        Text("YouTube results remain metadata-only; Spotify is not a playback source.")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(PioneerColors.cyberCyan)
                            .multilineTextAlignment(.center)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .pioneerCard(cornerRadius: 16)
                    .padding(16)
                }
            } else if catalog.searchResults.isEmpty {
                Spacer()
                VStack(spacing: 9) {
                    Image(systemName: "waveform").font(.system(size: 30)).foregroundColor(PioneerColors.cyberCyan)
                    Text("Search permitted audio records")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Choose a result to inspect its license record and public audio files. Playback stays in the existing DSP stream processor; no audio file is downloaded or saved.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                }
                Spacer()
            } else {
                List {
                    ForEach(catalog.searchResults) { item in
                        Button { selectedItem = item } label: {
                            HStack(spacing: 10) {
                                archiveArtwork(item, size: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title)
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .lineLimit(2)
                                    Text(item.creator)
                                        .font(.system(size: 9))
                                        .foregroundColor(PioneerColors.textMuted)
                                        .lineLimit(1)
                                    Text(item.licenseLabel.uppercased())
                                        .font(.system(size: 8, weight: .black, design: .monospaced))
                                        .foregroundColor(PioneerColors.cyberCyan)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(PioneerColors.textMuted)
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
        .sheet(item: $selectedItem) { item in
            ArchiveAudioItemDetailView(item: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func performSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        Task { await catalog.search(query: trimmed) }
    }

    private func archiveArtwork(_ item: ArchiveAudioItem, size: CGFloat) -> some View {
        AsyncImage(url: item.artworkURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.055))
                    Image(systemName: "music.note").foregroundColor(PioneerColors.cyberCyan)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

private struct ArchiveAudioItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var catalog = InternetArchiveAudioCatalog.shared
    @ObservedObject private var stream = DirectStreamDSPPlayer.shared
    let item: ArchiveAudioItem

    @State private var files: [ArchiveAudioFile] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var confirmsAuthorization = false

    var body: some View {
        ZStack {
            PioneerColors.carbonBg.ignoresSafeArea()
            VStack(spacing: 10) {
                HStack(spacing: 11) {
                    archiveArtwork
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(item.creator)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(PioneerColors.textMuted)
                            .lineLimit(1)
                        Text(item.licenseLabel.uppercased())
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(PioneerColors.cyberCyan)
                    }
                    Spacer(minLength: 3)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 21))
                            .foregroundColor(.white.opacity(0.65))
                    }
                    .accessibilityLabel("Close open-audio item")
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                HStack(spacing: 10) {
                    if let detailsURL = item.detailsURL {
                        Link(destination: detailsURL) {
                            Label("ITEM / RIGHTS", systemImage: "arrow.up.right.square")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if let licenseURL = URL(string: item.licenseURL) {
                        Link(destination: licenseURL) {
                            Label("LICENSE", systemImage: "checkmark.seal")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundColor(PioneerColors.cyberCyan)
                .padding(.horizontal, 15)

                Text("The license is Internet Archive metadata, not a rights guarantee. Review the item, honor attribution/share-alike terms, and stream only if you are authorized.")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 15)

                Toggle(isOn: $confirmsAuthorization) {
                    Text("I checked the source and am authorized to stream this audio.")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.9))
                }
                .tint(PioneerColors.amberOrange)
                .padding(.horizontal, 15)

                if isLoading {
                    Spacer()
                    ProgressView().tint(PioneerColors.cyberCyan)
                    Text("Verifying the item record and listing public audio files…")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(PioneerColors.textMuted)
                        .multilineTextAlignment(.center)
                    Spacer()
                } else if let errorMessage {
                    Spacer()
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                        .padding(16)
                    Spacer()
                } else {
                    List {
                        ForEach(files) { file in
                            Button { startStreaming(file) } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: "waveform")
                                        .foregroundColor(PioneerColors.amberOrange)
                                        .frame(width: 27)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(file.displayTitle)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        Text("\(file.format) • \(file.formattedSize) • processed live, not downloaded")
                                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                                            .foregroundColor(PioneerColors.textMuted)
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 2)
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 19))
                                        .foregroundColor(confirmsAuthorization ? PioneerColors.cyberCyan : PioneerColors.textMuted)
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!confirmsAuthorization)
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
        .task { await loadFiles() }
    }

    private var archiveArtwork: some View {
        AsyncImage(url: item.artworkURL) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.055))
                    Image(systemName: "music.note").foregroundColor(PioneerColors.cyberCyan)
                }
            }
        }
        .frame(width: 55, height: 55)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @MainActor
    private func loadFiles() async {
        isLoading = true
        errorMessage = nil
        do {
            files = try await catalog.audioFiles(for: item)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    @MainActor
    private func startStreaming(_ file: ArchiveAudioFile) {
        guard confirmsAuthorization else { return }
        stream.urlText = file.streamURL.absoluteString
        stream.start(authorized: true, title: file.displayTitle, artist: item.creator)
        dismiss()
    }
}
