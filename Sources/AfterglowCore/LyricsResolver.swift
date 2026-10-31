import Foundation

public enum LyricSource: String, Codable, Sendable {
    case lrclib, karalyr, netease, lyricsOVH, local
    public var name: String {
        switch self { case .lrclib: "LRCLIB"; case .karalyr: "Karalyr"; case .netease: "NetEase"; case .lyricsOVH: "lyrics.ovh"; case .local: "Your imported lyrics" }
    }
}

public struct LyricAlternative: Codable, Sendable, Identifiable {
    public let id: Int
    public let title: String
    public let artist: String
    public let album: String
    public let duration: Double
    public let lines: [LyricLine]
    public let plainText: String?
    public var document: LyricDocument {
        .init(lines: lines, plainText: plainText, source: .lrclib, manualMatch: true)
    }
}

public struct LyricDocument: Codable, Sendable {
    public let lines: [LyricLine]
    public let plainText: String?
    public let source: LyricSource
    public let instrumental: Bool
    public let alternatives: [LyricAlternative]?
    public let manualMatch: Bool?
    public let automaticMatch: Bool?
    public let matchedDuration: Double?
    public let timingRevision: Int?
    public let retrievedFromCache: Bool?
    public init(lines: [LyricLine] = [], plainText: String? = nil, source: LyricSource, instrumental: Bool = false,
                alternatives: [LyricAlternative]? = nil, manualMatch: Bool = false,
                automaticMatch: Bool = false, matchedDuration: Double? = nil, timingRevision: Int? = nil, retrievedFromCache: Bool = false) {
        self.lines = lines; self.plainText = plainText; self.source = source; self.instrumental = instrumental
        self.alternatives = alternatives; self.manualMatch = manualMatch
        self.automaticMatch = automaticMatch; self.matchedDuration = matchedDuration
        self.timingRevision = timingRevision
        self.retrievedFromCache = retrievedFromCache
    }
    public func including(_ alternatives: [LyricAlternative]) -> LyricDocument {
        .init(lines: lines, plainText: plainText, source: source, instrumental: instrumental,
              alternatives: alternatives, manualMatch: manualMatch == true,
              automaticMatch: automaticMatch == true, matchedDuration: matchedDuration, timingRevision: timingRevision, retrievedFromCache: retrievedFromCache == true)
    }
    public func markingCached() -> LyricDocument {
        .init(lines: lines, plainText: plainText, source: source, instrumental: instrumental,
            alternatives: alternatives, manualMatch: manualMatch == true, automaticMatch: automaticMatch == true,
            matchedDuration: matchedDuration, timingRevision: timingRevision, retrievedFromCache: true)
    }
    public func removingCredits() -> LyricDocument {
        guard source != .local else { return self }
        return .init(lines: LyricCredits.clean(lines), plainText: plainText, source: source,
            instrumental: instrumental, alternatives: alternatives, manualMatch: manualMatch == true,
            automaticMatch: automaticMatch == true, matchedDuration: matchedDuration, timingRevision: timingRevision, retrievedFromCache: retrievedFromCache == true)
    }
    public var timed: Bool { lines.contains { !$0.text.isEmpty } }
}

