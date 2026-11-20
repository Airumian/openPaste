import AppKit
import SwiftUI

/// A passive marker behind an inline editor. AppKit keeps text fields focused when a click
/// lands on non-focusable content, so ending the edit must also handle those clicks explicitly.
struct CommitOnOutsideClick: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> MarkerView { MarkerView() }

    func updateNSView(_ view: MarkerView, context: Context) {
        view.action = action
    }

    static func dismantleNSView(_ view: MarkerView, coordinator: ()) {
        view.stopMonitoring()
    }

    final class MarkerView: NSView {
        var action: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stopMonitoring()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
                [weak self] event in
                guard let self, let window = self.window, event.window === window,
                    !self.isHiddenOrHasHiddenAncestor,
                    !self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                else { return event }
                self.action?()
                return event  // The same click must still reach the tab, card, or button.
            }
        }

        func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { stopMonitoring() }
    }
}
