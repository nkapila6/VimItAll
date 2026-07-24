import AppKit
import SwiftUI
import Combine

/// Manages the menu bar status item showing the current Vim mode.
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var vimState: VimState
    private var cancellable: AnyCancellable?
    private var yankCancellable: AnyCancellable?
    private var prefsWindowController: NSWindowController?
    private var enableMenuItem: NSMenuItem?
    private let focusHighlight = FocusHighlight()

    init(vimState: VimState) {
        self.vimState = vimState
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateLabel(for: vimState.mode)

        let menu = NSMenu()

        let enableItem = NSMenuItem(title: "Enable vimitall", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = UserDefaults.standard.object(forKey: "vimitallEnabled") == nil
            ? .on
            : (UserDefaults.standard.bool(forKey: "vimitallEnabled") ? .on : .off)
        enableMenuItem = enableItem
        menu.addItem(enableItem)

        menu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit vimitall", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        cancellable = vimState.$mode.sink { [weak self] newMode in
            self?.updateLabel(for: newMode)
        }

        // Flash the icon blue briefly when a yank happens.
        yankCancellable = vimState.$didYank.sink { [weak self] didYank in
            if didYank {
                self?.showYankFlash()
            }
        }

        // Observe the enabled toggle so the icon updates to disabled state.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(enabledStateChanged),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func enabledStateChanged() {
        updateLabel(for: vimState.mode)
    }

    private func showYankFlash() {
        statusItem?.button?.image = yankIcon()
    }

    private func yankIcon() -> NSImage {
        return circleIcon(color: NSColor(srgbRed: 0.25, green: 0.50, blue: 0.95, alpha: 1.0), letter: "Y")
    }

    private func modeLetter(for mode: VimMode) -> String {
        switch mode {
        case .normal: return "N"
        case .insert: return "I"
        case .visual: return "V"
        }
    }

    private func modeColor(for mode: VimMode) -> NSColor {
        switch mode {
        case .insert: return NSColor(srgbRed: 0.20, green: 0.75, blue: 0.35, alpha: 1.0)
        case .normal: return NSColor(srgbRed: 0.90, green: 0.55, blue: 0.15, alpha: 1.0)
        case .visual: return NSColor(srgbRed: 0.25, green: 0.50, blue: 0.95, alpha: 1.0)
        }
    }

    private func modeIcon(for mode: VimMode) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        // Draw the colored circle.
        let rect = NSRect(x: 1, y: 1, width: 16, height: 16)
        let path = NSBezierPath(ovalIn: rect)
        modeColor(for: mode).setFill()
        path.fill()

        // Draw the letter on top.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let letter = modeLetter(for: mode) as NSString
        let textSize = letter.size(withAttributes: attrs)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 1,
            width: textSize.width,
            height: textSize.height
        )
        letter.draw(in: textRect, withAttributes: attrs)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "vimitallEnabled") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "vimitallEnabled")
    }

    private func updateLabel(for mode: VimMode) {
        let showIndicator = UserDefaults.standard.object(forKey: "showModeIndicator") == nil
            ? true
            : UserDefaults.standard.bool(forKey: "showModeIndicator")

        if !showIndicator {
            // Show a neutral app icon so the menu is still accessible.
            statusItem?.button?.image = neutralIcon()
            statusItem?.button?.attributedTitle = NSAttributedString(string: "")
        } else if isEnabled {
            statusItem?.button?.image = modeIcon(for: mode)
            statusItem?.button?.attributedTitle = NSAttributedString(
                string: " \(modeLetter(for: mode)) ",
                attributes: [.foregroundColor: modeColor(for: mode), .font: NSFont.systemFont(ofSize: 10, weight: .bold)]
            )
        } else {
            // Disabled: red dot with "D"
            statusItem?.button?.image = disabledIcon()
            statusItem?.button?.attributedTitle = NSAttributedString(
                string: " D ",
                attributes: [.foregroundColor: NSColor.systemRed, .font: NSFont.systemFont(ofSize: 10, weight: .bold)]
            )
        }
        updateCursor(for: mode)
        updateFocusHighlight(for: mode)
    }

    private func updateFocusHighlight(for mode: VimMode) {
        let showHighlight = UserDefaults.standard.object(forKey: "showFocusHighlight") == nil
            ? false
            : UserDefaults.standard.bool(forKey: "showFocusHighlight")
        if isEnabled && showHighlight && (mode == .normal || mode == .visual) {
            focusHighlight.show()
        } else {
            focusHighlight.hide()
        }
    }

    private func disabledIcon() -> NSImage {
        return circleIcon(color: NSColor.systemRed, letter: "D")
    }

    private func neutralIcon() -> NSImage {
        return circleIcon(color: NSColor.darkGray, letter: "v")
    }

    private func circleIcon(color: NSColor, letter: String) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(x: 1, y: 1, width: 16, height: 16)
        let path = NSBezierPath(ovalIn: rect)
        color.setFill()
        path.fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let str = letter as NSString
        let textSize = str.size(withAttributes: attrs)
        let textRect = NSRect(
            x: (size.width - textSize.width) / 2,
            y: (size.height - textSize.height) / 2 - 1,
            width: textSize.width,
            height: textSize.height
        )
        str.draw(in: textRect, withAttributes: attrs)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func updateCursor(for mode: VimMode) {
        switch mode {
        case .insert:
            NSCursor.iBeam.set()
        case .normal, .visual:
            NSCursor.arrow.set()
        }
    }

    @objc private func toggleEnabled() {
        let key = "vimitallEnabled"
        let current = UserDefaults.standard.object(forKey: key) == nil
            ? true
            : UserDefaults.standard.bool(forKey: key)
        let newValue = !current
        UserDefaults.standard.set(newValue, forKey: key)
        enableMenuItem?.state = newValue ? .on : .off
    }

    @objc private func openPreferences() {
        // SwiftUI's Settings scene does not reliably respond to showSettingsWindow:
        // via the responder chain, so host the preferences view in our own window.
        if prefsWindowController == nil {
            let hostingController = NSHostingController(rootView: PreferencesView())
            let window = NSWindow(contentViewController: hostingController)
            window.title = "vimitall Preferences"
            window.styleMask = [.titled, .closable]
            window.center()
            prefsWindowController = NSWindowController(window: window)
        }
        prefsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
