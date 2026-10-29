import SwiftUI
import AppKit
import AfterglowCore

@main struct LayoutRender {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let width = Double(CommandLine.arguments[2]) ?? 1440
        let height = Double(CommandLine.arguments[3]) ?? 860
        let tint = Color(red: 0.72, green: 0.61, blue: 0.84)
        let content = ZStack {
            Theme.background
            GlowFrame(tint: tint, active: true)
            VStack {
                HStack { Text("afterglow").font(.system(size: 17, weight: .medium, design: .rounded)).tracking(1).foregroundStyle(tint); Spacer() }
                Spacer(minLength: 8)
                Constellation(lines: [.init(time: 0, text: "Just let it happen let it happen", end: 10)],
                    position: 1, duration: 15, tint: tint, reduceMotion: true, estimatedWords: true,
                    beatFrame: .silent, liveBeats: false, playing: false, waveWidth: width)
                    .frame(height: max(180, min(440, height * 0.48)))
                Color.clear.frame(height: 38)
                Spacer(minLength: 8)
                Text("Afterglow · layout preview").foregroundStyle(tint).padding(.bottom, 45)
            }.padding(.horizontal, max(32, width * 0.028)).padding(.top, 26).padding(.bottom, 35)
        }.frame(width: width, height: height).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
