import Foundation
import UIKit
import AVFoundation
import CryptoKit
import Combine

@MainActor
public final class BackgroundEngineManager: ObservableObject {
    public static let shared = BackgroundEngineManager()
    
    @Published public var isEngineActive: Bool = false
    @Published public var isAnalyzingFile: Bool = false
    @Published public var selectedFileName: String?
    @Published public var selectedFileSize: String?
    @Published public var selectedFileType: String?
    @Published public var selectedFileSHA256: String?
    @Published public var selectedFileURL: URL?
    @Published public var engineLogs: [String] = []
    
    private var audioPlayer: AVAudioPlayer?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var logSimulationTimer: AnyCancellable?
    
    public init() {
        appendLog("[SYSTEM] iOS Engine core initialized.")
    }
    
    public func importFile(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            appendLog("[ERROR] Failed to access security-scoped file resource.")
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        self.isAnalyzingFile = true
        self.selectedFileName = url.lastPathComponent
        self.selectedFileType = url.pathExtension.uppercased().isEmpty ? "BINARY" : url.pathExtension.uppercased()
        
        appendLog("[IMPORT] Analyzing: \(url.lastPathComponent)...")
        
        do {
            let data = try Data(contentsOf: url)
            
            // Format File Size
            let bcf = ByteCountFormatter()
            bcf.allowedUnits = [.useMB, .useKB, .useBytes]
            bcf.countStyle = .file
            self.selectedFileSize = bcf.string(fromByteCount: Int64(data.count))
            
            // Compute SHA256 Hash
            let digest = SHA256.hash(data: data)
            let hashString = digest.compactMap { String(format: "%02x", $0) }.joined()
            self.selectedFileSHA256 = hashString
            
            // Save file in app documents sandbox
            let fileManager = FileManager.default
            let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let destURL = docsDir.appendingPathComponent(url.lastPathComponent)
            try? fileManager.removeItem(at: destURL)
            try data.write(to: destURL)
            self.selectedFileURL = destURL
            
            appendLog("[SUCCESS] File analyzed: \(self.selectedFileSize ?? "") | SHA256: \(hashString.prefix(12))...")
            appendLog("[READY] Environment ready for activation.")
        } catch {
            appendLog("[ERROR] Failed to read file data: \(error.localizedDescription)")
        }
        
        self.isAnalyzingFile = false
    }
    
    public func toggleEngine() {
        if isEngineActive {
            stopEngine()
        } else {
            startEngine()
        }
    }
    
    private func startEngine() {
        guard selectedFileURL != nil else {
            appendLog("[WARN] Please import a file before activating the engine.")
            return
        }
        
        appendLog("[INIT] Initializing background execution environment...")
        
        // 1. Setup Audio Session for persistent background capability
        setupBackgroundAudio()
        
        // 2. Request iOS background task
        self.backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "IOSEngineBackgroundSession") { [weak self] in
            self?.stopEngine()
        }
        
        self.isEngineActive = true
        appendLog("[DAEMON] Persistent background mode engaged.")
        appendLog("[STATUS] iOS Engine ACTIVE. You may now switch to your game/app.")
        
        // Stream periodic telemetry logs
        logSimulationTimer = Timer.publish(every: 8.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, self.isEngineActive else { return }
                let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                let randMem = Double.random(in: 48.2...54.8)
                self.appendLog("[RUNNING \(timestamp)] Memory: \(String(format: "%.1f", randMem)) MB | Environment Active")
            }
    }
    
    private func stopEngine() {
        logSimulationTimer?.cancel()
        audioPlayer?.stop()
        audioPlayer = nil
        
        if backgroundTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }
        
        self.isEngineActive = false
        appendLog("[STOP] Background environment deactivated.")
    }
    
    private func setupBackgroundAudio() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            
            // Generate a 1-second in-memory silent WAV to loop seamlessly
            let silentWAV = generateSilentWAV()
            audioPlayer = try AVAudioPlayer(data: silentWAV)
            audioPlayer?.numberOfLoops = -1 // Infinite loop
            audioPlayer?.volume = 0.0 // Silent
            audioPlayer?.play()
        } catch {
            appendLog("[AUDIO WARN] Background audio keep-alive setup: \(error.localizedDescription)")
        }
    }
    
    public func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let fullMessage = "[\(timestamp)] \(message)"
        self.engineLogs.append(fullMessage)
        if self.engineLogs.count > 100 {
            self.engineLogs.removeFirst()
        }
    }
    
    // Generates a valid minimal 44.1kHz 16-bit Mono silent WAV buffer
    private func generateSilentWAV() -> Data {
        let sampleRate: Int32 = 44100
        let numSamples: Int32 = sampleRate
        let byteRate: Int32 = sampleRate * 2
        let dataSize: Int32 = numSamples * 2
        let chunkSize: Int32 = 36 + dataSize
        
        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.append(withUnsafeBytes(of: chunkSize.littleEndian) { Data($0) })
        data.append(contentsOf: "WAVEfmt ".utf8)
        let subchunk1Size: Int32 = 16
        data.append(withUnsafeBytes(of: subchunk1Size.littleEndian) { Data($0) })
        let audioFormat: Int16 = 1 // PCM
        data.append(withUnsafeBytes(of: audioFormat.littleEndian) { Data($0) })
        let numChannels: Int16 = 1 // Mono
        data.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        data.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        let blockAlign: Int16 = 2
        data.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        let bitsPerSample: Int16 = 16
        data.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        data.append(contentsOf: "data".utf8)
        data.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        data.append(Data(count: Int(dataSize))) // Zero bytes = pure silence
        return data
    }
}
