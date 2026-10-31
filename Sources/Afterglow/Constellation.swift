import AfterglowCore
import SwiftUI

struct Constellation: View {
  let lines: [LyricLine]
  let position: Double
  let duration: Double
  let tint: Color
  let reduceMotion: Bool
  let estimatedWords: Bool
  let beatFrame: BeatFrame
  let liveBeats: Bool
  let playing: Bool
  var waveWidth: Double? = nil
  var marker: LyricMarker = .diamond
  var markerEmoji: String = "✨"

  var body: some View {
    GeometryReader { geometry in
      let scene = LyricScene.resolve(lines: lines, at: position, duration: duration)
      let index = scene.lineIndex
      let line = index.map { lines[$0] }
      let end = index.map { $0 + 1 < lines.count ? lines[$0 + 1].time : duration } ?? duration
      let vocal = line.map { position < min(end, $0.end ?? end) } ?? false
      let page = line.map {
        LyricWordPage.resolve(line: $0, at: position, nextLineTime: end, estimated: estimatedWords)
      }
      let lineFocus = vocal && line?.words.isEmpty != false && !estimatedWords
      ZStack {
        // Keep one persistent wave clock across every lyric and gap.
        InstrumentalView(
          frame: beatFrame, live: liveBeats, playing: playing, tint: tint,
          reduceMotion: reduceMotion, visible: scene.waveOpacity > 0
        )
        .frame(
          width: max(geometry.size.width, waveWidth ?? geometry.size.width),
          height: geometry.size.height
        )
        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        .opacity(reduceMotion ? (scene.waveOpacity > 0 ? 1 : 0) : scene.waveOpacity)
        .accessibilityHidden(true)
        if let line, let page, !page.words.isEmpty {
          LyricGraph(
            words: page.words, active: page.activeIndex, lineFocus: lineFocus, tint: tint,
            reduceMotion: reduceMotion, size: geometry.size, marker: marker, markerEmoji: markerEmoji
          ).equatable().id(line.id)
        }
      }
      // Line boundaries are clock events. Crossfading old lyrics would add visible latency.
      .transition(.identity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(line?.text ?? "Instrumental passage")
    }
  }

}

private struct LyricGraph: View, Equatable {
  let words: [String]
  let active: Int?
  let lineFocus: Bool
  let tint: Color
  let reduceMotion: Bool
  let size: CGSize
  let marker: LyricMarker
  let markerEmoji: String
  var body: some View {
    let points = layout(count: words.count, size: size)
    ZStack {
      Canvas { context, _ in
        context.addFilter(.shadow(color: tint.opacity(0.45), radius: 5))
        for i in points.indices {
          guard i > 0 else { continue }
          var path = Path()
          path.move(to: points[i - 1])
          path.addLine(to: points[i])
          context.stroke(
            path, with: .color(tint.opacity(lineFocus || i <= (active ?? -1) ? 0.72 : 0.34)),
            lineWidth: 1.1)
          if i > 2 {
            var chord = Path()
            chord.move(to: points[i - 3])
            chord.addLine(to: points[i])
            context.stroke(chord, with: .color(tint.opacity(0.36)), lineWidth: 0.85)
          }
          if i > 4 && i % 2 == 0 {
            var crossing = Path()
            crossing.move(to: points[1])
            crossing.addLine(to: points[i])
            context.stroke(crossing, with: .color(tint.opacity(0.27)), lineWidth: 0.8)
          }
        }
      }
      .accessibilityHidden(true)
      ForEach(words.indices, id: \.self) { i in
        let columns = min(words.count, words.count > 12 ? 6 : 4)
        let labelWidth = max(40, size.width / Double(columns) - 18)
        ZStack {
          Text(words[i])
            .font(
              .system(
                size: wordSize(true, width: size.width, count: words.count),
                weight: .medium, design: .rounded)
            )
            .foregroundStyle(
              tint.opacity(i == active || lineFocus ? 1 : i < (active ?? -1) ? 0.78 : 0.48)
            )
            .shadow(
              color: tint.opacity(i == active ? 0.95 : lineFocus ? 0.38 : 0),
              radius: i == active ? 22 : 10
            )
            .lineLimit(1)
            .minimumScaleFactor(0.35)
            .frame(width: labelWidth, height: 70, alignment: .bottom)
            .scaleEffect(
              i == active ? 1 : wordSize(false, width: size.width, count: words.count)
                / wordSize(true, width: size.width, count: words.count), anchor: .bottom)
            .position(x: points[i].x, y: points[i].y - 47)
          MarkerSymbol(marker: marker, emoji: markerEmoji, tint: tint)
            .opacity(i == active || lineFocus ? 1 : 0.45)
            .scaleEffect(i == active ? 1 : 4.0 / 7)
            .position(points[i])
        }
        .animation(
          reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.14), value: active)
      }
      .accessibilityHidden(true)
    }
  }
  private func wordSize(_ active: Bool, width: Double, count: Int) -> Double {
    let base = min(width / (count > 12 ? 37 : 29), 38)
    return active ? max(22, base * 1.5) : max(14, base)
  }

  /// Columns keep labels apart; alternating heights draw the crossing constellation.
  private func layout(count: Int, size: CGSize) -> [CGPoint] {
    guard count > 0 else { return [] }
    let columns = min(count, count > 12 ? 6 : 4)
    let rows = Int(ceil(Double(count) / Double(columns)))
    return (0..<count).map { i in
      let row = i / columns
      let col = i % columns
      let occupied = min(columns, count - row * columns)
      let x = size.width * (Double(col) + 0.5 + Double(columns - occupied) / 2) / Double(columns)
      let rowHeight = size.height / Double(max(2, rows))
      let y =
        size.height / 2 + (Double(row) - Double(rows - 1) / 2) * rowHeight * 0.8
        + (col % 2 == 0 ? -1.0 : 1.0) * min(rowHeight * 0.22, 42)
      return CGPoint(x: x, y: y)
    }
  }
}

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
