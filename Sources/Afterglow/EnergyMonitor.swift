import AfterglowCore
import AppKit
import IOKit.ps
import SwiftUI

/// System activity is event driven; an inactive app can still have a visible desktop wallpaper.
@MainActor
final class EnergyMonitor: ObservableObject {
  static let shared = EnergyMonitor()
  @Published private(set) var budget = EnergyBudget()
  @Published private(set) var isAwake = true
  private var systemSleeping = false
  private var displaysSleeping = false
  private var sessionInactive = false
  private var observers: [(NotificationCenter, NSObjectProtocol)] = []
  private var powerSource: CFRunLoopSource?

  private init() {
    updateBudget()
    if let source = IOPSNotificationCreateRunLoopSource({ _ in
      Task { @MainActor in EnergyMonitor.shared.updateBudget() }
    }, nil)?.takeRetainedValue() {
      powerSource = source
      CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }
    observe(.NSProcessInfoPowerStateDidChange, center: .default) { $0.updateBudget() }
    observe(ProcessInfo.thermalStateDidChangeNotification, center: .default) { $0.updateBudget() }
    let workspace = NSWorkspace.shared.notificationCenter
    observe(NSWorkspace.willSleepNotification, center: workspace) { $0.systemSleeping = true; $0.updateActivity() }
    observe(NSWorkspace.didWakeNotification, center: workspace) { $0.systemSleeping = false; $0.updateActivity() }
    observe(NSWorkspace.screensDidSleepNotification, center: workspace) { $0.displaysSleeping = true; $0.updateActivity() }
    observe(NSWorkspace.screensDidWakeNotification, center: workspace) { $0.displaysSleeping = false; $0.updateActivity() }
    observe(NSWorkspace.sessionDidResignActiveNotification, center: workspace) { $0.sessionInactive = true; $0.updateActivity() }
    observe(NSWorkspace.sessionDidBecomeActiveNotification, center: workspace) { $0.sessionInactive = false; $0.updateActivity() }
  }

  private func updateActivity() {
    let awake = !systemSleeping && !displaysSleeping && !sessionInactive
    if isAwake != awake { isAwake = awake }
  }

  private func updateBudget() {
    let pressure: EnergyBudget.ThermalPressure
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: pressure = .nominal
    case .fair: pressure = .fair
    case .serious: pressure = .serious
    case .critical: pressure = .critical
    @unknown default: pressure = .serious
    }
    let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
    let powerType = info.flatMap { IOPSGetProvidingPowerSourceType($0)?.takeUnretainedValue() as String? }
    let onBattery = powerType.map { $0 == kIOPSBatteryPowerValue } ?? budget.onBattery
    let next = EnergyBudget(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled,
      onBattery: onBattery, thermalPressure: pressure)
    if budget != next { budget = next }
  }

  private func observe(_ name: Notification.Name, center: NotificationCenter,
    action: @escaping @MainActor (EnergyMonitor) -> Void) {
    let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { if let self { action(self) } }
    }
    observers.append((center, observer))
  }
}

private struct RenderBudgetKey: EnvironmentKey { static let defaultValue = EnergyBudget() }
private struct RenderActiveKey: EnvironmentKey { static let defaultValue = true }
private struct ParentRenderTickKey: EnvironmentKey { static let defaultValue: Date? = nil }
extension EnvironmentValues {
  var renderBudget: EnergyBudget {
    get { self[RenderBudgetKey.self] }
    set { self[RenderBudgetKey.self] = newValue }
  }
  var renderActive: Bool {
    get { self[RenderActiveKey.self] }
    set { self[RenderActiveKey.self] = newValue }
  }
  /// Ribbons inside an already ticking playback/preview view share that tick.
  var parentRenderTick: Date? {
    get { self[ParentRenderTickKey.self] }
    set { self[ParentRenderTickKey.self] = newValue }
  }
}

/// A clock needs only minute/second boundary events and no wakeups while hidden.
struct WallClockSchedule: TimelineSchedule {
  var seconds: Bool
  var paused = false
  func entries(from startDate: Date, mode: Mode) -> Entries {
    Entries(nextDate: startDate, interval: paused ? nil : seconds ? 1 : 60)
  }
  struct Entries: Sequence, IteratorProtocol {
    var nextDate: Date?
    let interval: TimeInterval?
    mutating func next() -> Date? {
      guard let date = nextDate else { return nil }
      nextDate = interval.map {
        Date(timeIntervalSince1970: (floor(date.timeIntervalSince1970 / $0) + 1) * $0)
      }
      return date
    }
  }
}

/// A visible settings sheet has its own render lifetime, independent of its covered parent.
struct RenderSurfaceActivity: ViewModifier {
  var onActivityChange: @MainActor (Bool) -> Void = { _ in }
  @ObservedObject private var energy = EnergyMonitor.shared
  @State private var visible = true
  private var active: Bool { visible && energy.isAwake }
  func body(content: Content) -> some View {
    content
      .background(SurfaceVisibilityReader { visible = $0 })
      .environment(\.renderActive, active)
      .environment(\.renderBudget, energy.budget)
      .onChange(of: active, initial: true) { _, value in onActivityChange(value) }
      .onDisappear { onActivityChange(false) }
  }
}

private struct SurfaceVisibilityReader: NSViewRepresentable {
  let changed: @MainActor (Bool) -> Void
  func makeNSView(context: Context) -> Reader { Reader(changed: changed) }
  func updateNSView(_ view: Reader, context: Context) { view.changed = changed }
  static func dismantleNSView(_ view: Reader, coordinator: ()) { view.detach() }

  final class Reader: NSView {
    var changed: @MainActor (Bool) -> Void
    private var observer: NSObjectProtocol?
    init(changed: @escaping @MainActor (Bool) -> Void) {
      self.changed = changed
      super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func detach() {
      if let observer { NotificationCenter.default.removeObserver(observer) }
      observer = nil
    }
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      detach()
      if let window {
        observer = NotificationCenter.default.addObserver(
          forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated { self?.updateVisibility() }
        }
      }
      updateVisibility()
    }
    private func updateVisibility() {
      let visible = window?.occlusionState.contains(.visible) == true
      Task { @MainActor [weak self] in self?.changed(visible) }
    }
  }
}
