import Foundation
import AVFoundation
import AudioToolbox
import Combine
import UIKit
import MediaPlayer
import SwiftUI
import Security
import CoreFoundation

// MARK: - LRCLIB Synchronized Lyrics Models & Service
public struct SyncedLyricLine: Identifiable, Equatable {
    public let id = UUID()
    public let time: TimeInterval
    public let text: String

    public init(time: TimeInterval, text: String) {
        self.time = time
        self.text = text
    }
}

public struct LyricsResult: Equatable {
    public let plainLyrics: String?
    public let syncedLyrics: [SyncedLyricLine]
    public let isInstrumental: Bool

    public init(plainLyrics: String?, syncedLyrics: [SyncedLyricLine], isInstrumental: Bool) {
        self.plainLyrics = plainLyrics
        self.syncedLyrics = syncedLyrics
        self.isInstrumental = isInstrumental
    }
}

@MainActor
public final class LRCLibService: ObservableObject {
    public static let shared = LRCLibService()

    @Published public var currentLyrics: LyricsResult?
    @Published public var isLoading: Bool = false

    private var cache: [String: LyricsResult] = [:]

    public func fetchLyrics(title: String, artist: String, duration: TimeInterval = 0) async {
        let cleanTitle = cleanTrackTitle(title)
        let cleanArtist = cleanArtistName(artist)
        let key = "\(cleanTitle.lowercased())|\(cleanArtist.lowercased())"

        if let cached = cache[key] {
            self.currentLyrics = cached
            return
        }

        self.isLoading = true
        defer { self.isLoading = false }

        // 1. Precise lookup via /api/get
        let titleEnc = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let artistEnc = cleanArtist.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        var urlStr = "https://lrclib.net/api/get?track_name=\(titleEnc)&artist_name=\(artistEnc)"
        if duration > 0 {
            urlStr += "&duration=\(Int(duration))"
        }

        if let url = URL(string: urlStr) {
            var req = URLRequest(url: url)
            req.setValue("DSPENGINE/3.0 (iOS)", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let res = parseLRCLibJson(json)
                cache[key] = res
                self.currentLyrics = res
                return
            }
        }

        // 2. Search fallback via /api/search
        let queryEnc = "\(cleanTitle) \(cleanArtist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let searchUrlStr = "https://lrclib.net/api/search?q=\(queryEnc)"
        if let url = URL(string: searchUrlStr) {
            var req = URLRequest(url: url)
            req.setValue("DSPENGINE/3.0 (iOS)", forHTTPHeaderField: "User-Agent")
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let first = list.first {
                let res = parseLRCLibJson(first)
                cache[key] = res
                self.currentLyrics = res
                return
            }
        }

        let empty = LyricsResult(plainLyrics: "No lyrics available for this track.", syncedLyrics: [], isInstrumental: false)
        cache[key] = empty
        self.currentLyrics = empty
    }

    private func parseLRCLibJson(_ dict: [String: Any]) -> LyricsResult {
        let isInst = dict["instrumental"] as? Bool ?? false
        let plain = dict["plainLyrics"] as? String
        let syncedStr = dict["syncedLyrics"] as? String
        let parsed = syncedStr != nil ? parseLrc(syncedStr!) : []
        return LyricsResult(plainLyrics: plain, syncedLyrics: parsed, isInstrumental: isInst)
    }

