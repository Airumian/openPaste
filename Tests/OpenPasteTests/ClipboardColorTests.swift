import XCTest
import SwiftUI
@testable import OpenPaste

final class ClipboardColorTests: XCTestCase {
    func testHexWithAndWithoutHashAndAlpha() throws {
        for text in ["#05a1dd", "05A1DD", " \n#05A1dd\t"] {
            try assertColor(text, 5 / 255.0, 161 / 255.0, 221 / 255.0)
        }
        for text in ["#abc", "AbC", "#aabbcc", "aabbcc"] {
            try assertColor(text, 170 / 255.0, 187 / 255.0, 204 / 255.0)
        }
        for text in ["#abcd", "ABCD", "#aabbccdd", "AABBCCDD"] {
            try assertColor(text, 170 / 255.0, 187 / 255.0, 204 / 255.0, alpha: 221 / 255.0)
        }
    }

    func testRGBSyntaxAndPercentages() throws {
        for text in ["rgb(255, 0, 128)", "RGB(255 0 128)", "rgba(255 0 128 / 100%)", "rgb(2.55e2, 0, 128)"] {
            try assertColor(text, 1, 0, 128 / 255.0)
        }
        for text in ["rgba(100%, 0%, 50%, .25)", "rgb(100% 0 50% / 25%)", "rgb(255 0 127.5/.25)"] {
            try assertColor(text, 1, 0, 0.5, alpha: 0.25)
        }
        try assertColor("rgb(400 -1 0 / 200%)", 1, 0, 0)
        try assertColor("rgb(none 0 0 / none)", 0, 0, 0, alpha: 0)
    }

    func testHSLAndHWBWithHueUnits() throws {
        for text in ["hsl(120, 100%, 50%)", "hsl(480deg 100% 50%)", "hsl(-240 100% 50%)",
                     "hsl(0.333333333333turn 100% 50%)", "hsl(133.3333333333grad 100% 50%)",
                     "hsl(2.094395102393rad 100% 50%)", "hwb(120 0% 0%)"] {
            try assertColor(text, 0, 1, 0)
        }
        try assertColor("hsla(240, 100%, 50%, .2)", 0, 0, 1, alpha: 0.2)
        try assertColor("hwb(0 20% 30% / 50%)", 0.7, 0.2, 0.2, alpha: 0.5)
        try assertColor("hwb(0 80% 80%)", 0.5, 0.5, 0.5)
    }

    func testPerceptualColorSpacesUseCSSReferenceRanges() throws {
        for text in ["oklab(62.795536% 0.22486306 0.1258463)",
                     "oklch(0.62795536 0.2576833 29.233885deg)",
                     "oklch(62.795536% 64.420825% 29.233885)",
                     "lab(54.29054% 80.80492 69.89099)",
                     "lch(54.29054% 106.83718 40.85767)"] {
            try assertColor(text, 1, 0, 0, accuracy: 0.001)
        }
        try assertColor("oklab(50% 0 0 / 50%)", 0.38857286, 0.38857286, 0.38857286, alpha: 0.5)
        try assertColor("lab(50% 0 0)", 0.4663266, 0.4663266, 0.4663266)
        try assertColor("oklch(100% 0 none)", 1, 1, 1)
        try assertColor("oklch(0 0 0)", 0, 0, 0)
    }

    func testExplicitColorSpacesAndNamedColors() throws {
        try assertColor("color(srgb 1 0% .5 / 80%)", 1, 0, 0.5, alpha: 0.8)
        try assertColor("color(srgb-linear .21404114 .21404114 .21404114)", 0.5, 0.5, 0.5)
        try assertColor("color(display-p3 .5 .5 .5)", 0.5, 0.5, 0.5, accuracy: 0.001)
        try assertColor("color(display-p3 1 0 0)", 1, 0, 0)
        try assertColor("RebeccaPurple", 0.4, 0.2, 0.6)
        try assertColor("green", 0, 128 / 255.0, 0)
        try assertColor("transparent", 0, 0, 0, alpha: 0)
    }

    func testRejectsPartialMalformedAndContextDependentColors() {
        for text in ["", "#", "#12", "12345", "#1234567", "#ggg", "0xff0000", "#fff trailing",
                     "color: #fff;", "Use rgb(255, 0, 0)", "#fff\n#000", "https://example.com/#fff",
                     "rgb()", "rgb(1 2)", "rgb(1 2 3 4)", "rgb(1,,3)", "rgb(1,2,3,)",
                     "rgb(1,2,3 / .5)", "rgb(100%, 0, 0)", "rgb(nan 0 0)", "rgb(inf 0 0)",
                     "rgb(1e999 0 0)", "rgb(1. 2 3)", "rgb(1 2 3)junk", "rgb(1 2 3 / .5 / .5)",
                     "hsl(50% 100% 50%)", "hwb(0, 0%, 0%)", "oklch(50%, .2, 30)",
                     "color(srgb 1 0)", "color(unknown 1 0 0)", "currentColor", "var(--accent)",
                     "rgb(from red r g b)", "rgb(calc(1 + 2) 0 0)", String(repeating: "a", count: 300)] {
            XCTAssertNil(ClipboardColor.parse(text), text)
        }
    }