public enum RecordingMatch {
    public static func title(_ value: String) -> String {
        normalize(queryTitle(value))
    }
    public static func queryTitle(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)\s*[\(\[]\s*(?:feat\.?|featuring|ft\.?|with)\s+[^\)\]]+[\)\]]"#,
                                   with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    public static func artist(_ value: String) -> String {
        normalize(value.replacingOccurrences(of: #"(?i)\s+(?:feat\.?|featuring|ft\.?)\s+.*$"#, with: "", options: .regularExpression))
    }
    public static func artistsMatch(_ track: Track, candidate: String) -> Bool {
        if normalize(candidate) == normalize(track.artist) { return true }
        let separator = #"(?i)\s*(?:,|;|\s&\s|\sfeat\.?\s|\sfeaturing\s|\sft\.?\s|\swith\s|\sx\s)\s*"#
        func parts(_ value: String) -> [String] {
            value.replacingOccurrences(of: separator, with: "|", options: .regularExpression)
                .split(separator: "|").map { normalize(String($0)) }.filter { !$0.isEmpty }
        }
        let candidateParts = parts(candidate)
        guard candidateParts.count > 1, candidateParts.first == artist(track.artist) else { return false }
        let expression = try! NSRegularExpression(pattern: #"(?i)[\(\[]\s*(?:feat\.?|featuring|ft\.?|with)\s+([^\)\]]+)[\)\]]"#)
        let title = track.title as NSString
        let guests = expression.matches(in: track.title, range: NSRange(location: 0, length: title.length))
            .flatMap { parts(title.substring(with: $0.range(at: 1))) }
        return Set(candidateParts.dropFirst()) == Set(guests) && !guests.isEmpty
    }
    private static func normalize(_ value: String) -> String {
        let lower = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "&", with: " and ")
        return String(lower.map { $0.isLetter || $0.isNumber ? $0 : " " }).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    /// Albums sometimes disclose a different performance even when the title omits it.
    public static func compatibleVersion(_ track: Track, candidateAlbum: String, candidateTitle: String? = nil) -> Bool {
        let recording = normalize(track.title + " " + track.album)
        let candidate = normalize((candidateTitle ?? track.title) + " " + candidateAlbum)
        let markers = ["live", "remix", "acoustic", "instrumental", "karaoke", "stripped", "sped up", "slowed"]
        func contains(_ value: String, _ marker: String) -> Bool {
            (" " + value + " ").contains(" " + marker + " ")
        }
        return markers.allSatisfy { contains(candidate, $0) == contains(recording, $0) }
    }

    public static func accepts(_ track: Track, title candidate: String, artist candidateArtist: String, duration: Double) -> Bool {
        duration.isFinite && track.duration.isFinite && track.duration > 0 && duration > 0
            && abs(duration - track.duration) <= 2
            && title(candidate) == title(track.title) && artistsMatch(track, candidate: candidateArtist)
    }
}

public struct LyricHTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public init(data: Data, status: Int) { self.data = data; self.status = status }
}

public protocol LyricTransport: Sendable {
    func get(_ url: URL) async throws -> LyricHTTPResponse
}

public struct URLSessionLyricTransport: LyricTransport {
    public init() {}
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForResource = 8
        return URLSession(configuration: configuration, delegate: LyricRedirects(), delegateQueue: nil)
    }()
    public static func allows(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil
            && ["lrclib.net", "karalyr.com", "www.karalyr.com", "music.163.com", "api.lyrics.ovh"].contains(url.host ?? "")
    }
    public static func allowsRedirect(from original: URL?, to destination: URL?) -> Bool {
        guard let original, let destination, allows(original), allows(destination) else { return false }
        if original.host == destination.host { return true }
        // Karalyr redirects its apex domain to its canonical www API host.
        return original.host == "karalyr.com" && destination.host == "www.karalyr.com"
    }
    public func get(_ url: URL) async throws -> LyricHTTPResponse {
        guard Self.allows(url) else { throw URLError(.unsupportedURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = url.path == "/api/get" ? 3 : 7
        request.setValue("Afterglow/3.0.7 (https://github.com/medhansh-19/Afterglow)", forHTTPHeaderField: "User-Agent")
        if url.host == "karalyr.com" || url.host == "www.karalyr.com" { request.setValue("afterglow/3.0.7", forHTTPHeaderField: "X-Karalyr-Client") }
        let host = url.host ?? ""
        try Task.checkCancellation()
        if let blocked = await LyricProviderHealth.shared.blockedResponse(host: host) {
            return blocked
        }
        do {
            let (data, response) = try await Self.session.data(for: request)
            try Task.checkCancellation()
            guard data.count <= 2_000_000, let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            let result = LyricHTTPResponse(data: data, status: response.statusCode)
            await LyricProviderHealth.shared.record(host: host, response: result,
                retryAfter: response.value(forHTTPHeaderField: "Retry-After"))
            return result
        } catch {
            if !(error is CancellationError), (error as? URLError)?.code != .cancelled, !Task.isCancelled {
                await LyricProviderHealth.shared.record(host: host,
                    response: .init(data: Data(), status: 503))
            }
            throw error
        }
    }
}

private final class LyricRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(URLSessionLyricTransport.allowsRedirect(from: task.originalRequest?.url, to: request.url) ? request : nil)
    }
}

