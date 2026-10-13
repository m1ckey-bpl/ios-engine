import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer
import SwiftUI

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
            req.setValue("PioneerDSP/4.1 (iOS)", forHTTPHeaderField: "User-Agent")
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
            req.setValue("PioneerDSP/4.1 (iOS)", forHTTPHeaderField: "User-Agent")
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

// MARK: - YouTube Music Service (YouTube Data API v3 & Fallback Gateways)
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
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

@MainActor
public final class YouTubeMusicService: ObservableObject {
    public static let shared = YouTubeMusicService()
    
    @Published public var searchResults: [YouTubeTrackResult] = []
    @Published public var isSearching: Bool = false
    @Published public var customApiKey: String = UserDefaults.standard.string(forKey: "pioneer_yt_api_key") ?? ""
    
    public func setApiKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        self.customApiKey = trimmed
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: "pioneer_yt_api_key")
        } else {
            UserDefaults.standard.set(trimmed, forKey: "pioneer_yt_api_key")
        }
    }
    
    public func search(query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            self.searchResults = []
            return
        }
        
        self.isSearching = true
        defer { self.isSearching = false }
        
        // 1. Try YouTube Data API v3 if custom key set
        if !customApiKey.isEmpty {
            let encQuery = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let urlStr = "https://www.googleapis.com/youtube/v3/search?part=snippet&type=video&videoCategoryId=10&maxResults=20&q=\(encQuery)&key=\(customApiKey)"
            if let url = URL(string: urlStr),
               let (data, resp) = try? await URLSession.shared.data(from: url),
               let http = resp as? HTTPURLResponse, http.statusCode == 200,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["items"] as? [[String: Any]] {
                var list: [YouTubeTrackResult] = []
                for item in items {
                    let idDict = item["id"] as? [String: Any]
                    let vId = (idDict?["videoId"] as? String) ?? (item["id"] as? String) ?? ""
                    let snip = item["snippet"] as? [String: Any] ?? [:]
                    let title = (snip["title"] as? String) ?? "Unknown Track"
                    let channel = (snip["channelTitle"] as? String) ?? "YouTube Music"
                    let thumbs = snip["thumbnails"] as? [String: Any]
                    let high = thumbs?["high"] as? [String: Any]
                    let art = (high?["url"] as? String) ?? ""
                    if !vId.isEmpty {
                        list.append(YouTubeTrackResult(id: vId, videoId: vId, title: title, artist: channel, duration: 210, artworkURL: art))
                    }
                }
                if !list.isEmpty {
                    self.searchResults = list
                    return
                }
            }
        }
        
        // 2. High-Speed Fallback Public Gateways
        let pipedInstances = [
            "https://pipedapi.kavin.rocks",
            "https://api.piped.private.coffee",
            "https://pipedapi.leptons.xyz"
        ]
        let encQ = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        for base in pipedInstances {
            let urlStr = "\(base)/search?q=\(encQ)&filter=music_songs"
            if let url = URL(string: urlStr) {
                var req = URLRequest(url: url)
                req.timeoutInterval = 4.0
                if let (data, resp) = try? await URLSession.shared.data(for: req),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let items = json["items"] as? [[String: Any]] {
                    var list: [YouTubeTrackResult] = []
                    for item in items {
                        let urlStr = (item["url"] as? String) ?? ""
                        let vId = urlStr.replacingOccurrences(of: "/watch?v=", with: "").replacingOccurrences(of: "/", with: "")
                        let title = (item["title"] as? String) ?? "Unknown"
                        let uploader = (item["uploaderName"] as? String) ?? "YouTube Music"
                        let thumb = (item["thumbnail"] as? String) ?? ""
                        let dur = Double((item["duration"] as? Int) ?? 180)
                        if !vId.isEmpty {
                            list.append(YouTubeTrackResult(id: vId, videoId: vId, title: title, artist: uploader, duration: dur, artworkURL: thumb))
                        }
                    }
                    if !list.isEmpty {
                        self.searchResults = list
                        return
                    }
                }
            }
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
            Color(hex: "#0e1017").ignoresSafeArea()
            
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

// MARK: - Pioneer Audio DSP Engine (32-Bit Floating Point Audio Processing)
@MainActor
public final class AudioDSPEngine: ObservableObject {
    public static let shared = AudioDSPEngine()
    
    // Published State
    @Published public var isPlaying: Bool = false
    @Published public var isConcertHallEnabled: Bool = false
    @Published public var currentPreset: DSPPreset = .flat
    @Published public var currentReverbRoom: ReverbRoomType = .concertHall
    @Published public var reverbWetDryMix: Float = 0.0 // 0 to 100%
    @Published public var superBassGain: Float = 0.0 // 0 to 12 dB
    @Published public var listeningPosition: ListeningPosition = .all
    
    // Track & Time Information
    @Published public var trackTitle: String = "Concert Hall Acoustic Master"
    @Published public var trackArtist: String = "Pioneer Philharmonic Studio"
    @Published public var currentTime: TimeInterval = 0.0
    @Published public var totalDuration: TimeInterval = 180.0
    
    // 10-Band EQ
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
    
    // Core Audio Nodes
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var eqNode: AVAudioUnitEQ
    private var reverbNode: AVAudioUnitReverb
    
    // Memory Buffer Cache (Prevents pause/play glitch)
    private var activePCMBuffer: AVAudioPCMBuffer?
    private var isPausedState: Bool = false
    private var playbackTimer: AnyCancellable?
    
    public init() {
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.eqNode = AVAudioUnitEQ(numberOfBands: 10)
        self.reverbNode = AVAudioUnitReverb()
        
        setupAudioSession()
        setupEngineGraph()
        setupEQParameters()
        setupRemoteCommandCenter()
        loadBuiltInDemo(title: "Concert Hall Acoustic Master", artist: "Pioneer Philharmonic Studio", duration: 180)
        startPlaybackClock()
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio Session Setup Error: \(error)")
        }
    }
    
    private func setupEngineGraph() {
        audioEngine.attach(playerNode)
        audioEngine.attach(eqNode)
        audioEngine.attach(reverbNode)
        
        let format = audioEngine.outputNode.outputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: eqNode, format: format)
        audioEngine.connect(eqNode, to: reverbNode, format: format)
        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: format)
        
        reverbNode.loadFactoryPreset(currentReverbRoom.avPreset)
        reverbNode.wetDryMix = 0.0
        
        do {
            try audioEngine.start()
        } catch {
            print("Failed to start AVAudioEngine: \(error)")
        }
    }
    
    private func setupEQParameters() {
        let freqs: [Float] = [31, 63, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
        for (i, f) in freqs.enumerated() {
            let band = eqNode.bands[i]
            band.frequency = f
            band.bandwidth = 1.0
            band.filterType = .parametric
            band.gain = 0.0
            band.bypass = false
        }
    }
    
    // MARK: - Lock Screen & Remote Command Center Integration
    private func setupRemoteCommandCenter() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.play()
            }
            return .success
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.pause()
            }
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            Task { @MainActor in
                self.togglePlayPause()
            }
            return .success
        }
        
        commandCenter.nextTrackCommand.addTarget { _ in
            Task { @MainActor in
                MusicLibraryManager.shared.playNext()
            }
            return .success
        }
        
        commandCenter.previousTrackCommand.addTarget { _ in
            Task { @MainActor in
                MusicLibraryManager.shared.playPrevious()
            }
            return .success
        }
        
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self, let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                self.seek(to: posEvent.positionTime / max(1.0, self.totalDuration))
            }
            return .success
        }
    }
    
    public func updateNowPlayingInfo() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = trackTitle
        info[MPMediaItemPropertyArtist] = trackArtist
        info[MPMediaItemPropertyPlaybackDuration] = totalDuration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        if let image = UIImage(named: "Logo") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    
    // FIXED PAUSE / PLAY LOGIC (Zero Glitch)
    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    public func play() {
        if !audioEngine.isRunning {
            try? audioEngine.start()
        }
        
        if isPausedState {
            playerNode.play()
            isPausedState = false
            isPlaying = true
        } else {
            startFreshBufferPlayback()
        }
        updateNowPlayingInfo()
    }
    
    public func pause() {
        playerNode.pause()
        isPausedState = true
        isPlaying = false
        updateNowPlayingInfo()
    }
    
    private func startFreshBufferPlayback() {
        guard let buffer = activePCMBuffer else { return }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        playerNode.play()
        isPausedState = false
        isPlaying = true
        updateNowPlayingInfo()
    }
    
    // Load Custom Audio File into PCM Buffer
    public func loadAudioFile(url: URL, title: String? = nil, artist: String? = nil, duration: TimeInterval = 180) {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let frameCount = AVAudioFrameCount(file.length)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
            try file.read(into: buffer)
            
            self.activePCMBuffer = buffer
            self.trackTitle = title ?? url.deletingPathExtension().lastPathComponent
            self.trackArtist = artist ?? "Imported Track"
            self.totalDuration = duration > 0 ? duration : Double(file.length) / format.sampleRate
            self.currentTime = 0.0
            self.isPausedState = false
            
            if isPlaying {
                startFreshBufferPlayback()
            }
            updateNowPlayingInfo()
        } catch {
            print("Failed to read audio file into buffer: \(error)")
        }
    }
    
    // Load Built-In Demo Synthesizer
    public func loadBuiltInDemo(title: String, artist: String, duration: TimeInterval) {
        self.trackTitle = title
        self.trackArtist = artist
        self.totalDuration = duration
        self.currentTime = 0.0
        self.isPausedState = false
        
        let sampleRate: Double = 44100.0
        let loopDuration: Double = 3.5
        let frameCount = AVAudioFrameCount(sampleRate * loopDuration)
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        
        buffer.frameLength = frameCount
        let left = buffer.floatChannelData![0]
        let right = buffer.floatChannelData![1]
        
        let chordFreqs = [130.81, 196.00, 246.94, 293.66, 329.63, 392.00]
        for f in 0..<Int(frameCount) {
            let t = Double(f) / sampleRate
            var sl: Float = 0.0
            var sr: Float = 0.0
            for (idx, freq) in chordFreqs.enumerated() {
                let phase = Double(idx) * 0.35
                let valL = sin(2.0 * .pi * freq * t) + 0.3 * sin(4.0 * .pi * freq * t)
                let valR = sin(2.0 * .pi * freq * t + phase) + 0.3 * sin(4.0 * .pi * freq * t + phase)
                sl += Float(valL * 0.12)
                sr += Float(valR * 0.12)
            }
            let pulse = sin(2.0 * .pi * 65.41 * t) * (0.5 + 0.5 * sin(2.0 * .pi * 1.2 * t))
            sl += Float(pulse * 0.22)
            sr += Float(pulse * 0.22)
            left[f] = sl
            right[f] = sr
        }
        
        self.activePCMBuffer = buffer
        if isPlaying {
            startFreshBufferPlayback()
        }
        updateNowPlayingInfo()
    }
    
    // Real-Time Clock
    private func startPlaybackClock() {
        playbackTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isPlaying else { return }
                self.currentTime += 1.0
                if self.currentTime >= self.totalDuration {
                    self.currentTime = 0.0
                }
                self.updateNowPlayingInfo()
            }
    }
    
    public func seek(to progress: Double) {
        self.currentTime = max(0, min(totalDuration, totalDuration * progress))
        updateNowPlayingInfo()
    }
    
    // DSP Controls
    public func toggleConcertHall() {
        isConcertHallEnabled.toggle()
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        if isConcertHallEnabled {
            currentReverbRoom = .concertHall
            reverbNode.loadFactoryPreset(.mediumHall)
            reverbWetDryMix = 65.0
            reverbNode.wetDryMix = 65.0
            
            setEQBandGain(index: 1, gain: 4.5)
            setEQBandGain(index: 8, gain: 3.5)
            setEQBandGain(index: 9, gain: 4.0)
        } else {
            reverbWetDryMix = 0.0
            reverbNode.wetDryMix = 0.0
            applyPreset(currentPreset)
        }
    }
    
    public func setReverbRoom(_ room: ReverbRoomType) {
        currentReverbRoom = room
        reverbNode.loadFactoryPreset(room.avPreset)
        if isConcertHallEnabled {
            reverbNode.wetDryMix = reverbWetDryMix
        }
    }
    
    public func setReverbWetDry(_ val: Float) {
        reverbWetDryMix = val
        if isConcertHallEnabled {
            reverbNode.wetDryMix = val
        }
    }
    
    public func setSuperBass(_ gain: Float) {
        superBassGain = gain
        setEQBandGain(index: 0, gain: gain * 0.7)
        setEQBandGain(index: 1, gain: gain)
    }
    
    public func setEQBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < eqBands.count else { return }
        eqBands[index].gain = gain
        eqNode.bands[index].gain = gain
    }
    
    public func setListeningPosition(_ pos: ListeningPosition) {
        listeningPosition = pos
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
    }
    
    public func applyPreset(_ preset: DSPPreset) {
        currentPreset = preset
        let gains = preset.gains
        for (i, g) in gains.enumerated() {
            setEQBandGain(index: i, gain: g)
        }
        
        if preset == .superBass {
            setSuperBass(9.0)
        } else if preset == .vocalBoost {
            setSuperBass(0.0)
        } else {
            setSuperBass(0.0)
        }
        
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}
