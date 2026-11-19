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
final class PanelController {
    let store: ClipStore
    let state = PanelState()
    private let panel: PastePanel
    private var monitor: Any?

    init(store: ClipStore) {
        self.store = store
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
                store: store, state: state,
                onPaste: { [unowned self] in paste($0) },
                onDelete: { [unowned self] in delete($0) },
                onSwitchBoard: { [unowned self] in switchBoard(to: $0) },
                onPin: { [unowned self] in pin($0, to: $1) }))
        host.sizingOptions = []  // show() owns the frame; the empty hidden view must not shrink the window
        panel.contentView = host

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            self?.hide()
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
            guard let self else { return e }
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

    /// Arrow keys, Enter and Esc are taken here before the search field sees them; other keys go to search.
    private func handle(_ e: NSEvent) -> Bool {
        if state.boardEditor != nil {  // the pinboard name field owns the keyboard
            if e.keyCode == 53 {
                state.boardEditor = nil
                return true
            }
            return false
        }
        let clips = state.visibleClips(store)
        let cmd = e.modifierFlags.contains(.command)
        if cmd, let n = Self.digitKeys[Int(e.keyCode)] {  // ⌘1…⌘9: pin selected card to pinboard N
            if store.pinboards.indices.contains(n - 1), clips.indices.contains(state.selection) {
                pin(clips[state.selection], to: store.pinboards[n - 1])
            }
            return true
        }
        switch Int(e.keyCode) {
        case 123 where cmd: moveBoard(-1)
        case 124 where cmd: moveBoard(+1)
        case 123: state.selection = max(state.selection - 1, 0)
        case 124: state.selection = min(state.selection + 1, max(clips.count - 1, 0))
        case 36, 76: if clips.indices.contains(state.selection) { paste(clips[state.selection]) }
        case 53: hide()
        // Plain ⌫ deletes the card only with an empty query; otherwise it edits the search text.
        case 51 where cmd || state.query.isEmpty:
            if clips.indices.contains(state.selection) { delete(clips[state.selection]) }
        case 6 where cmd:  // ⌘Z
            if let restored = store.undoDelete() {
                state.board = restored.pinboardID  // jump to the tab it came from
                state.selection = state.visibleClips(store).firstIndex { $0.id == restored.id } ?? 0
            }
        default: return false
        }
        return true
    }

    /// Key codes of the 1…9 row on ANSI layout (layout-independent, so it works with Russian input too).
    private static let digitKeys = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

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

    /// ⌘← / ⌘→: history tab, then pinboards in order; stops at the ends.
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
