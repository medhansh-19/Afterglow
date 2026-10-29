import SwiftUI
import AppKit
import AfterglowCore

@main struct MotionRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let content = InstrumentalView(frame: .silent, live: false, playing: true,
                                      tint: .gray, reduceMotion: false)
            .frame(width: 1100, height: 320).background(.black)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
