import SwiftUI
import AVFoundation

@main
struct iOS_EngineApp: App {
    init() {
        // Prepare audio session categories on launch for background capability
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            print("Audio session initial error: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
