import Foundation
import AfterglowCore

var checks = 0
@MainActor func expect<T: Equatable>(_ actual: T, _ expected: T, _ name: String) {
    checks += 1
    guard actual == expected else {
        fatalError("FAIL \(name): expected \(expected), got \(actual)")
    }
    print("PASS \(name)")
}

let fractions = Lyrics.parse("[ar:ignored]\n[00:01.5][01:02.025] सितारे ✨\n[00:04.12]Light")
expect(fractions.map(\.time), [1.5, 4.12, 62.025], "fraction precision and repeated timestamps")
expect(fractions.map(\.text), ["सितारे ✨", "Light", "सितारे ✨"], "Unicode preservation")
let offset = Lyrics.parse("[offset:+500]\n[00:00.10]A\n[00:01]Old\n[00:01]New\n[00:99]Invalid")
expect(offset, [.init(time: 0, text: "A"), .init(time: 0.5, text: "New")], "offset, duplicate timestamps and invalid seconds")
expect(Lyrics.parse("[offset:-500]\n[00:01]Later").first?.time, 1.5, "negative offset")
let lines = Lyrics.parse("[00:03]First\n[00:07]\n[00:11]Last")
expect(Lyrics.index(at: 2.99, in: lines), nil, "intro before first lyric")
expect(Lyrics.index(at: 3, in: lines), 0, "exact line boundary")
expect(Lyrics.index(at: 9, in: lines), 1, "instrumental passage lookup")
expect(lines[Lyrics.index(at: 9, in: lines)!].text, "", "preserve blank passage")
expect(Lyrics.index(at: 100, in: lines), 2, "past final line")
expect(Lyrics.index(at: 4, in: lines), 0, "backward seek")
expect(Lyrics.index(at: 0, in: []), nil, "empty timeline")
let words = ["a", "constellation", "glows"]
expect(Lyrics.wordIndex(progress: -1, words: words), 0, "word start clamp")
expect(Lyrics.wordIndex(progress: 0.3, words: words), 1, "weighted word timing")
expect(Lyrics.wordIndex(progress: 1, words: words), 2, "word end clamp")
expect(Lyrics.wordIndex(progress: 3, words: words), 2, "word overflow clamp")
expect(Lyrics.wordIndex(progress: 0, words: []), 0, "empty word list")
let yaml = """
version: '1.0'
lines:
- text: 'Light returns'
  start_ms: 1000
  end_ms: 4000
  words:
  - text: 'Light '
    start_ms: 1000
    end_ms: 1500
  - text: returns
    start_ms: 2000
    end_ms: 3200
- text: 'A line without word timing'
  start_ms: 5000
  end_ms: 8000
"""
let timed = Lyricsfile.parse(yaml)
expect(timed.count, 2, "Lyricsfile line count")
expect(timed.first?.words.map(\.time), [1, 2], "real word timestamps convert milliseconds")
expect(timed.first?.words.map(\.text), ["Light", "returns"], "trim display spaces without losing word alignment")
let first = timed[0]
expect(LyricTiming.activeWord(in: first, at: 0.9, estimated: false, nextLineTime: 5), nil, "before vocal onset")
expect(LyricTiming.activeWord(in: first, at: 1, estimated: false, nextLineTime: 5), 0, "exact word onset")
expect(LyricTiming.activeWord(in: first, at: 1.7, estimated: false, nextLineTime: 5), nil, "actual gap between words")
expect(LyricTiming.activeWord(in: first, at: 2, estimated: false, nextLineTime: 5), 1, "next exact word onset")
expect(LyricTiming.activeWord(in: first, at: 3.2, estimated: false, nextLineTime: 5), nil, "word ends before next lyric line")
expect(LyricTiming.activeWord(in: timed[1], at: 6, estimated: false, nextLineTime: 9), nil, "line timestamps never fabricate a current word")
expect(LyricTiming.activeWord(in: timed[1], at: 6, estimated: true, nextLineTime: 9) != nil, true, "estimates require explicit opt-in")
expect(LyricTiming.activeWord(in: timed[1], at: 8, estimated: true, nextLineTime: 9), nil, "respect explicit line end")
expect(Lyricsfile.parse("lines: [{ text: nope, start_ms: -100 }]"), [], "reject negative timestamps")
expect(Lyricsfile.parse("lines: [invalid yaml"), [], "malformed YAML safely falls back")
expect(Lyricsfile.parse(yaml.replacingOccurrences(of: "start_ms: 2000", with: "start_ms: 500")).first?.words, [], "out-of-order words fall back to line timing")
expect(Lyricsfile.parse(yaml.replacingOccurrences(of: "Light returns", with: "Different text")).first?.words, [], "mismatched text rejects word highlighting")
expect(Lyricsfile.parse(yaml.replacingOccurrences(of: "end_ms: 3200", with: "end_ms: 9000")).first?.words, [], "word end must fit inside its line")

