import AppKit
import XCTest

@testable import OpenPaste

@MainActor
final class ShortcutTests: XCTestCase {
    private func withStore(_ body: (ShortcutStore, UserDefaults) -> Void) {
        let suite = "OpenPaste.ShortcutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(ShortcutStore(defaults: defaults), defaults)
    }

    private func event(_ code: UInt16, flags: NSEvent.ModifierFlags = [], text: String = "")
        -> NSEvent
    {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: text,
            charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
    }

    func testDefaultsPreserveExistingCommands() async {
        withStore { store, _ in
            XCTAssertEqual(store.bindings.count, ShortcutAction.allCases.count)
            XCTAssertEqual(store[.togglePanel]?.display, "⇧⌘V")
            XCTAssertEqual(store.action(for: event(123), searchIsEmpty: true), .previousClip)
            XCTAssertEqual(
                store.action(for: event(124, flags: .command), searchIsEmpty: true), .nextBoard)
            XCTAssertEqual(store.action(for: event(76), searchIsEmpty: true), .paste)
            XCTAssertEqual(store.pinboardNumber(for: event(18, flags: .command)), 1)
        }
    }

    func testReassignmentDeletionAndModifierSurviveReload() async {
        withStore { store, defaults in
            let custom = AppShortcut(keyCode: 35, flags: [.command, .option], keyLabel: "P")
            XCTAssertTrue(store.set(custom, for: .paste))
            XCTAssertTrue(store.set(nil, for: .close))
            store.setPinboardModifier(.control)
            let reloaded = ShortcutStore(defaults: defaults)
            XCTAssertEqual(reloaded[.paste], custom)
            XCTAssertNil(reloaded[.close])
            XCTAssertEqual(reloaded.pinboardModifier, .control)
            XCTAssertEqual(reloaded[.nextBoard], ShortcutAction.nextBoard.defaultShortcut)
        }
    }

    func testNewKeyReplacesOldKeyImmediately() async {
        withStore { store, _ in
            XCTAssertTrue(
                store.set(AppShortcut(keyCode: 35, flags: .option, keyLabel: "P"), for: .paste))
            XCTAssertNil(store.action(for: event(36), searchIsEmpty: true))
            XCTAssertEqual(
                store.action(for: event(35, flags: .option), searchIsEmpty: true), .paste)
            XCTAssertNil(
                store.action(for: event(35, flags: [.option, .shift]), searchIsEmpty: true))
            XCTAssertTrue(store.set(nil, for: .paste))
            XCTAssertNil(store.action(for: event(35, flags: .option), searchIsEmpty: true))
        }
    }

    func testDeleteWithoutSearchDoesNotDeleteWhileTyping() async {
        withStore { store, _ in
            XCTAssertNil(store.action(for: event(51), searchIsEmpty: false))
            XCTAssertEqual(store.action(for: event(51), searchIsEmpty: true), .deleteWithoutSearch)
            XCTAssertEqual(
                store.action(for: event(51, flags: .command), searchIsEmpty: false), .delete)
        }
    }

    func testCommandFOpensSearch() async {
        withStore { store, _ in
            XCTAssertEqual(
                store.action(for: event(3, flags: .command), searchIsEmpty: true), .search)
            XCTAssertEqual(
                store.action(for: event(3, flags: .command), searchIsEmpty: false), .search)
        }
    }

    func testShiftArrowsAndCommandAMapToSelection() async {
        withStore { store, _ in
            XCTAssertEqual(
                store.action(for: event(123, flags: .shift), searchIsEmpty: true), .extendPrevious)
            XCTAssertEqual(
                store.action(for: event(124, flags: .shift), searchIsEmpty: true), .extendNext)
            XCTAssertEqual(
                store.action(for: event(0, flags: .command), searchIsEmpty: true), .selectAll)
            XCTAssertEqual(store.action(for: event(124), searchIsEmpty: true), .nextClip)
            XCTAssertEqual(store.action(for: event(48), searchIsEmpty: false), .tabToCards)
            XCTAssertNil(store.action(for: event(48, flags: .shift), searchIsEmpty: false))
        }
    }

    func testSelectionRangeGrowsAndCollapses() {
        let state = PanelState()
        state.selection = 2
        state.extendSelection(to: 3)
        state.extendSelection(to: 4)
        XCTAssertEqual(state.selectedRange, 2...4)
        state.extendSelection(to: 1)  // crossing the anchor flips the range
        XCTAssertEqual(state.selectedRange, 1...2)
        state.selection = 5  // plain move collapses
        XCTAssertEqual(state.selectedRange, 5...5)
        state.tabbedToCards = true
        state.query = "a"  // typing again returns Tab to "first card"
        XCTAssertFalse(state.tabbedToCards)
    }

    func testDuplicateBindingLeavesPreviousAssignmentIntact() async {
        withStore { store, _ in
            XCTAssertFalse(store.set(ShortcutAction.previousBoard.defaultShortcut, for: .nextBoard))
            XCTAssertEqual(store[.nextBoard], ShortcutAction.nextBoard.defaultShortcut)
            XCTAssertNotNil(store.errorMessage)
        }
    }

