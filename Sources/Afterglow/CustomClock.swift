import AfterglowCore
import AppKit
import SwiftUI

enum ClockStyle: String, CaseIterable, Identifiable {
  case minimal = "Minimal", flip = "Flip", rounded = "Rounded", glass = "Glass"
  case ring = "Ring", analog = "Analog", classic = "Classic"
  var id: String { rawValue }
  var analogFace: Bool { [.ring, .analog, .classic].contains(self) }
}

enum ClockPreferences {
  static func read(from d: UserDefaults = .standard) -> ClockAppearance {
    ClockAppearance(style: d.string(forKey: "afterglow.clockStyle") ?? "Minimal",
      color: d.string(forKey: "afterglow.clockColor") ?? "Off-white",
      followsLyrics: d.object(forKey: "afterglow.clockFollowLyrics") as? Bool ?? false,
      format: d.string(forKey: "afterglow.clockFormat") ?? "System",
      showsSeconds: d.bool(forKey: "afterglow.clockSeconds"),
      showsDate: d.object(forKey: "afterglow.clockDate") as? Bool ?? true,
      scale: d.object(forKey: "afterglow.clockSize") as? Double ?? 1)
  }
  static func write(_ value: ClockAppearance, to d: UserDefaults = .standard) {
    d.set(value.style, forKey: "afterglow.clockStyle")
    d.set(value.color, forKey: "afterglow.clockColor")
    d.set(value.followsLyrics, forKey: "afterglow.clockFollowLyrics")
    d.set(value.format, forKey: "afterglow.clockFormat")
    d.set(value.showsSeconds, forKey: "afterglow.clockSeconds")
    d.set(value.showsDate, forKey: "afterglow.clockDate")
    d.set(value.scale, forKey: "afterglow.clockSize")
  }
}

struct LiveClockDisplay: View {
  let lyricColor: Color
  var previewScale = 1.0
  @AppStorage("afterglow.clockSeconds") private var seconds = false
  @Environment(\.renderActive) private var active
  var body: some View {
    TimelineView(WallClockSchedule(seconds: seconds, paused: !active)) { timeline in
      ClockDisplay(date: timeline.date, lyricColor: lyricColor, previewScale: previewScale)
    }
  }
}

struct ClockDisplay: View {
  let date: Date
  let lyricColor: Color
  var previewScale = 1.0
  @AppStorage("afterglow.clockStyle") private var style = "Minimal"
  @AppStorage("afterglow.clockColor") private var colorName = "Off-white"
  @AppStorage("afterglow.clockFollowLyrics") private var followsLyrics = false
  @AppStorage("afterglow.clockFormat") private var format = "System"
  @AppStorage("afterglow.clockSeconds") private var seconds = false
  @AppStorage("afterglow.clockDate") private var showDate = true
  @AppStorage("afterglow.clockSize") private var size = 1.0
  var body: some View {
    ClockFace(date: date, style: ClockStyle(rawValue: style) ?? .minimal,
      color: followsLyrics ? lyricColor : Tint.resolve(colorName), format: format,
      seconds: seconds, showDate: showDate, scale: min(1.4, max(0.7, size)) * previewScale)
  }
}

struct ClockFace: View {
  let date: Date
  let style: ClockStyle
  let color: Color
  var format = "System"
  var seconds = false
  var showDate = true
  var scale = 1.0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("afterglow.motion") private var motion = true
  private var parts: DateComponents { Calendar.autoupdatingCurrent.dateComponents([.hour, .minute, .second], from: date) }
  private var twelve: Bool {
    format == "12-hour" || (format == "System" && Self.systemTwelve)
  }
  private static let systemTwelve = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a") == true
  private var hour: String {
    let h = parts.hour ?? 0
    return twelve ? String(h % 12 == 0 ? 12 : h % 12) : String(format: "%02d", h)
  }
  private var minute: String { String(format: "%02d", parts.minute ?? 0) }
  private var second: String { String(format: "%02d", parts.second ?? 0) }
  private var time: String { hour + ":" + minute + (seconds ? ":" + second : "") }
  private var baseHeight: CGFloat { style == .minimal ? 52 : 104 }
  private var baseWidth: CGFloat { style.analogFace ? 114 : 220 }

