import AppKit

/// Draws a colored border around the focused window when in Normal/Visual mode.
@MainActor
final class FocusHighlight {
    private var overlayWindow: NSWindow?

    func show() {
        hide()
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let pid = app.processIdentifier

        // Find the frontmost normal window of the focused app.
        // Filter out menu bars, overlays, and tiny utility windows.
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return }

        // Pick the largest window owned by this app that's at least 200x100.
        // This avoids menu bars, status items, and overlays.
        let candidates = windowList.filter { info in
            (info[kCGWindowOwnerPID as String] as? pid_t) == pid &&
            (info[kCGWindowLayer as String] as? Int == 0) &&
            (info[kCGWindowAlpha as String] as? Double ?? 0 > 0)
        }

        guard let windowInfo = candidates.max(by: { a, b in
            let aArea = area(info: a)
            let bArea = area(info: b)
            return aArea < bArea
        }) else { return }

        guard let boundsDict = windowInfo[kCGWindowBounds as String] as? [String: CGFloat],
              let x = boundsDict["X"], let y = boundsDict["Y"],
              let w = boundsDict["Width"], let h = boundsDict["Height"] else { return }

        // Skip if too small (likely a status item or menu, not a real window).
        guard w > 200 && h > 100 else { return }

        // CGWindowList uses top-left origin; NSWindow uses bottom-left.
        let screen = NSScreen.main
        let screenHeight = screen?.frame.height ?? 0
        let flippedY = screenHeight - y - h

        let borderWidth: CGFloat = 3
        let frame = NSRect(
            x: x - borderWidth,
            y: flippedY - borderWidth,
            width: w + borderWidth * 2,
            height: h + borderWidth * 2
        )

        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.borderColor = NSColor(srgbRed: 0.90, green: 0.55, blue: 0.15, alpha: 0.8).cgColor
        view.layer?.borderWidth = borderWidth
        window.contentView = view

        overlayWindow = window
        window.orderFrontRegardless()
    }

    private func area(info: [String: Any]) -> CGFloat {
        guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat],
              let w = bounds["Width"], let h = bounds["Height"] else { return 0 }
        return w * h
    }

    func hide() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }
}
