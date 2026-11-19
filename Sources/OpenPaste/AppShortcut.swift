import AppKit
import Carbon

struct AppShortcut: Codable, Equatable {
    let keyCode: UInt16
    let modifiers: UInt
    let keyLabel: String

    static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    static let digitKeys: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
    private static let specialKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "Esc", 76: "↩", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7",
        100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13",
        107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    init(keyCode: UInt16, flags: NSEvent.ModifierFlags = [], keyLabel: String) {
        self.keyCode = keyCode == 76 ? 36 : keyCode
        modifiers = flags.intersection(Self.modifierMask).rawValue
        self.keyLabel = Self.specialKeys[keyCode] ?? keyLabel.uppercased()
    }

    init?(event: NSEvent) {
        guard event.type == .keyDown, !event.isARepeat else { return nil }
        let label = Self.specialKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased()
        guard let label, !label.isEmpty else { return nil }
        self.init(keyCode: event.keyCode, flags: event.modifierFlags, keyLabel: label)
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers).intersection(Self.modifierMask) }
    var display: String { Self.symbols(for: flags) + keyLabel }
    var hasCommandModifier: Bool { !flags.intersection([.command, .option, .control]).isEmpty }
    var isFunctionKey: Bool { Self.specialKeys[keyCode]?.hasPrefix("F") == true }
    var isNavigationKey: Bool { [36, 48, 51, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(keyCode) }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    func matches(_ event: NSEvent) -> Bool {
        let code: UInt16 = event.keyCode == 76 ? 36 : event.keyCode
        return keyCode == code && flags == event.modifierFlags.intersection(Self.modifierMask)
    }

    static func symbols(for flags: NSEvent.ModifierFlags) -> String {
        (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "")
            + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.flags == rhs.flags
    }
}
