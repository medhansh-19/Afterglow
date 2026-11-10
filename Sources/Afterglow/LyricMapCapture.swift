import AfterglowCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A view-local snapshot preserves the displayed graph geometry and highlighted word.
/// It reads only Afterglow's own view, without capturing another app or the desktop.
struct LyricMapCaptureAnchor: NSViewRepresentable {
  let panels: DisplayPanels
  let track: Track?
  func makeNSView(context: Context) -> NSView { NSView() }
  func updateNSView(_ view: NSView, context: Context) {
    panels.captureLyricMap = { [weak view] in
      guard let view, view.window?.isVisible == true, panels.presented == nil,
            let root = view.window?.contentView, let track,
            view.bounds.width > 0, view.bounds.height > 0 else { return nil }
      root.layoutSubtreeIfNeeded()
      let rect = view.convert(view.bounds, to: root).intersection(root.bounds)
      guard !rect.isEmpty, let bitmap = root.bitmapImageRepForCachingDisplay(in: rect) else { return nil }
      root.cacheDisplay(in: rect, to: bitmap)
      let image = NSImage(size: rect.size)
      image.addRepresentation(bitmap)
      let artwork = LyricMapCaptureArtwork(image: image, track: track, size: rect.size)
      let renderer = ImageRenderer(content: artwork)
      renderer.scale = view.window?.backingScaleFactor ?? 2
      guard let cg = renderer.cgImage,
            let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { return nil }
      return LyricMapCapture(png: png, title: track.title)
    }
  }
}

struct LyricMapCapture {
  let png: Data
  let title: String
  var image: NSImage? { NSImage(data: png) }
}

struct LyricMapCaptureArtwork: View {
  let image: NSImage
  let track: Track
  let size: CGSize
  var body: some View {
    VStack(spacing: 0) {
      Image(nsImage: image).resizable().frame(width: size.width, height: size.height)
      HStack(alignment: .bottom, spacing: 24) {
        VStack(alignment: .leading, spacing: 6) {
          Text(track.title).font(.system(size: 18, weight: .medium, design: .rounded)).lineLimit(2)
          Text(track.artist).font(.system(size: 13)).foregroundStyle(Theme.secondary).lineLimit(2)
        }
        Spacer(minLength: 12)
        Text("AFTERGLOW").font(.system(size: 11, weight: .medium, design: .rounded)).tracking(3)
      }.padding(28).frame(width: size.width, alignment: .leading)
    }.foregroundStyle(Theme.text).background(Theme.background)
      .environment(\.colorScheme, .dark)
  }
}

struct LyricMapCaptureView: View {
  @ObservedObject var panels: DisplayPanels
  let dismiss: () -> Void
  @State private var message: String?
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Text("Share lyric map").font(.title2)
        Spacer()
        Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
      }
      if let capture = panels.lyricMapCapture, let image = capture.image {
        Image(nsImage: image).resizable().scaledToFit().frame(maxHeight: 360)
          .accessibilityLabel("Captured lyric map for \(capture.title), with Afterglow branding")
        HStack {
          LyricMapShareButton(image: image, onShared: dismiss, onError: { message = $0 })
          Button("Save PNG…") { save(capture) }
          Button("Copy Image") {
            NSPasteboard.general.clearContents()
            if NSPasteboard.general.setData(capture.png, forType: .png) { dismiss() }
            else { message = "Couldn’t copy the image. Try Save PNG." }
          }
        }
        Text("Captured exactly as displayed. Choose a destination in the macOS share menu.")
          .font(.caption).foregroundStyle(.secondary)
      } else {
        Text("The lyric map couldn’t be captured. Close this preview and try again while lyrics are visible.")
          .foregroundStyle(Theme.secondary)
      }
      if let message { Text(message).font(.caption).foregroundStyle(Theme.amber) }
    }.padding(26).frame(width: 640).preferredColorScheme(.dark)
      .onExitCommand { dismiss() }
  }
  private func save(_ capture: LyricMapCapture) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = capture.title.replacingOccurrences(of: "/", with: "-") + " — Afterglow.png"
    panels.presentCaptureSavePanel(panel) { response in
      guard response == .OK, let url = panel.url else { return }
      do { try capture.png.write(to: url, options: .atomic); dismiss() }
      catch { message = "Couldn’t save here. Choose another folder." }
    }
  }
}

/// Retains the picker and anchors it to a live native control. Opening the menu never sends an image.
struct LyricMapShareButton: NSViewRepresentable {
  let image: NSImage
  let onShared: () -> Void
  let onError: (String) -> Void
  func makeCoordinator() -> Coordinator {
    Coordinator(image: image, onShared: onShared, onError: onError)
  }
  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(title: "Share…", target: context.coordinator, action: #selector(Coordinator.share(_:)))
    button.bezelStyle = .rounded
    button.setAccessibilityLabel("Share lyric map")
    // Present only after the preview has attached to its window.
    context.coordinator.schedulePresentation(button)
    return button
  }
  func updateNSView(_ view: NSButton, context: Context) {
    context.coordinator.image = image
    context.coordinator.onShared = onShared
    context.coordinator.onError = onError
  }
  @MainActor final class Coordinator: NSObject, @preconcurrency NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    var image: NSImage
    var onShared: () -> Void
    var onError: (String) -> Void
    private var picker: NSSharingServicePicker?
    init(image: NSImage, onShared: @escaping () -> Void, onError: @escaping (String) -> Void) {
      self.image = image; self.onShared = onShared; self.onError = onError
    }
    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
      delegateFor sharingService: NSSharingService) -> (any NSSharingServiceDelegate)? {
      self
    }
    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { onShared() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
      onError("Sharing didn’t finish. Try again or save the image.")
    }
    func schedulePresentation(_ button: NSButton) {
      Task { @MainActor [weak self, weak button] in
        for _ in 0..<20 {
          try? await Task.sleep(for: .milliseconds(50))
          guard let self, let button else { return }
          if button.window?.isVisible == true { self.share(button); return }
        }
      }
    }
    @objc func share(_ sender: NSButton) {
      guard sender.window != nil else { return }
      picker = NSSharingServicePicker(items: [image])
      picker?.delegate = self
      picker?.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
  }
}
