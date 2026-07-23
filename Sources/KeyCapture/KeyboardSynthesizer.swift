import CoreGraphics

enum ArrowDirection {
    case left
    case right
    case down
    case up
}

/// Synthesizes macOS key events to simulate Vim motions when AX text access is unavailable.
/// Uses CGEvent posting to send key presses to the focused app.
/// Limitations: cannot read text or caret position; relies on OS-standard key bindings.
@MainActor
final class KeyboardSynthesizer {
    private let source = CGEventSource(stateID: .hidSystemState)

    /// Marker tagged onto synthesized events so our event tap can ignore them.
    /// Prevents a feedback loop where synthesized keys re-enter the tap.
    static let synthMarker: UInt64 = 0xDEADBEEF

    // MARK: - Core posting

    private func post(_ keyCode: CGKeyCode, _ flags: CGEventFlags, keyDown: Bool) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { return }
        event.flags = flags
        // Tag with our marker so the event tap skips our own events.
        event.setIntegerValueField(.eventSourceUserData, value: Int64(KeyboardSynthesizer.synthMarker))
        event.post(tap: .cghidEventTap)
    }

    private func sendKeyDownUp(_ keyCode: CGKeyCode, flags: CGEventFlags = [], count: Int = 1) {
        for _ in 0..<count {
            post(keyCode, flags, keyDown: true)
            post(keyCode, flags, keyDown: false)
        }
    }

    // MARK: - Arrow keys

    func sendArrow(_ direction: ArrowDirection, shift: Bool = false, option: Bool = false, command: Bool = false, count: Int = 1) {
        let keyCode: CGKeyCode = switch direction {
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
        }
        var flags: CGEventFlags = []
        if shift { flags.insert(.maskShift) }
        if option { flags.insert(.maskAlternate) }
        if command { flags.insert(.maskCommand) }
        sendKeyDownUp(keyCode, flags: flags, count: count)
    }

    // MARK: - Generic key

    func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags = [], count: Int = 1) {
        sendKeyDownUp(keyCode, flags: flags, count: count)
    }

    // MARK: - Delete keys

    func sendDelete(count: Int = 1) {
        sendKeyDownUp(51, count: count)
    }

    func sendForwardDelete(count: Int = 1) {
        // fn+delete = forward delete
        sendKeyDownUp(117, count: count)
    }

    // MARK: - Navigation

    /// cmd+left = start of line (macOS Home equivalent)
    func sendHome(shift: Bool = false, count: Int = 1) {
        sendCmdLeft(shift: shift, count: count)
    }

    /// cmd+right = end of line (macOS End equivalent)
    func sendEnd(shift: Bool = false, count: Int = 1) {
        sendCmdRight(shift: shift, count: count)
    }

    func sendCmdLeft(shift: Bool = false, count: Int = 1) {
        var flags: CGEventFlags = .maskCommand
        if shift { flags.insert(.maskShift) }
        sendKeyDownUp(123, flags: flags, count: count)
    }

    func sendCmdRight(shift: Bool = false, count: Int = 1) {
        var flags: CGEventFlags = .maskCommand
        if shift { flags.insert(.maskShift) }
        sendKeyDownUp(124, flags: flags, count: count)
    }

    func sendCmdUp(shift: Bool = false, count: Int = 1) {
        var flags: CGEventFlags = .maskCommand
        if shift { flags.insert(.maskShift) }
        sendKeyDownUp(126, flags: flags, count: count)
    }

    func sendCmdDown(shift: Bool = false, count: Int = 1) {
        var flags: CGEventFlags = .maskCommand
        if shift { flags.insert(.maskShift) }
        sendKeyDownUp(125, flags: flags, count: count)
    }

    // MARK: - Word navigation

    func sendOptionLeft(shift: Bool = false, count: Int = 1) {
        var flags: CGEventFlags = .maskAlternate
        if shift { flags.insert(.maskShift) }
        sendKeyDownUp(123, flags: flags, count: count)
    }

    func sendOptionRight(shift: Bool = false, count: Int = 1) {
        var flags: CGEventFlags = .maskAlternate
        if shift { flags.insert(.maskShift) }
        sendKeyDownUp(124, flags: flags, count: count)
    }

    func sendOptionLeftDelete(count: Int = 1) {
        sendKeyDownUp(51, flags: .maskAlternate, count: count)
    }

    // MARK: - Selection helpers

    func selectToEndOfLine() {
        sendCmdRight(shift: true)
    }

    func selectToStartOfLine() {
        sendCmdLeft(shift: true)
    }

    /// Selects the entire current line: cmd+left then shift+cmd+right.
    func selectLine() {
        sendCmdLeft()
        sendCmdRight(shift: true)
    }

    // MARK: - Clipboard

    func copy() {
        sendKeyDownUp(8, flags: .maskCommand)  // C key = 8
    }

    func paste() {
        sendKeyDownUp(9, flags: .maskCommand)  // V key = 9
    }

    // MARK: - Undo

    func undo() {
        sendKeyDownUp(6, flags: .maskCommand)  // Z key = 6
    }

    // MARK: - Return

    func sendReturn(count: Int = 1) {
        sendKeyDownUp(36, count: count)
    }
}