    func testPinboardConflictsAreCheckedInBothDirections() async {
        withStore { store, _ in
            XCTAssertFalse(
                store.set(AppShortcut(keyCode: 18, flags: .command, keyLabel: "1"), for: .paste))
            XCTAssertTrue(
                store.set(AppShortcut(keyCode: 18, flags: .option, keyLabel: "1"), for: .paste))
            store.setPinboardModifier(.option)
            XCTAssertEqual(store.pinboardModifier, .command)
            store.setPinboardModifier(.disabled)
            XCTAssertNil(store.pinboardNumber(for: event(18, flags: .command)))
            XCTAssertTrue(
                store.set(AppShortcut(keyCode: 18, flags: .command, keyLabel: "1"), for: .paste))
        }
    }

    func testModifierChangesPinboardRoutingImmediately() async {
        withStore { store, _ in
            store.setPinboardModifier(.control)
            XCTAssertNil(store.pinboardNumber(for: event(19, flags: .command)))
            XCTAssertEqual(store.pinboardNumber(for: event(19, flags: .control)), 2)
            XCTAssertNil(store.pinboardNumber(for: event(19, flags: [.control, .shift])))
        }
    }

    func testRecordingSuspendsCommandsAndResumesOnce() async {
        withStore { store, _ in
            var changes: [Bool] = []
            store.recordingChanged = {
                changes.append($0)
                return nil
            }
            store.setRecording(true)
            store.setRecording(true)
            XCTAssertNil(store.action(for: event(36), searchIsEmpty: true))
            XCTAssertNil(store.pinboardNumber(for: event(18, flags: .command)))
            store.setRecording(false)
            XCTAssertEqual(changes, [true, false])
            XCTAssertEqual(store.action(for: event(36), searchIsEmpty: true), .paste)
        }
    }

    func testRegistrationFailureDoesNotPersistNewGlobalShortcut() async {
        withStore { store, defaults in
            store.applyGlobalShortcut = { _ in "Занято" }
            XCTAssertFalse(
                store.set(
                    AppShortcut(keyCode: 35, flags: [.command, .option], keyLabel: "P"),
                    for: .togglePanel))
            XCTAssertEqual(store[.togglePanel], ShortcutAction.togglePanel.defaultShortcut)
            XCTAssertEqual(
                ShortcutStore(defaults: defaults)[.togglePanel],
                ShortcutAction.togglePanel.defaultShortcut)
        }
    }

    func testResetFailureIsAtomic() async {
        withStore { store, defaults in
            XCTAssertTrue(store.set(nil, for: .paste))
            store.setPinboardModifier(.control)
            store.applyGlobalShortcut = { _ in "Занято" }
            XCTAssertFalse(store.reset())
            XCTAssertNil(store[.paste])
            XCTAssertEqual(store.pinboardModifier, .control)
            XCTAssertNil(ShortcutStore(defaults: defaults)[.paste])
        }
    }

    func testResetRestoresOnlyShortcutPreferences() async {
        withStore { store, defaults in
            defaults.set(4, forKey: "unrelatedRetention")
            XCTAssertTrue(store.set(nil, for: .togglePanel))
            XCTAssertNil(ShortcutStore(defaults: defaults)[.togglePanel])
            store.setPinboardModifier(.disabled)
            XCTAssertTrue(store.reset())
            let reloaded = ShortcutStore(defaults: defaults)
            XCTAssertEqual(reloaded.bindings.count, ShortcutAction.allCases.count)
            XCTAssertEqual(reloaded.pinboardModifier, .command)
            XCTAssertEqual(defaults.integer(forKey: "unrelatedRetention"), 4)
        }
    }

    func testTypingKeysRequireModifiers() async {
        withStore { store, _ in
            XCTAssertFalse(store.set(AppShortcut(keyCode: 0, keyLabel: "A"), for: .paste))
            XCTAssertFalse(
                store.set(AppShortcut(keyCode: 0, flags: .shift, keyLabel: "A"), for: .togglePanel))
            XCTAssertFalse(store.set(AppShortcut(keyCode: 36, keyLabel: "↩"), for: .togglePanel))
            XCTAssertTrue(
                store.set(AppShortcut(keyCode: 0, flags: .control, keyLabel: "A"), for: .paste))
            XCTAssertTrue(store.set(AppShortcut(keyCode: 111, keyLabel: "F12"), for: .togglePanel))
        }
    }

    func testMatchingUsesPhysicalKeyAndIgnoresCapsLockAndFunctionFlags() async {
        let shortcut = ShortcutAction.togglePanel.defaultShortcut
        XCTAssertTrue(
            shortcut.matches(event(9, flags: [.command, .shift, .capsLock, .function], text: "М")))
        XCTAssertEqual(shortcut, AppShortcut(keyCode: 9, flags: [.command, .shift], keyLabel: "М"))
        XCTAssertFalse(shortcut.matches(event(9, flags: [.command, .shift, .option])))
    }
}
