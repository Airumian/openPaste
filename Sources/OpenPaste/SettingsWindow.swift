import AppKit

final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Settings are already visible. Consume the command so it never reaches
        // the responder's unhandled-key beep. Shortcut recording runs before this.
        if AppShortcut.openSettings.matches(event) { return true }
        return super.performKeyEquivalent(with: event)
    }
}
