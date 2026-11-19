import AppKit

/// Dimensions measured against Paste's settings window, in screen points.
enum SettingsLayout {
    static let windowSize = NSSize(width: 640, height: 666)
    static let sidebarWidth: CGFloat = 200
    static let headerHeight: CGFloat = 52
    static let contentInset: CGFloat = 20
    static let cardInset: CGFloat = 10
}
