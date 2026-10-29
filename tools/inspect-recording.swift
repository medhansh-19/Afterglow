import Foundation
import AVFoundation
import AppKit

let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let duration = try await asset.load(.duration).seconds
let audio = try await asset.loadTracks(withMediaType: .audio)
print("Duration: \(duration)s; audio tracks: \(audio.count)")
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 640, height: 400)
let count = 12
let contact = NSImage(size: NSSize(width: 1920, height: 1760))
contact.lockFocus()
NSColor.black.setFill(); NSRect(x: 0, y: 0, width: 1920, height: 1760).fill()
for i in 0..<count {
    let time = min(duration - 0.1, duration * Double(i) / Double(count))
    let image = try generator.copyCGImage(at: CMTime(seconds: time, preferredTimescale: 600), actualTime: nil)
    let frame = NSImage(cgImage: image, size: .zero)
    let col = i % 3, row = i / 3
    let rect = NSRect(x: col * 640, y: 1760 - (row + 1) * 440, width: 640, height: 400)
    frame.draw(in: rect)
    (String(format: "%.2f s", time) as NSString).draw(at: NSPoint(x: rect.minX + 10, y: rect.maxY + 8), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular)])
}
contact.unlockFocus()
let bitmap = NSBitmapImageRep(data: contact.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("recording-contact-sheet.png"))
if !audio.isEmpty {
    let target = output.appendingPathComponent("recording-audio.m4a")
    if !FileManager.default.fileExists(atPath: target.path) {
        let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)!
        try await export.export(to: target, as: .m4a)
        print("Audio extracted: \(target.path)")
    }
}
