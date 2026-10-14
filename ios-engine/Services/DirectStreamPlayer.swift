import AVFoundation
import AudioToolbox
import Combine
import CoreFoundation
import Darwin
import Foundation
import MediaToolbox
import MediaPlayer

/// Plays an authorized, direct HTTPS audio resource and applies DSP to the decoded
/// PCM buffers before they reach the audio output. It does not download or save audio.
@MainActor
public final class DirectStreamDSPPlayer: ObservableObject {
    public static let shared = DirectStreamDSPPlayer()

    @Published public var urlText: String = ""
    @Published public private(set) var isLoading = false
    @Published public private(set) var isBuffering = false
    @Published public private(set) var isPlaying = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var sourceLabel: String?
    @Published public private(set) var streamTitle: String?
    @Published public private(set) var streamArtist: String?
    @Published public private(set) var errorMessage: String?
    @Published public var bassGainDB: Float = 0 {
        didSet { tapState?.setControls(bassGainDB: bassGainDB, roomMix: roomMix) }
    }
    @Published public var roomMix: Float = 0 {
        didSet { tapState?.setControls(bassGainDB: bassGainDB, roomMix: roomMix) }
    }

    private var player: AVPlayer?
    private var currentItem: AVPlayerItem?
    private var audioMix: AVMutableAudioMix?
    private var tapOwner: StreamAudioProcessingTap?
    private var tapState: StreamTapState?
    private var periodicObserver: Any?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var generation = 0
    private var settingsSubscriptions = Set<AnyCancellable>()
    private var sessionObservers: [NSObjectProtocol] = []
    private var wasPlayingBeforeInterruption = false
    private var shouldPlayWhenReady = true
    private var masterVolume: Float = 0.82

    public var isActive: Bool { player != nil && currentItem != nil }
    public var isActiveOrLoading: Bool { isActive || isLoading }
    public var isPlaybackRequested: Bool {
        shouldPlayWhenReady && (isPlaying || isBuffering || isLoading)
    }
    public var currentDisplayTitle: String { streamTitle ?? "Authorized direct audio stream" }
    public var currentDisplayArtist: String { streamArtist ?? sourceLabel ?? "Direct authorized stream" }