public actor LyricCache {
    // Older releases cannot decode the newer provider/word-timing payloads. Give
    // them a different file so launching an archived app cannot erase this cache.
    private static let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Afterglow")
    public static let shared = LyricCache(storageURL: folder?.appendingPathComponent("Lyrics-v3.json"),
        legacyStorageURL: folder?.appendingPathComponent("Lyrics-v2.json"))
    private struct Entry: Codable { let track: Track; let document: LyricDocument; let saved: Date; var accessed: Date; let matchingRevision: Int? }
    private var entries: [Track: Entry] = [:]
    private var missing: [Track: Date] = [:]
    private let storageURL: URL?
    public init(storageURL: URL? = nil, legacyStorageURL: URL? = nil) {
        self.storageURL = storageURL
        // Import old data first; the isolated cache always owns newer records.
        for path in [legacyStorageURL, storageURL].compactMap({ $0 }) {
            guard let size = try? path.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                size <= 10_000_000, let data = try? Data(contentsOf: path),
                let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
            // A future/unknown provider must not make every other saved song vanish.
            for row in rows.suffix(64) {
                guard let encoded = try? JSONSerialization.data(withJSONObject: row),
                    let entry = try? JSONDecoder().decode(Entry.self, from: encoded) else { continue }
                entries[entry.track] = entry
            }
        }
    }
    public func read(_ track: Track, allowPlain: Bool, allowTimedFallback: Bool = true, allowExpired: Bool = false) -> LyricDocument? {
        guard var entry = entries[track],
              entry.matchingRevision == 5 || (allowExpired && entry.document.timed
                && track.duration > 0 && entry.document.lines.allSatisfy { $0.time >= 0 && $0.time <= max(track.duration, entry.document.matchedDuration ?? 0) + min(10, track.duration * 0.05) }),
              Date().timeIntervalSince(entry.saved) < (allowExpired ? 90 * 86400 : (entry.document.timed && entry.document.automaticMatch != true ? 30 * 86400 : 600)),
              entry.document.source != .netease || entry.document.timingRevision == 2 || allowExpired,
              allowPlain || entry.document.source != .lyricsOVH,
              allowTimedFallback || ![LyricSource.karalyr, .netease].contains(entry.document.source) else { return nil }
        entry.accessed = Date(); entries[track] = entry
        return entry.document.removingCredits().markingCached()
    }
    public func isMissing(_ track: Track) -> Bool {
        guard let date = missing[track] else { return false }
        return Date().timeIntervalSince(date) < 300
    }
    public func recordMissing(_ track: Track) {
        if missing.count >= 64 { missing.removeAll(keepingCapacity: true) }
        missing[track] = Date()
    }
    public func put(_ track: Track, _ document: LyricDocument) {
        missing[track] = nil
        entries[track] = Entry(track: track, document: document, saved: Date(), accessed: Date(), matchingRevision: 5)
        while entries.count > 64 { evictOldest() }
        persist()
    }
    private func evictOldest() {
        if let oldest = entries.min(by: { $0.value.accessed < $1.value.accessed })?.key { entries[oldest] = nil }
    }
    private func persist() {
        guard let storageURL else { return }
        do {
            var data = try JSONEncoder().encode(Array(entries.values))
            while data.count > 10_000_000, entries.count > 1 {
                evictOldest(); data = try JSONEncoder().encode(Array(entries.values))
            }
            guard data.count <= 10_000_000 else { return }
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: storageURL, options: .atomic)
        } catch { /* Cache failures never prevent lyric display. */ }
    }
}

public struct LyricsResolver: Sendable {
    private let transport: any LyricTransport
    private let cache: LyricCache
    public init(transport: any LyricTransport = URLSessionLyricTransport(), cache: LyricCache = .shared) {
        self.transport = transport; self.cache = cache
    }

    private struct Record: Decodable {
        let id: Int?
        let albumName: String?
        let trackName: String?
        let artistName: String?
        let duration: Double?
        let plainLyrics: String?
        let syncedLyrics: String?
        let lyricsfile: String?
        let instrumental: Bool?
        var document: LyricDocument {
            let yaml = lyricsfile.map(Lyricsfile.parse) ?? []
            let lines = yaml.contains(where: { !$0.text.isEmpty }) ? yaml : syncedLyrics.map(Lyrics.parse) ?? []
            return .init(lines: lines, plainText: plainLyrics, source: .lrclib, instrumental: instrumental == true)
        }
        func matches(_ track: Track) -> Bool {
            guard let trackName, let artistName, let duration else { return false }
            return RecordingMatch.accepts(track, title: trackName, artist: artistName, duration: duration)
                && RecordingMatch.compatibleVersion(track, candidateAlbum: albumName ?? "", candidateTitle: trackName)
        }
    }

