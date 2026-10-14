import Foundation
import AVFoundation

public enum DSPPreset: String, CaseIterable, Identifiable {
    case flat = "FLAT / DIRECT"
    case concertHall = "CONCERT HALL"
    case superBass = "SUPER BASS (TODOROKI)"
    case dynamic = "DYNAMIC LIVE"
    case vocal = "VOCAL CLARITY"
    case club = "CLUB DANCE"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .flat: return "waveform"
        case .concertHall: return "building.columns.fill"
        case .superBass: return "speaker.wave.3.fill"
        case .dynamic: return "bolt.fill"
        case .vocal: return "mic.fill"
        case .club: return "music.note.house.fill"
        }
    }

    public var subtitle: String {
        switch self {
        case .flat: return "Studio reference response with zero coloration."
        case .concertHall: return "3D spatial acoustics with wide reverberation."
        case .superBass: return "Todoroki-style low-end lift for a fuller bass response."
        case .dynamic: return "V-shape curve with elevated presence."
        case .vocal: return "Enhanced mid frequencies for pristine vocals."
        case .club: return "Punchy sub-kick with bright high-end."
        }
    }
}

public enum RepeatMode: String, CaseIterable, Identifiable {
    case off = "OFF"
    case all = "ALL"
    case one = "ONE"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .off, .all: return "repeat"
        case .one: return "repeat.1"
        }
    }

    public var accessibilityDescription: String {
        switch self {
        case .off: return "Repeat off"
        case .all: return "Repeat all"
        case .one: return "Repeat one"
        }
    }
}

public enum ReverbRoomType: String, CaseIterable, Identifiable {
    case concertHall = "Concert Hall"
    case largeHall = "Large Arena"
    case cathedral = "Cathedral"
    case mediumRoom = "Live Studio"
    case plate = "Plate Reverb"

    public var id: String { rawValue }

    public var avPreset: AVAudioUnitReverbPreset {
        switch self {
        case .concertHall: return .mediumHall
        case .largeHall: return .largeHall
        case .cathedral: return .cathedral
        case .mediumRoom: return .mediumRoom
        case .plate: return .plate
        }
    }
}

public enum ListeningPosition: String, CaseIterable, Identifiable {
    case all = "ALL SEATS"
    case frontLeft = "DRIVER (FL)"
    case frontRight = "PASSENGER (FR)"
    case frontCenter = "FRONT CENTER"
    case rearLeft = "REAR LEFT"
    case rearRight = "REAR RIGHT"

    public var id: String { rawValue }

    /// AVAudioPlayerNode pan is stereo left/right balance only; it does not create rear-channel audio.
    public var balancePan: Float {
        switch self {
        case .all, .frontCenter: return 0.0
        case .frontLeft: return -0.45
        case .frontRight: return 0.45
        case .rearLeft: return -0.30
        case .rearRight: return 0.30
        }
    }
}

public struct EQBand: Identifiable, Equatable {
    public let id: Int
    public let frequency: Float
    public let label: String
    public var gain: Float // -12.0 to +12.0 dB

    public init(id: Int, frequency: Float, label: String, gain: Float = 0.0) {
        self.id = id
        self.frequency = frequency
        self.label = label
        self.gain = gain
    }
}
