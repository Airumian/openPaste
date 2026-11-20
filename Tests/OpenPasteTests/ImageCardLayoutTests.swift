import AppKit
import SwiftUI
import XCTest
@testable import OpenPaste

@MainActor
final class ImageCardLayoutTests: XCTestCase {
    func testImageFitsBelowHeaderForPortraitTallAndWideImages() throws {
        for size in [CGSize(width: 1131, height: 1193),
                     CGSize(width: 200, height: 1600),
                     CGSize(width: 2400, height: 200)] {
            let context = try XCTUnwrap(CGContext(
                data: nil, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(red: 1, green: 0, blue: 1, alpha: 1))
            context.fill(CGRect(origin: .zero, size: size))
            let image = NSImage(cgImage: try XCTUnwrap(context.makeImage()), size: .zero)
            let now = Date()
            let renderer = ImageRenderer(content: CardView(
                clip: Clip(kind: .image, date: now), index: 1, selected: false,
                now: now, thumbnail: image, imageSize: size)
                .environment(\.colorScheme, .light))
            renderer.scale = 1
            let rendered = try XCTUnwrap(renderer.cgImage)
            let bitmap = NSBitmapImageRep(cgImage: rendered)
            XCTAssertEqual(rendered.width, 232)
            XCTAssertEqual(rendered.height, 232)

            let header = try color(bitmap, x: 116, y: 24)
            XCTAssertFalse(isMagenta(header), "The image must not cover the header: \(size)")
            XCTAssertTrue(isMagenta(try color(bitmap, x: 116, y: 140)),
                          "The preview must remain visible: \(size)")

            let margin = try size.width > size.height
                ? color(bitmap, x: 116, y: 60)
                : color(bitmap, x: 10, y: 140)
            XCTAssertGreaterThan(margin.redComponent, 0.9)
            XCTAssertGreaterThan(margin.greenComponent, 0.9)
            XCTAssertGreaterThan(margin.blueComponent, 0.9)
        }
    }

    func testCardBodiesAndTextFollowLightAndDarkAppearance() throws {
        for kind in [Clip.Kind.text, .link, .file, .image] {
            let now = Date()
            let card = CardView(
                clip: Clip(kind: kind, text: "Readable preview", date: now),
                index: 1, selected: false, now: now,
                thumbnail: kind == .file ? NSImage(systemSymbolName: "doc", accessibilityDescription: nil) : nil)
            let renderer = ImageRenderer(content: card.environment(\.colorScheme, .light))
            renderer.scale = 1
            var headerColors: [NSColor] = []
            // Change the same renderer's appearance to catch stale, resolved color values.
            for scheme in [ColorScheme.light, .dark] {
                renderer.content = card.environment(\.colorScheme, scheme)
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                let background = try color(bitmap, x: 12, y: 140)
                if scheme == .light {
                    XCTAssertGreaterThan(background.redComponent, 0.9, "\(kind)")
                } else {
                    XCTAssertLessThan(background.redComponent, 0.3, "\(kind)")
                }
                headerColors.append(try color(bitmap, x: 116, y: 44))

                if kind == .text {
                    var contrastingPixels = 0
                    for y in 58..<78 {
                        for x in 12..<190 {
                            let text = try color(bitmap, x: x, y: y)
                            let contrast = scheme == .light
                                ? background.redComponent - text.redComponent
                                : text.redComponent - background.redComponent
                            if contrast > 0.5 { contrastingPixels += 1 }
                        }
                    }
                    XCTAssertGreaterThan(contrastingPixels, 30, "Text must stay readable in \(scheme)")
                }
            }
            XCTAssertEqual(headerColors[0].redComponent, headerColors[1].redComponent, accuracy: 0.01)
            XCTAssertEqual(headerColors[0].greenComponent, headerColors[1].greenComponent, accuracy: 0.01)
            XCTAssertEqual(headerColors[0].blueComponent, headerColors[1].blueComponent, accuracy: 0.01)
        }
    }

    private func color(_ bitmap: NSBitmapImageRep, x: Int, y: Int) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
    }

    private func isMagenta(_ color: NSColor) -> Bool {
        // Allow ColorSync conversion between the source image and the renderer's output profile.
        color.redComponent > 0.8 && color.greenComponent < 0.4 && color.blueComponent > 0.8
    }
}
