import AfterglowCore
import AppKit
import SwiftUI

@main struct KeepsakeChecks {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "afterglow-checks-" + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: root) }
    defaults.set("Blue", forKey: "afterglow.tint")
    let first = Track(title: "First", artist: "Artist", album: "Album", duration: 180)
    let second = Track(title: "Second", artist: "Artist", album: "Album", duration: 180)
    let appearance = WallpaperAppearance(defaults: defaults, folder: root)
    appearance.activateScene(for: first)
    defaults.set("Rose", forKey: "afterglow.tint")
    appearance.saveScene()
    defaults.set("Mint", forKey: "afterglow.tint")
    appearance.activateScene(for: second)
    precondition(defaults.string(forKey: "afterglow.tint") == "Rose", "unsaved song restores defaults captured when scene saved")
    appearance.activateScene(for: first)
    precondition(defaults.string(forKey: "afterglow.tint") == "Rose", "saved scene returns")
    defaults.set("Violet", forKey: "afterglow.tint")
    appearance.saveScene()
    let recovered = WallpaperAppearance(defaults: defaults, folder: root)
    precondition(defaults.string(forKey: "afterglow.tint") == "Rose", "launch recovers baseline before active song")
    recovered.activateScene(for: first)
    precondition(defaults.string(forKey: "afterglow.tint") == "Violet", "updated scene persists across launches")
    recovered.activateScene(for: nil)
    precondition(defaults.string(forKey: "afterglow.tint") == "Rose", "disconnect restores baseline")
    recovered.activateScene(for: first)
    recovered.removeScene()
    precondition(!recovered.hasScene && defaults.string(forKey: "afterglow.tint") == "Rose", "remove restores baseline")
    defaults.set("Blue", forKey: "afterglow.tint")
    defaults.set("Star", forKey: "afterglow.marker")
    recovered.saveScene()
    recovered.activateScene(for: second)
    defaults.set("Amber", forKey: "afterglow.tint")
    defaults.set("Dot", forKey: "afterglow.marker")
    recovered.saveScene()
    recovered.activateScene(for: first)
    precondition(defaults.string(forKey: "afterglow.tint") == "Blue" && defaults.string(forKey: "afterglow.marker") == "Star", "first scene remains independent")
    recovered.activateScene(for: second)
    precondition(defaults.string(forKey: "afterglow.tint") == "Amber" && defaults.string(forKey: "afterglow.marker") == "Dot", "second scene restores its own style")
    recovered.activateScene(for: nil)
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    for (name, text) in [("normal", "When the night turns quiet\nI can hear the stars again"),
                         ("maximum", String(repeating: "夜空 shines ✨ softly in the dark — ", count: 8).prefix(280).description)] {
      let excerpt = SavedLyricExcerpt(track: Track(title: "A song with a long title that wraps across two lines", artist: "Artist · アーティスト", album: "The album under a midnight sky", duration: 200), text: text, color: GlowColor(red: 0.3, green: 0.8, blue: 0.7))
      let renderer = ImageRenderer(content: LyricCardArtwork(excerpt: excerpt)); renderer.scale = 2
      let cg = renderer.cgImage!
      precondition(cg.width == 1080 && cg.height == 1350)
      let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
      try data.write(to: output.appendingPathComponent("lyric-card-\(name).png"))
    }
    print("PASS scene restoration, persistence, crash recovery, removal and 1080×1350 card rendering")
  }
}

// Match the existing graph marker without compiling the animated graph for this isolated check.
struct Diamond: Shape {
  func path(in rect: CGRect) -> Path {
    Path { p in
      p.move(to: CGPoint(x: rect.midX, y: rect.minY))
      p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
      p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
      p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
      p.closeSubpath()
    }
  }
}
