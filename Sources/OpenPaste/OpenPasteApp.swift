import AppKit
import SwiftUI

@main
struct OpenPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("OpenPaste", systemImage: "doc.on.clipboard") {
            Button("Показать историю" + (delegate.shortcuts[.togglePanel].map { "  " + $0.display } ?? "")) {
                delegate.panel.toggle()
            }
            Button("Настройки…") { delegate.showSettings() }.keyboardShortcut(",")
            Divider()
            Button("Выход") { NSApp.terminate(nil) }.keyboardShortcut("q")
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
        hotKey = HotKey { [weak self] in self?.panel.toggle() }
        shortcuts.applyGlobalShortcut = { [weak self] in self?.hotKey?.setShortcut($0) }
        shortcuts.recordingChanged = { [weak self] in self?.hotKey?.setSuspended($0) }
        shortcuts.errorMessage = hotKey?.setShortcut(shortcuts[.togglePanel])
        Paster.requestAccess()
    }

    /// Own window instead of the SwiftUI Settings scene: openSettings is unreliable in menu-bar-only apps.
    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentViewController: NSHostingController(rootView: SettingsView(store: store, shortcuts: shortcuts)))
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
        NSApp.activate()  // menu bar apps are inactive; without this the window opens behind others
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush(wait: true)  // saves are debounced; don't lose the last half second
    }
}
