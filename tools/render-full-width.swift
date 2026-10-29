import SwiftUI
import AppKit
import AfterglowCore

@main struct FullWidthRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let width = Double(CommandLine.arguments[2]) ?? 1200
        let content = ZStack {
            Color.black
            Constellation(lines: [.init(time: 0, text: ""), .init(time: 10, text: "Next lyric")],
                          position: 5, duration: 15, tint: .gray, reduceMotion: false,
                          estimatedWords: false, beatFrame: .silent, liveBeats: false, playing: false,
                          waveWidth: width)
                .frame(width: min(800, width - 100), height: 300)
        }.frame(width: width, height: 300).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
