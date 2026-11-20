import AppKit
import SwiftUI

@main
struct OpenPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // No menu bar icon: settings and quit are in the panel's "⋯" menu. A scene is still required;
        // a Settings scene would open its own empty window on ⌘, next to ours.
        MenuBarExtra("OpenPaste", systemImage: "doc.on.clipboard", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = ClipStore()
    let shortcuts = ShortcutStore()
    lazy var panel = PanelController(store: store, shortcuts: shortcuts)
    private var hotKey: HotKey?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // no Dock icon
        store.start()
        panel.onSettings = { [weak self] in self?.showSettings() }
        hotKey = HotKey { [weak self] in self?.panel.toggle() }
        shortcuts.applyGlobalShortcut = { [weak self] in self?.hotKey?.setShortcut($0) }
        shortcuts.recordingChanged = { [weak self] in self?.hotKey?.setSuspended($0) }
        shortcuts.errorMessage = hotKey?.setShortcut(shortcuts[.togglePanel])
        Paster.requestAccess()
        panel.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panel.show()
        return false
    }

    /// Own window instead of the SwiftUI Settings scene: openSettings is unreliable in menu-bar-only apps.
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(
                    rootView: SettingsView(store: store, shortcuts: shortcuts)))
            window.title = "Настройки OpenPaste"
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar = NSToolbar(identifier: "OpenPasteSettings")
            window.toolbarStyle = .unified
            window.setContentSize(SettingsLayout.windowSize)
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        panel.hide()
        NSApp.activate()
        settingsWindow?.deminiaturize(nil)
        // Activation can complete after the menu action returns.
        settingsWindow?.orderFrontRegardless()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        store.flush(wait: true)
        guard let error = store.persistenceError else { return .terminateNow }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Не удалось сохранить историю"
        alert.informativeText = error
        alert.addButton(withTitle: "Оставить OpenPaste открытым")
        alert.addButton(withTitle: "Выйти без сохранения")
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
