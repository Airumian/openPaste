import AppKit
import XCTest
@testable import OpenPaste

@MainActor
final class HotKeyTests: XCTestCase {
    func testRegistrationReplacementSuspensionAndRemoval() async {
        let first = HotKey(action: {})
        let second = HotKey(action: {})
        let probe = HotKey(action: {})
        let a = AppShortcut(keyCode: 64, flags: [.control, .option, .command], keyLabel: "F17")
        let b = AppShortcut(keyCode: 79, flags: [.control, .option, .command], keyLabel: "F18")
        let c = AppShortcut(keyCode: 80, flags: [.control, .option, .command], keyLabel: "F19")

        XCTAssertNil(first.setShortcut(a))
        XCTAssertNotNil(second.setShortcut(a), "A registered combination must not be accepted twice")
        XCTAssertNil(second.setShortcut(b))
        XCTAssertNotNil(first.setShortcut(b))
        XCTAssertNotNil(probe.setShortcut(a), "A failed replacement must retain the old key")

        XCTAssertNil(first.setShortcut(c))
        XCTAssertNil(probe.setShortcut(a), "Successful replacement must release the old key")
        XCTAssertNil(probe.setShortcut(nil))

        XCTAssertNil(first.setSuspended(true))
        XCTAssertNil(probe.setShortcut(c), "Recording must release the active global key")
        XCTAssertNil(probe.setShortcut(nil))
        XCTAssertNil(first.setSuspended(false))
        XCTAssertNotNil(probe.setShortcut(c), "The active key must be restored after recording")

        XCTAssertNil(first.setShortcut(nil))
        XCTAssertNil(probe.setShortcut(c), "Clearing a shortcut must unregister it")
    }
}
