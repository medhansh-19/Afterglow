import SwiftUI

@MainActor
final class DisplayPanels: ObservableObject {
  enum Panel: String, Identifiable {
    case library, timing, beats, wallpaper, cards
    var id: String { rawValue }
  }
  @Published var presented: Panel?
}
