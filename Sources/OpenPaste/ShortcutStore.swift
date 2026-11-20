import AppKit
import Observation

@MainActor @Observable
final class ShortcutStore {
    private(set) var bindings: [ShortcutAction: AppShortcut] = [:]
    private(set) var pinboardModifier: PinboardModifier
    private(set) var isRecording = false
    var errorMessage: String?
    @ObservationIgnored var applyGlobalShortcut: ((AppShortcut?) -> String?)?
    @ObservationIgnored var recordingChanged: ((Bool) -> String?)?
    @ObservationIgnored private let defaults: UserDefaults
    private static let prefix = "keyboardShortcut."

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        pinboardModifier =
            PinboardModifier(
                rawValue: defaults.string(forKey: Self.prefix + "pinboardModifier") ?? "")
            ?? .command
        for action in ShortcutAction.allCases {
            let key = Self.prefix + action.rawValue
            if let data = defaults.data(forKey: key),
                let shortcut = try? JSONDecoder().decode(AppShortcut.self, from: data)
            {
                bindings[action] = shortcut
            } else if defaults.object(forKey: key) as? Bool != false {
                bindings[action] = action.defaultShortcut
            }
        }
    }

    subscript(action: ShortcutAction) -> AppShortcut? { bindings[action] }

    @discardableResult
    func set(_ shortcut: AppShortcut?, for action: ShortcutAction) -> Bool {
        if let shortcut, let message = validationError(shortcut, for: action) {
            errorMessage = message
            return false
        }
        if action == .togglePanel, let message = applyGlobalShortcut?(shortcut) {
            errorMessage = message
            return false
        }
        bindings[action] = shortcut
        let key = Self.prefix + action.rawValue
        if let shortcut {
            defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
        } else {
            defaults.set(false, forKey: key)
        }
        errorMessage = nil
        return true
    }

    func setPinboardModifier(_ modifier: PinboardModifier) {
        if modifier != .disabled,
            let conflict = ShortcutAction.allCases.first(where: {
                guard let shortcut = bindings[$0] else { return false }
                return shortcut.flags == modifier.flags
                    && AppShortcut.digitKeys[shortcut.keyCode] != nil
            })
        {
            errorMessage = "Это сочетание уже используется для команды «\(conflict.title)»."
            return
        }
        pinboardModifier = modifier
        defaults.set(modifier.rawValue, forKey: Self.prefix + "pinboardModifier")
        errorMessage = nil
    }

    @discardableResult
    func reset() -> Bool {
        // Register the default global key first; failure leaves all saved choices intact.
        if let message = applyGlobalShortcut?(ShortcutAction.togglePanel.defaultShortcut) {
            errorMessage = message
            return false
        }
        bindings = Dictionary(
            uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        pinboardModifier = .command
        for action in ShortcutAction.allCases {
            defaults.removeObject(forKey: Self.prefix + action.rawValue)
        }
        defaults.removeObject(forKey: Self.prefix + "pinboardModifier")
        errorMessage = nil
        return true
    }

    func setRecording(_ recording: Bool) {
        guard isRecording != recording else { return }
        isRecording = recording
        if let message = recordingChanged?(recording) { errorMessage = message }
    }

    func action(for event: NSEvent, searchIsEmpty: Bool) -> ShortcutAction? {
        guard !isRecording else { return nil }
        return ShortcutAction.allCases.first {
            $0 != .togglePanel && ($0 != .deleteWithoutSearch || searchIsEmpty)
                && bindings[$0]?.matches(event) == true
        }
    }

    func pinboardNumber(for event: NSEvent) -> Int? {
        guard !isRecording, pinboardModifier != .disabled,
            event.modifierFlags.intersection(AppShortcut.modifierMask) == pinboardModifier.flags
        else { return nil }
        return AppShortcut.digitKeys[event.keyCode]
    }

    private func validationError(_ shortcut: AppShortcut, for action: ShortcutAction) -> String? {
        if !shortcut.hasCommandModifier && !shortcut.isFunctionKey
            && (action == .togglePanel || !shortcut.isNavigationKey)
        {
            return
                "Добавьте ⌘ Command, ⌥ Option или ⌃ Control, чтобы сочетание не мешало вводу текста."
        }
        if let conflict = ShortcutAction.allCases.first(where: {
            $0 != action && bindings[$0] == shortcut
        }) {
            return "Это сочетание уже используется для команды «\(conflict.title)»."
        }
        if pinboardModifier != .disabled, shortcut.flags == pinboardModifier.flags,
            AppShortcut.digitKeys[shortcut.keyCode] != nil
        {
            return "Это сочетание используется для закрепления карточки в пинборде."
        }
        return nil
    }
}
