import AppKit
import AfterglowCore
import AudioToolbox
import Combine
import CoreGraphics
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

@MainActor
final class BeatCapture: ObservableObject {
  // Render clocks sample the newest frame; audio delivery must not invalidate the entire UI.
  private(set) var frame = BeatFrame.silent
  @Published private(set) var state = "Ambient motion"
  @Published private(set) var running = false
  @Published private(set) var starting = false
  @Published private(set) var permissionRequired = false
  private var stream: SCStream?
  private var processor: AudioProcessor?
  private var generation = 0
  private var healthCheck: Task<Void, Never>?
  private var activityEnabled = true
  private var suspendedSource: PlayerSource?
  private var stopping: Task<Void, Never>?
  private var energyObservation: AnyCancellable?

  init() {
    // Release capture at the sleep notification, even before SwiftUI can update a surface.
    energyObservation = EnergyMonitor.shared.$isAwake.sink { [weak self] awake in
      if !awake { self?.setActivity(active: false) }
    }
  }

  /// Keep the user's opt-in while releasing capture/DSP when it cannot affect the display.
  func setActivity(active: Bool) {
    guard activityEnabled != active else { return }
    activityEnabled = active
    if active, let source = suspendedSource {
      let ticket = generation
      Task {
        guard generation == ticket, activityEnabled, suspendedSource == source else { return }
        suspendedSource = nil
        running = false
        await start(source: source)
      }
    } else if !active, running || starting {
      let source = captureSource ?? suspendedSource
      stop()
      suspendedSource = source
      if source != nil {
        running = true
        state = "Beat sync paused to save energy"
      }
    }
  }
  private var captureSource: PlayerSource?

  func start(source: PlayerSource) async {
    guard !starting, !running else { return }
    // A denied request must not summon the system prompt on every shortcut press.
    // Retry capture once Settings reports the grant is active in this process.
    if permissionRequired && !CGPreflightScreenCaptureAccess() { return }
    captureSource = source
    if !activityEnabled {
      suspendedSource = source
      running = true
      state = "Beat sync paused to save energy"
      return
    }
    generation += 1
    let ticket = generation
    starting = true
    permissionRequired = false
    state = "Waiting for macOS audio permission…"
    if let stopping { await stopping.value }
    guard generation == ticket else { return }
    do {
      // Ask ScreenCaptureKit directly so capture and permission reporting use
      // the same API instead of stopping at the older CoreGraphics preflight.
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
      guard generation == ticket else { return }
      guard let display = content.displays.first,
        let application = content.applications.first(where: {
          $0.bundleIdentifier == source.bundleID
        })
      else {
        throw BeatCaptureError.playerUnavailable
      }
      let filter = SCContentFilter(display: display, including: [application], exceptingWindows: [])
      let configuration = SCStreamConfiguration()
      configuration.width = 2
      configuration.height = 2
      configuration.minimumFrameInterval = CMTime(seconds: 1, preferredTimescale: 60)
      configuration.capturesAudio = true
      configuration.sampleRate = 48000
      configuration.channelCount = 1
      configuration.excludesCurrentProcessAudio = true
      if #available(macOS 15, *) { configuration.captureMicrophone = false }
      let processor = AudioProcessor { [weak self] frame in
        Task { @MainActor in
          guard let self, self.generation == ticket else { return }
          self.frame = frame
        }
      }
      let stream = SCStream(filter: filter, configuration: configuration, delegate: processor)
      // Audio output only: no screen/microphone output, recording output, file writer or upload.
      try stream.addStreamOutput(processor, type: .audio, sampleHandlerQueue: processor.queue)
      processor.onError = { [weak self] in
        Task { @MainActor in
          guard let self, self.generation == ticket else { return }
          self.stop()
          self.state = "Audio sync stopped. Enable it again to reconnect."
        }
      }
      try await stream.startCapture()
      guard generation == ticket else {
        try? await stream.stopCapture()
        return
      }
      self.stream = stream
      self.processor = processor
      starting = false
      running = true
      state = "Waiting for audio from \(source.rawValue)…"
      healthCheck = Task { [weak self] in
        while !Task.isCancelled {
          do { try await Task.sleep(for: .seconds(1)) } catch { return }
          guard let self, self.generation == ticket else { return }
          let age = ProcessInfo.processInfo.systemUptime - self.frame.timestamp
          let nextState: String
          if self.frame.timestamp == 0 || age > 2 {
            nextState = "No audio received from \(source.rawValue). Start playback in the selected player; if it is already playing, disable beat sync and enable it again."
          } else if self.frame.level < 0.005 {
            nextState = "Connected to \(source.rawValue) — audio is silent."
          } else {
            nextState = "Live audio from \(source.rawValue)"
          }
          if self.state != nextState { self.state = nextState }
        }
      }
    } catch {
      guard generation == ticket else { return }
      starting = false
      running = false
      frame = .silent
      let detail = error as NSError
      Logger(subsystem: "local.medhansh.afterglow", category: "Audio").error(
        "Capture failed: \(detail.domain, privacy: .public) \(detail.code)")
      if error is BeatCaptureError {
        state = "Open the selected music player’s window, then enable beat sync again."
      } else if detail.domain == SCStreamErrorDomain && detail.code == -3801 {
        permissionRequired = true
        state = "Allow Afterglow in Screen & System Audio Recording. If it is already enabled after an app update, remove the old entry, add /Applications/Afterglow.app again, then quit and reopen Afterglow."
      } else {
        state =
          "macOS couldn’t start live audio. Try enabling it again; ambient waves remain available."
      }
    }
  }

