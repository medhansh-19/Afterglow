import AfterglowCore
import SwiftUI

struct LyricCardArtwork: View {
  let excerpt: SavedLyricExcerpt
  private var accent: Color { Color(red: excerpt.red, green: excerpt.green, blue: excerpt.blue) }
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        Text("AFTERGLOW").font(.system(size: 11, weight: .medium, design: .rounded)).tracking(4)
        Spacer()
        Image(systemName: "waveform.path").font(.system(size: 20))
      }.foregroundStyle(accent)
      Spacer(minLength: 0)
      Text(excerpt.text)
        .font(.system(size: 30, weight: .medium, design: .rounded))
        .lineSpacing(8).foregroundStyle(Theme.text)
        .minimumScaleFactor(0.55)
        .frame(maxWidth: .infinity, maxHeight: 345, alignment: .leading)
      Spacer(minLength: 0)
      HStack(spacing: 0) {
        ForEach(0..<8) { index in
          Diamond().fill(accent.opacity(index == 3 ? 1 : 0.45)).frame(width: 6, height: 6)
          if index < 7 { Rectangle().fill(accent.opacity(0.3)).frame(height: 1) }
        }
      }.frame(width: 180).accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 6) {
        Text(excerpt.track.title).font(.system(size: 20, weight: .semibold, design: .rounded)).lineLimit(2)
        Text(excerpt.track.artist).font(.system(size: 15)).lineLimit(2)
        if !excerpt.track.album.isEmpty {
          Text(excerpt.track.album).font(.system(size: 12)).foregroundStyle(Theme.secondary).lineLimit(2)
        }
      }.foregroundStyle(Theme.text)
    }
    .padding(42).frame(width: 540, height: 675)
    .background {
      ZStack(alignment: .topLeading) {
        Theme.background
        LinearGradient(colors: [accent.opacity(0.24), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
      }
    }
    .overlay { RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.5), lineWidth: 1).padding(16) }
    .environment(\.colorScheme, .dark)
  }
}
