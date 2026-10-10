import Foundation
import AVFoundation
import Combine
import UIKit

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
            // RESUME from exact paused location (DO NOT STOP OR RESCHEDULE)
            playerNode.play()
            isPausedState = false
            isPlaying = true
        } else {
            // Fresh playback start
            startFreshBufferPlayback()
        }
    }
    
    public func pause() {
        playerNode.pause()
        isPausedState = true
        isPlaying = false
    }
    
    private func startFreshBufferPlayback() {
        guard let buffer = activePCMBuffer else { return }
        playerNode.stop()
        playerNode.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        playerNode.play()
        isPausedState = false
        isPlaying = true
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
            }
    }
    
    public func seek(to progress: Double) {
        self.currentTime = max(0, min(totalDuration, totalDuration * progress))
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
        if isConcertHallEnabled || val > 0 {
            reverbNode.wetDryMix = val
        }
    }
    
    public func setSuperBass(_ gain: Float) {
        superBassGain = gain
        setEQBandGain(index: 0, gain: gain * 0.8)
        setEQBandGain(index: 1, gain: gain)
    }
    
    public func setEQBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < eqBands.count else { return }
        eqBands[index].gain = gain
        eqNode.bands[index].gain = gain
    }
    
    public func applyPreset(_ preset: DSPPreset) {
        currentPreset = preset
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        
        switch preset {
        case .flat:
            resetEQToZero()
            isConcertHallEnabled = false
            reverbNode.wetDryMix = 0.0
            reverbWetDryMix = 0.0
            superBassGain = 0.0
            
        case .concertHall:
            resetEQToZero()
            isConcertHallEnabled = true
            currentReverbRoom = .concertHall
            reverbNode.loadFactoryPreset(.mediumHall)
            reverbNode.wetDryMix = 65.0
            reverbWetDryMix = 65.0
            setEQBandGain(index: 1, gain: 4.5)
            setEQBandGain(index: 8, gain: 4.0)
            
        case .superBass:
            resetEQToZero()
            isConcertHallEnabled = false
            reverbNode.wetDryMix = 0.0
            reverbWetDryMix = 0.0
            setSuperBass(9.0)
            
        case .dynamic:
            isConcertHallEnabled = false
            reverbNode.loadFactoryPreset(.largeHall)
            reverbNode.wetDryMix = 25.0
            reverbWetDryMix = 25.0
            setEQBandGain(index: 0, gain: 6.0)
            setEQBandGain(index: 1, gain: 5.0)
            setEQBandGain(index: 2, gain: 2.0)
            setEQBandGain(index: 4, gain: -1.0)
            setEQBandGain(index: 5, gain: -1.5)
            setEQBandGain(index: 7, gain: 3.0)
            setEQBandGain(index: 8, gain: 6.0)
            setEQBandGain(index: 9, gain: 7.0)
            
        case .vocal:
            resetEQToZero()
            isConcertHallEnabled = false
            reverbNode.loadFactoryPreset(.mediumRoom)
            reverbNode.wetDryMix = 15.0
            reverbWetDryMix = 15.0
            setEQBandGain(index: 0, gain: -2.0)
            setEQBandGain(index: 1, gain: -2.0)
            setEQBandGain(index: 4, gain: 3.5)
            setEQBandGain(index: 5, gain: 5.5)
            setEQBandGain(index: 6, gain: 4.0)
            setEQBandGain(index: 7, gain: 2.0)
            
        case .club:
            resetEQToZero()
            isConcertHallEnabled = false
            reverbNode.loadFactoryPreset(.plate)
            reverbNode.wetDryMix = 20.0
            reverbWetDryMix = 20.0
            setEQBandGain(index: 1, gain: 7.0)
            setEQBandGain(index: 2, gain: 4.0)
            setEQBandGain(index: 7, gain: 3.0)
            setEQBandGain(index: 8, gain: 5.0)
        }
    }
    
    public func resetEQToZero() {
        for i in 0..<eqBands.count {
            setEQBandGain(index: i, gain: 0.0)
        }
    }
    
    public func setPosition(_ position: ListeningPosition) {
        listeningPosition = position
        audioEngine.mainMixerNode.pan = position.balancePan
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
}
