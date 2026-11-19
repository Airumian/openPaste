import AppKit
import SwiftUI

@Observable
final class PanelState {
    var query = ""
    var selection = 0
    var shownAt = Date()
    var isVisible = false
    var board: UUID?  // nil = clipboard history tab
    var searchExpanded = false  // search field opened via the magnifier (it also shows whenever the query is non-empty)
    var renamingClip: UUID?  // card whose title is being edited inline
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
    private var hideAnimationID: UUID?
    var onSettings: () -> Void = {}

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
        panel.hasShadow = false  // the glass draws its own rim and shadow; the window shadow added a second, mismatched border
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let host = NSHostingView(
            rootView: PanelView(
                store: store, shortcuts: shortcuts, state: state,
                onPaste: { [unowned self] in paste($0) },
                onDelete: { [unowned self] in delete($0) },
                onSwitchBoard: { [unowned self] in switchBoard(to: $0) },
                onPin: { [unowned self] in pin($0, to: $1) },
                onSettings: { [unowned self] in onSettings() }))
        host.sizingOptions = []  // show() owns the frame; the empty hidden view must not shrink the window
        panel.contentView = host

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state.isVisible else { return }
                self.hide(animated: true)
            }
        }
    }

    // Uses state, not panel.isVisible: during the slide-out the window is still on screen.
    func toggle() { state.isVisible ? hide(animated: true) : show() }

    func show() {
        if state.isVisible {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        hideAnimationID = nil
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main!
        let f = screen.frame
        // The window spans the screen bottom; PanelView insets the glass inside it so the glass shadow
        // has transparent room instead of being cut off at the window's square corners.
        panel.setFrame(
            NSRect(
                x: f.minX, y: f.minY, width: f.width,
                height: 324 + PanelView.shadowRoom.top + PanelView.shadowRoom.bottom),
            display: true)

        store.pruneExpired()
        state.query = ""
        state.selection = 0
        state.boardEditor = nil
        state.renamingClip = nil
        state.searchExpanded = false
        state.dragging = nil
        if let b = state.board, !store.pinboards.contains(where: { $0.id == b }) {
            state.board = nil
        }
        state.shownAt = Date()
        panel.makeKeyAndOrderFront(nil)
        // Content is inserted under an animation, so PanelView's transition slides it up from the screen edge.
        // Critically damped: no gesture momentum behind a hotkey, so no overshoot (Apple's default spring).
        withAnimation(.spring(duration: 0.35, bounce: 0)) { state.isVisible = true }

        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self, e.window === panel else { return e }
            return handle(e) ? nil : e
        }
    }

    /// Pasting hides immediately so the target app gets keyboard focus before the synthetic ⌘V.
    func hide(animated: Bool = false) {
        guard panel.isVisible else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard animated else {
            hideAnimationID = nil
            panel.orderOut(nil)
            state.isVisible = false
            return
        }
        let animationID = UUID()
        hideAnimationID = animationID
        withAnimation(.spring(duration: 0.25, bounce: 0)) {  // mirrors the entrance spring
            state.isVisible = false
        } completion: { [weak self] in
            guard let self, hideAnimationID == animationID else { return }
            hideAnimationID = nil
            panel.orderOut(nil)
        }
    }

    /// Assigned panel commands are handled before the search field; other keys go to search.
    private func handle(_ e: NSEvent) -> Bool {
        if state.boardEditor != nil || state.renamingClip != nil {  // a name field owns the keyboard
            if e.keyCode == 53 {
                state.boardEditor = nil
                state.renamingClip = nil
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
        guard let action = shortcuts.action(for: e, searchIsEmpty: state.query.isEmpty) else {
            return false
        }
        switch action {
        case .previousBoard: moveBoard(-1)
        case .nextBoard: moveBoard(+1)
        case .previousClip: state.selection = max(state.selection - 1, 0)
        case .nextClip: state.selection = min(state.selection + 1, max(clips.count - 1, 0))
        case .paste: if clips.indices.contains(state.selection) { paste(clips[state.selection]) }
        case .close where !state.query.isEmpty || state.searchExpanded:
            // First Esc leaves search (clears and collapses it); the next one closes the panel.
            state.query = ""
            state.searchExpanded = false
        case .close: hide(animated: true)
        case .delete where !state.query.isEmpty:  // Clear the search before deleting cards, like a text field.
            state.query = ""
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
        // Without Accessibility the synthetic ⌘V is silently dropped; ask instead of failing invisibly.
        // The clip is already on the clipboard, so a manual ⌘V still works meanwhile.
        guard AXIsProcessTrusted() else {
            Paster.requestAccess()
            return
        }
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
        // No withAnimation here: it animated the whole card list too, making it flicker on every switch.
        state.board = board
        state.selection = 0
    }
}
