# Pioneer DSP for iOS 🍏
**Audiophile Audio Effects Engine, 10-Band Graphic Equalizer, Spotify Remote & Native Swift Music Player**

[![Build iOS IPA](https://github.com/m1ckey-bpl/ios-engine/actions/workflows/build-ios.yml/badge.svg)](https://github.com/m1ckey-bpl/ios-engine/actions/workflows/build-ios.yml)
[![Release](https://img.shields.io/github/v/release/m1ckey-bpl/ios-engine?color=orange)](https://github.com/m1ckey-bpl/ios-engine/releases)

---

## 📱 Overview

**Pioneer DSP for iOS** is a pure native iOS audio application engineered in Swift and SwiftUI. It features a hardware-accelerated DSP processing pipeline built on top of Apple's AVFoundation and AudioToolbox frameworks.

### 🤖 Looking for the Android Version?
The Android APK is now maintained in its own dedicated repository:
👉 **[github.com/m1ckey-bpl/pioneer-dsp-android](https://github.com/m1ckey-bpl/pioneer-dsp-android)**

---

## ✨ iOS Features:
* **Native Swift & SwiftUI**: High-performance 60fps UI matching iOS design conventions.
* **10-Band Graphic Equalizer**: AudioUnit EQ faders across ISO frequencies.
* **Todoroki Super Bass**: Dual-stage low-shelf and peaking bass enhancement.
* **Concert Hall 3D Reverb**: Environmental convolution and acoustic simulation.
* **Spotify Remote Integration**: Control playback telemetry and playlists via Spotify Web API.
* **Local Music Playback**: Import lossless FLAC, ALAC, WAV, AAC, and MP3 files via iOS Files app.

---

## 🛠️ Building for iOS

### Requirements:
* macOS Sonoma (or newer)
* Xcode 15+
* iOS Deployment Target: 16.0+

### Build Unsigned IPA:
```bash
xcodebuild -project ios-engine.xcodeproj            -scheme ios-engine            -configuration Release            -destination 'generic/platform=iOS'            -derivedDataPath build            CODE_SIGNING_ALLOWED=NO clean build

mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/ios-engine.app Payload/
zip -r -y Pioneer_DSP_unsigned.ipa Payload
```
