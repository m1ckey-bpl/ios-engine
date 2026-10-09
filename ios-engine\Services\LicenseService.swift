import Foundation
import UIKit
import Combine

@MainActor
public final class LicenseService: ObservableObject {
    public static let shared = LicenseService()
    
    @Published public var currentLicense: LicenseKeyInfo?
    @Published public var isAuthenticated: Bool = false
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String?
    @Published public var isRevokedAlertPresented: Bool = false
    @Published public var revocationReason: String = ""
    @Published public var countdownDisplay: String = "00d : 00h : 00m : 00s"
    
    // Optional Firebase Realtime DB URL (leave empty for standalone mock keys)
    public var firebaseDbURL: String = ""
    
    private var countdownTimer: AnyCancellable?
    private var heartbeatTimer: AnyCancellable?
    
    public var deviceHWID: String {
        UIDevice.current.identifierForVendor?.uuidString ?? "SIMULATOR-HWID-001"
    }
    
    // Built-in offline mock keys for out-of-the-box testing
    private var mockDatabase: [String: LicenseKeyInfo] = [
        "VIP-GAMER-2026": LicenseKeyInfo(
            key: "VIP-GAMER-2026",
            customerName: "Mickey Pro Member",
            deviceId: nil,
            expiresAt: Date().addingTimeInterval(30 * 86400).timeIntervalSince1970,
            status: .active,
            totalDays: 30
        ),
        "ENGINE-TRIAL-7D": LicenseKeyInfo(
            key: "ENGINE-TRIAL-7D",
            customerName: "VIP Customer",
            deviceId: nil,
            expiresAt: Date().addingTimeInterval(7 * 86400).timeIntervalSince1970,
            status: .active,
            totalDays: 7
        ),
        "TEST-REVOKED-KEY": LicenseKeyInfo(
            key: "TEST-REVOKED-KEY",
            customerName: "Terminated User",
            deviceId: nil,
            expiresAt: Date().addingTimeInterval(10 * 86400).timeIntervalSince1970,
            status: .revoked,
            totalDays: 10
        )
    ]
    
    public init() {
        restoreSession()
    }
    
    public func activateKey(_ rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !key.isEmpty else {
            self.errorMessage = "Please enter a valid license key."
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        // Simulating network roundtrip for smooth UI
        try? await Task.sleep(nanoseconds: 600_000_000)
        
        // 1. Check if Firebase Database URL is configured
        if !firebaseDbURL.isEmpty, let url = URL(string: "\(firebaseDbURL)/licenses/\(key).json") {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                   let decoded = try? JSONDecoder().decode(LicenseKeyInfo.self, from: data) {
                    processLicense(decoded, key: key)
                    self.isLoading = false
                    return
                }
            } catch {
                print("Firebase check failed, falling back to local database: \(error)")
            }
        }
        
        // 2. Fallback / Mock Database Check
        if var license = mockDatabase[key] {
            // Check device binding
            if let boundDevice = license.deviceId, !boundDevice.isEmpty {
                if boundDevice != self.deviceHWID {
                    self.errorMessage = "Device Mismatch: This key is bound to another iPhone."
                    self.isLoading = false
                    return
                }
            } else {
                // Bind device HWID on first activation!
                license.deviceId = self.deviceHWID
                mockDatabase[key] = license
            }
            
            // Check status
            if license.status == .revoked || license.status == .terminated {
                self.errorMessage = "License Terminated: Key was revoked by administrator."
                self.isLoading = false
                return
            }
            
            if license.isExpired {
                self.errorMessage = "License Expired: The validity period has ended."
                self.isLoading = false
                return
            }
            
            // Successfully verified!
            self.currentLicense = license
            self.isAuthenticated = true
            self.errorMessage = nil
            saveSession(license)
            startTimers()
        } else {
            self.errorMessage = "Invalid Key: License not found in database."
        }
        
        self.isLoading = false
    }
    
    private func processLicense(_ license: LicenseKeyInfo, key: String) {
        var mutableLicense = license
        if let boundDevice = mutableLicense.deviceId, !boundDevice.isEmpty {
            if boundDevice != self.deviceHWID {
                self.errorMessage = "Device Mismatch: Key bound to another device."
                return
            }
        } else {
            mutableLicense.deviceId = self.deviceHWID
        }
        
        if mutableLicense.status == .revoked || mutableLicense.status == .terminated {
            self.errorMessage = "License Terminated: Key was revoked by administrator."
            return
        }
        
        self.currentLicense = mutableLicense
        self.isAuthenticated = true
        saveSession(mutableLicense)
        startTimers()
    }
    
    private func startTimers() {
        countdownTimer?.cancel()
        heartbeatTimer?.cancel()
        
        // 1. Live Countdown Timer every 1 second
        countdownTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self, let license = self.currentLicense else { return }
                let countdown = license.formattedCountdown
                self.countdownDisplay = String(format: "%02dd : %02dh : %02dm : %02ds",
                                               countdown.days, countdown.hours, countdown.minutes, countdown.seconds)
                
                if license.isExpired {
                    self.handleRevocation(reason: "Your license period has expired.")
                }
            }
        
        // 2. Real-time Heartbeat check every 10 seconds for instant revocation
        heartbeatTimer = Timer.publish(every: 10.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { [weak self] in
                    await self?.checkLicenseStatusHeartbeat()
                }
            }
    }
    
    private func checkLicenseStatusHeartbeat() async {
        guard let license = currentLicense else { return }
        
        // If Firebase is configured, poll remote status
        if !firebaseDbURL.isEmpty, let url = URL(string: "\(firebaseDbURL)/licenses/\(license.key).json") {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let remote = try? JSONDecoder().decode(LicenseKeyInfo.self, from: data) {
                if remote.status == .revoked || remote.status == .terminated {
                    self.handleRevocation(reason: "Your access was revoked by the administrator in real time.")
                    return
                }
            }
        }
    }
    
    public func handleRevocation(reason: String) {
        countdownTimer?.cancel()
        heartbeatTimer?.cancel()
        self.isAuthenticated = false
        self.currentLicense = nil
        self.revocationReason = reason
        self.isRevokedAlertPresented = true
        UserDefaults.standard.removeObject(forKey: "saved_license_key")
    }
    
    public func logout() {
        countdownTimer?.cancel()
        heartbeatTimer?.cancel()
        self.isAuthenticated = false
        self.currentLicense = nil
        UserDefaults.standard.removeObject(forKey: "saved_license_key")
    }
    
    private func saveSession(_ license: LicenseKeyInfo) {
        if let encoded = try? JSONEncoder().encode(license) {
            UserDefaults.standard.set(encoded, forKey: "saved_license_info")
            UserDefaults.standard.set(license.key, forKey: "saved_license_key")
        }
    }
    
    private func restoreSession() {
        if let data = UserDefaults.standard.data(forKey: "saved_license_info"),
           let license = try? JSONDecoder().decode(LicenseKeyInfo.self, from: data) {
            if !license.isExpired && license.status == .active {
                self.currentLicense = license
                self.isAuthenticated = true
                startTimers()
            }
        }
    }
}
