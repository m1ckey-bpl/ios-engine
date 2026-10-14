# DSP ENGINE for iOS

**made by avx**

DSP ENGINE is a native SwiftUI audio-effects app. Compatible local, non-DRM files are played through an `AVAudioEngine` graph with a 10-band EQ and effects. Imported tracks stay in the app’s sandbox.

## Playback boundaries

- **Local files:** import compatible mono or stereo audio from Files to use the local DSP chain.
- **Authorized direct streams:** paste a direct HTTPS audio-only URL (for example MP3, AAC/M4A, WAV, AIFF, or CAF) from a source that permits streaming. The app applies real-time DSP to decoded audio; it does not save a stream copy. The stream path follows the shared 10-band EQ and cabin balance; Hall room/mix selects the multi-tap room-tail profile. A separate bass shelf is also available for streams.
- **Not accepted:** Spotify or YouTube URLs, protected third-party app playback, DRM/FairPlay streams, HLS playlists, video pages, and URLs without authorization. iOS does not let this app capture another app’s protected audio.
- **YouTube search:** the official YouTube Data API v3 is used for metadata search only. There is no embedded player, audio extraction, download, caching, or MP3 conversion. Use audio you own or are licensed to use for DSP playback.

The YouTube API key is entered on-device and stored in iOS Keychain. Restrict the key to YouTube Data API v3 and the iOS app bundle ID (`com.pioneerdsp.app`). No API key or OAuth token is committed in this repository.

## Build an unsigned iOS IPA

Requirements: macOS, Xcode, and an iOS 17+ deployment target. The GitHub Actions workflow uses the standard `macos-15` runner.

```bash
xcodebuild -project ios-engine.xcodeproj \
  -scheme ios-engine \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build

mkdir -p Payload
cp -R build/Build/Products/Release-iphoneos/ios-engine.app Payload/
zip -r -y DSP_ENGINE_unsigned.ipa Payload
```

The CI IPA is **unsigned**. Sign it with a valid Apple development/distribution identity and matching provisioning profile—or use a trusted sideloading workflow—before installation. A successful CI build does not prove on-device playback, signing, installation, or crash-free runtime.
