// Visual check: compile with Theme.swift, WelcomeView.swift, GlowFrame.swift and BorderMotion object.
import AppKit
import SwiftUI

enum PlayerSource { case spotify, music }

@main struct WelcomeRender {
  @MainActor static func main() throws {
    _ = NSApplication.shared
    let width = Double(CommandLine.arguments[2]) ?? 1120
    let height = Double(CommandLine.arguments[3]) ?? 740
    let error = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : nil
    let view = WelcomeView(error: error, connect: { _ in }, demo: {})
      .frame(width: width, height: height)
      .environment(\.colorScheme, .dark)
      .environment(\.scenePhase, .active)
    // AppKit hosting is required: ImageRenderer omits native ScrollView contents.
    let host = NSHostingView(rootView: view)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
      styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    window.orderBack(nil)
    RunLoop.main.run(until: Date(timeIntervalSinceNow: Double(ProcessInfo.processInfo.environment["CAPTURE_DELAY"] ?? "2.2") ?? 2.2))
    host.layoutSubtreeIfNeeded()
    guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)
    else { throw CocoaError(.fileWriteUnknown) }
    host.cacheDisplay(in: host.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:])
    else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
  }
}
