import Combine
import SwiftUI
@preconcurrency import Sparkle

/// Sparkle owns scheduling, preferences, verification, installation and relaunch.
@MainActor
final class AppUpdates: ObservableObject {
  static let shared = AppUpdates()
  @Published private(set) var canCheck = false
  @Published private(set) var automaticChecks = false
  private let controller: SPUStandardUpdaterController?

  private init() {
    // `swift run` has no application bundle or embedded installer helpers.
    guard Bundle.main.bundleURL.pathExtension == "app" else {
      controller = nil
      return
    }
    let controller = SPUStandardUpdaterController(
      startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    self.controller = controller
    controller.updater.publisher(for: \.canCheckForUpdates)
      .receive(on: RunLoop.main).assign(to: &$canCheck)
    controller.updater.publisher(for: \.automaticallyChecksForUpdates)
      .receive(on: RunLoop.main).assign(to: &$automaticChecks)
  }

  func check() { controller?.checkForUpdates(nil) }
  func setAutomaticChecks(_ enabled: Bool) {
    controller?.updater.automaticallyChecksForUpdates = enabled
  }
}

struct UpdateMenu: View {
  @ObservedObject var updates: AppUpdates
  var body: some View {
    Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
    Toggle("Automatically Check for Updates", isOn: Binding(
      get: { updates.automaticChecks }, set: { updates.setAutomaticChecks($0) }))
      .disabled(!updates.canCheck)
  }
}
