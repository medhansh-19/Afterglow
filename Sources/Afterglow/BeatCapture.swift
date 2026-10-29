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
  private var stream: SCStream?
  private var processor: AudioProcessor?
  private var generation = 0

  func start(source: PlayerSource) async {
    guard !starting, !running else { return }
    generation += 1
    let ticket = generation
    starting = true
    state = "Waiting for macOS audio permission…"
    do {
      guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
        throw NSError(domain: SCStreamErrorDomain, code: -3801)
      }
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
      state = "Live audio from \(source.rawValue)"
    } catch {
      guard generation == ticket else { return }
      starting = false
      running = false
      let detail = error as NSError
      Logger(subsystem: "local.medhansh.afterglow", category: "Audio").error(
        "Capture failed: \(detail.domain, privacy: .public) \(detail.code)")
      if error is BeatCaptureError {
        state = "Open the selected music player’s window, then enable beat sync again."
      } else if detail.domain == SCStreamErrorDomain && detail.code == -3801 {
        state =
          "Allow Afterglow in System Settings → Privacy & Security → Screen & System Audio Recording, then try again."
      } else {
        state =
          "macOS couldn’t start live audio. Try enabling it again; ambient waves remain available."
      }
    }
  }

  func stop() {
    generation += 1
    let previous = stream
    stream = nil
    processor = nil
    running = false
    starting = false
    frame = .silent
    state = "Ambient motion"
    if let previous { Task { try? await previous.stopCapture() } }
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
