# DSP ENGINE for iOS

**made by avx**

DSP ENGINE is the existing native SwiftUI audio-effects app, with its identity and bundle ID preserved (`com.pioneerdsp.app`). The app targets iOS 17 and keeps its existing AVAudioEngine playback path for compatible local files. It also includes three new portrait anime wink backgrounds in the crimson, violet, and cyan palettes; the existing crossfade and native AVX wordmark overlay remain in place.

## Local library and DSP

- Import compatible mono/stereo audio files from Files. Imports are staged inside the app sandbox, probed as audio, SHA-256 fingerprinted for duplicate detection, and moved into the persistent library only after validation. Imported files are not transcoded.
- The library restores after relaunch, reads supported embedded title/artist/album/artwork metadata, and supports filtering, sorting, playback, and confirmed deletion.
- Local playback uses the existing `AVAudioEngine` graph with the 10-band EQ, bass and treble shaping, live room reverb and delay, dynamics processing, listening-position balance, and master volume. These controls update the running graph rather than requiring a track restart.
- The app does not claim to restore information lost in lossy audio.

## Authorized direct streams and downloads

- **Direct stream:** accepts user-supplied HTTPS audio-file links from sources that permit streaming. Compatible decoded mono/stereo PCM is processed through the stream DSP tap using shared EQ, tone, delay, room, balance, peak-control, and volume settings. The stream path does not save an audio copy. Protected/DRM content, video pages, YouTube/Spotify URLs, HLS playlists, and decoded formats the tap cannot process are rejected; only sources iOS actually decodes into a supported format can be processed.
- **Authorized downloads:** a separate manager accepts direct HTTPS audio-file URLs after the user confirms they have permission. It reports URLSession transfer progress and measured transfer rate, offers pause/resume when the server supplies resume data, and supports retry/cancel. Completed files are validated and imported atomically into the same local DSP library; duplicate audio is not added twice.
- The authorization checkbox is the user's declaration. DSP ENGINE cannot independently verify a source's license or terms. Only use audio you own or are licensed/otherwise authorized to download, stream, and process.
- The original file format is retained. iOS does not provide a native MP3 encoder here, so there is no pretend MP3 conversion or lossy-to-lossless claim.

## YouTube metadata search

The official YouTube Data API v3 is used for **metadata search only**. Results can show a thumbnail, title, and channel and link to YouTube's official source. DSP ENGINE does not play, capture, extract, download, cache, or convert YouTube audio. Spotify is not a playback or download source. Protected third-party app audio is not captured or processed.

The YouTube API key is entered on-device and stored in iOS Keychain. Restrict it to YouTube Data API v3 and the iOS app bundle ID (`com.pioneerdsp.app`). No API key or OAuth token is committed in this repository.

## Build an unsigned iOS IPA

Requirements: macOS, Xcode, and an iOS 17+ deployment target. The GitHub Actions workflow uses the standard `macos-15` runner and disables code signing.

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

The CI IPA is **unsigned**. Sign it with a valid Apple development/distribution identity and matching provisioning profile—or use a trusted sideloading workflow—before installation. A successful CI compile/package does not prove device signing, installation, visual behavior, playback, or crash-free runtime. No device test is implied by this README.