    private func parseLrc(_ text: String) -> [SyncedLyricLine] {
        var lines: [SyncedLyricLine] = []
        let pattern = "\\[(\\d{2}):(\\d{2}(?:\\.\\d{1,3})?)\\](.*)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let rawLines = text.components(separatedBy: .newlines)
        for line in rawLines {
            let nsLine = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
            for match in matches {
                if match.numberOfRanges >= 4 {
                    let minStr = nsLine.substring(with: match.range(at: 1))
                    let secStr = nsLine.substring(with: match.range(at: 2))
                    let lyric = nsLine.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespaces)
                    if let m = Double(minStr), let s = Double(secStr) {
                        lines.append(SyncedLyricLine(time: m * 60 + s, text: lyric))
                    }
                }
            }
        }
        return lines.sorted { $0.time < $1.time }
    }

    private func cleanTrackTitle(_ t: String) -> String {
        return t.replacingOccurrences(of: "(Official Video)", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "[Official Audio]", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "(Audio)", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
    }

    private func cleanArtistName(_ a: String) -> String {
        return a.replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - YouTube search metadata only — no player, audio extraction, or download
public struct YouTubeTrackResult: Identifiable, Equatable {
    public let id: String
    public let videoId: String
    public let title: String
    public let artist: String
    public let duration: TimeInterval
    public let artworkURL: String

    public init(id: String, videoId: String, title: String, artist: String, duration: TimeInterval, artworkURL: String) {
        self.id = id
        self.videoId = videoId
        self.title = title
        self.artist = artist
        self.duration = duration
        self.artworkURL = artworkURL
    }

    public var formattedDuration: String {
        guard duration > 0 else { return "OPEN" }
        return String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

private enum YouTubeAPIKeyStore {
    private static let service = Bundle.main.bundleIdentifier ?? "com.avx.dsp-engine"
    private static let account = "youtube-data-api-key"

    static func load() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return "" }
        return value
    }

    static func save(_ value: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }
}

@MainActor
public final class YouTubeMusicService: ObservableObject {
    public static let shared = YouTubeMusicService()

    @Published public var searchResults: [YouTubeTrackResult] = []
    @Published public var isSearching: Bool = false
    @Published public private(set) var customApiKey: String = YouTubeAPIKeyStore.load()
    @Published public var errorMessage: String?

    public func setApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        customApiKey = trimmed
        YouTubeAPIKeyStore.save(trimmed)
        errorMessage = nil
        searchResults = []
    }

    public func search(query: String) async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            errorMessage = nil
            return
        }
        guard !customApiKey.isEmpty else {
            searchResults = []
            errorMessage = "Add a YouTube Data API key to search. Restrict it to the YouTube Data API and this iOS app."
            return
        }

        isSearching = true
        errorMessage = nil
        searchResults = []
        defer { isSearching = false }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "videoCategoryId", value: "10"),
            URLQueryItem(name: "maxResults", value: "12"),
            URLQueryItem(name: "q", value: trimmedQuery),
            URLQueryItem(name: "key", value: customApiKey)
        ]
        guard let url = components?.url else {
            errorMessage = "Could not create the YouTube search request."
            return
        }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "YouTube returned an invalid response."
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = http.statusCode == 403
                    ? "YouTube rejected the API key or the project has reached its quota. Check its API restrictions and quota."
                    : "YouTube search failed (HTTP \(http.statusCode)). Try again later."
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let items = json["items"] as? [[String: Any]] else {
                errorMessage = "YouTube returned an unreadable search response."
                return
            }

            searchResults = items.compactMap { item in
                guard let video = item["id"] as? [String: Any],
                      let videoID = video["videoId"] as? String,
                      !videoID.isEmpty else { return nil }
                let snippet = item["snippet"] as? [String: Any] ?? [:]
                let thumbnails = snippet["thumbnails"] as? [String: Any] ?? [:]
                let image = (thumbnails["high"] as? [String: Any])
                    ?? (thumbnails["medium"] as? [String: Any])
                    ?? (thumbnails["default"] as? [String: Any])
                return YouTubeTrackResult(
                    id: videoID,
                    videoId: videoID,
                    title: (snippet["title"] as? String) ?? "YouTube video",
                    artist: (snippet["channelTitle"] as? String) ?? "YouTube",
                    duration: 0, // search.list does not return video duration
                    artworkURL: (image?["url"] as? String) ?? ""
                )
            }
            if searchResults.isEmpty {
                errorMessage = "No YouTube videos found for that search."
            }
        } catch {
            errorMessage = "Could not reach YouTube. Check your connection and try again."
        }
    }
}

// MARK: - Synchronized Lyrics Sheet View
public struct LRCLyricsSheetView: View {
    @ObservedObject var dspEngine = AudioDSPEngine.shared
    @ObservedObject var lyricsService = LRCLibService.shared
    @Environment(\.dismiss) var dismiss

    public init() {}

