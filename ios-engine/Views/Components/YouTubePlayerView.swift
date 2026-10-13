import SwiftUI
import WebKit
import UIKit

/// A visible embedded YouTube player. No stream URLs are extracted or downloaded.
public struct YouTubePlayerWebView: UIViewRepresentable {
    public let videoID: String

    public init(videoID: String) {
        self.videoID = videoID
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        context.coordinator.attach(webView)
        context.coordinator.load(videoID: videoID, in: webView)
        return webView
    }

    public func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(videoID: videoID, in: webView)
    }

    public static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Remove the visible player when the sheet is dismissed; it must not continue as hidden audio.
        coordinator.stop(webView)
    }

    public final class Coordinator: NSObject {
        private var loadedVideoID: String?
        private var currentVideoID: String?
        private weak var webView: WKWebView?
        private var backgroundObserver: NSObjectProtocol?
        private var activeObserver: NSObjectProtocol?
        private var isAppActive = true

        func attach(_ webView: WKWebView) {
            self.webView = webView
            activeObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                self.isAppActive = true
                if let videoID = self.currentVideoID, let webView = self.webView {
                    self.load(videoID: videoID, in: webView)
                }
            }
            backgroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                guard let self, let webView = self.webView else { return }
                self.isAppActive = false
                // Unload playback on app-switch/background so YouTube never becomes a hidden player.
                webView.stopLoading()
                webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
                self.loadedVideoID = nil
            }
        }

        func stop(_ webView: WKWebView) {
            webView.stopLoading()
            webView.loadHTMLString("<html><body style='background:#000'></body></html>", baseURL: nil)
            loadedVideoID = nil
            currentVideoID = nil
            self.webView = nil
            if let backgroundObserver {
                NotificationCenter.default.removeObserver(backgroundObserver)
                self.backgroundObserver = nil
            }
            if let activeObserver {
                NotificationCenter.default.removeObserver(activeObserver)
                self.activeObserver = nil
            }
        }

        deinit {
            if let backgroundObserver {
                NotificationCenter.default.removeObserver(backgroundObserver)
            }
            if let activeObserver {
                NotificationCenter.default.removeObserver(activeObserver)
            }
        }

        func load(videoID: String, in webView: WKWebView) {
            guard isAppActive, loadedVideoID != videoID,
                  videoID.range(of: "^[A-Za-z0-9_-]{6,}$", options: .regularExpression) != nil,
                  var components = URLComponents(string: "https://www.youtube.com/embed/\(videoID)") else { return }
            components.queryItems = [
                URLQueryItem(name: "playsinline", value: "1"),
                URLQueryItem(name: "controls", value: "1"),
                URLQueryItem(name: "rel", value: "0")
            ]
            guard let url = components.url else { return }
            currentVideoID = videoID
            loadedVideoID = videoID
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            webView.load(request)
        }
    }
}

public struct YouTubePlayerSheet: View {
    public let track: YouTubeTrackResult
    @Environment(\.dismiss) private var dismiss

    public init(track: YouTubeTrackResult) {
        self.track = track
    }

    public var body: some View {
        ZStack {
            PioneerColors.carbonBg.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUTUBE PLAYER")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(PioneerColors.amberOrange)
                        Text(track.title)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        Text(track.artist)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(PioneerColors.textMuted)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 27))
                            .foregroundColor(.white.opacity(0.72))
                    }
                    .accessibilityLabel("Close YouTube player")
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)

                YouTubePlayerWebView(videoID: track.videoId)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(PioneerColors.titaniumCardBorder, lineWidth: 1)
                    }
                    .padding(.horizontal, 16)

                Label("Official YouTube player", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(red: 1.0, green: 0.25, blue: 0.24))

                Text("YouTube playback stays in this visible player and is not processed by DSP ENGINE. Import a local, non-DRM audio file to use EQ and effects.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(PioneerColors.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 24)

                Button(action: openInYouTube) {
                    Label("OPEN IN YOUTUBE", systemImage: "arrow.up.right.square")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.78), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 18)

                Spacer(minLength: 8)
            }
        }
    }

    private func openInYouTube() {
        var components = URLComponents(string: "https://www.youtube.com/watch")
        components?.queryItems = [URLQueryItem(name: "v", value: track.videoId)]
        if let url = components?.url {
            UIApplication.shared.open(url, options: [:])
        }
    }
}
