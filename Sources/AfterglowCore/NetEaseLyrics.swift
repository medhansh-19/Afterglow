import Foundation

/// Independent timed lookup. Match the recording before requesting its supplied timestamps.
enum NetEaseLyrics {
    private struct Search: Decodable {
        struct Result: Decodable { let songs: [Song]? }
        let code: Int
        let result: Result?
    }
    private struct Song: Decodable {
        struct Artist: Decodable { let name: String }
        struct Album: Decodable { let name: String? }
        let id: Int
        let name: String
        let artists: [Artist]
        let album: Album?
        let duration: Double
    }
    private struct Payload: Decodable {
        struct LRC: Decodable { let lyric: String? }
        let code: Int
        let lrc: LRC?
        let yrc: LRC?
    }

    static func fetch(_ track: Track, transport: any LyricTransport) async throws -> LyricDocument? {
        var search = URLComponents(string: "https://music.163.com/api/search/get")!
        search.queryItems = [
            .init(name: "s", value: track.artist + " " + RecordingMatch.queryTitle(track.title)),
            .init(name: "type", value: "1"), .init(name: "limit", value: "10")
        ]
        let response = try await transport.get(search.url!)
        try Task.checkCancellation()
        if response.status == 404 { return nil }
        guard response.status == 200 else { throw URLError(.badServerResponse) }
        let metadata = try JSONDecoder().decode(Search.self, from: response.data)
        guard metadata.code == 200 else { throw URLError(.badServerResponse) }
        let candidates = (metadata.result?.songs ?? []).filter { song in
            let seconds = song.duration / 1000
            let creditedArtists = song.artists.map(\.name).joined(separator: ", ")
            // Spotify's AppleScript metadata may expose only the primary artist when
            // the title has no feature credit. Preserve explicit guest credits when present.
            let primaryOnly = RecordingMatch.queryTitle(track.title) == track.title
                && song.artists.first.map { RecordingMatch.artistsMatch(track, candidate: $0.name) } == true
            return song.id > 0 && seconds.isFinite && seconds > 0 && track.duration > 0
                && abs(seconds - track.duration) <= min(10, track.duration * 0.05)
                && RecordingMatch.title(song.name) == RecordingMatch.title(track.title)
                && (RecordingMatch.artistsMatch(track, candidate: creditedArtists) || primaryOnly)
                && RecordingMatch.compatibleVersion(track, candidateAlbum: song.album?.name ?? "", candidateTitle: song.name)
        }.sorted { abs($0.duration / 1000 - track.duration) < abs($1.duration / 1000 - track.duration) }
        for candidate in candidates.prefix(2) {
            var url = URLComponents(string: "https://music.163.com/api/song/lyric/v1")!
            url.queryItems = [.init(name: "id", value: String(candidate.id)), .init(name: "lv", value: "-1"),
                .init(name: "kv", value: "-1"), .init(name: "tv", value: "-1"), .init(name: "yv", value: "-1")]
            let response = try await transport.get(url.url!)
            try Task.checkCancellation()
            if response.status == 404 { continue }
            guard response.status == 200 else { throw URLError(.badServerResponse) }
            let payload = try JSONDecoder().decode(Payload.self, from: response.data)
            guard payload.code == 200 else { continue }
            let wordTimed = LyricCredits.clean(NetEaseYRC.parse(payload.yrc?.lyric ?? ""))
            let lines = wordTimed.filter({ LyricScene.isVocal($0) }).count >= 2
                ? wordTimed : LyricCredits.clean(EnhancedLRC.parse(payload.lrc?.lyric ?? ""))
            guard lines.filter({ LyricScene.isVocal($0) }).count >= 2,
                lines.allSatisfy({ $0.time <= candidate.duration / 1000 + 2 && ($0.words.last?.time ?? 0) <= candidate.duration / 1000 + 2 }) else { continue }
            return LyricDocument(lines: lines, plainText: lines.map(\.text).joined(separator: "\n"), source: .netease,
                automaticMatch: abs(candidate.duration / 1000 - track.duration) > 2,
                matchedDuration: candidate.duration / 1000, timingRevision: 2)
        }
        return nil
    }
}