    private let blockedDomains: Set<String> = [
        "youtube.com", "youtu.be", "youtube-nocookie.com", "googlevideo.com",
        "spotify.com", "spotify.link", "scdn.co", "spotifycdn.com"
    ]
    private let acceptedAudioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf"
    ]

    private init() {
        let dspEngine = AudioDSPEngine.shared
        dspEngine.$eqBands
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$listeningPosition
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$isConcertHallEnabled
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$reverbWetDryMix
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$trebleGain
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$delayMix
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$compressorAmount
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$currentReverbRoom
            .sink { [weak self] _ in self?.synchronizeSharedDSPSettings() }
            .store(in: &settingsSubscriptions)
        dspEngine.$masterVolume
            .sink { [weak self] volume in self?.setMasterVolume(volume) }
            .store(in: &settingsSubscriptions)
        observeAudioSessionChanges()
    }

    private func synchronizeSharedDSPSettings(to state: StreamTapState? = nil) {
        guard let target = state ?? tapState else { return }
        let dspEngine = AudioDSPEngine.shared
        target.setEqualizerGains(dspEngine.eqBands.map(\.gain))
        target.setBalancePan(dspEngine.listeningPosition.balancePan)
        target.setTrebleGain(dspEngine.trebleGain)
        target.setDelayMix(dspEngine.delayMix)
        target.setCompressorAmount(dspEngine.compressorAmount)
        target.setConcertHall(
            enabled: dspEngine.isConcertHallEnabled,
            wetDryMix: dspEngine.reverbWetDryMix,
            room: dspEngine.currentReverbRoom
        )
    }

    public func start(authorized: Bool, title: String? = nil, artist: String? = nil) {
        guard authorized else {
            errorMessage = "Confirm that you’re authorized to stream this source before connecting."
            return
        }

        let text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacingActiveStream = isActiveOrLoading
        generation &+= 1
        let requestGeneration = generation
        tearDownCurrentPlayer()
        isLoading = false
        isBuffering = false
        isPlaying = false
        shouldPlayWhenReady = false
        currentTime = 0
        duration = 0
        sourceLabel = nil
        streamTitle = nil
        streamArtist = nil
        errorMessage = nil
        if replacingActiveStream { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        updateRemoteSkipCommands()

        guard let url = URL(string: text) else {
            errorMessage = "Enter a valid HTTPS link to a direct, authorized audio resource."
            return
        }
        if let reason = validationError(for: url) {
            errorMessage = reason
            return
        }

        sourceLabel = url.host
        streamTitle = cleanedMetadata(title)
        streamArtist = cleanedMetadata(artist)
        AudioDSPEngine.shared.stopLocalPlayback()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        shouldPlayWhenReady = true
        isLoading = true
        updateRemoteSkipCommands()
        Task { await prepareAndPlay(url: url, generation: requestGeneration) }
    }

    public func togglePlayback() {
        isPlaybackRequested ? pause() : resume()
    }

    public func pause() {
        shouldPlayWhenReady = false
        isBuffering = false
        guard let player else { return }
        player.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    public func resume() {
        shouldPlayWhenReady = true
        guard let player else { return }
        do { try AVAudioSession.sharedInstance().setActive(true) }
        catch {
            errorMessage = "iOS could not resume the direct stream after an audio-session change."
            return
        }
        if duration > 0, currentTime >= duration - 0.25 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self, weak player] finished in
                guard finished else { return }
                Task { @MainActor [weak self, weak player] in
                    guard let self, let player, self.shouldPlayWhenReady else { return }
                    player.play()
                    self.isPlaying = player.timeControlStatus == .playing
                    self.isBuffering = !self.isLoading
                        && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                    self.updateNowPlayingInfo()
                }
            }
            return
        }
        player.play()
        isPlaying = player.timeControlStatus == .playing
        isBuffering = !isLoading && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
        updateNowPlayingInfo()
    }

    public func setMasterVolume(_ value: Float) {
        masterVolume = min(1, max(0, value))
        player?.volume = masterVolume
    }

    public func stop() {
        generation &+= 1
        shouldPlayWhenReady = false
        tearDownCurrentPlayer()
        isLoading = false
        isBuffering = false
        isPlaying = false
        currentTime = 0
        duration = 0
        sourceLabel = nil
        streamTitle = nil
        streamArtist = nil
        errorMessage = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        updateRemoteSkipCommands()
    }

    public func seek(toFraction fraction: Double) {
        guard duration > 0, duration.isFinite, let player else { return }
        let clamped = min(1, max(0, fraction))
        let time = CMTime(seconds: duration * clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    public func setBassGain(_ value: Float) {
        bassGainDB = min(12, max(0, value))
    }

    public func setRoomMix(_ value: Float) {
        roomMix = min(0.45, max(0, value))
    }

    private func cleanedMetadata(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(160))
    }

    private func validationError(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let rawHost = components.host?.lowercased(),
              !rawHost.isEmpty else {
            return "Only secure HTTPS direct-stream URLs are accepted."
        }

        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
        if blockedDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
            return "YouTube and Spotify service URLs aren’t accepted here. Use an authorized direct audio URL or import audio you’re licensed to use."
        }

        let pathExtension = url.pathExtension.lowercased()
        if pathExtension == "m3u8" || components.percentEncodedPath.lowercased().contains(".m3u8") {
            return "HLS playlists aren’t enabled in this build. Paste a direct, non-DRM audio-file URL instead."
        }
        if !acceptedAudioExtensions.contains(pathExtension) {
            return "Use a direct HTTPS audio-file URL ending in MP3, AAC/M4A, WAV, AIFF, or CAF—not an extensionless link, playlist, or video page."
        }
        return nil
    }

    private func prepareAndPlay(url: URL, generation requestGeneration: Int) async {
        do {
            let asset = AVURLAsset(url: url)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            guard requestGeneration == generation else { return }
            let hasProtectedContent = try await asset.load(.hasProtectedContent)
            guard requestGeneration == generation else { return }
            if hasProtectedContent {
                throw DirectStreamError.protectedContent
            }
            guard let audioTrack = audioTracks.first else {
                throw DirectStreamError.noAudioTrack
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard requestGeneration == generation else { return }
            guard videoTracks.isEmpty else {
                throw DirectStreamError.audioOnly
            }

            let state = StreamTapState()
            state.setControls(bassGainDB: bassGainDB, roomMix: roomMix)
            synchronizeSharedDSPSettings(to: state)
            let tap = try StreamAudioProcessingTap(state: state)
            let inputParameters = AVMutableAudioMixInputParameters(track: audioTrack)
            inputParameters.audioTapProcessor = tap.tap

            let mix = AVMutableAudioMix()
            mix.inputParameters = [inputParameters]

            let item = AVPlayerItem(asset: asset)
            item.audioMix = mix
            let streamPlayer = AVPlayer(playerItem: item)
            streamPlayer.automaticallyWaitsToMinimizeStalling = true
            streamPlayer.volume = masterVolume

            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                throw DirectStreamError.audioSession(error.localizedDescription)
            }

            guard requestGeneration == generation else { return }
            tapState = state
            tapOwner = tap
            audioMix = mix
            currentItem = item
            player = streamPlayer
            sourceLabel = url.host
            observe(item: item, player: streamPlayer, generation: requestGeneration)
            if shouldPlayWhenReady {
                streamPlayer.play()
                isPlaying = streamPlayer.timeControlStatus == .playing
            } else {
                streamPlayer.pause()
                isPlaying = false
            }
            updateNowPlayingInfo()
        } catch {
            guard requestGeneration == generation else { return }
            isLoading = false
            isBuffering = false
            isPlaying = false
            shouldPlayWhenReady = false
            sourceLabel = nil
            streamTitle = nil
            streamArtist = nil
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            errorMessage = error.localizedDescription
            updateRemoteSkipCommands()
        }
    }

    private func observe(item: AVPlayerItem, player: AVPlayer, generation requestGeneration: Int) {
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] observedItem, _ in
            let status = observedItem.status
            let detail = observedItem.error?.localizedDescription ?? "The source may be unavailable or unsupported."
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestGeneration else { return }
                if status == .failed {
                    self.stop()
                    self.errorMessage = "Stream playback failed. \(detail)"
                } else if status == .readyToPlay {
                    self.isLoading = false
                    if self.shouldPlayWhenReady {
                        player.play()
                        self.isPlaying = player.timeControlStatus == .playing
                    } else {
                        player.pause()
                        self.isPlaying = false
                    }
                    self.isBuffering = self.shouldPlayWhenReady
                        && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                    self.updateNowPlayingInfo()
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] observedPlayer, _ in
            let status = observedPlayer.timeControlStatus
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestGeneration else { return }
                if status == .playing {
                    self.isLoading = false
                    self.isBuffering = false
                    self.isPlaying = true
                } else if status == .waitingToPlayAtSpecifiedRate {
                    self.isPlaying = false
                    self.isBuffering = !self.isLoading
                } else if status == .paused {
                    self.isPlaying = false
                    self.isBuffering = false
                }
                self.updateNowPlayingInfo()
            }
        }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        periodicObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, self.generation == requestGeneration else { return }
                let seconds = time.seconds
                self.currentTime = seconds.isFinite ? max(0, seconds) : 0
                let itemDuration = player.currentItem?.duration.seconds ?? 0
                self.duration = itemDuration.isFinite && itemDuration > 0 ? itemDuration : 0
                if let support = self.tapState?.processingSupportStatus,
                   support.isPrepared, !support.isSupported {
                    self.stop()
                    self.errorMessage = "iOS provided a decoded audio format this DSP processor cannot safely modify. Use a supported PCM source or import the file locally."
                    return
                }
                if player.currentItem?.status == .readyToPlay {
                    self.isLoading = false
                }
                self.isPlaying = player.timeControlStatus == .playing
                self.isBuffering = !self.isLoading
                    && player.timeControlStatus == .waitingToPlayAtSpecifiedRate
                self.updateNowPlayingInfo()
            }
        }
    }

    private func updateNowPlayingInfo() {
        guard isActive else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: currentDisplayTitle,
            MPMediaItemPropertyArtist: currentDisplayArtist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateRemoteSkipCommands() {
        let commands = MPRemoteCommandCenter.shared()
        let canSkipLocalTracks = !isActiveOrLoading
        commands.nextTrackCommand.isEnabled = canSkipLocalTracks
        commands.previousTrackCommand.isEnabled = canSkipLocalTracks
    }

    private func observeAudioSessionChanges() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        let interruption = center.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleAudioInterruption(notification) }
        }
        let routeChange = center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in self?.handleAudioRouteChange(notification) }
        }
        sessionObservers = [interruption, routeChange]
    }

    private func handleAudioInterruption(_ notification: Notification) {
        guard let rawType = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began {
            let intendedToPlay = shouldPlayWhenReady && (isPlaying || isBuffering || isLoading)
            wasPlayingBeforeInterruption = intendedToPlay
            if intendedToPlay { pause() }
        } else if type == .ended {
            let rawOptions = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if wasPlayingBeforeInterruption && options.contains(.shouldResume) { resume() }
            wasPlayingBeforeInterruption = false
        }
    }

    private func handleAudioRouteChange(_ notification: Notification) {
        guard let rawReason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason) else { return }
        guard reason == .oldDeviceUnavailable,
              let previous = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription else { return }
        let personalOutputs: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE]
        if previous.outputs.contains(where: { personalOutputs.contains($0.portType) }), isPlaybackRequested {
            pause()
        }
    }

    private func tearDownCurrentPlayer() {
        if let periodicObserver, let player {
            player.removeTimeObserver(periodicObserver)
        }
        periodicObserver = nil
        itemStatusObservation = nil
        timeControlObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        currentItem = nil
        audioMix = nil
        tapOwner = nil
        tapState = nil
    }
}

