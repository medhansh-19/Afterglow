import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
let points = [NSPoint(x: 230, y: 350), NSPoint(x: 420, y: 655), NSPoint(x: 655, y: 405), NSPoint(x: 790, y: 700)]
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let context = NSGraphicsContext.current!.cgContext
    context.scaleBy(x: Double(size) / 1024, y: Double(size) / 1024)
    NSColor(calibratedRed: 0.035, green: 0.025, blue: 0.045, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 210, yRadius: 210).fill()
    let pink = NSColor(calibratedRed: 0.94, green: 0.40, blue: 0.67, alpha: 1)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 40, color: pink.cgColor)
    pink.withAlphaComponent(0.7).setStroke()
    let frame = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 155, yRadius: 155)
    frame.lineWidth = 5; frame.stroke()
    context.restoreGState()
    pink.withAlphaComponent(0.5).setStroke()
    let lines = NSBezierPath()
    lines.move(to: points[0]); lines.line(to: points[1]); lines.line(to: points[2]); lines.line(to: points[3])
    lines.move(to: points[0]); lines.line(to: points[2]); lines.move(to: points[1]); lines.line(to: points[3])
    lines.lineWidth = 4; lines.stroke()
    for (i, point) in points.enumerated() {
        let r: Double = i == 1 ? 36 : 12
        context.saveGState()
        context.setShadow(offset: .zero, blur: i == 1 ? 35 : 12, color: pink.cgColor)
        (i == 1 ? NSColor.white : pink).setFill()
        let diamond = NSBezierPath()
        diamond.move(to: NSPoint(x: point.x, y: point.y + r))
        diamond.line(to: NSPoint(x: point.x + r, y: point.y))
        diamond.line(to: NSPoint(x: point.x, y: point.y - r))
        diamond.line(to: NSPoint(x: point.x - r, y: point.y))
        diamond.close(); diamond.fill()
        context.restoreGState()
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name)) }
}
