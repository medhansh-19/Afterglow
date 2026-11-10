import SwiftUI

@MainActor
final class DisplayPanels: ObservableObject {
  enum Panel: String, Identifiable {
    case library, timing, beats, wallpaper, cards, clock, collections
    var id: String { rawValue }
  }
  @Published var presented: Panel?
  @Published private(set) var lyricMapCapture: LyricMapCapture?
  private var captureWindow: NSPanel?
  var captureLyricMap: (() -> LyricMapCapture?)?

  func showCapturedMap(_ capture: LyricMapCapture) {
    lyricMapCapture = capture
    captureWindow?.close()
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 640, height: 520),
      styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Afterglow · Share lyric map"
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: LyricMapCaptureView(panels: self,
      dismiss: { [weak window] in window?.close() }))
    window.center()
    captureWindow = window
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func presentCaptureSavePanel(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
    guard let window = captureWindow, window.isVisible else { completion(.cancel); return }
    panel.beginSheetModal(for: window, completionHandler: completion)
  }

  func captureMap() {
    guard let captured = captureLyricMap?() else { return }
    showCapturedMap(captured)
  }
}