private enum DirectStreamError: LocalizedError {
    case noAudioTrack
    case audioOnly
    case protectedContent
    case tapCreationFailed
    case audioSession(String)

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No playable audio track was found at that URL."
        case .audioOnly:
            return "This DSP stream input accepts audio-only resources, not video files or video pages."
        case .protectedContent:
            return "iOS identified this source as protected. DRM/FairPlay audio can’t be processed by DSP ENGINE."
        case .tapCreationFailed:
            return "iOS couldn’t attach its real-time audio DSP processor to this stream. Try a supported direct audio URL."
        case .audioSession(let detail):
            return "iOS couldn’t start the audio session. \(detail)"
        }
    }
}

/// Owns one tap instance. The retained callback context is released by finalize,
/// after AVFoundation has finished using that tap.
private final class StreamAudioProcessingTap {
    let tap: MTAudioProcessingTap
    private let state: StreamTapState

    init(state: StreamTapState) throws {
        self.state = state
        let retainedState = Unmanaged.passRetained(state)
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: retainedState.toOpaque(),
            init: { _, clientInfo, tapStorageOut in
                tapStorageOut.pointee = clientInfo
            },
            finalize: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                Unmanaged<StreamTapState>.fromOpaque(storage).release()
            },
            prepare: { tap, _, processingFormat in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let state = Unmanaged<StreamTapState>.fromOpaque(storage).takeUnretainedValue()
                state.prepare(format: processingFormat.pointee)
            },
            unprepare: { tap in
                let storage = MTAudioProcessingTapGetStorage(tap)
                let state = Unmanaged<StreamTapState>.fromOpaque(storage).takeUnretainedValue()
                state.unprepare()
            },
            process: { tap, numberFrames, _, bufferListInOut, numberFramesOut, flagsOut in
                let status = MTAudioProcessingTapGetSourceAudio(
                    tap,
                    numberFrames,
                    bufferListInOut,
                    flagsOut,
                    nil,
                    numberFramesOut
                )
                guard status == noErr, numberFramesOut.pointee > 0 else { return }
                let storage = MTAudioProcessingTapGetStorage(tap)
                let state = Unmanaged<StreamTapState>.fromOpaque(storage).takeUnretainedValue()
                state.process(bufferList: bufferListInOut, frameCount: Int(numberFramesOut.pointee))
            }
        )

        var outputTap: Unmanaged<MTAudioProcessingTap>?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PreEffects,
            &outputTap
        )
        guard status == noErr, let outputTap else {
            outputTap?.release()
            retainedState.release()
            throw DirectStreamError.tapCreationFailed
        }
        tap = outputTap.takeRetainedValue()
    }
}

