import Combine
import Foundation

/// Read-only discovery for a small set of Internet Archive music collections.
/// Search is limited to audio items with explicitly recognized permissive CC/PD
/// metadata; the item manifest is checked again before any stream URL is exposed.
@MainActor
final class InternetArchiveAudioCatalog: ObservableObject {
    static let shared = InternetArchiveAudioCatalog()

    @Published private(set) var searchResults: [ArchiveAudioItem] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private var searchGeneration = 0
    private let searchEndpoint = URL(string: "https://archive.org/advancedsearch.php")!
    private let metadataEndpoint = URL(string: "https://archive.org/metadata")!

    // Excludes NC/ND licenses because DSP ENGINE cannot enforce those restrictions
    // or determine how the user intends to use the audio.
    private static let permittedLicensePaths: Set<String> = [
        "/publicdomain/mark/1.0/",
        "/publicdomain/zero/1.0/",
        "/licenses/by/2.0/",
        "/licenses/by/2.5/",
        "/licenses/by/3.0/",
        "/licenses/by/4.0/",
        "/licenses/by-sa/2.0/",
        "/licenses/by-sa/2.5/",
        "/licenses/by-sa/3.0/",
        "/licenses/by-sa/4.0/"
    ]

    private static let permittedCollections: Set<String> = [
        "freemusicarchive", "netlabels", "audio_music"
    ]

