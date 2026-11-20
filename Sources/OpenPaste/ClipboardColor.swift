import AppKit

/// A standalone clipboard color, stored as sRGB. The original clipboard text is never changed.
struct ClipboardColor: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    static func parse(_ text: String) -> ClipboardColor? {
        // Do not scan or parse large text clips on every card redraw.
        guard text.utf8.prefix(257).count <= 256 else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let hex = hex(value) { return hex }
        if value == "transparent" { return ClipboardColor(red: 0, green: 0, blue: 0, alpha: 0) }
        if let named = namedColors[value] { return hex(named) }
        guard let opening = value.firstIndex(of: "("), value.last == ")" else { return nil }
        let name = String(value[..<opening])
        let arguments = String(
            value[value.index(after: opening)..<value.index(before: value.endIndex)])
        guard let (parts, alpha) = components(arguments, function: name) else { return nil }
        let rgb: [Double]
        switch name {
        case "rgb", "rgba":
            guard let values = numbers(parts, percentage: 1, number: 1 / 255.0) else { return nil }
            rgb = values
        case "hsl", "hsla", "hwb":
            guard let hue = hue(parts[0]),
                let second = percentage(parts[1]), let third = percentage(parts[2])
            else { return nil }
            if name == "hwb" {
                let white = clamp(second)
                let black = clamp(third)
                rgb =
                    white + black >= 1
                    ? Array(repeating: white / (white + black), count: 3)
                    : hsl(hue, 1, 0.5).map { $0 * (1 - white - black) + white }
            } else {
                rgb = hsl(hue, clamp(second), clamp(third))
            }
        case "oklab", "oklch", "lab", "lch":
            let isOK = name.hasPrefix("ok")
            let polar = name.hasSuffix("lch")
            guard let lightness = scalar(parts[0], percentage: isOK ? 1 : 100),
                let second = scalar(parts[1], percentage: isOK ? 0.4 : (polar ? 150 : 125)),
                let third = polar ? hue(parts[2]) : scalar(parts[2], percentage: isOK ? 0.4 : 125)
            else { return nil }
            let a = polar ? max(0, second) * cos(third * .pi / 180) : second
            let b = polar ? max(0, second) * sin(third * .pi / 180) : third
            rgb = isOK ? oklab(clamp(lightness), a, b) : lab(clamp(lightness / 100) * 100, a, b)
        case "color":
            guard let values = numbers(Array(parts.dropFirst()), percentage: 1, number: 1) else {
                return nil
            }
            switch parts[0] {
            case "srgb": rgb = values
            case "srgb-linear": rgb = values.map(encoded)
            case "display-p3":
                guard
                    let color = NSColor(
                        displayP3Red: values[0], green: values[1], blue: values[2], alpha: 1
                    )
                    .usingColorSpace(.extendedSRGB)
                else { return nil }
                rgb = [color.redComponent, color.greenComponent, color.blueComponent]
            default: return nil
            }
        default: return nil
        }
        guard rgb.allSatisfy(\.isFinite) else { return nil }
        return ClipboardColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: alpha)
    }

    func composited(over background: ClipboardColor) -> ClipboardColor {
        ClipboardColor(
            red: red * alpha + background.red * (1 - alpha),
            green: green * alpha + background.green * (1 - alpha),
            blue: blue * alpha + background.blue * (1 - alpha))
    }

    var usesDarkText: Bool {
        let luminance =
            0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
        // Prefer white on saturated swatches; use black when large text would fall below 3:1.
        return 1.05 / (luminance + 0.05) < 3
    }

    static func displayValue(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let color = hex(trimmed.lowercased()) else { return trimmed }
        let digits = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        let channels =
            [color.red, color.green, color.blue]
            + ([4, 8].contains(digits.count) ? [color.alpha] : [])
        return "#" + channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    private static func hex(_ value: String) -> ClipboardColor? {
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard [3, 4, 6, 8].contains(digits.utf8.count),
            digits.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { return nil }
        let expanded = digits.count < 5 ? digits.map { "\($0)\($0)" }.joined() : digits
        guard let packed = UInt32(expanded, radix: 16) else { return nil }
        let rgba = expanded.count == 8 ? packed : (packed << 8) | 255
        return ClipboardColor(
            red: Double((rgba >> 24) & 255) / 255,
            green: Double((rgba >> 16) & 255) / 255,
            blue: Double((rgba >> 8) & 255) / 255,
            alpha: Double(rgba & 255) / 255)
    }

    private static func components(_ text: String, function: String) -> ([String], Double)? {
        let parts: [String]
        let opacity: String
        if text.contains(",") {
            guard ["rgb", "rgba", "hsl", "hsla"].contains(function), !text.contains("/") else {
                return nil
            }
            let tokens = text.components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard [3, 4].contains(tokens.count), !tokens.contains("none") else { return nil }
            parts = Array(tokens.prefix(3))
            opacity = tokens.count == 4 ? tokens[3] : "1"
            if function.hasPrefix("rgb") {
                let percentages = parts.filter { $0.hasSuffix("%") }.count
                guard percentages == 0 || percentages == 3 else { return nil }
            }
        } else {
            let halves = text.components(separatedBy: "/")
            guard halves.count <= 2 else { return nil }
            parts = halves[0].split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count == (function == "color" ? 4 : 3) else { return nil }
            opacity =
                halves.count == 2 ? halves[1].trimmingCharacters(in: .whitespacesAndNewlines) : "1"
        }
        guard let alpha = scalar(opacity, percentage: 1) else { return nil }
        return (parts, clamp(alpha))
    }

    private static func scalar(_ token: String, percentage: Double, number: Double = 1) -> Double? {
        if token == "none" { return 0 }
        let isPercentage = token.hasSuffix("%")
        let digits = isPercentage ? String(token.dropLast()) : token
        guard
            digits.range(
                of: #"^[+-]?(?:[0-9]*\.[0-9]+|[0-9]+)(?:e[+-]?[0-9]+)?$"#,
                options: .regularExpression) != nil,
            let value = Double(digits), value.isFinite
        else { return nil }
        let result = value * (isPercentage ? percentage / 100 : number)
        return result.isFinite ? result : nil
    }

    private static func percentage(_ token: String) -> Double? {
        guard token.hasSuffix("%") || token == "none" else { return nil }
        return scalar(token, percentage: 1)
    }

    private static func numbers(_ tokens: [String], percentage: Double, number: Double) -> [Double]?
    {
        let values = tokens.compactMap { scalar($0, percentage: percentage, number: number) }
        return values.count == tokens.count ? values : nil
    }

    private static func hue(_ token: String) -> Double? {
        for (suffix, multiplier) in [
            ("grad", 0.9), ("turn", 360.0), ("deg", 1.0), ("rad", 180 / Double.pi), ("", 1.0),
        ] {
            if token.hasSuffix(suffix) {
                let digits = suffix.isEmpty ? token : String(token.dropLast(suffix.count))
                guard !digits.hasSuffix("%"), let number = scalar(digits, percentage: 1) else {
                    return nil
                }
                let value = number.truncatingRemainder(dividingBy: 360 / multiplier) * multiplier
                return value < 0 ? value + 360 : value
            }
        }
        return nil
    }

    private static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> [Double] {
        let amplitude = saturation * min(lightness, 1 - lightness)
        return [0.0, 8.0, 4.0].map { offset in
            let k = (offset + hue / 30).truncatingRemainder(dividingBy: 12)
            return lightness - amplitude * max(-1, min(k - 3, 9 - k, 1))
        }
    }

    // CSS Color 4 conversions: https://www.w3.org/TR/css-color-4/#color-conversion-code
    // Preview colors outside sRGB are clipped to the displayable sRGB range.
    private static func oklab(_ lightness: Double, _ a: Double, _ b: Double) -> [Double] {
        let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
        return [
            4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
        ].map(encoded)
    }

    private static func lab(_ lightness: Double, _ a: Double, _ b: Double) -> [Double] {
        let y = (lightness + 16) / 116
        func inverse(_ value: Double) -> Double {
            pow(value, 3) > 216 / 24389.0 ? pow(value, 3) : (116 * value - 16) / (24389 / 27.0)
        }
        let x50 = inverse(y + a / 500) * (0.3457 / 0.3585)
        let y50 = inverse(y)
        let z50 = inverse(y - b / 200) * ((1 - 0.3457 - 0.3585) / 0.3585)
        let x = 0.9554734215 * x50 - 0.0230984549 * y50 + 0.0632592432 * z50
        let yy = -0.0283697093 * x50 + 1.0099953981 * y50 + 0.0210414412 * z50
        let z = 0.0123140149 * x50 - 0.0205076493 * y50 + 1.3303659262 * z50
        return [
            3.2409699419 * x - 1.5373831776 * yy - 0.4986107603 * z,
            -0.9692436363 * x + 1.8759675015 * yy + 0.0415550574 * z,
            0.0556300797 * x - 0.2039769589 * yy + 1.0569715142 * z,
        ].map(encoded)
    }

    private static func linear(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ value: Double) -> Double {
        value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private static func clamp(_ value: Double) -> Double { min(1, max(0, value)) }

    // CSS named colors use sRGB, independent of the system's named NSColor palette.
    private static let namedColors: [String: String] = [
        "aliceblue": "f0f8ff", "antiquewhite": "faebd7", "aqua": "00ffff", "aquamarine": "7fffd4",
        "azure": "f0ffff", "beige": "f5f5dc", "bisque": "ffe4c4", "black": "000000",
        "blanchedalmond": "ffebcd", "blue": "0000ff", "blueviolet": "8a2be2", "brown": "a52a2a",
        "burlywood": "deb887", "cadetblue": "5f9ea0", "chartreuse": "7fff00", "chocolate": "d2691e",
        "coral": "ff7f50", "cornflowerblue": "6495ed", "cornsilk": "fff8dc", "crimson": "dc143c",
        "cyan": "00ffff", "darkblue": "00008b", "darkcyan": "008b8b", "darkgoldenrod": "b8860b",
        "darkgray": "a9a9a9", "darkgreen": "006400", "darkgrey": "a9a9a9", "darkkhaki": "bdb76b",
        "darkmagenta": "8b008b", "darkolivegreen": "556b2f", "darkorange": "ff8c00",
        "darkorchid": "9932cc",
        "darkred": "8b0000", "darksalmon": "e9967a", "darkseagreen": "8fbc8f",
        "darkslateblue": "483d8b",
        "darkslategray": "2f4f4f", "darkslategrey": "2f4f4f", "darkturquoise": "00ced1",
        "darkviolet": "9400d3",
        "deeppink": "ff1493", "deepskyblue": "00bfff", "dimgray": "696969", "dimgrey": "696969",
        "dodgerblue": "1e90ff", "firebrick": "b22222", "floralwhite": "fffaf0",
        "forestgreen": "228b22",
        "fuchsia": "ff00ff", "gainsboro": "dcdcdc", "ghostwhite": "f8f8ff", "gold": "ffd700",
        "goldenrod": "daa520", "gray": "808080", "green": "008000", "greenyellow": "adff2f",
        "grey": "808080", "honeydew": "f0fff0", "hotpink": "ff69b4", "indianred": "cd5c5c",
        "indigo": "4b0082", "ivory": "fffff0", "khaki": "f0e68c", "lavender": "e6e6fa",
        "lavenderblush": "fff0f5", "lawngreen": "7cfc00", "lemonchiffon": "fffacd",
        "lightblue": "add8e6",
        "lightcoral": "f08080", "lightcyan": "e0ffff", "lightgoldenrodyellow": "fafad2",
        "lightgray": "d3d3d3",
        "lightgreen": "90ee90", "lightgrey": "d3d3d3", "lightpink": "ffb6c1",
        "lightsalmon": "ffa07a",
        "lightseagreen": "20b2aa", "lightskyblue": "87cefa", "lightslategray": "778899",
        "lightslategrey": "778899",
        "lightsteelblue": "b0c4de", "lightyellow": "ffffe0", "lime": "00ff00",
        "limegreen": "32cd32",
        "linen": "faf0e6", "magenta": "ff00ff", "maroon": "800000", "mediumaquamarine": "66cdaa",
        "mediumblue": "0000cd", "mediumorchid": "ba55d3", "mediumpurple": "9370db",
        "mediumseagreen": "3cb371",
        "mediumslateblue": "7b68ee", "mediumspringgreen": "00fa9a", "mediumturquoise": "48d1cc",
        "mediumvioletred": "c71585",
        "midnightblue": "191970", "mintcream": "f5fffa", "mistyrose": "ffe4e1",
        "moccasin": "ffe4b5",
        "navajowhite": "ffdead", "navy": "000080", "oldlace": "fdf5e6", "olive": "808000",
        "olivedrab": "6b8e23", "orange": "ffa500", "orangered": "ff4500", "orchid": "da70d6",
        "palegoldenrod": "eee8aa", "palegreen": "98fb98", "paleturquoise": "afeeee",
        "palevioletred": "db7093",
        "papayawhip": "ffefd5", "peachpuff": "ffdab9", "peru": "cd853f", "pink": "ffc0cb",
        "plum": "dda0dd", "powderblue": "b0e0e6", "purple": "800080", "rebeccapurple": "663399",
        "red": "ff0000", "rosybrown": "bc8f8f", "royalblue": "4169e1", "saddlebrown": "8b4513",
        "salmon": "fa8072", "sandybrown": "f4a460", "seagreen": "2e8b57", "seashell": "fff5ee",
        "sienna": "a0522d", "silver": "c0c0c0", "skyblue": "87ceeb", "slateblue": "6a5acd",
        "slategray": "708090", "slategrey": "708090", "snow": "fffafa", "springgreen": "00ff7f",
        "steelblue": "4682b4", "tan": "d2b48c", "teal": "008080", "thistle": "d8bfd8",
        "tomato": "ff6347", "turquoise": "40e0d0", "violet": "ee82ee", "wheat": "f5deb3",
        "white": "ffffff", "whitesmoke": "f5f5f5", "yellow": "ffff00", "yellowgreen": "9acd32",
    ]
}