/// Compact realtime processor for the stream path: the shared ten-band EQ curve,
/// seat-balance pan, a low-frequency shelf, and a three-tap room tail. It processes
/// Float32 PCM in-place and allocates its buffers during prepare, not per sample.
private final class StreamTapState {
    private struct Controls {
        var bassGainDB: Float = 0
        var roomMix: Float = 0
        var delayMix: Float = 0
        var trebleGainDB: Float = 0
        var compressorAmount: Float = 0
        var equalizerGains = [Float](repeating: 0, count: 10)
        var balancePan: Float = 0
        var hallEnabled = false
        var hallWetDryMix: Float = 0
        var roomType: ReverbRoomType = .concertHall
    }

    private struct BiquadCoefficients {
        var b0: Float = 1
        var b1: Float = 0
        var b2: Float = 0
        var a1: Float = 0
        var a2: Float = 0
    }

    private enum PCMKind {
        case float32
        case signedInt16
        case unsupported
    }

    private static let equalizerFrequencies: [Double] = [31, 63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]
    private let controlsLock = NSLock()
    private let formatLock = NSLock()
    private var controls = Controls()
    private var formatWasPrepared = false
    private var formatIsSupported = false
    /// Written only by the tap's prepare/unprepare callbacks and read by its render callback.
    private var canProcessAudio = false

