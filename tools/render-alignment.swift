import AppKit
import SwiftUI
import AfterglowCore

@main struct AlignmentRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let width = Double(CommandLine.arguments[2]) ?? 1470
        let height = Double(CommandLine.arguments[3]) ?? 900
        let text = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "This love has taken its toll on me"
        let content = ZStack {
            Theme.background
            Constellation(lines: [.init(time: 0, text: text, end: 10)],
                          position: 9, duration: 12, tint: .red, reduceMotion: true,
                          estimatedWords: true, beatFrame: .silent, liveBeats: false, playing: false,
                          waveWidth: width)
                .frame(width: min(1000, width - max(64, width * 0.18)),
                       height: max(180, min(440, height * 0.48)))
        }.frame(width: width, height: height).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
