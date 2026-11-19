import AppKit
import Observation

@MainActor @Observable
final class ShortcutRecorder {
    private(set) var action: ShortcutAction?
    @ObservationIgnored private let shortcuts: ShortcutStore
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private weak var window: NSWindow?

    init(shortcuts: ShortcutStore) { self.shortcuts = shortcuts }

    func start(_ action: ShortcutAction) {
        stop()
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.action = action
        shortcuts.errorMessage = nil
        shortcuts.setRecording(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        window = nil
        action = nil
        shortcuts.setRecording(false)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.type == .keyDown else {
            stop()  // Clicking elsewhere cancels recording, then delivers the click normally.
            return event
        }
        guard event.window === window, let action else { return event }
        if event.keyCode == 53, event.modifierFlags.intersection(AppShortcut.modifierMask).isEmpty {
            stop()
            return nil
        }
        guard let shortcut = AppShortcut(event: event) else { return nil }
        shortcuts.set(shortcut, for: action)
        stop()
        return nil
    }
}
