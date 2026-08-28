import AppKit

// Renders a simple clock-face app icon (green ring + clock hands, like the
// menu bar DayProgressRing motif) at every size macOS expects for an
// AppIcon.appiconset, so the app doesn't ship with the default blank icon.

let outputDir = CommandLine.arguments[1]

struct IconSize {
    let pixels: Int
    let filename: String
}

let sizes: [IconSize] = [
    IconSize(pixels: 16, filename: "icon_16x16.png"),
    IconSize(pixels: 32, filename: "icon_16x16@2x.png"),
    IconSize(pixels: 32, filename: "icon_32x32.png"),
    IconSize(pixels: 64, filename: "icon_32x32@2x.png"),
    IconSize(pixels: 128, filename: "icon_128x128.png"),
    IconSize(pixels: 256, filename: "icon_128x128@2x.png"),
    IconSize(pixels: 256, filename: "icon_256x256.png"),
    IconSize(pixels: 512, filename: "icon_256x256@2x.png"),
    IconSize(pixels: 512, filename: "icon_512x512.png"),
    IconSize(pixels: 1024, filename: "icon_512x512@2x.png"),
]

func drawIcon(pixels: Int) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let cornerRadius = CGFloat(pixels) * 0.22
    let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    let backgroundGradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.16, alpha: 1.0),
            NSColor(calibratedRed: 0.05, green: 0.06, blue: 0.09, alpha: 1.0),
        ]
    )
    backgroundGradient?.draw(in: backgroundPath, angle: -90)

    let inset = CGFloat(pixels) * 0.14
    let ringRect = rect.insetBy(dx: inset, dy: inset)
    let ringWidth = CGFloat(pixels) * 0.075

    let trackPath = NSBezierPath(ovalIn: ringRect)
    trackPath.lineWidth = ringWidth
    NSColor(calibratedWhite: 1.0, alpha: 0.15).setStroke()
    trackPath.stroke()

    let progress: CGFloat = 0.72
    let progressPath = NSBezierPath()
    let center = NSPoint(x: rect.midX, y: rect.midY)
    let radius = ringRect.width / 2
    progressPath.appendArc(
        withCenter: center,
        radius: radius,
        startAngle: 90,
        endAngle: 90 - 360 * progress,
        clockwise: true
    )
    progressPath.lineWidth = ringWidth
    progressPath.lineCapStyle = .round
    NSColor(calibratedRed: 0.20, green: 0.78, blue: 0.35, alpha: 1.0).setStroke()
    progressPath.stroke()

    let handWidth = CGFloat(pixels) * 0.045
    let minuteHand = NSBezierPath()
    minuteHand.move(to: center)
    minuteHand.line(to: NSPoint(x: center.x, y: center.y + radius * 0.62))
    minuteHand.lineWidth = handWidth
    minuteHand.lineCapStyle = .round
    NSColor.white.setStroke()
    minuteHand.stroke()

    let hourHand = NSBezierPath()
    hourHand.move(to: center)
    hourHand.line(to: NSPoint(x: center.x + radius * 0.38, y: center.y + radius * 0.20))
    hourHand.lineWidth = handWidth
    hourHand.lineCapStyle = .round
    NSColor.white.setStroke()
    hourHand.stroke()

    let hubRadius = CGFloat(pixels) * 0.03
    let hubRect = NSRect(x: center.x - hubRadius, y: center.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)
    NSColor.white.setFill()
    NSBezierPath(ovalIn: hubRect).fill()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for iconSize in sizes {
    let bitmap = drawIcon(pixels: iconSize.pixels)
    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        continue
    }
    let path = (outputDir as NSString).appendingPathComponent(iconSize.filename)
    try? pngData.write(to: URL(fileURLWithPath: path))
    print("Wrote \(path)")
}
