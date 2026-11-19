import AppKit
import Carbon

/// Global hotkey via Carbon: still the only public API that works without Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private static var action: (() -> Void)?

    init(
        keyCode: Int = kVK_ANSI_V, modifiers: Int = cmdKey | shiftKey, action: @escaping () -> Void
    ) {
        HotKey.action = action
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                HotKey.action?()
                return noErr
            }, 1, &spec, nil, nil)
        RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: 0x4F50_5354, id: 1),
            GetApplicationEventTarget(), 0, &ref)
    }
}

enum Paster {
    /// Shows the system prompt the first time. Without it, ⌘V simulation is silently dropped.
    @discardableResult
    static func requestAccess() -> Bool {
        AXIsProcessTrustedWithOptions(
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary)
    }

    static func sendCmdV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            let e = CGEvent(
                keyboardEventSource: src, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: down)
            e?.flags = .maskCommand
            e?.post(tap: .cghidEventTap)
        }
    }
}
