import AppKit
import SwiftUI

@Observable
final class PanelState {
    var query = ""
    var selection = 0
    var shownAt = Date()
    var isVisible = false
    var board: UUID?  // nil = clipboard history tab
    var boardEditor: BoardEditor?  // inline name field for a new or renamed pinboard
    var dragging: Clip?  // card being dragged onto a pinboard tab

    enum BoardEditor: Equatable {
        case new
        case rename(UUID)
    }

    func visibleClips(_ store: ClipStore) -> [Clip] { store.filtered(query, board: board) }
}

final class PastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Bottom-of-screen panel. Non-activating, so the app you were typing in stays frontmost and receives ⌘V.
@MainActor
final class PanelController {
    let store: ClipStore
    let shortcuts: ShortcutStore
    let state = PanelState()
    private let panel: PastePanel
    private var monitor: Any?

    init(store: ClipStore, shortcuts: ShortcutStore) {
        self.store = store
        self.shortcuts = shortcuts
        panel = PastePanel(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        // isFloatingPanel resets the window level; set it afterward to stay above the Dock.
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(
            rootView: PanelView(
                store: store, shortcuts: shortcuts, state: state,
                onPaste: { [unowned self] in paste($0) },
                onDelete: { [unowned self] in delete($0) },
                onSwitchBoard: { [unowned self] in switchBoard(to: $0) },
                onPin: { [unowned self] in pin($0, to: $1) }))
        host.sizingOptions = []  // show() owns the frame; the empty hidden view must not shrink the window
        panel.contentView = host

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    func toggle() { panel.isVisible ? hide() : show() }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let f = screen.frame
        panel.setFrame(
            NSRect(x: f.minX + 8, y: f.minY + 8, width: f.width - 16, height: 320), display: true)

        store.pruneExpired()
        state.query = ""
        state.selection = 0
        state.boardEditor = nil
        state.dragging = nil
        if let b = state.board, !store.pinboards.contains(where: { $0.id == b }) {
            state.board = nil
        }
        state.shownAt = Date()
        state.isVisible = true
        panel.makeKeyAndOrderFront(nil)

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === panel else { return e }
            return handle(e) ? nil : e
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        state.isVisible = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Assigned panel commands are handled before the search field; other keys go to search.
    private func handle(_ e: NSEvent) -> Bool {
        if state.boardEditor != nil {  // the pinboard name field owns the keyboard
            if e.keyCode == 53 {
                state.boardEditor = nil
                return true
            }
            return false
        }
        let clips = state.visibleClips(store)
        if let n = shortcuts.pinboardNumber(for: e) {
            if store.pinboards.indices.contains(n - 1), clips.indices.contains(state.selection) {
                pin(clips[state.selection], to: store.pinboards[n - 1])
            }
            return true
        }
        guard let action = shortcuts.action(for: e, searchIsEmpty: state.query.isEmpty) else { return false }
        switch action {
        case .previousBoard: moveBoard(-1)
        case .nextBoard: moveBoard(+1)
        case .previousClip: state.selection = max(state.selection - 1, 0)
        case .nextClip: state.selection = min(state.selection + 1, max(clips.count - 1, 0))
        case .paste: if clips.indices.contains(state.selection) { paste(clips[state.selection]) }
        case .close: hide()
        case .delete, .deleteWithoutSearch:
            if clips.indices.contains(state.selection) { delete(clips[state.selection]) }
        case .undoDelete:
            if let restored = store.undoDelete() {
                state.board = restored.pinboardID  // jump to the tab it came from
                state.selection = state.visibleClips(store).firstIndex { $0.id == restored.id } ?? 0
            }
        case .togglePanel: return false  // handled by Carbon, not the local event monitor
        }
        return true
    }

    private func pin(_ clip: Clip, to board: Pinboard) {
        guard clip.pinboardID != board.id else { return }
        store.pin(clip, to: board)
    }

    private func paste(_ clip: Clip) {
        store.copy(clip)
        hide()
        // Give the target app a moment to become key again before the synthetic ⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { Paster.sendCmdV() }
    }

    private func delete(_ clip: Clip) {
        store.delete(clip)
        state.selection = min(state.selection, max(state.visibleClips(store).count - 1, 0))
    }

    /// History tab, then pinboards in order; stops at the ends.
    private func moveBoard(_ delta: Int) {
        let tabs: [UUID?] = [nil] + store.pinboards.map(\.id)
        let i = tabs.firstIndex(of: state.board) ?? 0
        switchBoard(to: tabs[min(max(i + delta, 0), tabs.count - 1)])
    }

    private func switchBoard(to board: UUID?) {
        withAnimation(.bouncy(duration: 0.35)) { state.board = board }
        state.selection = 0
    }
}
