// Draws the app icon and packs it into AppIcon.icns.
// Run from the repo root: swift icon/make-icon.swift
import AppKit

let canvas: CGFloat = 1024

func color(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

/// One clipboard card: colored header strip, light body with text lines (mirrors the app's cards).
func card(_ cg: CGContext, center: CGPoint, degrees: CGFloat, header: NSColor) {
    cg.saveGState()
    cg.translateBy(x: center.x, y: center.y)
    cg.rotate(by: degrees * .pi / 180)
    let w: CGFloat = 400
    let h: CGFloat = 460
    let headerH: CGFloat = 118
    let r = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)
    let shape = NSBezierPath(roundedRect: r, xRadius: 54, yRadius: 54)

    cg.setShadow(
        offset: CGSize(width: 0, height: -16), blur: 36,
        color: NSColor.black.withAlphaComponent(0.5).cgColor)
    color(0xF4F4F7).setFill()
    shape.fill()
    cg.setShadow(offset: .zero, blur: 0, color: nil)

    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    header.setFill()
    NSRect(x: r.minX, y: r.maxY - headerH, width: w, height: headerH).fill()
    NSGraphicsContext.restoreGraphicsState()

    color(0xC9CAD1).setFill()
    for (i, fraction) in [0.80, 0.62, 0.72, 0.42].enumerated() {
        let line = NSRect(
            x: r.minX + 46, y: r.maxY - headerH - 70 - CGFloat(i) * 60,
            width: (w - 92) * fraction, height: 26)
        NSBezierPath(roundedRect: line, xRadius: 13, yRadius: 13).fill()
    }
    cg.restoreGState()
}

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ns
    let cg = ns.cgContext
    cg.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)

    // macOS icon grid: 824 pt body centered on a 1024 canvas.
    let body = NSBezierPath(
        roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    cg.saveGState()
    cg.setShadow(
        offset: CGSize(width: 0, height: -10), blur: 24,
        color: NSColor.black.withAlphaComponent(0.3).cgColor)
    color(0x15171C).setFill()
    body.fill()
    cg.restoreGState()
    NSGradient(starting: color(0x121419), ending: color(0x3A3F4C))!.draw(in: body, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    card(cg, center: CGPoint(x: 432, y: 528), degrees: 13, header: color(0xFF9F0A))
    card(cg, center: CGPoint(x: 592, y: 528), degrees: -13, header: color(0x30D158))
    card(cg, center: CGPoint(x: 512, y: 472), degrees: 0, header: color(0x0A84FF))
    NSGraphicsContext.restoreGraphicsState()

    // Thin top-lit rim so the shape reads on dark Docks.
    NSColor.white.withAlphaComponent(0.10).setStroke()
    body.lineWidth = 3
    body.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: "icon")
let iconset = dir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try render(pixels: base * scale).representation(using: .png, properties: [:])!
            .write(to: iconset.appendingPathComponent(name))
    }
}
try render(pixels: 1024).representation(using: .png, properties: [:])!
    .write(to: dir.appendingPathComponent("AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
try FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "icon/AppIcon.icns ready" : "iconutil failed")