    public var body: some View {
        ZStack {
            PioneerColors.carbonBg.ignoresSafeArea()

            VStack(spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("SYNCHRONIZED LYRICS")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(PioneerColors.amberOrange)
                        Text(dspEngine.trackTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(Color.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                if lyricsService.isLoading {
                    Spacer()
                    ProgressView()
                        .tint(PioneerColors.amberOrange)
                    Text("Fetching lyrics from LRCLIB...")
                        .font(.system(size: 12))
                        .foregroundColor(PioneerColors.textMuted)
                    Spacer()
                } else if let lyrics = lyricsService.currentLyrics {
                    if lyrics.isInstrumental {
                        Spacer()
                        Image(systemName: "waveform")
                            .font(.system(size: 40))
                            .foregroundColor(PioneerColors.cyberCyan)
                        Text("Instrumental Track")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                        Spacer()
                    } else if !lyrics.syncedLyrics.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                LazyVStack(spacing: 16) {
                                    ForEach(lyrics.syncedLyrics) { line in
                                        let isCurrent = isCurrentLine(line, allLines: lyrics.syncedLyrics, curTime: dspEngine.currentTime)
                                        Text(line.text)
                                            .font(.system(size: isCurrent ? 18 : 15, weight: isCurrent ? .bold : .regular))
                                            .foregroundColor(isCurrent ? PioneerColors.amberOrange : Color.white.opacity(0.4))
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 4)
                                            .background(isCurrent ? PioneerColors.amberOrange.opacity(0.12) : Color.clear)
                                            .cornerRadius(8)
                                            .id(line.id)
                                            .onTapGesture {
                                                dspEngine.seek(to: line.time / max(1.0, dspEngine.totalDuration))
                                            }
                                    }
                                }
                                .padding(.vertical, 30)
                            }
                            .onChange(of: dspEngine.currentTime) { newTime in
                                if let active = lyrics.syncedLyrics.last(where: { $0.time <= newTime + 0.3 }) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        proxy.scrollTo(active.id, anchor: .center)
                                    }
                                }
                            }
                        }
                    } else if let plain = lyrics.plainLyrics {
                        ScrollView(showsIndicators: false) {
                            Text(plain)
                                .font(.system(size: 15))
                                .lineSpacing(8)
                                .foregroundColor(Color.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(24)
                        }
                    }
                } else {
                    Spacer()
                    Text("No lyrics available")
                        .font(.system(size: 14))
                        .foregroundColor(PioneerColors.textMuted)
                    Spacer()
                }
            }
        }
    }

    private func isCurrentLine(_ line: SyncedLyricLine, allLines: [SyncedLyricLine], curTime: TimeInterval) -> Bool {
        guard let idx = allLines.firstIndex(where: { $0.id == line.id }) else { return false }
        if line.time > curTime { return false }
        if idx == allLines.count - 1 { return true }
        return curTime < allLines[idx + 1].time
    }
}

// MARK: - DSP ENGINE local-audio processing pipeline
@MainActor
public final class AudioDSPEngine: ObservableObject {
    public static let shared = AudioDSPEngine()

    @Published public var isPlaying = false
    @Published public var isConcertHallEnabled = false
    @Published public var currentPreset: DSPPreset = .flat
    @Published public var currentReverbRoom: ReverbRoomType = .concertHall
    @Published public var reverbWetDryMix: Float = 0.0
    @Published public var superBassGain: Float = 0.0
    @Published public var trebleGain: Float = 0.0
    @Published public var delayMix: Float = 0.0
    @Published public var compressorAmount: Float = 0.0
    @Published public var masterVolume: Float = 0.82 {
        didSet { audioEngine.mainMixerNode.outputVolume = min(1, max(0, masterVolume)) }
    }
    @Published public var listeningPosition: ListeningPosition = .all
    @Published public var playbackError: String?

    @Published public var trackTitle = "DSP ENGINE Test Signal"
    @Published public var trackArtist = "Built-in audio demo"
    @Published public private(set) var sourceFormatDescription = "44.1 kHz • STEREO DEMO"
    @Published public var currentTime: TimeInterval = 0.0
    @Published public var totalDuration: TimeInterval = 180.0

    @Published public var eqBands: [EQBand] = [
        EQBand(id: 0, frequency: 31, label: "31Hz", gain: 0),
        EQBand(id: 1, frequency: 63, label: "63Hz", gain: 0),
        EQBand(id: 2, frequency: 125, label: "125Hz", gain: 0),
        EQBand(id: 3, frequency: 250, label: "250Hz", gain: 0),
        EQBand(id: 4, frequency: 500, label: "500Hz", gain: 0),
        EQBand(id: 5, frequency: 1000, label: "1kHz", gain: 0),
        EQBand(id: 6, frequency: 2000, label: "2kHz", gain: 0),
        EQBand(id: 7, frequency: 4000, label: "4kHz", gain: 0),
        EQBand(id: 8, frequency: 8000, label: "8kHz", gain: 0),
        EQBand(id: 9, frequency: 16000, label: "16kHz", gain: 0)
    ]