var clock = PlaybackClock()
clock.sample(position: 10, playing: true, sampledAt: 100, receivedAt: 100.1)
expect(abs(clock.position(at: 100.5) - 10.5) < 0.0001, true, "account for query transit time")
clock.sample(position: 10.38, playing: true, sampledAt: 100.4, receivedAt: 100.5)
expect(abs(clock.position(at: 100.5) - 10.5) < 0.01, true, "small poll jitter is smoothed")
clock.sample(position: 40, playing: true, sampledAt: 101, receivedAt: 101)
expect(clock.position(at: 101), 40, "forward seek snaps immediately")
clock.sample(position: 4, playing: true, sampledAt: 102, receivedAt: 102)
expect(clock.position(at: 102), 4, "backward seek snaps immediately")
clock.sample(position: 4.4, playing: false, sampledAt: 102.4, receivedAt: 102.5)
expect(clock.position(at: 200), 4.4, "pause freezes at player position")
clock.sample(position: 4.4, playing: true, sampledAt: 200, receivedAt: 200)
expect(clock.position(at: 201), 5.4, "resume restarts interpolation")
clock.sample(position: .nan, playing: true, sampledAt: 201, receivedAt: 201)
expect(clock.position(at: 201), 5.4, "invalid samples cannot poison playback")
expect(clock.position(at: 190), 4.4, "host time before anchor never rewinds media")
expect(Lyrics.parse("[999999999999999999999999:10]bad"), [], "reject overflowing LRC minutes")
if let fixturePath = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("--") }) {
    let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
    let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    let actual = Lyricsfile.parse(object["lyricsfile"] as? String ?? "")
    expect(actual.isEmpty, false, "decode real LRCLIB response")
    print("Live fixture: \(actual.count) lines; \(actual.filter { !$0.words.isEmpty }.count) lines have real word timestamps")
}
func pixels(_ color: [UInt8], count: Int) -> [UInt8] { Array(repeating: color, count: count).flatMap { $0 } }
let yellow = AlbumPalette.extract(rgba: pixels([235, 200, 20, 255], count: 200))!
expect(yellow.red > 0.9 && yellow.green > 0.75 && yellow.blue < 0.15, true, "album yellow remains yellow")
let white = AlbumPalette.extract(rgba: pixels([210, 209, 205, 255], count: 200) + pixels([180, 30, 30, 255], count: 10))!
expect(white.saturation < 0.1 && white.brightness > 0.9, true, "mostly white cover remains neutral")
let blue = AlbumPalette.extract(rgba: pixels([30, 85, 225, 255], count: 200))!
expect(blue.blue > 0.9 && blue.red < 0.5, true, "album blue stays blue")
expect(blue.luminance >= 0.18, true, "dark album hues lift to readable contrast")
expect(AlbumPalette.extract(rgba: []), nil, "empty artwork safely falls back")
expect(AlbumPalette.extract(rgba: [255, 0, 0, 0]), nil, "fully transparent artwork has no accent")
let dark = AlbumPalette.extract(rgba: pixels([0, 0, 0, 255], count: 20))!
expect(dark.brightness > 0.8, true, "black artwork gets a readable neutral accent")
let dominant = AlbumPalette.extract(rgba: pixels([230, 30, 40, 255], count: 180) + pixels([20, 70, 220, 255], count: 20))!
expect(dominant.red > dominant.blue * 3, true, "dominant cover hue beats a minor complementary hue")

var analyzer = BeatAnalyzer()
let silence = Array(repeating: Float(0), count: 4800)
let quiet = analyzer.process(samples: silence, sampleRate: 48000, at: 1)
expect(quiet.beatCount, 0, "silence never fabricates beats")
expect(quiet.level, 0, "silence has no level")
let kick: [Float] = (0..<4800).map { i -> Float in
    let angle = Double(i) * (2.0 * Double.pi * 70.0 / 48000.0)
    let decay = exp(-Double(i) / 1400.0)
    return Float(sin(angle) * decay * 0.8)
}
let hit = analyzer.process(samples: kick, sampleRate: 48000, at: 1.3)
expect(hit.beatCount, 1, "actual audio onset increments beat count")
expect(hit.pulse > 0.9 && hit.level > 0, true, "audio onset produces a visible pulse")
let refractory = analyzer.process(samples: kick, sampleRate: 48000, at: 1.35)
expect(refractory.beatCount, 1, "refractory interval prevents duplicate beat counting")
let released = analyzer.process(samples: silence, sampleRate: 48000, at: 2.5)
expect(released.pulse < 0.05, true, "pulse releases after audio stops")
expect(released.bars.count, 32, "waveform has bounded geometry")
let malformed = analyzer.process(samples: [.nan, .infinity, -.infinity], sampleRate: 48000, at: 3)
expect(malformed.level.isFinite && malformed.bars.allSatisfy(\.isFinite), true, "nonfinite audio cannot poison rendering")
var sequence = BeatAnalyzer()
var sequenceResult = BeatFrame.silent
for i in 0..<5 {
    let time = 10 + Double(i) * 0.6
    _ = sequence.process(samples: silence, sampleRate: 48000, at: time)
    sequenceResult = sequence.process(samples: kick, sampleRate: 48000, at: time + 0.2)
}
expect(sequenceResult.beatCount, 5, "five separated audio onsets reach the star stage")

var trace = StrokeTrace()
trace.advance(at: 0, beatCount: 40, live: true, playing: true)
expect(trace.snapshot.progress, 0, "existing beat count does not instantly draw")
trace.advance(at: 0.05, beatCount: 41, live: true, playing: true)
expect(trace.snapshot.progress > 0 && trace.snapshot.progress < 1, true, "beat draws a partial first edge")
let firstProgress = trace.snapshot.progress
trace.advance(at: 0.1, beatCount: 42, live: true, playing: false)
expect(trace.snapshot.progress, firstProgress, "paused pen freezes")
for i in 3...35 { trace.advance(at: Double(i) * 0.05, beatCount: 42, live: true, playing: true) }
expect(trace.snapshot.progress, 1, "silence finishes only the granted edge")
trace.advance(at: 2, beatCount: 900, live: true, playing: true)
expect(trace.snapshot.progress < 1.3, true, "backlogged beats cannot erupt a whole shape")
var ambient = StrokeTrace()
ambient.advance(at: 0, beatCount: 0, live: false, playing: true)
var sawComplete = false, sawFade = false, sawNext = false
for i in 1...160 {
    ambient.advance(at: Double(i) / 30, beatCount: 0, live: false, playing: true)
    let frame = ambient.snapshot
    if frame.route.count == 4 && frame.progress == 3 { sawComplete = true }
    if frame.opacity < 1 { sawFade = true }
    if frame.route.count == 6 && frame.progress < 1 { sawNext = true }
}
expect(sawComplete && sawFade && sawNext, true, "closed triangle holds and fades before a pentagon starts")
expect(StrokeTrace.staticSnapshot().completedEdges, 5, "reduced motion has static geometry")
expect(RecordingMatch.accepts(.init(title: "Song", artist: "Artist", album: "Deluxe", duration: 200), title: "Song (Live)", artist: "Artist", duration: 200), false, "never match live version to studio")
expect(RecordingMatch.accepts(.init(title: "Song", artist: "Artist", album: "", duration: 200), title: "Song", artist: "Other", duration: 200), false, "reject wrong artist")
expect(RecordingMatch.accepts(.init(title: "Song", artist: "Artist", album: "", duration: 200), title: "Song", artist: "Artist", duration: 210), false, "reject wrong recording duration")
expect(RecordingMatch.queryTitle("Song (feat. Friend)"), "Song", "feature credit can relax without stripping version")
expect(ImportedLyrics.parse("[00:01]Original line", extension: "lrc")?.lines.first?.time, 1, "import standard timed LRC")
expect(ImportedLyrics.parse(yaml, extension: "yaml")?.lines.first?.words.isEmpty, false, "import real word timestamps")
expect(ImportedLyrics.parse("My own text", extension: "txt")?.timed, false, "text import never invents timestamps")
expect(ImportedLyrics.parse("invalid", extension: "lrc") == nil, true, "reject invalid timed import")
expect(ImportedLyrics.parse(String(repeating: "x", count: 500001), extension: "txt") == nil, true, "bound import size")