    private var sampleRate: Double = 48_000
    private var channelCount = 2
    private var pcmKind: PCMKind = .unsupported
    private var isNonInterleaved = false
    private var lowPassAlpha: Float = 0.975
    private var lowPassState: [Float] = [0, 0]
    private var trebleLowPassAlpha: Float = 0.48
    private var trebleLowPassState: [Float] = [0, 0]
    private var delayLines: [[Float]] = []
    private var echoLines: [[Float]] = []
    private var echoCapacity = 1
    private var echoOffset = 1
    private var echoIndex = 0
    private var delayOffset1 = 1
    private var delayOffset2 = 2
    private var delayOffset3 = 3
    private var roomFeedback: Float = 0.12
    private var delayCapacity = 1
    private var delayIndex = 0
    private var filterCoefficients = [BiquadCoefficients](repeating: BiquadCoefficients(), count: 10)
    private var lastConfiguredGains = [Float](repeating: 0, count: 10)
    private var filterZ1: [Float] = []
    private var filterZ2: [Float] = []

    var processingSupportStatus: (isPrepared: Bool, isSupported: Bool) {
        formatLock.lock()
        let status = (formatWasPrepared, formatIsSupported)
        formatLock.unlock()
        return status
    }

    func setControls(bassGainDB: Float, roomMix: Float) {
        controlsLock.lock()
        controls.bassGainDB = min(12, max(0, bassGainDB))
        controls.roomMix = min(0.45, max(0, roomMix))
        controlsLock.unlock()
    }

    func setEqualizerGains(_ gains: [Float]) {
        var normalized = [Float](repeating: 0, count: 10)
        for index in 0..<min(10, gains.count) {
            normalized[index] = min(12, max(-12, gains[index]))
        }
        controlsLock.lock()
        controls.equalizerGains = normalized
        controlsLock.unlock()
    }

    func setBalancePan(_ pan: Float) {
        controlsLock.lock()
        controls.balancePan = min(1, max(-1, pan))
        controlsLock.unlock()
    }

    func setTrebleGain(_ gain: Float) {
        controlsLock.lock()
        controls.trebleGainDB = min(12, max(-12, gain))
        controlsLock.unlock()
    }

    func setDelayMix(_ mix: Float) {
        controlsLock.lock()
        controls.delayMix = min(35, max(0, mix))
        controlsLock.unlock()
    }

    func setCompressorAmount(_ amount: Float) {
        controlsLock.lock()
        controls.compressorAmount = min(1, max(0, amount))
        controlsLock.unlock()
    }

    func setConcertHall(enabled: Bool, wetDryMix: Float, room: ReverbRoomType) {
        controlsLock.lock()
        controls.hallEnabled = enabled
        controls.hallWetDryMix = min(100, max(0, wetDryMix))
        controls.roomType = room
        controlsLock.unlock()
    }

