// Run from the repository root:
// swift scripts/generate-icon.swift
// iconutil -c icns build/ClickMapper.iconset -o assets/ClickMapper.icns
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent("build/ClickMapper.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: root.appendingPathComponent("assets"), withIntermediateDirectories: true)

func rounded(_ rect: NSRect, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

func render(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(srgbRed: 0.18, green: 0.23, blue: 0.29, alpha: 1),
               ending: NSColor(srgbRed: 0.06, green: 0.09, blue: 0.14, alpha: 1))!.draw(in: tile, angle: -90)

    for (x, angle, plus) in [(CGFloat(310), CGFloat(12), false), (CGFloat(714), CGFloat(-12), true)] {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: x, yBy: 512)
        transform.rotate(byDegrees: angle)
        transform.concat()
        // Rounded, elongated controller shell with a raised orange rocker.
        rounded(NSRect(x: -150, y: -276, width: 300, height: 552), 140, NSColor.black.withAlphaComponent(0.3))
        rounded(NSRect(x: -150, y: -256, width: 300, height: 552), 140, NSColor(srgbRed: 0.49, green: 0.55, blue: 0.6, alpha: 1))
        rounded(NSRect(x: -139, y: -246, width: 278, height: 532), 130, NSColor(srgbRed: 0.12, green: 0.15, blue: 0.19, alpha: 1))
        let rocker = NSBezierPath(roundedRect: NSRect(x: -112, y: -30, width: 224, height: 286), xRadius: 104, yRadius: 104)
        NSGradient(starting: NSColor(srgbRed: 1, green: 0.64, blue: 0.18, alpha: 1),
                   ending: NSColor(srgbRed: 0.98, green: 0.32, blue: 0.08, alpha: 1))!.draw(in: rocker, angle: -90)
        rounded(NSRect(x: -53, y: 104, width: 106, height: 22), 11, .white)
        if plus { rounded(NSRect(x: -11, y: 62, width: 22, height: 106), 11, .white) }
        // Two navigation buttons remain legible at larger Finder sizes.
        for dx in [CGFloat(-58), CGFloat(58)] {
            rounded(NSRect(x: dx - 41, y: -162, width: 82, height: 82), 41,
                    NSColor(srgbRed: 0.24, green: 0.29, blue: 0.35, alpha: 1))
            let arrow = NSBezierPath()
            let direction: CGFloat = dx < 0 ? -1 : 1
            arrow.move(to: NSPoint(x: dx - direction * 8, y: -105))
            arrow.line(to: NSPoint(x: dx + direction * 8, y: -121))
            arrow.line(to: NSPoint(x: dx - direction * 8, y: -137))
            arrow.lineWidth = 7
            arrow.lineCapStyle = .round
            arrow.lineJoinStyle = .round
            NSColor.white.withAlphaComponent(0.9).setStroke()
            arrow.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let data = render(pixels: size * scale)
        try data.write(to: iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
        if size == 512 && scale == 2 {
            try data.write(to: root.appendingPathComponent("assets/ClickMapper.png"))
        }
    }
}
