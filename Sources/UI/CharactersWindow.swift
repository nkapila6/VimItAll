import AppKit

/// Small floating window showing the last Vim move/operator.
@MainActor
final class CharactersWindow {
    private var window: NSPanel?
    private var label: NSTextField?

    init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 80, height: 30),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = NSColor(white: 0.1, alpha: 0.85)
        panel.hasShadow = true
        panel.isMovableByWindowBackground = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.ignoresMouseEvents = true

        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.font = NSFont.monospacedSystemFont(ofSize: 16, weight: .semibold)
        label.textColor = .white
        label.frame = panel.contentView!.bounds
        label.autoresizingMask = [.width, .height]
        panel.contentView?.addSubview(label)

        self.window = panel
        self.label = label
    }

    func show(move: String, at position: NSPoint? = nil) {
        label?.stringValue = move

        if let position {
            window?.setFrameOrigin(position)
        } else {
            // Default: top-center of the main screen.
            if let screen = NSScreen.main {
                let frame = window!.frame
                let origin = NSPoint(
                    x: screen.visibleFrame.midX - frame.width / 2,
                    y: screen.visibleFrame.maxY - 40
                )
                window?.setFrameOrigin(origin)
            }
        }

        window?.orderFrontRegardless()

        // Auto-hide after 1 second.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.window?.orderOut(nil)
        }
    }

    func hide() {
        window?.orderOut(nil)
    }
}