    func prepare(format: AudioStreamBasicDescription) {
        let sampleRateIsSupported = format.mSampleRate.isFinite
            && format.mSampleRate >= 8_000
            && format.mSampleRate <= 192_000
        sampleRate = sampleRateIsSupported ? format.mSampleRate : 48_000
        let rawChannelCount = Int(format.mChannelsPerFrame)
        channelCount = max(1, min(2, rawChannelCount))
        isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        if format.mFormatID == kAudioFormatLinearPCM,
           format.mBitsPerChannel == 32,
           (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0 {
            pcmKind = .float32
        } else if format.mFormatID == kAudioFormatLinearPCM,
                  format.mBitsPerChannel == 16,
                  (format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0 {
            pcmKind = .signedInt16
        } else {
            pcmKind = .unsupported
        }
        let cutoff = min(165.0, sampleRate * 0.42)
        lowPassAlpha = Float(exp(-2.0 * Double.pi * cutoff / sampleRate))
        lowPassState = [Float](repeating: 0, count: channelCount)
        let trebleCutoff = min(5_000.0, sampleRate * 0.45)
        trebleLowPassAlpha = Float(exp(-2.0 * Double.pi * trebleCutoff / sampleRate))
        trebleLowPassState = [Float](repeating: 0, count: channelCount)
        delayCapacity = max(2, Int(sampleRate * 0.15) + 1)
        delayLines = (0..<channelCount).map { _ in [Float](repeating: 0, count: delayCapacity) }
        echoCapacity = max(2, Int(sampleRate * 0.5) + 1)
        echoOffset = min(echoCapacity - 1, max(1, Int(sampleRate * 0.32)))
        echoLines = (0..<channelCount).map { _ in [Float](repeating: 0, count: echoCapacity) }
        delayIndex = 0
        echoIndex = 0
        filterCoefficients = [BiquadCoefficients](repeating: BiquadCoefficients(), count: 10)
        lastConfiguredGains = [Float](repeating: .nan, count: 10)
        filterZ1 = [Float](repeating: 0, count: channelCount * 10)
        filterZ2 = [Float](repeating: 0, count: channelCount * 10)
        canProcessAudio = sampleRateIsSupported
            && pcmKind != .unsupported
            && (1...2).contains(rawChannelCount)
        formatLock.lock()
        formatWasPrepared = true
        formatIsSupported = canProcessAudio
        formatLock.unlock()
    }

    func unprepare() {
        canProcessAudio = false
        delayLines.removeAll(keepingCapacity: true)
        echoLines.removeAll(keepingCapacity: true)
        lowPassState = [Float](repeating: 0, count: max(1, channelCount))
        trebleLowPassState = [Float](repeating: 0, count: max(1, channelCount))
        filterZ1 = [Float](repeating: 0, count: max(1, channelCount) * 10)
        filterZ2 = [Float](repeating: 0, count: max(1, channelCount) * 10)
        delayIndex = 0
        echoIndex = 0
        formatLock.lock()
        formatWasPrepared = false
        formatIsSupported = false
        formatLock.unlock()
    }

    func process(bufferList: UnsafeMutablePointer<AudioBufferList>, frameCount: Int) {
        guard frameCount > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !buffers.isEmpty else { return }
        guard canProcessAudio else {
            silence(buffers)
            return
        }

        let currentControls: Controls
        controlsLock.lock()
        currentControls = controls
        controlsLock.unlock()

        let bassBoost = powf(10, currentControls.bassGainDB / 20) - 1
        let trebleBoost = powf(10, currentControls.trebleGainDB / 20) - 1
        let hallMix = currentControls.hallEnabled ? (currentControls.hallWetDryMix / 100) * 0.45 : 0
        let baseRoomMix = min(0.72, 1 - (1 - currentControls.roomMix) * (1 - hallMix))
        let roomMix = min(0.72, baseRoomMix)
        let echoMix = min(0.35, currentControls.delayMix / 100)
        configureRoomProfile(currentControls.roomType)
        if currentControls.equalizerGains != lastConfiguredGains {
            configureFilterCoefficients(gains: currentControls.equalizerGains)
            lastConfiguredGains = currentControls.equalizerGains
        }

        switch pcmKind {
        case .float32:
            processFloat32(buffers, frameCount: frameCount, bassBoost: bassBoost, trebleBoost: trebleBoost, roomMix: roomMix, echoMix: echoMix, compressorAmount: currentControls.compressorAmount, balancePan: currentControls.balancePan)
        case .signedInt16:
            processInt16(buffers, frameCount: frameCount, bassBoost: bassBoost, trebleBoost: trebleBoost, roomMix: roomMix, echoMix: echoMix, compressorAmount: currentControls.compressorAmount, balancePan: currentControls.balancePan)
        case .unsupported:
            return
        }
    }

    private func silence(_ buffers: UnsafeMutableAudioBufferListPointer) {
        for index in 0..<buffers.count {
            let audioBuffer = buffers[index]
            guard let data = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { continue }
            _ = memset(data, 0, Int(audioBuffer.mDataByteSize))
        }
    }

    private func processFloat32(_ buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int, bassBoost: Float, trebleBoost: Float, roomMix: Float, echoMix: Float, compressorAmount: Float, balancePan: Float) {
        if isNonInterleaved {
            let usableBuffers = min(buffers.count, channelCount)
            for frame in 0..<frameCount {
                for channel in 0..<usableBuffers {
                    let audioBuffer = buffers[channel]
                    guard let rawData = audioBuffer.mData else { continue }
                    let samples = rawData.assumingMemoryBound(to: Float.self)
                    let availableFrames = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                    guard frame < availableFrames else { continue }
                    samples[frame] = processSample(samples[frame], channel: channel, bassBoost: bassBoost, trebleBoost: trebleBoost, roomMix: roomMix, echoMix: echoMix, compressorAmount: compressorAmount, balancePan: balancePan)
                }
                advanceDelayIndex()
            }
        } else {
            let audioBuffer = buffers[0]
            guard let rawData = audioBuffer.mData else { return }
            let samples = rawData.assumingMemoryBound(to: Float.self)
            let channelsInBuffer = max(1, Int(audioBuffer.mNumberChannels))
            let activeChannels = min(channelsInBuffer, channelCount)
            let availableFrames = Int(audioBuffer.mDataByteSize) / (MemoryLayout<Float>.size * channelsInBuffer)
            let usableFrames = min(frameCount, availableFrames)
            for frame in 0..<usableFrames {
                let base = frame * channelsInBuffer
                for channel in 0..<activeChannels {
                    let index = base + channel
                    samples[index] = processSample(samples[index], channel: channel, bassBoost: bassBoost, trebleBoost: trebleBoost, roomMix: roomMix, echoMix: echoMix, compressorAmount: compressorAmount, balancePan: balancePan)
                }
                advanceDelayIndex()
            }
        }
    }

    private func processInt16(_ buffers: UnsafeMutableAudioBufferListPointer, frameCount: Int, bassBoost: Float, trebleBoost: Float, roomMix: Float, echoMix: Float, compressorAmount: Float, balancePan: Float) {
        if isNonInterleaved {
            let usableBuffers = min(buffers.count, channelCount)
            for frame in 0..<frameCount {
                for channel in 0..<usableBuffers {
                    let audioBuffer = buffers[channel]
                    guard let rawData = audioBuffer.mData else { continue }
                    let samples = rawData.assumingMemoryBound(to: Int16.self)
                    let availableFrames = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size
                    guard frame < availableFrames else { continue }
                    let input = Float(samples[frame]) / 32_768
                    samples[frame] = Int16(processSample(input, channel: channel, bassBoost: bassBoost, trebleBoost: trebleBoost, roomMix: roomMix, echoMix: echoMix, compressorAmount: compressorAmount, balancePan: balancePan) * 32_767)
                }
                advanceDelayIndex()
            }
        } else {
            let audioBuffer = buffers[0]
            guard let rawData = audioBuffer.mData else { return }
            let samples = rawData.assumingMemoryBound(to: Int16.self)
            let channelsInBuffer = max(1, Int(audioBuffer.mNumberChannels))
            let activeChannels = min(channelsInBuffer, channelCount)
            let availableFrames = Int(audioBuffer.mDataByteSize) / (MemoryLayout<Int16>.size * channelsInBuffer)
            let usableFrames = min(frameCount, availableFrames)
            for frame in 0..<usableFrames {
                let base = frame * channelsInBuffer
                for channel in 0..<activeChannels {
                    let index = base + channel
                    let input = Float(samples[index]) / 32_768
                    samples[index] = Int16(processSample(input, channel: channel, bassBoost: bassBoost, trebleBoost: trebleBoost, roomMix: roomMix, echoMix: echoMix, compressorAmount: compressorAmount, balancePan: balancePan) * 32_767)
                }
                advanceDelayIndex()
            }
        }
    }

    private func configureRoomProfile(_ room: ReverbRoomType) {
        let profile: (Double, Double, Double, Float)
        switch room {
        case .concertHall:
            profile = (0.031, 0.053, 0.087, 0.12)
        case .largeHall:
            profile = (0.037, 0.073, 0.116, 0.20)
        case .cathedral:
            profile = (0.043, 0.084, 0.135, 0.25)
        case .mediumRoom:
            profile = (0.018, 0.034, 0.058, 0.10)
        case .plate:
            profile = (0.012, 0.026, 0.047, 0.15)
        }
        delayOffset1 = min(delayCapacity - 1, max(1, Int(sampleRate * profile.0)))
        delayOffset2 = min(delayCapacity - 1, max(1, Int(sampleRate * profile.1)))
        delayOffset3 = min(delayCapacity - 1, max(1, Int(sampleRate * profile.2)))
        roomFeedback = profile.3
    }

    private func configureFilterCoefficients(gains: [Float]) {
        let maximumFrequency = sampleRate * 0.45
        for index in 0..<10 {
            let gain = index < gains.count ? gains[index] : 0
            guard abs(gain) >= 0.01 else {
                filterCoefficients[index] = BiquadCoefficients()
                continue
            }

            let frequency = min(Self.equalizerFrequencies[index], maximumFrequency)
            let amplitude = pow(10.0, Double(gain) / 40.0)
            let omega = 2.0 * Double.pi * frequency / sampleRate
            let cosine = cos(omega)
            let alpha = sin(omega) / 2.0 // Q = 1.0, matching the graphic EQ's broad bands.
            let a0 = 1.0 + alpha / amplitude
            filterCoefficients[index] = BiquadCoefficients(
                b0: Float((1.0 + alpha * amplitude) / a0),
                b1: Float((-2.0 * cosine) / a0),
                b2: Float((1.0 - alpha * amplitude) / a0),
                a1: Float((-2.0 * cosine) / a0),
                a2: Float((1.0 - alpha / amplitude) / a0)
            )
        }
    }

    private func processSample(_ input: Float, channel: Int, bassBoost: Float, trebleBoost: Float, roomMix: Float, echoMix: Float, compressorAmount: Float, balancePan: Float) -> Float {
        guard channel < lowPassState.count, channel < delayLines.count else { return input }
        let low = (1 - lowPassAlpha) * input + lowPassAlpha * lowPassState[channel]
        lowPassState[channel] = low
        var output = input + low * bassBoost

        let trebleLow = (1 - trebleLowPassAlpha) * output + trebleLowPassAlpha * trebleLowPassState[channel]
        trebleLowPassState[channel] = trebleLow
        output += (output - trebleLow) * trebleBoost

        for band in 0..<10 {
            let stateIndex = channel * 10 + band
            let coefficients = filterCoefficients[band]
            let filtered = coefficients.b0 * output + filterZ1[stateIndex]
            filterZ1[stateIndex] = coefficients.b1 * output - coefficients.a1 * filtered + filterZ2[stateIndex]
            filterZ2[stateIndex] = coefficients.b2 * output - coefficients.a2 * filtered
            output = filtered
        }

        if channel == 0 && balancePan > 0 {
            output *= 1 - balancePan
        } else if channel == 1 && balancePan < 0 {
            output *= 1 + balancePan
        }

        let d1 = delayLines[channel][(delayIndex + delayCapacity - delayOffset1) % delayCapacity]
        let d2 = delayLines[channel][(delayIndex + delayCapacity - delayOffset2) % delayCapacity]
        let d3 = delayLines[channel][(delayIndex + delayCapacity - delayOffset3) % delayCapacity]
        let earlyRoom = d1 * 0.45 + d2 * 0.34 + d3 * 0.21
        let activeFeedback = roomMix > 0.0001 ? roomFeedback : 0
        delayLines[channel][delayIndex] = output + (d1 + d2 + d3) * activeFeedback
        if roomMix > 0.0001 {
            output = output * (1 - roomMix) + earlyRoom * roomMix
        }

        let echoReadIndex = (echoIndex + echoCapacity - echoOffset) % echoCapacity
        let delayed = echoLines[channel][echoReadIndex]
        echoLines[channel][echoIndex] = output + (echoMix > 0.0001 ? delayed * 0.18 : 0)
        if echoMix > 0.0001 {
            output = output * (1 - echoMix) + delayed * echoMix
        }

        guard output.isFinite else { return 0 }
        let magnitude = abs(output)
        let threshold = 0.94 - 0.22 * compressorAmount
        let ceiling: Float = 0.985
        guard magnitude > threshold else { return output }
        let knee = max(0.001, ceiling - threshold)
        let limitedMagnitude = min(ceiling, threshold + knee * (magnitude - threshold) / (magnitude - threshold + knee))
        return output < 0 ? -limitedMagnitude : limitedMagnitude
    }

    private func advanceDelayIndex() {
        delayIndex += 1
        if delayIndex >= delayCapacity { delayIndex = 0 }
        echoIndex += 1
        if echoIndex >= echoCapacity { echoIndex = 0 }
    }
}
