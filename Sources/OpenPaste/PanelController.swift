import AppKit
import SwiftUI

@Observable
final class PanelState {
    var query = "" {
        didSet {
            guard query != oldValue else { return }
            if !query.isEmpty { searchExpanded = true }
            tabbedToCards = false
            select(nil)
        }
    }
    private(set) var cursor: UUID?
    private var anchor: UUID?
    private var selection: Set<UUID> = []
    var deletionSelection: UUID?
    var tabbedToCards = false

    func select(_ id: UUID?) {
        cursor = id
        anchor = nil
        selection = id.map { [$0] } ?? []
    }

    func selectedIDs(in clips: [Clip]) -> Set<UUID> {
        if cursor != nil { return selection }
        return clips.first.map { [$0.id] } ?? []
    }

    func cursorIndex(in clips: [Clip]) -> Int? {
        guard let cursor else { return clips.indices.first }
        return clips.firstIndex { $0.id == cursor }
    }

    func extendSelection(to index: Int, in clips: [Clip]) {
        guard clips.indices.contains(index) else { return }
        let start =
            anchor.flatMap { id in clips.firstIndex { $0.id == id } }
            ?? cursorIndex(in: clips) ?? index
        anchor = clips[start].id
        cursor = clips[index].id
        selection = Set(clips[min(start, index)...max(start, index)].map(\.id))
    }

    func selectAll(in clips: [Clip]) {
        cursor = clips.first?.id
        anchor = clips.last?.id
        selection = Set(clips.map(\.id))
    }
    var shownAt = Date()
    var isVisible = false
    var board: UUID? { didSet { if board != oldValue { select(nil) } } }  // nil = history
    var searchExpanded = false { didSet { tabbedToCards = false } }
    var searchFieldVisible: Bool { searchExpanded && !tabbedToCards }

    func switchSearchFocus(firstClipID: UUID?) {
        if tabbedToCards {
            searchExpanded = true
        } else {
            select(firstClipID)
            tabbedToCards = true
        }
    }
    var searchFocusRequest = Date()  // bumped by ⌘F to move keyboard focus into the search field
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
    private var clipEditor: ClipEditorWindow?
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
                onEdit: { [unowned self] in edit($0) },
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
        if let clipEditor {
            clipEditor.makeKeyAndOrderFront(nil)
            return
        }
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
        let frame = NSRect(x: f.minX, y: f.minY, width: f.width, height: PanelView.windowHeight)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }

        store.pruneExpired()
        state.query = ""
        state.boardEditor = nil
        state.renamingClip = nil
        state.searchExpanded = false
        state.dragging = nil
        if let b = state.board, !store.pinboards.contains(where: { $0.id == b }) {
            state.board = nil
        }
        state.select(state.visibleClips(store).first?.id)
        state.shownAt = Date()
        panel.makeKeyAndOrderFront(nil)
        withAnimation(.easeOut(duration: 0.12)) { state.isVisible = true }

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
        withAnimation(.easeOut(duration: 0.12)) {
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
        let index = state.cursorIndex(in: clips)
        if let n = shortcuts.pinboardNumber(for: e) {
            if store.pinboards.indices.contains(n - 1), let index {
                pin(clips[index], to: store.pinboards[n - 1])
            }
            return true
        }
        guard let action = shortcuts.action(for: e, searchIsEmpty: !state.searchExpanded) else {
            return false
        }
        switch action {
        case .previousBoard: moveBoard(-1)
        case .nextBoard: moveBoard(+1)
        case .previousClip:
            if !clips.isEmpty { state.select(clips[max((index ?? 1) - 1, 0)].id) }
        case .nextClip:
            if !clips.isEmpty { state.select(clips[min((index ?? -1) + 1, clips.count - 1)].id) }
        case .extendPrevious:
            state.extendSelection(to: max((index ?? 1) - 1, 0), in: clips)
        case .extendNext:
            state.extendSelection(to: min((index ?? -1) + 1, clips.count - 1), in: clips)
        case .tabToCards:
            state.switchSearchFocus(firstClipID: clips.first?.id)
        case .selectAll:
            state.selectAll(in: clips)
        case .paste:
            if let index { paste(clips[index]) }
        case .edit:
            if let index { edit(clips[index]) }
        case .close where !state.query.isEmpty || state.searchExpanded:
            // First Esc leaves search (clears and collapses it); the next one closes the panel.
            state.query = ""
            state.searchExpanded = false
        case .close: hide(animated: true)
        case .search:
            state.searchExpanded = true
            state.searchFocusRequest = Date()  // refocus even if search is already open
        case .delete where !state.query.isEmpty:  // Clear the search before deleting cards, like a text field.
            state.query = ""
        case .delete, .deleteWithoutSearch:
            guard state.deletionSelection == nil else { return true }
            let ids = state.selectedIDs(in: clips)
            let selected = clips.filter { ids.contains($0.id) }
            if selected.count == 1, let clip = selected.first {
                delete(clip)
            } else if let first = clips.firstIndex(where: { ids.contains($0.id) }) {
                let replacement =
                    clips[first...].first { !ids.contains($0.id) }
                    ?? clips.prefix(first).last
                remove(selected, selecting: replacement?.id)
            }
        case .undoDelete:
            if let restored = store.undoDelete() {
                state.board = restored.pinboardID
                state.select(restored.id)
            }
        case .togglePanel: return false  // handled by Carbon, not the local event monitor
        }
        return true
    }

    private func pin(_ clip: Clip, to board: Pinboard) {
        guard clip.pinboardID != board.id else { return }
        store.pin(clip, to: board)
    }

    private func edit(_ clip: Clip) {
        guard clip.canEditContents else { return }
        if let clipEditor {
            clipEditor.makeKeyAndOrderFront(nil)
            return
        }
        do {
            let editor = ClipEditorWindow(
                text: try store.textForEditing(clip), richText: clip.richText,
                onSave: { [store] text, richText in
                    try store.editContents(of: clip.id, text: text, richText: richText)
                },
                onClose: { [weak self] in
                    guard let self else { return }
                    self.clipEditor = nil
                    self.show()
                    if self.state.visibleClips(self.store).contains(where: { $0.id == clip.id }) {
                        self.state.select(clip.id)
                    }
                }
            )
            clipEditor = editor
            hide()
            NSApp.activate()
            editor.center()
            editor.makeKeyAndOrderFront(nil)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Не удалось открыть содержимое карточки"
            alert.beginSheetModal(for: panel)
        }
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
        guard state.deletionSelection == nil else { return }
        let clips = state.visibleClips(store)
        if let index = clips.firstIndex(where: { $0.id == clip.id }),
            state.selectedIDs(in: clips).contains(clip.id), clips.count > 1
        {
            let replacement = clips[index + 1 < clips.count ? index + 1 : index - 1].id
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                remove([clip], selecting: replacement)
                return
            }
            state.deletionSelection = replacement
            // Render the replacement's outline at its old position before shifting the row.
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
                self?.remove([clip], selecting: replacement)
            }
            return
        }
        remove([clip])
    }

    private func remove(_ selection: [Clip], selecting replacement: UUID? = nil) {
        let animation: Animation? =
            NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            ? nil : .easeOut(duration: 0.23)
        withAnimation(animation) {
            store.delete(selection)
            let clips = state.visibleClips(store)
            let remaining = Set(clips.map(\.id))
            state.select(
                [replacement, state.cursor].compactMap { $0 }.first { remaining.contains($0) })
            state.deletionSelection = nil
        }
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
        state.select(state.visibleClips(store).first?.id)
    }
}
