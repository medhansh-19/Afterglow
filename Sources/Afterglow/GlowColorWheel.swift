import AppKit
import SwiftUI

/// An in-place hue/saturation disk; native sliders provide keyboard alternatives to dragging.
struct GlowColorWheel: View {
  @Binding var color: Color
  @State private var hue = 0.58
  @State private var saturation = 0.6
  @State private var brightness = 1.0
  @State private var pendingColor: Color?
  @State private var pendingBinding: Binding<Color>?
  @State private var colorUpdate: Task<Void, Never>?
  @State private var lastPublication = 0.0
  @State private var publishedHex: String?
  private let diameter = 180.0

  var body: some View {
    VStack(spacing: 14) {
      ZStack {
        Circle().fill(AngularGradient(colors: (0...6).map { Color(hue: Double($0) / 6, saturation: 1, brightness: 1) },
                                       center: .center))
        Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center,
                                     startRadius: 0, endRadius: diameter / 2))
        Circle().fill(.black.opacity(1 - brightness))
        Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1)
        Circle().fill(Color(hue: hue, saturation: saturation, brightness: brightness))
          .frame(width: 14, height: 14)
          .overlay(Circle().strokeBorder(.white, lineWidth: 2))
          .shadow(color: .black.opacity(0.6), radius: 2)
          .position(x: diameter / 2 + cos(hue * 2 * .pi) * saturation * (diameter / 2 - 2),
                    y: diameter / 2 + sin(hue * 2 * .pi) * saturation * (diameter / 2 - 2))
      }
      .frame(width: diameter, height: diameter).contentShape(Circle())
      .gesture(DragGesture(minimumDistance: 0).onChanged { value in
        let x = value.location.x - diameter / 2, y = value.location.y - diameter / 2
        let angle = atan2(y, x) / (2 * .pi)
        hue = angle < 0 ? angle + 1 : angle
        saturation = min(1, hypot(x, y) / (diameter / 2 - 2))
        updateColor()
      }.onEnded { _ in publishColor() })
      .accessibilityHidden(true)
      channel("Hue", value: $hue, display: "\(Int(hue * 359))°")
      channel("Saturation", value: $saturation, display: "\(Int(saturation * 100))%")
      channel("Brightness", value: $brightness, display: "\(Int(brightness * 100))%")
    }
    .onAppear { synchronize(color) }
    .onChange(of: color) { _, value in
      if GlowColorLibrary.hex(from: value) == publishedHex {
        if pendingColor == nil { synchronize(value) }
        return
      }
      // External color/hex changes take precedence over a pending drag sample.
      colorUpdate?.cancel(); colorUpdate = nil; pendingColor = nil; pendingBinding = nil
      synchronize(value)
    }
    .onDisappear { publishColor() }
  }

  private func channel(_ label: String, value: Binding<Double>, display: String) -> some View {
    VStack(spacing: 4) {
      HStack {
        Text(label)
        Spacer()
        Text(display).monospacedDigit()
      }.font(.system(size: 11)).foregroundStyle(.secondary)
      Slider(value: Binding(get: { value.wrappedValue }, set: { new in
        value.wrappedValue = new
        updateColor()
      }), in: 0...1, onEditingChanged: { editing in if !editing { publishColor() } }) { Text(label) }
        .labelsHidden().tint(Color(hue: hue, saturation: 0.65, brightness: 0.9))
    }
  }

  private func updateColor() {
    pendingColor = Color(hue: hue, saturation: saturation, brightness: brightness)
    pendingBinding = _color
    let delay = 1.0 / 15 - (ProcessInfo.processInfo.systemUptime - lastPublication)
    if delay <= 0 { publishColor(); return }
    guard colorUpdate == nil else { return }
    colorUpdate = Task { @MainActor in
      do { try await Task.sleep(for: .seconds(delay)) } catch { return }
      publishColor()
    }
  }
  private func publishColor() {
    colorUpdate?.cancel(); colorUpdate = nil
    guard let value = pendingColor else { return }
    let destination = pendingBinding ?? _color
    pendingColor = nil
    pendingBinding = nil
    lastPublication = ProcessInfo.processInfo.systemUptime
    publishedHex = GlowColorLibrary.hex(from: value)
    // A queued sample belongs to the song/collection that was being edited.
    if destination.wrappedValue != value { destination.wrappedValue = value }
  }
  private func synchronize(_ value: Color) {
    guard let rgb = NSColor(value).usingColorSpace(.sRGB) else { return }
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    rgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    // Preserve the chosen hue at white, and hue/saturation at black.
    if b > 0.0001 {
      if s > 0.0001 { hue = Double(h) }
      saturation = Double(s)
    }
    brightness = Double(b)
  }
}
