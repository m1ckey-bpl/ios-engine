# iOS Engine ⚡

**iOS Engine** is an advanced mobile utility built with a futuristic **Apple Liquid Glass** gaming UI, device-bound licensing, native file analysis, and persistent background session execution.

---

## 🚀 Key Features

* 🪟 **Liquid Glass Gaming Interface**: Ultra-thin frosted glass cards, dynamic glowing cyber cyan and purple neon highlights, and animated fluid mesh loop.
* 🔐 **Hardware ID (HWID) Licensing**:
  * Automatically binds each license key to the customer's unique device hardware ID (`identifierForVendor`).
  * Prevents key sharing across different devices.
  * Live countdown timer displaying days, hours, minutes, and seconds remaining.
  * Real-time revocation listener: instantly terminates access with a notification if an admin revokes a key.
* 📁 **File Manager Importer**:
  * Native iOS Document Picker integration to import binaries, configs, and environment profiles.
  * Real-time file inspection: File size, type, and SHA-256 cryptographic checksum calculation.
* ⚡ **Persistent Background Environment**:
  * Silent background audio keep-alive and background task runner to keep the engine active when minimized.
  * Live diagnostic telemetry console streaming background events.

---

## 🧪 Built-in Test Keys (Out of the Box)

| Key | Tier | Validity | Features |
|---|---|---|---|
| `VIP-GAMER-2026` | Pro VIP | 30 Days | Full access, auto-HWID lock, countdown |
| `ENGINE-TRIAL-7D` | Trial VIP | 7 Days | Full access, auto-HWID lock, countdown |
| `TEST-REVOKED-KEY` | Revoked | N/A | Demonstrates instant revocation popup |

---

## 🛠️ Compiling & Installing

1. **GitHub Actions**:
   This repository compiles the unsigned `.ipa` automatically on every push via `build-ipa.yml` using a hosted macOS runner.
2. **Download**:
   Go to the **Actions** tab or **Releases** tab and download `iOS_Engine_unsigned.ipa`.
3. **Sign & Sideload**:
   Sign the `.ipa` using your preferred tool:
   - **Sideloadly** (Windows / macOS)
   - **AltStore**
   - **ESign / Scarlet**
   - **TrollStore** (Direct install without revokes)

---

## 🌐 Connecting Custom Firebase Database

In `ios-engine/Services/LicenseService.swift`, set your Firebase Realtime Database URL:
```swift
public var firebaseDbURL: String = "https://your-firebase-project.firebaseio.com"
```
Database JSON structure:
```json
{
  "licenses": {
    "VIP-GAMER-2026": {
      "key": "VIP-GAMER-2026",
      "customerName": "John Doe",
      "deviceId": "DEVICE-UUID-OR-NULL",
      "expiresAt": 1791600000,
      "status": "ACTIVE",
      "totalDays": 30
    }
  }
}
```