  var body: some View {
    VStack(spacing: 4) {
      if style == .glass && showDate { dateLabel }
      Group {
        switch style {
        case .minimal:
          Text(time).font(.system(size: 29, weight: .ultraLight, design: .rounded)).foregroundStyle(color)
        case .flip:
          HStack(spacing: 6) {
            flipTile(hour, label: twelve ? ((parts.hour ?? 0) < 12 ? "AM" : "PM") : "")
            flipTile(minute)
            if seconds { flipTile(second) }
          }
        case .rounded:
          Text(time).font(.system(size: 60, weight: .heavy, design: .rounded))
            .tracking(-4).foregroundStyle(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
        case .glass:
          ZStack {
            ForEach(0..<4) { index in
              Text(time).foregroundStyle(color.opacity(0.75))
                .offset(x: [0.7, -0.7, 0, 0][index], y: [0, 0, 0.7, -0.7][index])
            }
            Text(time).blendMode(.destinationOut)
          }.compositingGroup()
            .overlay(Text(time).foregroundStyle(color.opacity(0.18)))
            .font(.system(size: 58, weight: .bold, design: .rounded)).tracking(-2)
        case .ring, .analog, .classic:
          analog.frame(width: 88, height: 88)
        }
      }.monospacedDigit().lineLimit(1).minimumScaleFactor(0.45)
      if showDate && style != .glass { dateLabel }
      if twelve && !style.analogFace && style != .flip {
        Text((parts.hour ?? 0) < 12 ? "AM" : "PM").font(.system(size: 7, weight: .medium)).foregroundStyle(color.opacity(0.7))
      }
    }
    .frame(width: baseWidth, height: baseHeight)
    .scaleEffect(scale).frame(width: baseWidth * scale, height: baseHeight * scale)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(date.formatted(date: showDate ? .abbreviated : .omitted, time: seconds ? .standard : .shortened))
    .transaction { if reduceMotion || !motion { $0.disablesAnimations = true } }
  }
  private var dateLabel: some View {
    Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
      .font(.system(size: 9, weight: .medium)).foregroundStyle(color.opacity(0.75))
  }
  private func flipTile(_ value: String, label: String = "") -> some View {
    Text(value).font(.system(size: seconds ? 38 : 48, weight: .bold, design: .rounded))
      .foregroundStyle(color).contentTransition(.numericText())
      .frame(width: seconds ? 62 : 78, height: 68)
      .background(Color(white: 0.085), in: RoundedRectangle(cornerRadius: 9))
      .overlay { Rectangle().fill(.black.opacity(0.8)).frame(height: 1) }
      .overlay(alignment: .bottomLeading) {
        Text(label).font(.system(size: 7, weight: .medium)).foregroundStyle(color.opacity(0.7)).padding(5)
      }
      .animation(reduceMotion || !motion ? nil : .easeInOut(duration: 0.25), value: value)
  }
  private var analog: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let r = min(size.width, size.height) / 2 - 2
      let face = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
      if style == .analog {
        context.fill(Path(roundedRect: face, cornerRadius: 18), with: .color(color.opacity(0.22)))
        context.fill(Path(ellipseIn: face.insetBy(dx: 5, dy: 5)), with: .color(.black.opacity(0.25)))
      } else {
        context.stroke(Path(ellipseIn: face), with: .color(color.opacity(style == .classic ? 0.85 : 0.22)), lineWidth: style == .ring ? 10 : 1.2)
      }
      func point(_ angle: Double, _ radius: Double) -> CGPoint {
        CGPoint(x: center.x + sin(angle) * radius, y: center.y - cos(angle) * radius)
      }
      if style == .classic {
        for n in 1...12 {
          context.draw(Text("\(n)").font(.system(size: 10, weight: .semibold, design: .serif)).foregroundColor(color),
                       at: point(Double(n) * .pi / 6, r - 10))
        }
      } else if style == .ring {
        for tick in 0..<60 {
          let a = Double(tick) * .pi / 30
          var path = Path(); path.move(to: point(a, r - (tick % 5 == 0 ? 6 : 3))); path.addLine(to: point(a, r))
          context.stroke(path, with: .color(color.opacity(tick % 5 == 0 ? 1 : 0.45)), lineWidth: tick % 5 == 0 ? 1.7 : 0.7)
        }
      }
      func hand(_ angle: Double, _ length: Double, _ width: Double, _ opacity: Double) {
        var path = Path(); path.move(to: point(angle + .pi, r * 0.13)); path.addLine(to: point(angle, length))
        context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round))
      }
      let h = Double((parts.hour ?? 0) % 12), m = Double(parts.minute ?? 0), s = Double(parts.second ?? 0)
      hand((h + m / 60) * .pi / 6, r * 0.48, 3, 0.95)
      hand((m + (seconds ? s / 60 : 0)) * .pi / 30, r * 0.73, 2, 0.85)
      if seconds { hand(s * .pi / 30, r * 0.8, 0.8, 0.65) }
      context.fill(Path(ellipseIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)), with: .color(color))
    }.accessibilityHidden(true)
  }
}
