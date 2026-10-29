import SwiftUI
import AppKit
import AfterglowCore

@main struct LongGapRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let lines: [LyricLine] = [.init(time: 156.66, text: "Tell my mother I'm sorry", end: 420.51),
                                 .init(time: 420.51, text: "Returning lyric", end: 425)]
        let view = Constellation(lines: lines, position: 171, duration: 461.976, tint: .gray,
                                 reduceMotion: false, estimatedWords: true, beatFrame: .silent,
                                 liveBeats: false, playing: false, waveWidth: 1200)
            .frame(width: 1200, height: 320).background(.black).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
