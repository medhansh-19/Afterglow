import SwiftUI

@MainActor
final class DisplayPanels: ObservableObject {
  enum Panel: String, Identifiable {
    case library, timing, beats, wallpaper
    var id: String { rawValue }
  }
  @Published var presented: Panel?
}