    func testTextContrastIncludesTransparency() throws {
        let black = ClipboardColor(red: 0, green: 0, blue: 0)
        let white = ClipboardColor(red: 1, green: 1, blue: 1)
        let transparent = try XCTUnwrap(ClipboardColor.parse("#0000"))
        XCTAssertTrue(transparent.composited(over: white).usesDarkText)
        XCTAssertFalse(transparent.composited(over: black).usesDarkText)
        XCTAssertFalse(black.usesDarkText)
        XCTAssertTrue(white.usesDarkText)
        XCTAssertTrue(try XCTUnwrap(ClipboardColor.parse("yellow")).usesDarkText)
        XCTAssertFalse(try XCTUnwrap(ClipboardColor.parse("blue")).usesDarkText)
        let halfRed = try XCTUnwrap(ClipboardColor.parse("rgb(255 0 0 / .5)"))
        XCTAssertEqual(halfRed.composited(over: white), ClipboardColor(red: 1, green: 0.5, blue: 0.5))
    }

    private func assertColor(_ input: String, _ red: Double, _ green: Double, _ blue: Double,
                             alpha: Double = 1, accuracy: Double = 0.0001,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        let result = try XCTUnwrap(ClipboardColor.parse(input), input, file: file, line: line)
        XCTAssertEqual(result.red, red, accuracy: accuracy, input, file: file, line: line)
        XCTAssertEqual(result.green, green, accuracy: accuracy, input, file: file, line: line)
        XCTAssertEqual(result.blue, blue, accuracy: accuracy, input, file: file, line: line)
        XCTAssertEqual(result.alpha, alpha, accuracy: accuracy, input, file: file, line: line)
    }
}

@MainActor
final class ColorCardLayoutTests: XCTestCase {
    func testColorFillsBodyAndTextStaysReadableInBothThemes() throws {
        let now = Date()
        for value in ["#ffffff", "000000", "0093c7", "rgb(255 0 255)", "oklch(62.795536% .2576833 29.233885)", "#0000", "#ff000080"] {
            let parsed = try XCTUnwrap(ClipboardColor.parse(value))
            let card = CardView(clip: Clip(kind: .text, text: value, date: now), index: 1,
                                selected: false, now: now, thumbnail: nil)
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: card.environment(\.colorScheme, scheme))
                renderer.scale = 1
                let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
                let ordinary = ImageRenderer(content: CardView(
                    clip: Clip(kind: .text, text: "ordinary text", date: now), index: 1,
                    selected: false, now: now, thumbnail: nil).environment(\.colorScheme, scheme))
                ordinary.scale = 1
                let baseline = NSBitmapImageRep(cgImage: try XCTUnwrap(ordinary.cgImage))
                let base = try pixel(baseline, 116, 140)
                let expected = parsed.composited(over: ClipboardColor(
                    red: base.redComponent, green: base.greenComponent, blue: base.blueComponent))
                // ImageRenderer output is color-managed. Render the expected sRGB swatch
                // through the same output profile instead of comparing display-profile bytes.
                let reference = ImageRenderer(content: Color(.sRGB, red: parsed.red,
                    green: parsed.green, blue: parsed.blue, opacity: parsed.alpha)
                    .frame(width: 232, height: 232)
                    .background(Color(nsColor: .textBackgroundColor))
                    .environment(\.colorScheme, scheme))
                reference.scale = 1
                let referencePixel = try pixel(NSBitmapImageRep(cgImage: XCTUnwrap(reference.cgImage)), 10, 140)
                // Include the footer region, not only the text content area.
                for y in [140, 218] {
                    let body = try pixel(bitmap, 10, y)
                    XCTAssertEqual(body.redComponent, referencePixel.redComponent, accuracy: 0.015, value)
                    XCTAssertEqual(body.greenComponent, referencePixel.greenComponent, accuracy: 0.015, value)
                    XCTAssertEqual(body.blueComponent, referencePixel.blueComponent, accuracy: 0.015, value)
                }
                let header = try pixel(bitmap, 116, 44)
                let originalHeader = try pixel(baseline, 116, 44)
                XCTAssertEqual(header.redComponent, originalHeader.redComponent, accuracy: 0.01)
                XCTAssertEqual(header.greenComponent, originalHeader.greenComponent, accuracy: 0.01)
                XCTAssertEqual(header.blueComponent, originalHeader.blueComponent, accuracy: 0.01)
                var textPixels: [CGPoint] = []
                for y in 84..<196 {
                    for x in 24..<208 {
                        let color = try pixel(bitmap, x, y)
                        let components = [color.redComponent, color.greenComponent, color.blueComponent]
                        if expected.usesDarkText ? components.allSatisfy({ $0 < 0.15 }) : components.allSatisfy({ $0 > 0.85 }) {
                            textPixels.append(CGPoint(x: x, y: y))
                        }
                    }
                }
                XCTAssertGreaterThan(textPixels.count, 100, "\(value), \(scheme)")
                let minX = try XCTUnwrap(textPixels.map(\.x).min())
                let maxX = try XCTUnwrap(textPixels.map(\.x).max())
                let minY = try XCTUnwrap(textPixels.map(\.y).min())
                let maxY = try XCTUnwrap(textPixels.map(\.y).max())
                XCTAssertEqual((minX + maxX) / 2, 116, accuracy: 6, "Value must be horizontally centered")
                XCTAssertEqual((minY + maxY) / 2, 140, accuracy: 6, "Value must be centered below the header")
                XCTAssertGreaterThanOrEqual(maxY - minY, 13, "Value must be larger than ordinary text")
            }
        }
    }

    private func pixel(_ bitmap: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> NSColor {
        try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
    }
}
