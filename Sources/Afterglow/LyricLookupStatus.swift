import SwiftUI

/// Quiet, bounded status for the listening surface; diagnostics stay in the help text.
struct LyricLookupStatus: View {
  let title: String
  let detail: String
  let diagnostic: String
  let interactive: Bool
  let loading: Bool
  let retry: () -> Void
  let openLibrary: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "text.quote")
        .font(.system(size: 15, weight: .light))
        .foregroundStyle(Theme.secondary)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Theme.text.opacity(0.88))
        Text(detail)
          .font(.system(size: 10))
          .foregroundStyle(Theme.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if interactive {
        HStack(spacing: 2) {
          Button(action: retry) {
            Image(systemName: "arrow.clockwise").frame(width: 28, height: 30)
          }
          .disabled(loading)
          .help("Retry lyrics")
          .accessibilityLabel("Retry lyrics")
          Button(action: openLibrary) {
            Image(systemName: "books.vertical").frame(width: 28, height: 30)
          }
          .help("Open lyric library")
          .accessibilityLabel("Open lyric library")
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(Theme.text.opacity(0.78))
        .buttonStyle(.borderless)
        .fixedSize()
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
    .frame(width: 330)
    .background(Theme.panel.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.text.opacity(0.07), lineWidth: 0.5)
    }
    .help(diagnostic)
  }
}