  func openPermissionSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
    NSWorkspace.shared.open(url)
  }

  func stop() {
    generation += 1
    healthCheck?.cancel()
    healthCheck = nil
    let previous = stream
    stream = nil
    processor = nil
    suspendedSource = nil
    captureSource = nil
    running = false
    starting = false
    frame = .silent
    state = "Ambient motion"
    permissionRequired = false
    if let previous { stopping = Task { try? await previous.stopCapture() } }
  }
}

private enum BeatCaptureError: Error { case playerUnavailable }

/// Mutable DSP state is confined to the serial sample-handler queue.
private final class AudioProcessor: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable
{
  let queue = DispatchQueue(label: "afterglow.audio-analysis", qos: .userInitiated)
  var onError: (@Sendable () -> Void)?
  private let deliver: @Sendable (BeatFrame) -> Void
  private var analyzer = BeatAnalyzer()
  private var lastDelivery = 0.0
  init(deliver: @escaping @Sendable (BeatFrame) -> Void) { self.deliver = deliver }

  func stream(_ stream: SCStream, didStopWithError error: Error) { onError?() }

  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of type: SCStreamOutputType
  ) {
    guard type == .audio, sampleBuffer.isValid,
      let format = CMSampleBufferGetFormatDescription(sampleBuffer),
      let description = CMAudioFormatDescriptionGetStreamBasicDescription(format),
      description.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0,
      description.pointee.mBitsPerChannel == 32
    else { return }
    var buffers = AudioBufferList(
      mNumberBuffers: 1, mBuffers: AudioBuffer(mNumberChannels: 1, mDataByteSize: 0, mData: nil))
    var block: CMBlockBuffer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &buffers,
      bufferListSize: MemoryLayout<AudioBufferList>.size,
      blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault,
      flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
      blockBufferOut: &block)
    guard status == noErr, buffers.mNumberBuffers == 1, let data = buffers.mBuffers.mData else {
      return
    }
    let size = min(16384, Int(buffers.mBuffers.mDataByteSize) / MemoryLayout<Float>.size)
    guard size > 0 else { return }
    let samples = Array(
      UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: size))
    let now = ProcessInfo.processInfo.systemUptime
    let frame = analyzer.process(
      samples: samples, sampleRate: description.pointee.mSampleRate, at: now)
    if now - lastDelivery >= 1.0 / 30 {
      lastDelivery = now
      deliver(frame)
    }
  }
}