    private let audioEngine: AVAudioEngine
    private let playerNode: AVAudioPlayerNode
    private let eqNode: AVAudioUnitEQ
    private let delayNode: AVAudioUnitDelay
    private let reverbNode: AVAudioUnitReverb
    private let dynamicsNode: AVAudioUnitEffect
    private var activePCMBuffer: AVAudioPCMBuffer?
    private var cachedDemoBuffer: AVAudioPCMBuffer?
    private var activeAudioFile: AVAudioFile?
    private var currentAudioFormat: AVAudioFormat
    private var isPausedState = false
    /// Invalidates callbacks from segments that were stopped, sought, or replaced.
    private var playbackGeneration: UInt64 = 0
    private var playbackTimer: AnyCancellable?
    private var notificationObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeInterruption = false

    private static var demoFormat: AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
    }

    public init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        eqNode = AVAudioUnitEQ(numberOfBands: 11)
        delayNode = AVAudioUnitDelay()
        reverbNode = AVAudioUnitReverb()
        dynamicsNode = Self.makeDynamicsNode()
        currentAudioFormat = Self.demoFormat

        audioEngine.attach(playerNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(delayNode)
        audioEngine.attach(reverbNode)
        audioEngine.attach(dynamicsNode)
        delayNode.delayTime = 0.32
        delayNode.feedback = 18
        delayNode.wetDryMix = 0
        dynamicsNode.bypass = true
        setupAudioSession()
        setupEngineGraph(for: currentAudioFormat)
        setupRemoteCommandCenter()
        observeAudioSessionChanges()
        loadBuiltInDemo(title: "DSP ENGINE Test Signal", artist: "Built-in audio demo", duration: 30)
        startPlaybackClock()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        } catch {
            playbackError = "iOS could not activate the audio session. Check audio output and try again."
        }
    }

    /// Reconnect all DSP nodes to the source's PCM format. Matching the player-node
    /// connection to the actual source avoids AVAudioPlayerNode format-assertion crashes.
    private func setupEngineGraph(for format: AVAudioFormat) {
        playbackGeneration &+= 1
        audioEngine.stop()
        playerNode.stop()
        audioEngine.disconnectNodeOutput(playerNode)
        audioEngine.disconnectNodeOutput(eqNode)
        audioEngine.disconnectNodeOutput(delayNode)
        audioEngine.disconnectNodeOutput(reverbNode)
        audioEngine.disconnectNodeOutput(dynamicsNode)

        audioEngine.connect(playerNode, to: eqNode, format: format)
        playerNode.pan = listeningPosition.balancePan
        audioEngine.connect(eqNode, to: delayNode, format: format)
        audioEngine.connect(delayNode, to: reverbNode, format: format)
        audioEngine.connect(reverbNode, to: dynamicsNode, format: format)
        audioEngine.connect(dynamicsNode, to: audioEngine.mainMixerNode, format: format)
        currentAudioFormat = format
        configureEQParameters(sampleRate: format.sampleRate)
        let trebleBand = eqNode.bands[10]
        trebleBand.filterType = .highShelf
        trebleBand.frequency = min(6_000, Float(max(20, format.sampleRate * 0.45)))
        trebleBand.gain = trebleGain
        trebleBand.bypass = false
        delayNode.wetDryMix = delayMix
        reverbNode.loadFactoryPreset(currentReverbRoom.avPreset)
        reverbNode.wetDryMix = isConcertHallEnabled ? reverbWetDryMix : 0
        configureDynamics()
        audioEngine.mainMixerNode.outputVolume = min(1, max(0, masterVolume))
        audioEngine.prepare()
    }

    private func configureEQParameters(sampleRate: Double) {
        let maximumFrequency = Float(max(20, sampleRate * 0.45))
        for index in eqBands.indices {
            let band = eqNode.bands[index]
            band.frequency = min(eqBands[index].frequency, maximumFrequency)
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.gain = eqBands[index].gain
            band.bypass = false
        }
    }

    private static func makeDynamicsNode() -> AVAudioUnitEffect {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        return AVAudioUnitEffect(audioComponentDescription: description)
    }

    private func setDynamicsParameter(_ parameterID: AudioUnitParameterID, value: AUValue) {
        dynamicsNode.auAudioUnit.parameterTree?
            .parameter(withID: parameterID, scope: kAudioUnitScope_Global, element: 0)?
            .value = value
    }

    private func configureDynamics() {
        let amount = min(1, max(0, compressorAmount))
        dynamicsNode.bypass = amount == 0

        // AUDynamicsProcessor has no fixed compressor-ratio parameter. Its
        // threshold and headroom together control the amount of compression.
        setDynamicsParameter(kDynamicsProcessorParam_Threshold, value: -8.0 - amount * 16.0)
        setDynamicsParameter(kDynamicsProcessorParam_HeadRoom, value: max(0.5, 5.0 - amount * 4.5))
        setDynamicsParameter(kDynamicsProcessorParam_ExpansionRatio, value: 1.0)
        setDynamicsParameter(kDynamicsProcessorParam_AttackTime, value: 0.003)
        setDynamicsParameter(kDynamicsProcessorParam_ReleaseTime, value: 0.12)
        setDynamicsParameter(kDynamicsProcessorParam_OverallGain, value: 0.0)
    }

    private func formatsMatch(_ lhs: AVAudioFormat, _ rhs: AVAudioFormat) -> Bool {
        abs(lhs.sampleRate - rhs.sampleRate) < 0.5
            && lhs.channelCount == rhs.channelCount
            && lhs.commonFormat == rhs.commonFormat
            && lhs.isInterleaved == rhs.isInterleaved
    }

    private func describeSourceFormat(_ format: AVAudioFormat, isDemo: Bool = false) -> String {
        let rate = String(format: "%.1f kHz", format.sampleRate / 1_000)
        let channels = format.channelCount == 1 ? "MONO" : "STEREO"
        return isDemo ? "\(rate) • \(channels) DEMO" : "\(rate) • \(channels)"
    }

    private func observeAudioSessionChanges() {
        let center = NotificationCenter.default
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in self?.handleAudioInterruption(note) }
        }
        let engineChange = center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.repairAudioEngineAfterConfigurationChange() }
        }
        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            Task { @MainActor [weak self] in self?.handleAudioRouteChange(note) }
        }
        notificationObservers = [interruption, engineChange, routeChange]
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        if reason == .oldDeviceUnavailable,
           let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
            let personalOutputs: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
            if previous.outputs.contains(where: { personalOutputs.contains($0.portType) }), isPlaying {
                pause()
                return
            }
        }
        guard isPlaying else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !audioEngine.isRunning { try audioEngine.start() }
        } catch {
            reportPlaybackError("Audio output changed and playback could not resume.")
        }
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying { pause() }
        } else if type == .ended {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) { play() }
            wasPlayingBeforeInterruption = false
        }
    }

    private func repairAudioEngineAfterConfigurationChange() {
        let shouldResume = isPlaying
        if activePCMBuffer != nil && !formatsMatch(currentAudioFormat, Self.demoFormat) {
            setupEngineGraph(for: Self.demoFormat)
        }
        guard shouldResume else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !audioEngine.isRunning { try audioEngine.start() }
        } catch {
            reportPlaybackError("Audio output changed and the DSP engine could not restart.")
            return
        }
        startFreshPlayback(from: currentTime)
    }

    // MARK: Lock Screen / Control Center commands
    private func setupRemoteCommandCenter() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { _ in
            Task { @MainActor in
                guard !DirectStreamDSPPlayer.shared.isActiveOrLoading else { return }
                MusicLibraryManager.shared.playNext()
            }
            return .success
        }
        center.previousTrackCommand.addTarget { _ in
            Task { @MainActor in
                guard !DirectStreamDSPPlayer.shared.isActiveOrLoading else { return }
                MusicLibraryManager.shared.playPrevious()
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let position = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let stream = DirectStreamDSPPlayer.shared
                if stream.isActiveOrLoading {
                    stream.seek(toFraction: position.positionTime / max(1.0, stream.duration))
                } else {
                    self.seek(to: position.positionTime / max(1.0, self.totalDuration))
                }
            }
            return .success
        }
    }

    public func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: trackTitle,
            MPMediaItemPropertyArtist: trackArtist,
            MPMediaItemPropertyPlaybackDuration: totalDuration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if let image = UIImage(named: "Logo") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: Playback
    public func togglePlayPause() {
        if DirectStreamDSPPlayer.shared.isActiveOrLoading {
            DirectStreamDSPPlayer.shared.togglePlayback()
        } else {
            isPlaying ? pause() : play()
        }
    }

    public func play() {
        if DirectStreamDSPPlayer.shared.isActiveOrLoading {
            DirectStreamDSPPlayer.shared.resume()
            return
        }
        guard activeAudioFile != nil || activePCMBuffer != nil else {
            reportPlaybackError("Select a local audio track before pressing Play.")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !audioEngine.isRunning { try audioEngine.start() }
        } catch {
            reportPlaybackError("iOS could not start audio playback. Check the selected output and try again.")
            return
        }

        if isPausedState {
            playerNode.play()
            isPausedState = false
            isPlaying = true
            updateNowPlayingInfo()
        } else {
            startFreshPlayback()
        }
    }

    public func pause() {
        if DirectStreamDSPPlayer.shared.isActiveOrLoading {
            DirectStreamDSPPlayer.shared.pause()
            return
        }
        guard isPlaying || playerNode.isPlaying else { return }
        playerNode.pause()
        isPausedState = true
        isPlaying = false
        updateNowPlayingInfo()
    }

    public func stop() {
        if DirectStreamDSPPlayer.shared.isActiveOrLoading {
            DirectStreamDSPPlayer.shared.stop()
        }
        stopLocalPlayback()
    }

    /// Stops only the AVAudioEngine local source; used when a direct stream takes ownership.
    public func stopLocalPlayback() {
        playbackGeneration &+= 1
        playerNode.stop()
        isPausedState = false
        isPlaying = false
        currentTime = 0
        updateNowPlayingInfo()
    }

    private func startFreshPlayback(from startTime: TimeInterval = 0) {
        guard activeAudioFile != nil || activePCMBuffer != nil else { return }
        playbackGeneration &+= 1
        let generation = playbackGeneration
        do {
            if !audioEngine.isRunning { try audioEngine.start() }
        } catch {
            reportPlaybackError("The DSP audio graph could not be restarted.")
            return
        }

        playerNode.stop()
        if let file = activeAudioFile {
            let startFrame = AVAudioFramePosition(max(0, min(Double(file.length), startTime * file.processingFormat.sampleRate)))
            scheduleFileSegment(file, from: startFrame, shouldPlay: true, generation: generation)
        } else if let buffer = activePCMBuffer {
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            playerNode.play()
            isPausedState = false
            isPlaying = true
            currentTime = startTime
        }
        updateNowPlayingInfo()
    }

    private func scheduleFileSegment(
        _ file: AVAudioFile,
        from startFrame: AVAudioFramePosition,
        shouldPlay: Bool,
        generation: UInt64
    ) {
        let totalFrames = file.length
        let safeStart = max(0, min(startFrame, max(0, totalFrames - 1)))
        let remaining = max(0, totalFrames - safeStart)
        guard remaining > 0 else {
            reportPlaybackError("This audio file has no playable frames.")
            return
        }
        let frameCount = AVAudioFrameCount(min(remaining, Int64(UInt32.max)))
        playerNode.scheduleSegment(file, startingFrame: safeStart, frameCount: frameCount, at: nil) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.playbackGeneration == generation else { return }
                self.handleFilePlaybackFinished()
            }
        }
        if shouldPlay {
            playerNode.play()
            isPlaying = true
            isPausedState = false
        } else {
            isPlaying = false
            isPausedState = true
        }
    }

    private func handleFilePlaybackFinished() {
        guard isPlaying, activeAudioFile != nil else { return }
        isPlaying = false
        isPausedState = false
        currentTime = totalDuration
        updateNowPlayingInfo()

        if !MusicLibraryManager.shared.advanceAfterTrackFinished() {
            finishPlaybackAtTrackEnd()
        }
    }

    private func finishPlaybackAtTrackEnd() {
        playbackGeneration &+= 1
        playerNode.stop()
        isPlaying = false
        isPausedState = false
        currentTime = totalDuration
        updateNowPlayingInfo()
    }

    // MARK: File / demo loading
    @discardableResult
    public func loadAudioFile(
        url: URL,
        title: String? = nil,
        artist: String? = nil,
        duration: TimeInterval = 0,
        autoplay: Bool = false
    ) -> Bool {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            guard format.sampleRate.isFinite, format.sampleRate >= 8_000, format.sampleRate <= 192_000,
                  format.channelCount > 0, format.channelCount <= 2 else {
                reportPlaybackError("This file’s audio format is not supported yet. Use a stereo or mono audio file at 8–192 kHz.")
                return false
            }

            let shouldResume = isPlaying || autoplay
            playbackGeneration &+= 1
            playerNode.stop()
            isPlaying = false
            isPausedState = false
            activePCMBuffer = nil
            if !formatsMatch(currentAudioFormat, format) { setupEngineGraph(for: format) }

            activeAudioFile = file
            sourceFormatDescription = describeSourceFormat(format)
            trackTitle = title ?? url.deletingPathExtension().lastPathComponent
            trackArtist = artist ?? "Imported audio"
            let measuredDuration = Double(file.length) / format.sampleRate
            totalDuration = measuredDuration.isFinite && measuredDuration > 0 ? measuredDuration : max(0, duration)
            currentTime = 0
            playbackError = nil
            updateNowPlayingInfo()
            if shouldResume { startFreshPlayback() }
            return true
        } catch {
            reportPlaybackError("Couldn’t read this audio file. It may be DRM-protected, damaged, or an unsupported format.")
            return false
        }
    }

    @discardableResult
    public func loadBuiltInDemo(
        title: String,
        artist: String,
        duration: TimeInterval,
        autoplay: Bool = false
    ) -> Bool {
        let shouldResume = isPlaying || autoplay
        playbackGeneration &+= 1
        if !formatsMatch(currentAudioFormat, Self.demoFormat) {
            setupEngineGraph(for: Self.demoFormat)
        }
        playerNode.stop()
        isPlaying = false
        isPausedState = false
        playbackError = nil
        activeAudioFile = nil
        if cachedDemoBuffer == nil { cachedDemoBuffer = makeDemoBuffer() }
        guard let demoBuffer = cachedDemoBuffer else {
            reportPlaybackError("The built-in audio test signal could not be created.")
            return false
        }
        activePCMBuffer = demoBuffer
        sourceFormatDescription = describeSourceFormat(Self.demoFormat, isDemo: true)
        trackTitle = title
        trackArtist = artist
        totalDuration = max(1, duration)
        currentTime = 0
        updateNowPlayingInfo()
        if shouldResume { startFreshPlayback() }
        return true
    }

    private func makeDemoBuffer() -> AVAudioPCMBuffer? {
        let format = Self.demoFormat
        let sampleRate = format.sampleRate
        let duration = 2.5
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channels = buffer.floatChannelData else {
            return nil
        }

        buffer.frameLength = frameCount
        let left = channels[0]
        let right = channels[1]
        for frame in 0..<Int(frameCount) {
            let time = Double(frame) / sampleRate
            let bass = sin(2 * .pi * 65.41 * time) * (0.5 + 0.5 * sin(2 * .pi * 1.2 * time))
            let chord = sin(2 * .pi * 130.81 * time) * 0.16
                + sin(2 * .pi * 196.0 * time + 0.35) * 0.12
                + sin(2 * .pi * 261.63 * time + 0.7) * 0.09
            left[frame] = Float(chord + bass * 0.20)
            right[frame] = Float(chord + bass * 0.20)
        }
        return buffer
    }

    // MARK: Playback clock and seek
    private func startPlaybackClock() {
        playbackTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, self.isPlaying else { return }
                if self.activePCMBuffer != nil, self.currentTime + 1.0 >= self.totalDuration {
                    self.currentTime = self.totalDuration
                    if !MusicLibraryManager.shared.advanceAfterTrackFinished() {
                        self.finishPlaybackAtTrackEnd()
                    }
                    return
                }
                self.currentTime = min(self.currentTime + 1.0, self.totalDuration)
                self.updateNowPlayingInfo()
            }
    }

    public func seek(to progress: Double) {
        if DirectStreamDSPPlayer.shared.isActiveOrLoading {
            DirectStreamDSPPlayer.shared.seek(toFraction: progress)
            return
        }
        guard totalDuration.isFinite, totalDuration > 0 else { return }
        let clamped = max(0, min(1, progress))
        let targetTime = totalDuration * clamped
        currentTime = targetTime
        if let file = activeAudioFile {
            let shouldPlay = isPlaying
            let frame = AVAudioFramePosition(targetTime * file.processingFormat.sampleRate)
            playbackGeneration &+= 1
            let generation = playbackGeneration
            playerNode.stop()
            scheduleFileSegment(file, from: frame, shouldPlay: shouldPlay, generation: generation)
        }
        updateNowPlayingInfo()
    }

    public func reportPlaybackError(_ message: String) {
        playbackGeneration &+= 1
        playbackError = message
        playerNode.stop()
        isPlaying = false
        isPausedState = false
        updateNowPlayingInfo()
    }

    public func clearPlaybackError() {
        playbackError = nil
    }

    // MARK: DSP controls
    public func toggleConcertHall() {
        isConcertHallEnabled.toggle()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if isConcertHallEnabled {
            currentPreset = .concertHall
            currentReverbRoom = .concertHall
            reverbNode.loadFactoryPreset(.mediumHall)
            reverbWetDryMix = 65
            reverbNode.wetDryMix = 65
            setEQBandGain(index: 1, gain: 4.5)
            setEQBandGain(index: 8, gain: 3.5)
            setEQBandGain(index: 9, gain: 4.0)
        } else {
            reverbWetDryMix = 0
            reverbNode.wetDryMix = 0
            if currentPreset == .concertHall { currentPreset = .flat }
            applyPreset(currentPreset)
        }
    }

    public func setReverbRoom(_ room: ReverbRoomType) {
        currentReverbRoom = room
        reverbNode.loadFactoryPreset(room.avPreset)
        if isConcertHallEnabled { reverbNode.wetDryMix = reverbWetDryMix }
    }

    public func setReverbWetDry(_ value: Float) {
        let clamped = max(0, min(100, value))
        reverbWetDryMix = clamped
        if isConcertHallEnabled { reverbNode.wetDryMix = clamped }
    }

    public func setSuperBass(_ gain: Float) {
        let clamped = max(0, min(12, gain))
        superBassGain = clamped
        setEQBandGain(index: 0, gain: clamped * 0.7)
        setEQBandGain(index: 1, gain: clamped)
    }

    public func setTreble(_ gain: Float) {
        let clamped = max(-12, min(12, gain))
        trebleGain = clamped
        eqNode.bands[10].filterType = .highShelf
        eqNode.bands[10].frequency = min(6_000, Float(max(20, currentAudioFormat.sampleRate * 0.45)))
        eqNode.bands[10].gain = clamped
        eqNode.bands[10].bypass = false
    }

    public func setDelayMix(_ mix: Float) {
        let clamped = max(0, min(35, mix))
        delayMix = clamped
        delayNode.wetDryMix = clamped
    }

    public func setCompressorAmount(_ amount: Float) {
        compressorAmount = max(0, min(1, amount))
        configureDynamics()
    }

    public func setMasterVolume(_ volume: Float) {
        masterVolume = max(0, min(1, volume))
    }

    public func setEQBandGain(index: Int, gain: Float) {
        guard eqBands.indices.contains(index) else { return }
        let clamped = max(-12, min(12, gain))
        eqBands[index].gain = clamped
        eqNode.bands[index].gain = clamped
    }

    public func setListeningPosition(_ position: ListeningPosition) {
        listeningPosition = position
        playerNode.pan = position.balancePan
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public func setPosition(_ position: ListeningPosition) {
        setListeningPosition(position)
    }

    public func resetEQToZero() {
        for index in eqBands.indices { setEQBandGain(index: index, gain: 0) }
        superBassGain = 0
        applyPreset(.flat)
    }

    public func applyPreset(_ preset: DSPPreset) {
        currentPreset = preset
        switch preset {
        case .flat:
            for index in eqBands.indices { setEQBandGain(index: index, gain: 0) }
            setSuperBass(0)
            setTreble(0)
            setDelayMix(0)
            setCompressorAmount(0)
            if isConcertHallEnabled {
                isConcertHallEnabled = false
                reverbWetDryMix = 0
                reverbNode.wetDryMix = 0
            }
        case .concertHall:
            for index in eqBands.indices { setEQBandGain(index: index, gain: 0) }
            setSuperBass(0)
            if !isConcertHallEnabled { toggleConcertHall() }
        case .superBass:
            let gains: [Float] = [6, 8, 6, 2, 0, 0, 0, 1, 2, 3]
            for (index, gain) in gains.enumerated() { setEQBandGain(index: index, gain: gain) }
            superBassGain = 9
        case .dynamic:
            let gains: [Float] = [5, 4, 2, 0, -1, 1, 3, 5, 6, 5]
            for (index, gain) in gains.enumerated() { setEQBandGain(index: index, gain: gain) }
            superBassGain = 5
        case .vocal:
            let gains: [Float] = [-2, -1, 0, 2, 4, 5, 4, 2, 1, 0]
            for (index, gain) in gains.enumerated() { setEQBandGain(index: index, gain: gain) }
            superBassGain = 0
        case .club:
            let gains: [Float] = [7, 7, 4, 1, -1, 1, 3, 5, 6, 6]
            for (index, gain) in gains.enumerated() { setEQBandGain(index: index, gain: gain) }
            superBassGain = 7
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
