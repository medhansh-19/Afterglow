import SwiftUI
import AppKit
import AfterglowCore

@main struct TransitionRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let lines: [LyricLine] = [.init(time: 0, text: "Keep a little light", end: 2),
            .init(time: 2.1, text: "Across the quiet sky", end: 4), .init(time: 4, text: ""),
            .init(time: 6, text: "Let the words return", end: 8)]
        let scenes: [(String, Double)] = [("Short gap: graph retained", 2.05), ("Instrumental gap", 5),
            ("Just before vocal onset", 5.98), ("Vocal onset: graph returns", 6)]
        let content = VStack(spacing: 12) {
            ForEach(scenes.indices, id: \.self) { i in
                VStack(alignment: .leading) {
                    Text(scenes[i].0).font(.system(size: 14)).foregroundStyle(.gray)
                    Constellation(lines: lines, position: scenes[i].1, duration: 8, tint: .gray,
                                  reduceMotion: true, estimatedWords: false, beatFrame: .silent,
                                  liveBeats: false, playing: false).frame(width: 800, height: 170)
                }
            }
        }.padding(22).background(.black).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1.5
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