    private static let supportedExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "aif", "aiff", "caf"
    ]

    private init() {}

    func search(query: String) async {
        searchGeneration &+= 1
        let requestGeneration = searchGeneration
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchResults = []
            errorMessage = nil
            isSearching = false
            return
        }
        guard trimmed.count >= 2 else {
            searchResults = []
            errorMessage = "Enter at least two characters to search the open-audio catalog."
            isSearching = false
            return
        }
        isSearching = true
        errorMessage = nil
        searchResults = []
        defer {
            if requestGeneration == searchGeneration { isSearching = false }
        }

        guard let url = searchURL(for: String(trimmed.prefix(80))) else {
            errorMessage = "Could not create the Internet Archive catalog request."
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
            guard requestGeneration == searchGeneration else { return }
            guard let http = response as? HTTPURLResponse else {
                errorMessage = "Internet Archive returned an invalid catalog response."
                return
            }
            guard http.statusCode == 200 else {
                errorMessage = "Open-audio search failed (HTTP \(http.statusCode)). Try again later."
                return
            }
            guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let responseObject = root["response"] as? [String: Any],
                  let documents = responseObject["docs"] as? [[String: Any]] else {
                errorMessage = "Internet Archive returned an unreadable catalog response."
                return
            }

            let results = documents.compactMap(Self.parseSearchItem)
            guard requestGeneration == searchGeneration else { return }
            searchResults = results
            if results.isEmpty {
                errorMessage = "No items with a recognized CC BY, CC BY-SA, CC0, or Public Domain Mark record were found in the supported music collections."
            }
        } catch {
            guard requestGeneration == searchGeneration else { return }
            errorMessage = "Could not reach the open-audio catalog. Check your connection and try again."
        }
    }

    func audioFiles(for item: ArchiveAudioItem) async throws -> [ArchiveAudioFile] {
        guard var components = URLComponents(url: metadataEndpoint, resolvingAgainstBaseURL: false) else {
            throw ArchiveCatalogError.invalidItem
        }
        components.path += "/\(item.identifier)"
        guard let url = components.url else { throw ArchiveCatalogError.invalidItem }

        let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ArchiveCatalogError.metadataUnavailable
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = root["metadata"] as? [String: Any],
              let identifier = text(metadata["identifier"]), identifier == item.identifier,
              text(metadata["mediatype"])?.lowercased() == "audio",
              let licenseURL = Self.strings(metadata["licenseurl"]).first(where: Self.isPermittedLicense),
              Self.strings(metadata["collection"]).contains(where: { Self.permittedCollections.contains($0.lowercased()) }),
              let rawFiles = root["files"] as? [[String: Any]] else {
            throw ArchiveCatalogError.noAuthorizedAudio
        }

        let audioFiles = rawFiles.compactMap { file -> ArchiveAudioFile? in
            guard let name = text(file["name"]),
                  Self.isPublicFile(file),
                  Self.isSafeArchivePath(name),
                  Self.supportedExtensions.contains(URL(fileURLWithPath: name).pathExtension.lowercased()),
                  let streamURL = Self.downloadURL(identifier: item.identifier, fileName: name) else { return nil }
            return ArchiveAudioFile(
                id: "\(item.identifier)/\(name)",
                name: name,
                format: text(file["format"]) ?? URL(fileURLWithPath: name).pathExtension.uppercased(),
                sizeBytes: integer(file["size"]),
                streamURL: streamURL
            )
        }
        .sorted {
            let left = Self.extensionRank(for: $0.name)
            let right = Self.extensionRank(for: $1.name)
            return left == right ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending : left < right
        }

        guard !audioFiles.isEmpty else { throw ArchiveCatalogError.noPlayableFiles }
        return audioFiles
    }

    private func searchURL(for term: String) -> URL? {
        let phrase = Self.lucenePhrase(term)
        let licenseClause = Self.permittedLicensePaths
            .sorted()
            .map { "licenseurl:\"http://creativecommons.org\($0)\"" }
            .joined(separator: " OR ")
        let collectionClause = Self.permittedCollections.sorted().map { "collection:\($0)" }.joined(separator: " OR ")
        let query = "mediatype:audio AND (\(licenseClause)) AND (\(collectionClause)) AND (title:\(phrase) OR creator:\(phrase) OR subject:\(phrase))"

        var components = URLComponents(url: searchEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fl[]", value: "identifier"),
            URLQueryItem(name: "fl[]", value: "title"),
            URLQueryItem(name: "fl[]", value: "creator"),
            URLQueryItem(name: "fl[]", value: "licenseurl"),
            URLQueryItem(name: "fl[]", value: "collection"),
            URLQueryItem(name: "rows", value: "25"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "sort[]", value: "downloads desc")
        ]
        return components?.url
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("DSP ENGINE iOS audio catalog", forHTTPHeaderField: "User-Agent")
        return request
    }

    private static func parseSearchItem(_ document: [String: Any]) -> ArchiveAudioItem? {
        guard let identifier = text(document["identifier"]),
              isSafeIdentifier(identifier),
              let title = text(document["title"]),
              let licenseURL = strings(document["licenseurl"]).first(where: isPermittedLicense),
              strings(document["collection"]).contains(where: { permittedCollections.contains($0.lowercased()) }) else { return nil }
        return ArchiveAudioItem(
            identifier: identifier,
            title: title,
            creator: text(document["creator"]) ?? "Creator not listed",
            licenseURL: licenseURL
        )
    }

    private static func isPermittedLicense(_ rawValue: String) -> Bool {
        guard let components = URLComponents(string: rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              (components.scheme?.lowercased() == "http" || components.scheme?.lowercased() == "https"),
              let host = components.host?.lowercased(),
              (host == "creativecommons.org" || host == "www.creativecommons.org") else { return false }
        return permittedLicensePaths.contains(components.path.lowercased())
    }

    private static func isPublicFile(_ file: [String: Any]) -> Bool {
        let value = file["private"]
        if let flag = value as? Bool { return !flag }
        if let text = value as? String { return text != "1" && text.lowercased() != "true" }
        return true
    }

    private static func downloadURL(identifier: String, fileName: String) -> URL? {
        guard isSafeIdentifier(identifier), isSafeArchivePath(fileName) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "archive.org"
        components.path = "/download/\(identifier)/\(fileName)"
        return components.url
    }

    private static func isSafeIdentifier(_ identifier: String) -> Bool {
        !identifier.isEmpty
            && identifier.count <= 200
            && !identifier.contains("/")
            && !identifier.contains("\\")
            && identifier.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private static func isSafeArchivePath(_ name: String) -> Bool {
        guard !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), name.count <= 1_024,
              name.rangeOfCharacter(from: .controlCharacters) == nil else { return false }
        return !name.split(separator: "/", omittingEmptySubsequences: false).contains { $0 == ".." || $0 == "." }
    }

    private static func lucenePhrase(_ value: String) -> String {
        let specials = CharacterSet(charactersIn: "+-&|!(){}[]^\"~*?:\\/")
        let escaped = value.unicodeScalars.map { scalar in
            specials.contains(scalar) ? "\\" + String(scalar) : String(scalar)
        }.joined()
        return "\"\(escaped)\""
    }

    private static func extensionRank(for name: String) -> Int {
        switch URL(fileURLWithPath: name).pathExtension.lowercased() {
        case "mp3": return 0
        case "m4a", "m4b": return 1
        case "aac": return 2
        case "wav": return 3
        case "aif", "aiff": return 4
        case "caf": return 5
        default: return 6
        }
    }

    private static func strings(_ value: Any?) -> [String] {
        if let string = value as? String, !string.isEmpty { return [string] }
        if let array = value as? [String] { return array.filter { !$0.isEmpty } }
        if let array = value as? [Any] { return array.compactMap { $0 as? String }.filter { !$0.isEmpty } }
        return []
    }

    private static func text(_ value: Any?) -> String? {
        let values = strings(value).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        return values.joined(separator: ", ")
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}

struct ArchiveAudioItem: Identifiable, Equatable {
    let identifier: String
    let title: String
    let creator: String
    let licenseURL: String

    var id: String { identifier }
    var artworkURL: URL? { Self.url(path: "/services/img/\(identifier)") }
    var detailsURL: URL? { Self.url(path: "/details/\(identifier)") }

    var licenseLabel: String {
        let path = URLComponents(string: licenseURL)?.path.lowercased() ?? ""
        let version = path.split(separator: "/").last.map { String($0) } ?? ""
        if path.contains("publicdomain/zero") { return "CC0 1.0" }
        if path.contains("publicdomain/mark") { return "Public Domain Mark 1.0" }
        if path.contains("licenses/by-sa/") { return "CC BY-SA \(version)" }
        if path.contains("licenses/by/") { return "CC BY \(version)" }
        return "CC license record"
    }

    private static func url(path: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "archive.org"
        components.path = path
        return components.url
    }
}

struct ArchiveAudioFile: Identifiable, Equatable {
    let id: String
    let name: String
    let format: String
    let sizeBytes: Int64?
    let streamURL: URL

    var displayTitle: String {
        URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
    }

    var formattedSize: String {
        guard let sizeBytes, sizeBytes > 0 else { return "Size not listed" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

private enum ArchiveCatalogError: LocalizedError {
    case invalidItem
    case metadataUnavailable
    case noAuthorizedAudio
    case noPlayableFiles

    var errorDescription: String? {
        switch self {
        case .invalidItem:
            return "The selected archive item has an invalid identifier."
        case .metadataUnavailable:
            return "The archive item metadata could not be loaded."
        case .noAuthorizedAudio:
            return "The item no longer matches the public audio, music-collection, and license checks. No stream was started."
        case .noPlayableFiles:
            return "No public MP3, AAC/M4A, WAV, AIFF, or CAF audio file was listed for this item."
        }
    }
}