    public func fetch(_ track: Track, allowPlainFallback: Bool = true, allowTimedFallback: Bool = true, bypassCache: Bool = false) async throws -> LyricDocument? {
        try Task.checkCancellation()
        if !bypassCache, await cache.isMissing(track), allowPlainFallback && allowTimedFallback { return nil }
        var plain: LyricDocument?
        if !bypassCache, let cached = await cache.read(track, allowPlain: allowPlainFallback, allowTimedFallback: allowTimedFallback) {
            if cached.timed || cached.instrumental || !allowTimedFallback { return cached }
            // An untimed cache hit must not suppress a newly available synchronized backup.
            plain = cached
        }
        var alternatives: [LyricAlternative] = []
        var hadFailure = false
        var rateLimited = false
        // Album editions and feature-credit spelling often differ. Relax only the album/credit text;
        // artist, title/version and recording duration must still match before using timestamps.
        let signatures: [(String, String?)] = [(track.title, track.album.isEmpty ? nil : track.album), (RecordingMatch.queryTitle(track.title), nil)]
        var visited = Set<URL>()
        for (title, album) in signatures {
            let url = endpoint("/api/get", track: track, title: title, album: album)
            guard visited.insert(url).inserted else { continue }
            do {
                let response = try await transport.get(url)
                try Task.checkCancellation()
                if response.status == 404 { continue }
                guard response.status == 200 else { hadFailure = true; rateLimited = response.status == 429; break }
                let record = try JSONDecoder().decode(Record.self, from: response.data)
                guard record.matches(track) else { continue }
                let document = record.document
                if document.timed || document.instrumental { await cache.put(track, document); return document }
                if document.plainText?.isEmpty == false { plain = document }
            } catch {
                try propagateCancellation(error)
                hadFailure = true; break
            }
        }
        if !rateLimited {
            // Broad searches are capped by the service. Album-specific results prevent common
            // titles and compilation editions from crowding the matching recording out of view.
            let searches: [(String, String?)] = track.album.isEmpty
                ? [(track.title, nil), (RecordingMatch.queryTitle(track.title), nil)]
                : [(RecordingMatch.queryTitle(track.title), track.album), (track.title, nil), (RecordingMatch.queryTitle(track.title), nil)]
            var records: [Record] = []
            for (title, album) in searches {
                let url = endpoint("/api/search", track: track, title: title, album: album)
                guard visited.insert(url).inserted else { continue }
                do {
                    let response = try await transport.get(url)
                    try Task.checkCancellation()
                    if response.status == 404 { continue }
                    guard response.status == 200 else {
                        hadFailure = true
                        if response.status == 429 { break }
                        continue
                    }
                    records.append(contentsOf: try JSONDecoder().decode([Record].self, from: response.data).prefix(60))
                    let matching = records.filter { $0.matches(track) }
                    let documents = matching.map(\.document).filter(\.timed)
                    if let best = documents.max(by: { $0.lines.filter { !$0.words.isEmpty }.count < $1.lines.filter { !$0.words.isEmpty }.count }) {
                        await cache.put(track, best); return best
                    }
                    if plain == nil { plain = matching.map(\.document).first { $0.plainText?.isEmpty == false } }
                } catch { try propagateCancellation(error); hadFailure = true }
            }
            var seen = Set<String>()
            let candidates = records.filter {
                guard let title = $0.trackName, let artist = $0.artistName, let duration = $0.duration else { return false }
                return RecordingMatch.title(title) == RecordingMatch.title(track.title)
                    && RecordingMatch.artistsMatch(track, candidate: artist)
                    && duration.isFinite && duration > 0 && abs(duration - track.duration) <= 20
            }.sorted {
                let left = abs(($0.duration ?? 0) - track.duration), right = abs(($1.duration ?? 0) - track.duration)
                if left != right { return left < right }
                return ($0.albumName == track.album ? 1 : 0) > ($1.albumName == track.album ? 1 : 0)
            }
            for record in candidates {
                let document = record.document
                guard document.timed, let id = record.id, let title = record.trackName,
                      let artist = record.artistName, let duration = record.duration else { continue }
                let signature = document.lines.map { "\($0.time):\($0.text)" }.joined(separator: "|")
                guard seen.insert(signature).inserted else { continue }
                alternatives.append(.init(id: id, title: title, artist: artist, album: record.albumName ?? "Unknown album",
                    duration: duration, lines: document.lines, plainText: document.plainText))
                if alternatives.count == 6 { break }
            }
        }
        // Independent timed provider runs before accepting untimed text from any source.
        if allowTimedFallback {
            var fallbackURLs = Set<URL>()
            for title in [track.title, RecordingMatch.queryTitle(track.title)] {
                let url = endpoint("/api/get", track: track, title: title, album: nil, host: "www.karalyr.com")
                guard fallbackURLs.insert(url).inserted else { continue }
                do {
                    let response = try await transport.get(url)
                    try Task.checkCancellation()
                    if response.status == 404 { continue }
                    guard response.status == 200 else { hadFailure = true; break }
                    let record = try JSONDecoder().decode(Record.self, from: response.data)
                    guard record.matches(track) else { continue }
                    let lines = record.syncedLyrics.map(EnhancedLRC.parse) ?? []
                    guard lines.contains(where: { !$0.text.isEmpty }),
                          lines.allSatisfy({ $0.time <= track.duration + 2 && ($0.words.last?.time ?? 0) <= track.duration + 2 }) else { continue }
                    let document = LyricDocument(lines: lines, plainText: record.plainLyrics, source: .karalyr)
                    await cache.put(track, document)
                    return document
                } catch { try propagateCancellation(error); hadFailure = true; break }
            }
        }
        if allowTimedFallback {
            do {
                if let document = try await NetEaseLyrics.fetch(track, transport: transport) {
                    await cache.put(track, document)
                    return document
                }
            } catch { try propagateCancellation(error); hadFailure = true }
        }
        if let closest = alternatives.first(where: { alternative in
            let difference = abs(alternative.duration - track.duration)
            return track.duration > 0 && difference <= min(10, track.duration * 0.05)
                && RecordingMatch.compatibleVersion(track, candidateAlbum: alternative.album, candidateTitle: alternative.title)
        }) {
            let result = LyricDocument(lines: closest.lines, plainText: closest.plainText,
                source: .lrclib, alternatives: alternatives, automaticMatch: true,
                matchedDuration: closest.duration)
            await cache.put(track, result)
            return result
        }
        // Migration must not strand previously working timed lyrics during an outage.
        // Fresh results still pass the stricter recording/version checks above.
        if hadFailure, let saved = await cache.read(track, allowPlain: allowPlainFallback,
            allowTimedFallback: allowTimedFallback, allowExpired: true), saved.timed { return saved }
        if let plain { let result = plain.including(alternatives); await cache.put(track, result); return result }
        if allowPlainFallback {
            do {
                var components = URLComponents(string: "https://api.lyrics.ovh")!
                let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#%"))
                let segments = [track.artist, RecordingMatch.queryTitle(track.title)].map { $0.addingPercentEncoding(withAllowedCharacters: allowed)! }
                components.percentEncodedPath = "/v1/" + segments.joined(separator: "/")
                let url = components.url!
                let response = try await transport.get(url)
                try Task.checkCancellation()
                if response.status == 200 {
                    struct Plain: Decodable { let lyrics: String }
                    let text = try JSONDecoder().decode(Plain.self, from: response.data).lyrics.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty, text.utf8.count <= 250_000 {
                        let document = LyricDocument(plainText: text, source: .lyricsOVH, alternatives: alternatives)
                        await cache.put(track, document); return document
                    }
                } else if response.status != 404 { hadFailure = true }
            } catch { try propagateCancellation(error); hadFailure = true }
        }
        if !alternatives.isEmpty {
            let result = LyricDocument(source: .lrclib, alternatives: alternatives)
            await cache.put(track, result); return result
        }
        if hadFailure {
            // A provider outage must not discard lyrics already saved for this exact recording.
            // Keep source privacy settings and matching-revision validation in force.
            if let saved = await cache.read(track, allowPlain: allowPlainFallback,
                allowTimedFallback: allowTimedFallback, allowExpired: true) { return saved }
            throw URLError(.resourceUnavailable)
        }
        if allowPlainFallback && allowTimedFallback { await cache.recordMissing(track) }
        return nil
    }

    private func propagateCancellation(_ error: Error) throws {
        if error is CancellationError || (error as? URLError)?.code == .cancelled { throw error }
        try Task.checkCancellation()
    }

    private func endpoint(_ path: String, track: Track, title: String, album: String?, host: String = "lrclib.net") -> URL {
        var url = URLComponents(string: "https://\(host)\(path)")!
        url.queryItems = [.init(name: "track_name", value: title), .init(name: "artist_name", value: track.artist)]
        if let album { url.queryItems?.append(.init(name: "album_name", value: album)) }
        if path == "/api/get", track.duration >= 1, track.duration <= 3600 {
            url.queryItems?.append(.init(name: "duration", value: String(Int(track.duration.rounded()))))
        }
        return url.url!
    }
}
