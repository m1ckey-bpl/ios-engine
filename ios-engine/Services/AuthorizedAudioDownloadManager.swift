import Foundation
import Combine

public enum AudioDownloadState: String, Equatable {
    case downloading
    case pausing
    case paused
    case validating
    case completed
    case failed
    case cancelled

    public var title: String {
        switch self {
        case .downloading: return "DOWNLOADING"
        case .pausing: return "PAUSING"
        case .paused: return "PAUSED"
        case .validating: return "VERIFYING AUDIO"
        case .completed: return "ADDED TO LIBRARY"
        case .failed: return "FAILED"
        case .cancelled: return "CANCELLED"
        }
    }
}

public struct AudioDownloadRecord: Identifiable, Equatable {
    public let id: UUID
    public let title: String
    public let artist: String
    public let sourceURL: String
    public var state: AudioDownloadState
    public var bytesWritten: Int64
    public var expectedBytes: Int64?
    public var bytesPerSecond: Double?
    public var errorMessage: String?

    public var progress: Double? {
        guard let expectedBytes, expectedBytes > 0 else { return nil }
        return min(1, max(0, Double(bytesWritten) / Double(expectedBytes)))
    }

    public var estimatedRemaining: TimeInterval? {
        guard let expectedBytes, expectedBytes > bytesWritten,
              let bytesPerSecond, bytesPerSecond > 0 else { return nil }
        return Double(expectedBytes - bytesWritten) / bytesPerSecond
    }
}

/// Downloads only user-supplied, direct HTTPS audio URLs after an authorization
/// confirmation. It never turns search results or service pages into audio.
@MainActor
public final class AuthorizedAudioDownloadManager: ObservableObject {
    public static let shared = AuthorizedAudioDownloadManager()

    @Published public private(set) var downloads: [AudioDownloadRecord] = []
    @Published public var lastError: String?

    private let delegate: AudioDownloadSessionDelegate
    private var session: URLSession!
    private var tasks: [UUID: URLSessionDownloadTask] = [:]
    private var resumeData: [UUID: Data] = [:]
    private var progressSamples: [UUID: (date: Date, bytes: Int64)] = [:]

    private let supportedExtensions: Set<String> = ["mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf"]
    private let blockedDomains: Set<String> = [
        "youtube.com", "youtu.be", "youtube-nocookie.com", "googlevideo.com",
        "spotify.com", "spotify.link", "scdn.co", "spotifycdn.com"
    ]

