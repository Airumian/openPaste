import AppKit
import SwiftUI

/// Icon and header color of the app a clip was copied from.
enum AppStyle {
    static let fallback = Color(white: 0.5)
    private static var cache: [String: (icon: NSImage, color: Color)] = [:]

    static func style(for bundleID: String?) -> (icon: NSImage?, color: Color) {
        guard let id = bundleID else { return (nil, fallback) }
        if let hit = cache[id] { return hit }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return (nil, fallback)
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let style = (icon, dominantColor(of: icon).map { Color(nsColor: $0) } ?? fallback)
        cache[id] = style
        return style
    }

    /// Saturation-weighted average of the icon's colorful pixels; nil for monochrome icons.
    /// Keep the icon's brightness, with a gentle saturation boost and a soft ceiling for header text.
    static func dominantColor(of image: NSImage) -> NSColor? {
        let size = 64
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        NSGraphicsContext.restoreGraphicsState()

        var r = 0.0
        var g = 0.0
        var b = 0.0
        var total = 0.0
        for x in 0..<size {
            for y in 0..<size {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.5,
                    c.saturationComponent > 0.3, c.brightnessComponent > 0.2
                else { continue }
                let w = c.saturationComponent
                r += c.redComponent * w
                g += c.greenComponent * w
                b += c.blueComponent * w
                total += w
            }
        }
        // Ignore icons where color is just a few stray pixels.
        guard total > Double(size * size) * 0.03 else { return nil }
        let avg = NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1)
        return NSColor(
            hue: avg.hueComponent, saturation: min(avg.saturationComponent * 1.05, 0.98),
            brightness: min(avg.brightnessComponent, 0.87), alpha: 1)
    }
}

enum Format {
    /// Russian plural: 1 символ, 2 символа, 5 символов, 11 символов, 21 символ.
    static func characters(_ n: Int) -> String {
        let mod10 = n % 10
        let mod100 = n % 100
        let word =
            mod10 == 1 && mod100 != 11
            ? "символ"
            : (2...4).contains(mod10) && !(12...14).contains(mod100)
                ? "символа"
                : "символов"
        return "\(n.formatted()) \(word)"
    }

    /// "https://www.github.com/a/b/" -> "github.com/a/b"
    static func linkLabel(_ s: String) -> String {
        guard let url = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)),
            let host = url.host()
        else { return s }
        let path = url.path().hasSuffix("/") ? String(url.path().dropLast()) : url.path()
        return (host.hasPrefix("www.") ? String(host.dropFirst(4)) : host) + path
    }
}