actor FixtureTransport: LyricTransport {
    var replies: [LyricHTTPResponse]
    var urls: [URL] = []
    let cancel: Bool
    init(_ replies: [LyricHTTPResponse], cancel: Bool = false) { self.replies = replies; self.cancel = cancel }
    func get(_ url: URL) async throws -> LyricHTTPResponse {
        urls.append(url)
        if cancel { throw CancellationError() }
        guard !replies.isEmpty else { return .init(data: Data(), status: 404) }
        return replies.removeFirst()
    }
    func calls() -> [URL] { urls }
}
func response(_ text: String, status: Int = 200) -> LyricHTTPResponse { .init(data: Data(text.utf8), status: status) }
let testTrack = Track(title: "Song", artist: "Artist", album: "Deluxe", duration: 200)
let timedRecord = #"{"trackName":"Song","artistName":"Artist","duration":200,"syncedLyrics":"[00:01]Example"}"#
let relaxedTransport = FixtureTransport([response("", status: 404), response(timedRecord)])
let relaxedResolver = LyricsResolver(transport: relaxedTransport, cache: LyricCache())
let resolved = try await relaxedResolver.fetch(testTrack)
expect(resolved?.timed, true, "alternate album lookup recovers timed lyrics")
let relaxedCalls = await relaxedTransport.calls()
expect(URLComponents(url: relaxedCalls[1], resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "album_name" }, false, "second lookup omits mismatched album edition")
_ = try await relaxedResolver.fetch(testTrack)
expect(await relaxedTransport.calls().count, 2, "successful lyrics cache avoids repeated requests")
let fallback = FixtureTransport([response("", status: 503), response("", status: 503), response("", status: 503), response("", status: 404), response(#"{"lyrics":"Untimed example"}"#)])
let fallbackResult = try await LyricsResolver(transport: fallback, cache: LyricCache()).fetch(testTrack)
expect(fallbackResult?.source, .lyricsOVH, "service failure falls back to independent provider")
expect(fallbackResult?.lines.isEmpty, true, "plain fallback never becomes fake karaoke")
let disabled = FixtureTransport([response("", status: 503)])
do { _ = try await LyricsResolver(transport: disabled, cache: LyricCache()).fetch(testTrack, allowPlainFallback: false) } catch {}
expect(await disabled.calls().allSatisfy { $0.host != "api.lyrics.ovh" }, true, "disabled plain fallback sends no metadata to lyrics.ovh")
let cancellation = FixtureTransport([], cancel: true)
var cancelled = false
do { _ = try await LyricsResolver(transport: cancellation, cache: LyricCache()).fetch(testTrack) } catch is CancellationError { cancelled = true }
expect(cancelled, true, "cancelled requests propagate cancellation")
expect(await cancellation.calls().count, 1, "cancellation never starts another provider")
let special = FixtureTransport([response("", status: 503), response("", status: 503), response("", status: 404), response(#"{"lyrics":"Example"}"#)])
_ = try await LyricsResolver(transport: special, cache: LyricCache()).fetch(.init(title: "A/B?", artist: "AC/DC", album: "", duration: 200))
expect(await special.calls().last?.absoluteString.contains("AC%2FDC/A%2FB%3F"), true, "encode artist and title as individual URL segments")
let missing = FixtureTransport([])
expect(try await LyricsResolver(transport: missing, cache: LyricCache()).fetch(testTrack) == nil, true, "all providers missing returns honest empty result")
expect(ImportedLyrics.parse("[00:01]<00:01.00>Hidden tags", extension: "lrc") == nil, true, "unsupported enhanced LRC cannot leak timing markup")

let recoveredSearch = FixtureTransport([response("", status: 503), response("[" + timedRecord + "]")])
expect(try await LyricsResolver(transport: recoveredSearch, cache: LyricCache()).fetch(testTrack)?.timed, true, "search recovers timed lyrics after exact endpoint fails")
expect(await recoveredSearch.calls().last?.path, "/api/search", "server error no longer skips search")
let versionRecord = #"{"id":12,"trackName":"Song","artistName":"Artist","albumName":"Original album","duration":206,"syncedLyrics":"[00:01]Example"}"#
let versions = FixtureTransport([response("", status: 404), response("", status: 404), response("[" + versionRecord + "]"), response("[]"), response("", status: 404), response(#"{"lyrics":"Plain text"}"#)])
let versionResult = try await LyricsResolver(transport: versions, cache: LyricCache()).fetch(testTrack)
expect(versionResult?.timed, true, "nearby recording starts lyrics automatically")
expect(versionResult?.automaticMatch, true, "closest recording is labeled automatic")
expect(versionResult?.matchedDuration, 206, "automatic match retains provider duration")
expect(versionResult?.alternatives?.first?.duration, 206, "automatic match still offers version overrides")
expect(versionResult?.alternatives?.first?.document.manualMatch, true, "chosen timing labeled manual recording match")
let cacheFolder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
let cacheURL = cacheFolder.appendingPathComponent("lyrics.json")
let disk = LyricCache(storageURL: cacheURL)
await disk.put(testTrack, LyricDocument(lines: [.init(time: 1, text: "Cached")], source: .lrclib))
let reloadedCache = LyricCache(storageURL: cacheURL)
expect(await reloadedCache.read(testTrack, allowPlain: true)?.lines.first?.text, "Cached", "timed cache survives relaunch")
let negative = FixtureTransport([])
let negativeResolver = LyricsResolver(transport: negative, cache: LyricCache())
_ = try await negativeResolver.fetch(testTrack)
let initialCalls = await negative.calls().count
_ = try await negativeResolver.fetch(testTrack)
expect(await negative.calls().count, initialCalls, "missing tracks do not repeat failed requests on reconnect")
_ = try await negativeResolver.fetch(testTrack, bypassCache: true)
expect(await negative.calls().count > initialCalls, true, "explicit retry bypasses negative cache")
expect(await reloadedCache.read(testTrack, allowPlain: false)?.timed, true, "privacy toggle retains safe timed cache")
if FileManager.default.fileExists(atPath: "/tmp/afterglow-ophelia-search.json") {
    let fixture = try Data(contentsOf: URL(fileURLWithPath: "/tmp/afterglow-ophelia-search.json"))
    let opheliaTransport = FixtureTransport([response("", status: 404), response("", status: 404), .init(data: fixture, status: 200)])
    let ophelia = try await LyricsResolver(transport: opheliaTransport, cache: LyricCache()).fetch(.init(title: "The Fate of Ophelia", artist: "Taylor Swift", album: "The Life of a Showgirl", duration: 220), allowPlainFallback: false)
    expect(ophelia?.alternatives?.isEmpty, false, "real Ophelia response exposes alternate timed versions")
    expect(ophelia?.timed, true, "nearby real recording no longer requires explicit choice")
}

let throttled = FixtureTransport([response("", status: 429), response("", status: 404), response(#"{"lyrics":"Fallback"}"#)])
_ = try await LyricsResolver(transport: throttled, cache: LyricCache()).fetch(testTrack)
expect(await throttled.calls().filter { $0.host == "lrclib.net" }.count, 1, "rate limit avoids more requests to the same service")
let offlineTransport = FixtureTransport([])
let offlineResult = try await LyricsResolver(transport: offlineTransport, cache: reloadedCache).fetch(testTrack)
expect(offlineResult?.timed, true, "saved timed lyrics display without network")
expect(await offlineTransport.calls().isEmpty, true, "relaunch cache avoids all network requests")
let legacy = try JSONDecoder().decode(LyricDocument.self, from: Data(#"{"lines":[],"plainText":"Original import","source":"local","instrumental":false}"#.utf8))
expect(legacy.plainText, "Original import", "existing imported libraries survive schema update")
if CommandLine.arguments.contains("--live-ophelia") {
    let start = Date()
    let result = try await LyricsResolver(cache: LyricCache()).fetch(.init(title: "The Fate of Ophelia", artist: "Taylor Swift", album: "The Life of a Showgirl", duration: 220))
    print("LIVE Ophelia: source=\(result?.source.name ?? "none"), timed=\(result?.timed ?? false), alternatives=\(result?.alternatives?.count ?? 0), elapsed=\(Date().timeIntervalSince(start))")
}

func tone(_ frequency: Double) -> [Float] {
    (0..<4096).map { Float(sin(Double($0) * 2 * .pi * frequency / 48000) * 0.5) }
}
var lowFrequency = BeatAnalyzer(), highFrequency = BeatAnalyzer()
let lowBands = lowFrequency.process(samples: tone(100), sampleRate: 48000, at: 1).bars
let highBands = highFrequency.process(samples: tone(6000), sampleRate: 48000, at: 1).bars
let lowPeak = lowBands.indices.max(by: { lowBands[$0] < lowBands[$1] })!
let highPeak = highBands.indices.max(by: { highBands[$0] < highBands[$1] })!
expect(lowPeak < 10, true, "bass tone appears in lower spectrum bands")
expect(highPeak > 23, true, "treble tone appears in upper spectrum bands")
expect(highPeak > lowPeak + 12, true, "equalizer separates frequencies rather than time chunks")
let silentBands = highFrequency.process(samples: Array(repeating: 0, count: 4096), sampleRate: 48000, at: 2).bars
expect(silentBands.allSatisfy { $0 == 0 }, true, "silent audio has a flat spectrum")
var wave = WaveDynamics()
let strongFrame = BeatFrame(level: 0.9, pulse: 1, beatCount: 1, bars: Array(repeating: 0.8, count: 32), timestamp: 10)
wave.advance(at: 10, frame: strongFrame, live: true, playing: true, reducedMotion: false)
wave.advance(at: 10.033, frame: strongFrame, live: true, playing: true, reducedMotion: false)
expect(wave.bands[0] > 0 && wave.bands[0] < 0.8, true, "spectrum attack rises smoothly")
let pausedPhase = wave.phase, pausedBand = wave.bands[0]
wave.advance(at: 10.1, frame: .silent, live: true, playing: false, reducedMotion: false)
expect(wave.phase, pausedPhase, "pause freezes ribbon travel")
expect(wave.bands[0], pausedBand, "pause freezes spectrum bars")
for i in 0..<60 { wave.advance(at: 11 + Double(i) / 30, frame: strongFrame, live: true, playing: true, reducedMotion: false) }
expect(wave.bands.allSatisfy { $0 < 0.0001 }, true, "stale capture drains to silence instead of frozen fake beats")
let motionPhase = wave.phase
wave.advance(at: 20, frame: strongFrame, live: true, playing: true, reducedMotion: true)
expect(wave.phase, motionPhase, "reduced motion never advances ribbon phase")
var invalidWave = WaveDynamics()
let corruptFrame = BeatFrame(level: .nan, pulse: .infinity, beatCount: 0, bars: [.nan, .infinity], timestamp: 1)
invalidWave.advance(at: 1, frame: corruptFrame, live: true, playing: true, reducedMotion: false)
invalidWave.advance(at: 1.03, frame: corruptFrame, live: true, playing: true, reducedMotion: false)
expect(invalidWave.bands.allSatisfy(\.isFinite) && invalidWave.energy.isFinite, true, "nonfinite audio cannot corrupt visualizer geometry")

var lively = WaveDynamics()
lively.advance(at: 10, frame: strongFrame, live: true, playing: true, reducedMotion: false)
lively.advance(at: 10.05, frame: strongFrame, live: true, playing: true, reducedMotion: false)
let hitPeak = lively.peaks[0]
expect(lively.pulse > 0.9, true, "audio onset drives visualizer pulse")
let quietFrame = BeatFrame(level: 0, pulse: 0, beatCount: 1, bars: Array(repeating: 0, count: 32), timestamp: 10.1)
lively.advance(at: 10.1, frame: quietFrame, live: true, playing: true, reducedMotion: false)
expect(lively.peaks[0] >= lively.bands[0] && lively.peaks[0] <= hitPeak, true, "peak caps fall more slowly than spectrum bars")
let frozenPeak = lively.peaks, frozenPulse = lively.pulse
lively.advance(at: 10.2, frame: quietFrame, live: true, playing: false, reducedMotion: false)
expect(lively.peaks, frozenPeak, "pause freezes floating peak caps")
expect(lively.pulse, frozenPulse, "pause freezes beat glow")
var ambientWaves = WaveDynamics()
ambientWaves.advance(at: 1, frame: .silent, live: false, playing: true, reducedMotion: false)
ambientWaves.advance(at: 1.1, frame: .silent, live: false, playing: true, reducedMotion: false)
expect(ambientWaves.phase > 0.15, true, "ambient ribbons have clearly visible travel")
expect(ambientWaves.pulse, 0, "ambient movement does not fabricate detected beats")

let sceneLines: [LyricLine] = [.init(time: 2, text: "First", end: 4), .init(time: 4.1, text: "Second", end: 6),
    .init(time: 6, text: ""), .init(time: 8, text: "Third", end: 10)]
expect(LyricScene.resolve(lines: sceneLines, at: 4.05, duration: 12).lineIndex, 0, "tiny explicit-end gap keeps prior graph instead of flashing waves")
expect(LyricScene.resolve(lines: sceneLines, at: 4.1, duration: 12).lineIndex, 1, "next lyric appears at its exact timestamp")
expect(LyricScene.resolve(lines: sceneLines, at: 6, duration: 12).waveOpacity, 0, "instrumental fade begins without a flash")
expect(LyricScene.resolve(lines: sceneLines, at: 6.09, duration: 12).waveOpacity > 0.4, true, "sustained gap fades in curves")
expect(LyricScene.resolve(lines: sceneLines, at: 7, duration: 12).waveOpacity, 1, "sustained gap shows complete wave scene")
expect(LyricScene.resolve(lines: sceneLines, at: 7.95, duration: 12).waveOpacity < 0.25, true, "curves fade away before vocal onset")
expect(LyricScene.resolve(lines: sceneLines, at: 8, duration: 12).lineIndex, 3, "lyric returns without delayed crossfade")
expect(LyricScene.resolve(lines: sceneLines, at: 8, duration: 12).waveOpacity, 0, "waves never overlay returning lyrics")
expect(LyricScene.resolve(lines: sceneLines, at: 3, duration: 12).lineIndex, 0, "backward seek immediately resolves correct lyric")
expect(LyricScene.resolve(lines: sceneLines, at: 12, duration: 12).waveOpacity, 0, "end of track clears the scene")
expect(LyricScene.resolve(lines: sceneLines, at: .nan, duration: 12).waveOpacity, 0, "invalid scene clock cannot create a transition")
let tinyBlank: [LyricLine] = [.init(time: 0, text: "Before"), .init(time: 2, text: ""), .init(time: 2.2, text: "After")]
expect(LyricScene.resolve(lines: tinyBlank, at: 2.1, duration: 4).lineIndex, 0, "brief blank LRC entries never trigger a wave flash")
let joinedBlank: [LyricLine] = [.init(time: 0, text: "Before", end: 2), .init(time: 2, text: ""), .init(time: 2.2, text: ""), .init(time: 4, text: "After")]
expect(LyricScene.resolve(lines: joinedBlank, at: 2.21, duration: 5).waveOpacity, 1, "consecutive empty entries do not restart gap fades")
var continuousWave = WaveDynamics()
var lastPhase = 0.0, largestStep = 0.0
for i in 0...1800 {
    continuousWave.advance(at: Double(i) / 60, frame: .silent, live: false, playing: true, reducedMotion: false)
    largestStep = max(largestStep, abs(continuousWave.phase - lastPhase))
    lastPhase = continuousWave.phase
}
expect(continuousWave.phase > 40, true, "layered phase remains continuous beyond multiple cycles")
expect(largestStep < 0.03, true, "no 2pi phase wrap jump during thirty seconds of motion")

let collaboration = Track(title: "Song (with Guest)", artist: "Artist", album: "Album", duration: 200)
expect(RecordingMatch.title(collaboration.title), "song", "with-credit suffix normalizes without stripping recording version")
expect(RecordingMatch.artistsMatch(collaboration, candidate: "Artist, Guest"), true, "accept collaborator explicitly named in track metadata")
expect(RecordingMatch.artistsMatch(collaboration, candidate: "Artist, Stranger"), false, "reject uncredited collaborator")
expect(RecordingMatch.artistsMatch(collaboration, candidate: "Guest, Artist"), false, "reject a different lead artist")
expect(RecordingMatch.accepts(collaboration, title: "Song (Acoustic)", artist: "Artist, Guest", duration: 200), false, "collaboration normalization preserves version safety")
let featureTrack = Track(title: "Song (feat. Guest)", artist: "Artist", album: "Album", duration: 200)
let fullTitleRecord = #"{"trackName":"Song (feat. Guest)","artistName":"Artist, Guest","duration":200,"syncedLyrics":"[00:01]Fixture"}"#
let fullTitleTransport = FixtureTransport([response("", status: 404), response("", status: 404), response("[]"), response("[" + fullTitleRecord + "]")])
expect(try await LyricsResolver(transport: fullTitleTransport, cache: LyricCache()).fetch(featureTrack)?.timed, true, "full feature-title search recovers crowded results")
let fullTitleCalls = await fullTitleTransport.calls()
expect(URLComponents(url: fullTitleCalls[2], resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "album_name" && $0.value == "Album" }, true, "album-focused search avoids compilation crowding")
expect(URLComponents(url: fullTitleCalls[3], resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "track_name" && $0.value == featureTrack.title }, true, "secondary search retains full collaboration title")
if let fixture = try? Data(contentsOf: URL(fileURLWithPath: "/tmp/afterglow-charlie-2.json")) {
    let transport = FixtureTransport([response("", status: 503), .init(data: fixture, status: 200)])
    let result = try await LyricsResolver(transport: transport, cache: LyricCache()).fetch(.init(title: "We Don't Talk Anymore (feat. Selena Gomez)", artist: "Charlie Puth", album: "Nine Track Mind", duration: 212.096))
    expect(result?.timed, true, "real screenshot recording recovers timed lyrics from album search")
    expect(result?.manualMatch, false, "screenshot recovery obeys strict automatic matching")
}
if CommandLine.arguments.contains("--coverage") {
    let tracks = try JSONDecoder().decode([Track].self, from: Data(contentsOf: URL(fileURLWithPath: "/tmp/afterglow-coverage-tracks.json")))
    var report: [[String: Any]] = []
    for track in tracks {
        let cache = LyricCache()
        let resolver = LyricsResolver(cache: cache)
        let start = Date()
        do {
            let document = try await resolver.fetch(track)
            let seconds = Date().timeIntervalSince(start)
            let warm = Date()
            _ = try await resolver.fetch(track)
            let row: [String: Any] = ["title": track.title, "artist": track.artist, "duration": track.duration,
                "timed": document?.timed ?? false, "lines": document?.lines.count ?? 0,
                "alternatives": document?.alternatives?.count ?? 0, "source": document?.source.name ?? "none",
                "seconds": seconds, "cachedSeconds": Date().timeIntervalSince(warm)]
            report.append(row)
            print("COVERAGE \(track.title): \(document?.timed == true ? "timed" : "untimed/missing"), \(document?.lines.count ?? 0) lines, \(String(format: "%.2f", seconds))s")
        } catch { report.append(["title": track.title, "error": String(describing: error)]); print("COVERAGE \(track.title): service error") }
    }
    try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "output/motion-review/coverage-v26.json"))
}
expect(RecordingMatch.artistsMatch(collaboration, candidate: "Artist feat. Stranger"), false, "feature-artist syntax cannot bypass collaborator identity")
let recoveredVariant = FixtureTransport([response("", status: 503), response("", status: 503), response("[" + timedRecord + "]")])
expect(try await LyricsResolver(transport: recoveredVariant, cache: LyricCache()).fetch(testTrack)?.timed, true, "broad search survives an album-specific service failure")
let migrationURL = cacheFolder.appendingPathComponent("old-cache.json")
let oldTrack = try JSONSerialization.jsonObject(with: JSONEncoder().encode(testTrack))
let oldPlainDocument = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LyricDocument(plainText: "Old fallback", source: .lyricsOVH)))
let oldEntry: [String: Any] = ["track": oldTrack, "document": oldPlainDocument, "saved": Date().timeIntervalSinceReferenceDate, "accessed": Date().timeIntervalSinceReferenceDate]
try JSONSerialization.data(withJSONObject: [oldEntry]).write(to: migrationURL)
expect(await LyricCache(storageURL: migrationURL).read(testTrack, allowPlain: true) == nil, true, "old untimed decisions recheck after matching upgrade")
var oldTimedEntry = oldEntry
oldTimedEntry["document"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(LyricDocument(lines: [.init(time: 1, text: "Preserved")], source: .lrclib)))
try JSONSerialization.data(withJSONObject: [oldTimedEntry]).write(to: migrationURL)
expect(await LyricCache(storageURL: migrationURL).read(testTrack, allowPlain: true)?.timed, true, "old timed cache survives the matching upgrade")

var border = BorderMotion()
border.advance(at: 1, energy: 0, pulse: 0, playing: true, reducedMotion: false)
border.advance(at: 1.033, energy: 1, pulse: 1, playing: true, reducedMotion: false)
expect(border.glow > 0 && border.glow < 0.5, true, "border beat glow rises gently rather than flashing")
expect(border.progress > 0 && border.progress < 0.002, true, "track highlight moves slowly enough to stay secondary")
let borderProgress = border.progress, borderGlow = border.glow
border.advance(at: 2, energy: 1, pulse: 1, playing: false, reducedMotion: false)
expect(border.progress, borderProgress, "pause freezes border highlight")
expect(border.glow, borderGlow, "pause does not pump border brightness")
border.advance(at: 2.033, energy: 1, pulse: 1, playing: true, reducedMotion: true)
expect(border.progress, borderProgress, "reduced motion stops track movement")
for i in 0...1800 { border.advance(at: 3 + Double(i) / 30, energy: .nan, pulse: .infinity, playing: true, reducedMotion: false) }
expect(border.progress.isFinite && border.progress >= 0 && border.progress < 1, true, "border wraps safely through a full circuit")
expect(border.glow < 0.001, true, "border returns to dim baseline without audio")

let paddedBreak: [LyricLine] = [.init(time: 156.66, text: "Tell my mother I'm sorry", end: 420.51), .init(time: 420.51, text: "Returning words", end: 425)]
expect(LyricScene.resolve(lines: paddedBreak, at: 171, duration: 461.976).lineIndex, nil, "provider four-minute lyric hold yields instrumental scene")
expect(LyricScene.resolve(lines: paddedBreak, at: 171, duration: 461.976).waveOpacity, 1, "screenshot beat section displays the curves")
expect(LyricScene.resolve(lines: paddedBreak, at: 158, duration: 461.976).lineIndex, 0, "long-hold fallback preserves the actual lyric onset")
expect(LyricScene.resolve(lines: paddedBreak, at: 420.51, duration: 461.976).lineIndex, 1, "words return at next supplied timestamp")
let noteBreak: [LyricLine] = [.init(time: 0, text: "Earlier", end: 4), .init(time: 4, text: "♪", end: 60), .init(time: 60, text: "Later", end: 65)]
expect(LyricScene.resolve(lines: noteBreak, at: 12, duration: 70).lineIndex, nil, "music-note markers are instrumental, never frozen lyric nodes")
expect(LyricScene.resolve(lines: noteBreak, at: 12, duration: 70).waveOpacity, 1, "musical-note interlude runs beat visualization")
expect(LyricScene.isVocal(.init(time: 0, text: "[Instrumental]")), false, "explicit instrumental labels become beat scenes")
expect(LyricScene.isVocal(.init(time: 0, text: "The music keeps us alive")), true, "actual words about music remain lyrics")
let genuineLong: [LyricLine] = [.init(time: 0, text: "A long timed passage", end: 50, words: [.init(text: "passage", time: 40, end: 50)]), .init(time: 60, text: "Next")]
expect(LyricScene.resolve(lines: genuineLong, at: 42, duration: 70).lineIndex, 0, "real word timestamps are never cut by sparse-line fallback")
let ordinaryHold: [LyricLine] = [.init(time: 0, text: "Sustained note", end: 25), .init(time: 25, text: "Next")]
expect(LyricScene.resolve(lines: ordinaryHold, at: 24, duration: 30).lineIndex, 0, "ordinary sustained lyric holds are preserved")

// Async polling must not let an old reply rewind the clock or change playback state.
var orderedClock = PlaybackClock()
orderedClock.sample(position: 10, playing: true, sampledAt: 100, receivedAt: 100)
orderedClock.sample(position: 1, playing: false, sampledAt: 99, receivedAt: 101)
expect(orderedClock.position(at: 102), 12, "out-of-order player replies cannot rewind or pause playback")
orderedClock.sample(position: 2, playing: false, sampledAt: 99, receivedAt: 102, force: true)
expect(orderedClock.position(at: 105), 2, "new-track forced samples can reset the playback clock")
let shortEstimate = LyricLine(time: 0, text: "one two three four", end: 4)
expect(LyricTiming.activeWord(in: shortEstimate, at: 3.5, estimated: true, nextLineTime: 30), 3,
       "opt-in estimates respect explicit line ends before long instrumental gaps")
expect(LyricTiming.activeWord(in: shortEstimate, at: 3.5, estimated: false, nextLineTime: 30), nil,
       "accurate line mode never fabricates word timestamps")
let sampleBands = (0..<32).map { Double($0) / 31 }
let mesh = RibbonMesh.make(width: 1440, height: 440, phase: 9.25, bands: sampleBands,
                           energy: 0.4, pulse: 0.2, live: true, reducedMotion: false)
expect(mesh.ribbons.count, 17, "optimized wave retains all seventeen ribbons")
expect(mesh.ribbons.allSatisfy { $0.first!.x == 0 && $0.last!.x == 1440 }, true,
       "every optimized ribbon reaches both display edges")
expect(mesh.ribbons.flatMap { $0 }.allSatisfy { $0.y >= 0 && $0.y <= 440 }, true,
       "live wave mesh stays within its visual bounds")
func referenceWaveY(_ x: Double, _ ribbon: Int) -> Double {
    func amplitude(_ x: Double) -> Double {
        let position = min(1, max(0, x)) * 31
        let left = Int(position), right = min(31, left + 1)
        return sampleBands[left] * (1 - position + Double(left)) + sampleBands[right] * (position - Double(left))
    }
    let layer = Double(ribbon - 8), phase = 9.25
    let local = (amplitude(x - 0.035) + amplitude(x) + amplitude(x + 0.035)) / 3
    let activity = min(1, local * 0.85 + 0.4 * 0.4 + 0.2 * 0.15)
    let wave = sin(x * 3.2 * .pi - phase + layer * 0.13) + 0.38 * sin(x * 6.4 * .pi + phase * 0.8 + layer * 0.09)
    let fan = sin(x * .pi) * layer * (0.05 + 0.055 * sin(x * 2 * .pi + phase * 0.55))
    return 220 + tanh((wave * 1.05 + fan) * activity) * 440 * 0.46
}
let geometryError = mesh.ribbons.enumerated().flatMap { index, points in
    points.map { abs($0.y - referenceWaveY($0.x / 1440, index)) }
}.max() ?? 0
expect(geometryError < 0.000001, true, "optimized wave preserves original geometry at each sample")
let tip = mesh.point(at: 0.5, ribbon: 8)
expect(abs(tip.x - 720) < 0.000001 && abs(tip.y - mesh.ribbons[8][72].y) < 0.000001, true,
       "traveling highlights follow the rendered ribbon path")
let badMesh = RibbonMesh.make(width: .infinity, height: .nan, phase: .infinity, bands: [.nan],
                              energy: .infinity, pulse: .nan, live: true, reducedMotion: false)
expect(badMesh.ribbons.flatMap { $0 }.allSatisfy { $0.x.isFinite && $0.y.isFinite }, true,
       "invalid wave inputs never produce nonfinite geometry")
let quietMeshA = RibbonMesh.make(width: 720, height: 300, phase: 0, bands: [], energy: 0, pulse: 0, live: true, reducedMotion: true)
let quietMeshB = RibbonMesh.make(width: 720, height: 300, phase: 50, bands: sampleBands, energy: 1, pulse: 1, live: true, reducedMotion: true)
expect(quietMeshA.ribbons, quietMeshB.ribbons, "reduced-motion wave geometry remains static")

// Independent timed fallback, matching, parsing and privacy regression checks.
let enhanced = "[00:01.00]<00:01.00>Hello <00:01.50>world<00:02.00>"
let enhancedLines = EnhancedLRC.parse(enhanced)
expect(enhancedLines.first?.text, "Hello world", "enhanced markup never appears in lyric text")
expect(enhancedLines.first?.words.count, 2, "Karalyr retains supplied word timestamps")
expect(enhancedLines.first?.words.last?.end, 2, "trailing enhanced timestamp bounds final word")
expect(EnhancedLRC.parse("[00:01]<00:02>One <00:01>two").first?.words.isEmpty, true, "reject reversed word timestamps")
expect(EnhancedLRC.parse("[00:01]Prefix <00:02>word").first?.words.isEmpty, true, "partial word timing does not highlight mismatched text")
expect(EnhancedLRC.parse("[00:01]<00:01>One <00:05>two\n[00:03]Next").first?.words.isEmpty, true, "word timings cannot cross next line")
let karalyrRecord = #"{"trackName":"Song","artistName":"Artist","duration":200,"syncedLyrics":"[00:01]<00:01>Hello <00:02>world"}"#
let timedBackup = FixtureTransport([response("", status: 429), response(karalyrRecord)])
let backupCache = LyricCache()
let backupResult = try await LyricsResolver(transport: timedBackup, cache: backupCache).fetch(testTrack)
expect(backupResult?.source, .karalyr, "LRCLIB failure recovers timed lyrics from Karalyr")
expect(backupResult?.lines.first?.words.count, 2, "backup uses real word timings")
expect(await timedBackup.calls().last?.host, "karalyr.com", "backup calls independent free provider")
expect(await backupCache.read(testTrack, allowPlain: true, allowTimedFallback: false) == nil, true, "disabled timed fallback excludes its cached lyrics")
let wrongBackup = FixtureTransport([response("", status: 429), response(karalyrRecord.replacingOccurrences(of: #""duration":200"#, with: #""duration":210"#)), response(#"{"lyrics":"Plain backup"}"#)])
expect(try await LyricsResolver(transport: wrongBackup, cache: LyricCache()).fetch(testTrack)?.source, .lyricsOVH, "wrong recording in timed backup falls through to plain lyrics")
let noBackups = FixtureTransport([])
_ = try await LyricsResolver(transport: noBackups, cache: LyricCache()).fetch(testTrack, allowPlainFallback: false, allowTimedFallback: false)
expect(await noBackups.calls().allSatisfy { $0.host == "lrclib.net" }, true, "both backups disabled sends metadata only to LRCLIB")
let primaryOnly = FixtureTransport([response(timedRecord)])
_ = try await LyricsResolver(transport: primaryOnly, cache: LyricCache()).fetch(testTrack)
expect(await primaryOnly.calls().count, 1, "primary success avoids every fallback")

expect(EnhancedLRC.parse("[offset:100]\n[00:01]<00:01>Hello").first?.words.first?.time, 0.9, "enhanced word and line offsets agree")
expect(EnhancedLRC.parse("[offset:999999999999999999999999999999]\n[00:01]Hello").isEmpty, true, "oversized enhanced offset is safely rejected")
let plainPrimary = #"{"trackName":"Song","artistName":"Artist","duration":200,"plainLyrics":"Primary plain"}"#
let upgradePlain = FixtureTransport([response(plainPrimary), response(plainPrimary), response("[]"), response("[]"), response(karalyrRecord)])
expect(try await LyricsResolver(transport: upgradePlain, cache: LyricCache()).fetch(testTrack)?.source, .karalyr, "timed backup takes precedence over primary untimed lyrics")
let backupRateLimit = FixtureTransport([response("", status: 429), response("", status: 429), response(#"{"lyrics":"Plain text"}"#)])
expect(try await LyricsResolver(transport: backupRateLimit, cache: LyricCache()).fetch(testTrack)?.source, .lyricsOVH, "backup rate limit still allows untimed provider")
expect(await backupRateLimit.calls().filter { $0.host == "karalyr.com" }.count, 1, "Karalyr rate limit stops same-provider retries")

let closestRecord = versionRecord.replacingOccurrences(of: "206", with: "204")
let autoVersions = FixtureTransport([response("", status: 404), response("", status: 404),
    response("[" + versionRecord + "," + closestRecord + "]"), response("[]"), response("", status: 404)])
let automatic = try await LyricsResolver(transport: autoVersions, cache: LyricCache()).fetch(testTrack)
expect(automatic?.matchedDuration, 204, "automatically select the nearest duration")
expect(automatic?.lines.first?.time, 1, "automatic fallback never stretches or shifts provider timestamps")
expect(await autoVersions.calls().contains { $0.host == "api.lyrics.ovh" }, false, "nearby timed lyrics take priority over untimed fallback")
let exactBackup = FixtureTransport([response("", status: 404), response("", status: 404),
    response("[" + versionRecord + "]"), response("[]"), response(karalyrRecord)])
expect(try await LyricsResolver(transport: exactBackup, cache: LyricCache()).fetch(testTrack)?.source, .karalyr,
       "exact independent provider is preferred over a nearby recording")
let distantVersion = versionRecord.replacingOccurrences(of: "206", with: "216")
let distant = FixtureTransport([response("", status: 404), response("", status: 404),
    response("[" + distantVersion + "]"), response("[]"), response("", status: 404)])
let distantResult = try await LyricsResolver(transport: distant, cache: LyricCache()).fetch(testTrack)
expect(distantResult?.timed, false, "large recording difference still requires explicit choice")
expect(distantResult?.alternatives?.isEmpty, false, "distant versions remain available for manual override")
expect(RecordingMatch.compatibleVersion(testTrack, candidateAlbum: "Song (Stripped)"), false,
       "automatic fallback rejects a different performance disclosed in album metadata")
let shortTrack = Track(title: "Song", artist: "Artist", album: "Deluxe", duration: 30)
let shortVersion = versionRecord.replacingOccurrences(of: "206", with: "36")
let shortTransport = FixtureTransport([response("", status: 404), response("", status: 404),
    response("[" + shortVersion + "]"), response("[]"), response("", status: 404)])
expect(try await LyricsResolver(transport: shortTransport, cache: LyricCache()).fetch(shortTrack)?.timed, false,
       "automatic duration tolerance scales down for short tracks")
let roundTripAutomatic = try JSONDecoder().decode(LyricDocument.self, from: JSONEncoder().encode(automatic!))
expect(roundTripAutomatic.automaticMatch, true, "automatic provenance survives cache encoding")
expect(legacy.automaticMatch == nil, true, "old imports decode without automatic match metadata")

print("ALL \(checks) CHECKS PASSED")
