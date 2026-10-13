# DSP ENGINE for iOS

**made by avx**

DSP ENGINE is a native SwiftUI audio-effects app. Local, non-DRM audio files are played through an `AVAudioEngine` graph with a 10-band EQ and reverb controls. Imported tracks stay in the app’s sandbox.

## Playback boundaries

- **Local files:** import compatible mono or stereo audio from Files to use the DSP chain.
- **Spotify:** playlist links open the official Spotify app or Spotify web player. Spotify streams are not captured or DSP-processed. The repository does not currently include Spotify OAuth/App Remote credentials, so it does not claim in-app remote playback control.
- **YouTube:** search uses the YouTube Data API v3 when the user provides a key; a result opens in a visible official YouTube embedded player. YouTube media is not extracted, cached, or processed by DSP ENGINE.

The YouTube API key is entered on-device and stored in iOS Keychain. Restrict the key to YouTube Data API v3 and the iOS app bundle ID (`com.pioneerdsp.app`). No API key or OAuth token is committed in this repository.

## Build an unsigned iOS IPA

Requirements: macOS, Xcode, and an iOS 17+ deployment target.

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
