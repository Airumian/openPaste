import Carbon

/// Carbon delivers global hotkeys without requiring Accessibility permission.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var current: AppShortcut?
    private var suspended = false
    private let action: () -> Void
    private static let signature: OSType = 0x4F50_5354

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let context, let event else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier) == noErr,
                  identifier.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            if !hotKey.suspended, hotKey.ref != nil { hotKey.action() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }

    /// Keep the old registration until the new one succeeds, including when restoring defaults.
    func setShortcut(_ shortcut: AppShortcut?) -> String? {
        if current == shortcut, (ref != nil || suspended || shortcut == nil) { return nil }
        var candidate: EventHotKeyRef?
        if let shortcut {
            if let error = register(shortcut, into: &candidate) { return error }
        }
        if let ref { UnregisterEventHotKey(ref) }
        current = shortcut
        if suspended, let candidate {
            UnregisterEventHotKey(candidate)
            ref = nil
        } else {
            ref = candidate
        }
        return nil
    }

    func setSuspended(_ value: Bool) -> String? {
        guard suspended != value else { return nil }
        suspended = value
        if value {
            if let ref { UnregisterEventHotKey(ref) }
            ref = nil
        } else if let current {
            return register(current, into: &ref)
        }
        return nil
    }

    private func register(_ shortcut: AppShortcut, into result: inout EventHotKeyRef?) -> String? {
        guard handler != nil else { return "Не удалось включить глобальное сочетание клавиш. Перезапустите OpenPaste." }
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                        EventHotKeyID(signature: Self.signature, id: 1),
                                        GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &result)
        guard status != noErr else { return nil }
        return "Сочетание \(shortcut.display) занято другой программой или системой. Выберите другое сочетание."
    }
}