    public init() {
        delegate = AudioDownloadSessionDelegate()
        delegate.onProgress = { [weak self] id, written, expected in
            Task { @MainActor [weak self] in self?.recordProgress(id: id, written: written, expected: expected) }
        }
        delegate.onFinish = { [weak self] id, stagedURL, responseURL, failure in
            Task { @MainActor [weak self] in
                await self?.finishDownload(id: id, stagedURL: stagedURL, responseURL: responseURL, failure: failure)
            }
        }
        delegate.onComplete = { [weak self] id, data, message in
            Task { @MainActor [weak self] in self?.completeTask(id: id, resumeData: data, message: message) }
        }
        let queue = OperationQueue()
        queue.name = "com.avx.dspengine.audio-download-delegate"
        queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: .default, delegate: delegate, delegateQueue: queue)
        let redirectBlocklist = blockedDomains
        let redirectExtensions = supportedExtensions
        delegate.canFollowRedirect = { url in
            guard let url,
                  url.scheme?.lowercased() == "https",
                  let rawHost = url.host?.lowercased() else { return false }
            let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost
            let pathExtension = url.pathExtension.lowercased()
            return redirectExtensions.contains(pathExtension)
                && !redirectBlocklist.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        }
        cleanStaleStagedDownloads()
    }

    public func startAuthorizedDownload(urlText: String, title: String, artist: String, authorized: Bool) {
        lastError = nil
        guard authorized else {
            lastError = "Confirm that you have permission to download and use this audio."
            return
        }
        let cleanURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleanURL), isSupportedDirectAudioURL(url) else {
            lastError = "Use an authorized direct HTTPS audio-file URL (MP3, AAC/M4A, WAV, AIFF, or CAF). Video pages, HLS, YouTube, and Spotify are not downloadable here."
            return
        }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = AudioDownloadRecord(
            id: UUID(),
            title: cleanTitle.isEmpty ? url.deletingPathExtension().lastPathComponent : cleanTitle,
            artist: cleanArtist.isEmpty ? "Authorized download" : cleanArtist,
            sourceURL: url.absoluteString,
            state: .downloading,
            bytesWritten: 0,
            expectedBytes: nil,
            bytesPerSecond: nil,
            errorMessage: nil
        )
        downloads.insert(item, at: 0)
        launch(item.id, url: url, resumeData: nil)
    }

    public func pause(_ id: UUID) {
        guard let task = tasks[id], let index = index(of: id),
              downloads[index].state == .downloading else { return }
        downloads[index].state = .pausing
        task.cancel { [weak self] data in
            Task { @MainActor [weak self] in self?.finishPause(id: id, data: data) }
        }
    }

    public func resume(_ id: UUID) {
        guard let item = record(id), item.state == .paused || item.state == .failed else { return }
        let savedData = resumeData.removeValue(forKey: id)
        let url = URL(string: item.sourceURL)
        guard savedData != nil || url != nil else {
            update(id) { $0.state = .failed; $0.errorMessage = "The original download URL is invalid." }
            return
        }
        update(id) {
            $0.state = .downloading
            $0.errorMessage = nil
            $0.bytesPerSecond = nil
            if savedData == nil { $0.bytesWritten = 0; $0.expectedBytes = nil }
        }
        launch(id, url: url, resumeData: savedData)
    }

    public func retry(_ id: UUID) {
        guard let item = record(id), item.state == .failed || item.state == .cancelled else { return }
        resumeData[id] = nil
        update(id) { $0.bytesWritten = 0; $0.expectedBytes = nil; $0.errorMessage = nil }
        resume(id)
    }

    public func cancel(_ id: UUID) {
        guard let index = index(of: id), downloads[index].state != .completed else { return }
        resumeData[id] = nil
        progressSamples[id] = nil
        update(id) { $0.state = .cancelled; $0.errorMessage = nil }
        tasks.removeValue(forKey: id)?.cancel()
    }

    public func canResume(_ id: UUID) -> Bool {
        guard let item = record(id), item.state == .failed,
              let data = resumeData[id], !data.isEmpty else { return false }
        return true
    }

    public func removeCompletedOrCancelled(_ id: UUID) {
        guard let index = index(of: id),
              [.completed, .cancelled, .failed].contains(downloads[index].state) else { return }
        downloads.remove(at: index)
        resumeData[id] = nil
        progressSamples[id] = nil
    }

    private func cleanStaleStagedDownloads() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DSP-ENGINE-Authorized-Downloads", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files { try? FileManager.default.removeItem(at: file) }
    }

    private func launch(_ id: UUID, url: URL?, resumeData data: Data?) {
        let task: URLSessionDownloadTask
        if let data, !data.isEmpty {
            task = session.downloadTask(withResumeData: data)
        } else if let url {
            task = session.downloadTask(with: url)
        } else {
            update(id) { $0.state = .failed; $0.errorMessage = "The original download URL is invalid." }
            return
        }
        task.taskDescription = id.uuidString
        tasks[id] = task
        progressSamples[id] = nil
        task.resume()
    }

    private func finishPause(id: UUID, data: Data?) {
        tasks[id] = nil
        progressSamples[id] = nil
        guard let index = index(of: id), downloads[index].state == .pausing else { return }
        if let data, !data.isEmpty {
            resumeData[id] = data
            downloads[index].state = .paused
            downloads[index].errorMessage = nil
        } else {
            downloads[index].state = .failed
            downloads[index].errorMessage = "This server did not provide resumable download data. Retry restarts the download."
        }
    }

    private func recordProgress(id: UUID, written: Int64, expected: Int64) {
        guard let index = index(of: id), downloads[index].state == .downloading else { return }
        let now = Date()
        let previous = progressSamples[id]
        let speed: Double?
        if let previous {
            let elapsed = now.timeIntervalSince(previous.date)
            let delta = written - previous.bytes
            speed = elapsed > 0.15 && delta > 0 ? Double(delta) / elapsed : downloads[index].bytesPerSecond
        } else {
            speed = nil
        }
        progressSamples[id] = (now, written)
        downloads[index].bytesWritten = max(0, written)
        downloads[index].expectedBytes = expected > 0 ? expected : nil
        downloads[index].bytesPerSecond = speed
    }

    private func finishDownload(id: UUID, stagedURL: URL?, responseURL: URL?, failure: String?) async {
        guard let index = index(of: id), downloads[index].state != .cancelled else {
            if let stagedURL { try? FileManager.default.removeItem(at: stagedURL) }
            return
        }
        guard failure == nil, let stagedURL else {
            update(id) { $0.state = .failed; $0.errorMessage = failure ?? "The download did not produce a file." }
            return
        }
        guard let responseURL, isSupportedDirectAudioURL(responseURL) else {
            try? FileManager.default.removeItem(at: stagedURL)
            update(id) { $0.state = .failed; $0.errorMessage = "The link redirected to an insecure, blocked, or unsupported destination; no audio was imported." }
            return
        }
        update(id) { $0.state = .validating; $0.errorMessage = nil }
        let item = downloads[index]
        let outcome = await MusicLibraryManager.shared.importDownloadedFile(
            from: stagedURL,
            title: item.title,
            artist: item.artist
        )
        tasks[id] = nil
        progressSamples[id] = nil
        switch outcome {
        case .imported:
            update(id) { $0.state = .completed; $0.bytesPerSecond = nil; $0.errorMessage = nil }
        case .alreadyInLibrary:
            update(id) { $0.state = .completed; $0.bytesPerSecond = nil; $0.errorMessage = "This audio already exists in the local library; no duplicate was added." }
        case .rejected(let message):
            update(id) { $0.state = .failed; $0.errorMessage = message }
        }
    }

    private func completeTask(id: UUID, resumeData data: Data?, message: String?) {
        guard let index = index(of: id) else { return }
        let state = downloads[index].state
        if state == .pausing || state == .paused || state == .cancelled || state == .validating || state == .completed { return }
        tasks[id] = nil
        progressSamples[id] = nil
        if let data, !data.isEmpty {
            resumeData[id] = data
        }
        if let message {
            downloads[index].state = .failed
            downloads[index].errorMessage = message
        }
    }

    private func update(_ id: UUID, _ body: (inout AudioDownloadRecord) -> Void) {
        guard let index = index(of: id) else { return }
        body(&downloads[index])
    }

    private func record(_ id: UUID) -> AudioDownloadRecord? {
        index(of: id).map { downloads[$0] }
    }

    private func index(of id: UUID) -> Int? {
        downloads.firstIndex(where: { $0.id == id })
    }

    private func isSupportedDirectAudioURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), isAllowedHost(host) else { return false }
        let ext = url.pathExtension.lowercased()
        return ext != "m3u8" && supportedExtensions.contains(ext)
    }

    private func isAllowedHost(_ rawHost: String?) -> Bool {
        guard let rawHost else { return false }
        let host = rawHost.lowercased().hasPrefix("www.") ? String(rawHost.lowercased().dropFirst(4)) : rawHost.lowercased()
        return !blockedDomains.contains(where: { host == $0 || host.hasSuffix("." + $0) })
    }
}

private final class AudioDownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    var onProgress: ((UUID, Int64, Int64) -> Void)?
    var onFinish: ((UUID, URL?, URL?, String?) -> Void)?
    var onComplete: ((UUID, Data?, String?) -> Void)?
    var canFollowRedirect: ((URL?) -> Bool)?

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        guard canFollowRedirect?(request.url) == true else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        onProgress?(id, totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        if let response = downloadTask.response as? HTTPURLResponse, !(200...299).contains(response.statusCode) {
            onFinish?(id, nil, response.url, "The source returned HTTP \(response.statusCode); no audio file was imported.")
            return
        }
        do {
            let ext = (downloadTask.response?.url ?? downloadTask.originalRequest?.url)?.pathExtension.lowercased() ?? "audio"
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DSP-ENGINE-Authorized-Downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent("\(id.uuidString).\(ext.isEmpty ? "audio" : ext)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            onFinish?(id, destination, downloadTask.response?.url, nil)
        } catch {
            onFinish?(id, nil, downloadTask.response?.url, "The completed download could not be staged safely.")
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let id = task.taskDescription.flatMap(UUID.init(uuidString:)) else { return }
        let data = (error as NSError?)?.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        onComplete?(id, data, error?.localizedDescription)
    }
}
