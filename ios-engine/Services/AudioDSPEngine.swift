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
    @Published public var trackTitle: String = "Pioneer Hi-Fi Master Loop"
    @Published public var trackArtist: String = "Pioneer Sound Tune Studio"
    @Published public var hasCustomFileLoaded: Bool = false
    @Published public var spectrumLevels: [CGFloat] = Array(repeating: 0.15, count: 16)
    
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
    private var currentAudioFile: AVAudioFile?
    private var synthBuffer: AVAudioPCMBuffer?
    private var spectrumTimer: AnyCancellable?
    
    public init() {
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()
        self.eqNode = AVAudioUnitEQ(numberOfBands: 10)
        self.reverbNode = AVAudioUnitReverb()
        
        setupAudioSession()
        setupEngineGraph()
        setupEQParameters()
        setupSynthDemoBuffer()
        startSpectrumAnimation()
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
        
        // Signal Chain: Player -> EQ -> Reverb -> MainMixer -> Output
        let format = audioEngine.outputNode.outputFormat(forBus: 0)
        audioEngine.connect(playerNode, to: eqNode, format: format)
        audioEngine.connect(eqNode, to: reverbNode, format: format)
        audioEngine.connect(reverbNode, to: audioEngine.mainMixerNode, format: format)
        
        // Reverb Initial Configuration
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
    
    // Real-Time Concert Hall Toggle
    public func toggleConcertHall() {
        isConcertHallEnabled.toggle()
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        if isConcertHallEnabled {
            currentReverbRoom = .concertHall
            reverbNode.loadFactoryPreset(.mediumHall)
            reverbWetDryMix = 65.0
            reverbNode.wetDryMix = 65.0
            
            // Expand soundstage via gentle treble and sub-bass lift
            setEQBandGain(index: 1, gain: 4.0) // 63Hz
            setEQBandGain(index: 8, gain: 3.5) // 8kHz
            setEQBandGain(index: 9, gain: 4.0) // 16kHz
        } else {
            reverbWetDryMix = 0.0
            reverbNode.wetDryMix = 0.0
            applyPreset(currentPreset)
        }
    }
    
    // Real-Time Reverb Setting
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
    
    // Real-Time Super Bass (Pioneer Todoroki Bass Boost)
    public func setSuperBass(_ gain: Float) {
        superBassGain = gain
        // Boost 31Hz and 63Hz sub-bass frequencies
        let g31 = gain * 0.8
        let g63 = gain
        setEQBandGain(index: 0, gain: g31)
        setEQBandGain(index: 1, gain: g63)
    }
    
    // Real-Time EQ Band Update
    public func setEQBandGain(index: Int, gain: Float) {
        guard index >= 0 && index < eqBands.count else { return }
        eqBands[index].gain = gain
        eqNode.bands[index].gain = gain
    }
    
    // Real-Time Preset Application
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
            setEQBandGain(index: 1, gain: 4.0)
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
            // V-Shape curve
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
    
    // Time Alignment (Listening Position)
    public func setPosition(_ position: ListeningPosition) {
        listeningPosition = position
        audioEngine.mainMixerNode.pan = position.balancePan
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
    }
    
    // Playback Controls
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
        
        if let audioFile = currentAudioFile {
            playerNode.stop()
            playerNode.scheduleFile(audioFile, at: nil) { [weak self] in
                Task { @MainActor in
                    if self?.isPlaying == true {
                        self?.play() // Loop file
                    }
                }
            }
            playerNode.play()
        } else if let buffer = synthBuffer {
            playerNode.stop()
            playerNode.scheduleBuffer(buffer, at: nil, options: .loops)
            playerNode.play()
        }
        
        isPlaying = true
    }
    
    public func pause() {
        playerNode.pause()
        isPlaying = false
    }
    
    // Load Custom Audio File from Document Picker
    public func loadAudioFile(url: URL) {
        do {
            let file = try AVAudioFile(forReading: url)
            self.currentAudioFile = file
            self.hasCustomFileLoaded = true
            self.trackTitle = url.deletingPathExtension().lastPathComponent
            self.trackArtist = "Imported Audio Track"
            
            if isPlaying {
                play()
            }
        } catch {
            print("Failed to load audio file: \(error)")
        }
    }
    
    // Synthesizes a warm high-fidelity audio buffer (Rich warm harmonic acoustic chords)
    private func setupSynthDemoBuffer() {
        let sampleRate: Double = 44100.0
        let duration: Double = 3.0 // 3-second seamless loop
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        
        buffer.frameLength = frameCount
        let leftChannel = buffer.floatChannelData![0]
        let rightChannel = buffer.floatChannelData![1]
        
        // Frequencies for a lush major 9th chord (C3, G3, B3, D4, E4)
        let chordFreqs: [Double] = [130.81, 196.00, 246.94, 293.66, 329.63]
        
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            var sampleLeft: Float = 0.0
            var sampleRight: Float = 0.0
            
            for (idx, freq) in chordFreqs.enumerated() {
                let panPhase = Double(idx) * 0.4
                let l = sin(2.0 * .pi * freq * t)
                let r = sin(2.0 * .pi * freq * t + panPhase)
                // Add soft harmonics
                let lHarm = 0.3 * sin(4.0 * .pi * freq * t)
                let rHarm = 0.3 * sin(4.0 * .pi * freq * t + panPhase)
                
                sampleLeft += Float((l + lHarm) * 0.15)
                sampleRight += Float((r + rHarm) * 0.15)
            }
            
            // Gentle rhythmic low-end pulse (60 BPM)
            let bassPulse = sin(2.0 * .pi * 65.41 * t) * (0.5 + 0.5 * sin(2.0 * .pi * 1.0 * t))
            sampleLeft += Float(bassPulse * 0.2)
            sampleRight += Float(bassPulse * 0.2)
            
            leftChannel[frame] = sampleLeft
            rightChannel[frame] = sampleRight
        }
        
        self.synthBuffer = buffer
    }
    
    // Spectrum Animation
    private func startSpectrumAnimation() {
        spectrumTimer = Timer.publish(every: 0.05, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.isPlaying {
                    var newLevels: [CGFloat] = []
                    for i in 0..<16 {
                        let boostFactor = CGFloat(self.eqBands[min(i, 9)].gain / 12.0)
                        let base = CGFloat.random(in: 0.25...0.85)
                        let adjusted = max(0.08, min(1.0, base + boostFactor * 0.3))
                        newLevels.append(adjusted)
                    }
                    self.spectrumLevels = newLevels
                } else {
                    self.spectrumLevels = self.spectrumLevels.map { max(0.08, $0 * 0.85) }
                }
            }
    }
}
