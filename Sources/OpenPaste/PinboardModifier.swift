import SwiftUI

enum PinboardModifier: String, CaseIterable, Identifiable {
    case command, option, control, shift, disabled

    var id: Self { self }
    var title: String {
        switch self {
        case .command: "⌘ Command"
        case .option: "⌥ Option"
        case .control: "⌃ Control"
        case .shift: "⇧ Shift"
        case .disabled: "Не назначено"
        }
    }
    var flags: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        case .disabled: []
        }
    }
    var eventModifiers: EventModifiers {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        case .disabled: []
        }
    }
    var symbol: String { AppShortcut.symbols(for: flags) }
}
