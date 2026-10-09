import Foundation

public enum LicenseStatus: String, Codable {
    case active = "ACTIVE"
    case revoked = "REVOKED"
    case terminated = "TERMINATED"
    case expired = "EXPIRED"
    case deviceMismatch = "DEVICE_MISMATCH"
}

public struct LicenseKeyInfo: Codable, Identifiable {
    public var id: String { key }
    public let key: String
    public let customerName: String
    public var deviceId: String?
    public let expiresAt: TimeInterval
    public var status: LicenseStatus
    public let totalDays: Int
    
    public init(key: String, customerName: String, deviceId: String? = nil, expiresAt: TimeInterval, status: LicenseStatus = .active, totalDays: Int = 30) {
        self.key = key
        self.customerName = customerName
        self.deviceId = deviceId
        self.expiresAt = expiresAt
        self.status = status
        self.totalDays = totalDays
    }
    
    public var isExpired: Bool {
        Date().timeIntervalSince1970 >= expiresAt
    }
    
    public var remainingSeconds: TimeInterval {
        max(0, expiresAt - Date().timeIntervalSince1970)
    }
    
    public var formattedCountdown: (days: Int, hours: Int, minutes: Int, seconds: Int) {
        let total = Int(remainingSeconds)
        let days = total / 86400
        let hours = (total % 86400) / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return (days, hours, minutes, seconds)
    }
}
