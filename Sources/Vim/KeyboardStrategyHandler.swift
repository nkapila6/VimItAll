import Foundation
import CoreGraphics
import os.log

/// Handles normal and visual mode when AX text access is unavailable.
/// Uses KeyboardSynthesizer to simulate Vim motions via synthesized key events.
/// Limitations: cannot read text or caret position; word motions use macOS
/// option+arrow which may differ from Vim's word definition. Visual mode
/// selection tracking is approximate since we can't read the selection state.
/// f/F/t/T are no-ops in keyboard mode (can't read text to search).
@MainActor
final class KeyboardStrategyHandler {
    private let vimState: VimState
    private let synth: KeyboardSynthesizer
    private var keySequence = KeySequence()
    private var pendingReplace = false
    private let log = OSLog(subsystem: "app.vimitall.vimitall", category: "KeyboardStrategy")

    init(vimState: VimState, synth: KeyboardSynthesizer) {
        self.vimState = vimState
        self.synth = synth
    }

    /// Handle a key string. Returns true if the event was consumed.
    func handle(_ key: String) -> Bool {
        if pendingReplace {
            pendingReplace = false
            performReplace(with: key)
            keySequence.reset()
            return true
        }

        // f/F/t/T second keystroke: swallow it, do nothing in keyboard mode.
        if vimState.pendingFind != nil {
            vimState.pendingFind = nil
            vimState.reset()
            return true
        }

        // Operator+motion second keystroke: the motion.
        if let pendingOp = vimState.pendingOperator {
            return handlePendingOperator(pendingOp, motionKey: key)
        }

        if key == "esc" {
            pendingReplace = false
            vimState.reset()
            if vimState.mode == .visual {
                // Collapse selection by sending a non-shift arrow, then normal mode.
                synth.sendArrow(.left)
                vimState.enterNormalMode()
                return true
            }
            return false
        }

        let result = keySequence.feed(key)

        switch result {
        case .incomplete:
            // If the buffer is a single operator key (d/c/y), set pendingOperator
            // for operator+motion and reset the sequence.
            if let op = operatorForSingleKey(key) {
                vimState.pendingOperator = op
                keySequence.reset()
            }
            return true

        case .complete(let mapping):
            execute(mapping)
            keySequence.reset()
            return true

        case .cancel:
            keySequence.reset()
            return true
        }
    }

    // MARK: - Pending operator (d/c/y + motion)

    private func operatorForSingleKey(_ key: String) -> Operator? {
        switch key {
        case "d": return .deleteLine
        case "c": return .changeLine
        case "y": return .yankLine
        default: return nil
        }
    }

    private func isRepeatOfPendingOperator(_ key: String, pending: Operator) -> Bool {
        switch pending {
        case .deleteLine: return key == "d"
        case .changeLine: return key == "c"
        case .yankLine: return key == "y"
        default: return false
        }
    }

    private func handlePendingOperator(_ op: Operator, motionKey: String) -> Bool {
        // Same operator key again -> line-wise (dd, cc, yy).
        if isRepeatOfPendingOperator(motionKey, pending: op) {
            vimState.pendingOperator = nil
            executeOperator(op, count: 1)
            return true
        }

        // esc cancels.
        if motionKey == "esc" {
            vimState.reset()
            return false
        }

        // Resolve the key as a motion.
        guard let motion = Motion(rawValue: motionKey) else {
            vimState.reset()
            return true
        }

        vimState.pendingOperator = nil
        executeOperatorOnMotion(op, motion: motion)
        return true
    }

    private func executeOperatorOnMotion(_ op: Operator, motion: Motion) {
        switch op {
        case .deleteLine:
            // d + motion: select to motion target, then delete.
            selectToMotion(motion)
            synth.sendDelete()
            vimState.reset()

        case .changeLine:
            // c + motion: select to motion target, delete, enter insert.
            selectToMotion(motion)
            synth.sendDelete()
            vimState.enterInsertMode()

        case .yankLine:
            // y + motion: select to motion target, copy.
            selectToMotion(motion)
            synth.copy()
            // Collapse selection: send left arrow.
            synth.sendArrow(.left)
            vimState.reset()

        default:
            vimState.reset()
        }
    }

    /// Select text from current position to the motion target using shift+key combos.
    private func selectToMotion(_ motion: Motion) {
        switch motion {
        case .left:
            synth.sendArrow(.left, shift: true)
        case .right:
            synth.sendArrow(.right, shift: true)
        case .down:
            synth.sendArrow(.down, shift: true)
        case .up:
            synth.sendArrow(.up, shift: true)
        case .wordForward, .wordForwardWORD:
            synth.sendOptionRight(shift: true)
        case .wordBack, .wordBackWORD:
            synth.sendOptionLeft(shift: true)
        case .wordEnd, .wordEndWORD:
            synth.sendOptionRight(shift: true)
            synth.sendArrow(.left, shift: true)
        case .lineStart:
            synth.sendCmdLeft(shift: true)
        case .lineEnd:
            synth.sendCmdRight(shift: true)
        case .documentStart:
            synth.sendCmdUp(shift: true)
        case .documentEnd:
            synth.sendCmdDown(shift: true)
        }
    }

    // MARK: - Replace

    private func performReplace(with key: String) {
        guard key != "esc" else { return }
        // Delete char under cursor, then type the replacement.
        synth.sendForwardDelete()
        // Type the replacement character as a regular keystroke.
        // We need to post the character as a CGEvent.
        if let firstChar = key.first {
            typeCharacter(firstChar)
        }
    }

    /// Types a single character by creating a CGEvent with the unicode string.
    private func typeCharacter(_ char: Character) {
        let str = String(char)
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else { return }
        guard let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { return }

        let chars: [UniChar] = Array(str.utf16)
        down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Execute

    private func execute(_ mapping: KeyMapping) {
        let count = mapping.count

        switch mapping.action {
        case .motion(let motion):
            executeMotion(motion, count: count)

        case .operator(let op):
            executeOperator(op, count: count)

        case .enterInsert(let trigger):
            executeInsertTrigger(trigger)
            vimState.enterInsertMode()

        case .enterVisual(let lineWise):
            vimState.enterVisualMode(anchor: 0, lineWise: lineWise)
            if lineWise {
                // Select the current line to start line-wise visual mode.
                synth.selectLine()
            }

        case .pendingReplace:
            pendingReplace = true

        case .pendingFind(let forward, let till):
            // f/F/t/T: set pending state, next key is swallowed.
            vimState.pendingFind = (forward, till)

        case .repeatFind:
            // ; and , are no-ops in keyboard mode (can't read text).
            break

        case .repeatLastChange:
            // . is a no-op in keyboard mode (can't reliably replay).
            break

        case .passthrough:
            break
        }
    }

    // MARK: - Motions

    private func executeMotion(_ motion: Motion, count: Int) {
        if vimState.mode == .visual {
            executeVisualMotion(motion, count: count)
            return
        }

        switch motion {
        case .left:
            synth.sendArrow(.left, count: count)
        case .down:
            synth.sendArrow(.down, count: count)
        case .up:
            synth.sendArrow(.up, count: count)
        case .right:
            synth.sendArrow(.right, count: count)
        case .wordForward, .wordForwardWORD:
            // option+right = word forward in most macOS text fields
            synth.sendOptionRight(count: count)
        case .wordBack, .wordBackWORD:
            synth.sendOptionLeft(count: count)
        case .wordEnd, .wordEndWORD:
            // Approximate: go to start of next word, then back one char.
            synth.sendOptionRight(count: count)
            synth.sendArrow(.left)
        case .lineStart:
            synth.sendCmdLeft(count: count)
        case .lineEnd:
            synth.sendCmdRight(count: count)
        case .documentStart:
            synth.sendCmdUp(count: count)
        case .documentEnd:
            synth.sendCmdDown(count: count)
        }

        vimState.reset()
    }

    // MARK: - Visual motions (shift+arrows to extend selection)

    private func executeVisualMotion(_ motion: Motion, count: Int) {
        switch motion {
        case .left:
            synth.sendArrow(.left, shift: true, count: count)
        case .down:
            synth.sendArrow(.down, shift: true, count: count)
        case .up:
            synth.sendArrow(.up, shift: true, count: count)
        case .right:
            synth.sendArrow(.right, shift: true, count: count)
        case .wordForward, .wordForwardWORD:
            synth.sendOptionRight(shift: true, count: count)
        case .wordBack, .wordBackWORD:
            synth.sendOptionLeft(shift: true, count: count)
        case .wordEnd, .wordEndWORD:
            synth.sendOptionRight(shift: true, count: count)
            synth.sendArrow(.left, shift: true)
        case .lineStart:
            synth.sendCmdLeft(shift: true, count: count)
        case .lineEnd:
            synth.sendCmdRight(shift: true, count: count)
        case .documentStart:
            synth.sendCmdUp(shift: true, count: count)
        case .documentEnd:
            synth.sendCmdDown(shift: true, count: count)
        }
    }

    // MARK: - Operators

    private func executeOperator(_ op: Operator, count: Int) {
        if vimState.mode == .visual {
            executeVisualOperator(op)
            return
        }

        switch op {
        case .deleteChar:
            synth.sendForwardDelete(count: count)
            vimState.reset()

        case .deleteCharBefore:
            synth.sendDelete(count: count)
            vimState.reset()

        case .deleteLine:
            executeDeleteLine(count: count)
            vimState.reset()

        case .yankLine:
            executeYankLine(count: count)
            vimState.reset()

        case .pasteAfter:
            executePasteAfter()
            vimState.reset()

        case .pasteBefore:
            executePasteBefore()
            vimState.reset()

        case .deleteToEnd:
            synth.selectToEndOfLine()
            synth.sendDelete()
            vimState.reset()

        case .changeToEnd:
            synth.selectToEndOfLine()
            synth.sendDelete()
            vimState.enterInsertMode()

        case .changeLine, .substituteLine:
            executeChangeLine()
            vimState.enterInsertMode()

        case .joinLines:
            synth.sendEnd()
            synth.sendForwardDelete()
            vimState.reset()

        case .undo:
            synth.undo()
            vimState.reset()
        }
    }

    // MARK: - Visual operators

    private func executeVisualOperator(_ op: Operator) {
        switch op {
        case .deleteChar, .deleteLine:
            // Delete the selection and return to normal mode.
            synth.sendDelete()
            vimState.enterNormalMode()

        case .yankLine:
            // Copy selection to clipboard.
            synth.copy()
            vimState.enterNormalMode()

        case .changeLine, .changeToEnd:
            // Delete selection and enter insert mode.
            synth.sendDelete()
            vimState.enterInsertMode()

        default:
            vimState.enterNormalMode()
        }
    }

    // MARK: - Line operations

    private func executeDeleteLine(count: Int) {
        for _ in 0..<count {
            // Go to start of line, select to end, copy (for yank), delete, then delete newline.
            synth.sendCmdLeft()
            synth.selectToEndOfLine()
            synth.copy()
            synth.sendDelete()
            // Delete the newline to join with next line.
            synth.sendForwardDelete()
        }
        YankBuffer.isLineWise = true
    }

    private func executeYankLine(count: Int) {
        for _ in 0..<count {
            synth.sendCmdLeft()
            synth.selectToEndOfLine()
            synth.copy()
            // Move to next line for multi-count yank.
            synth.sendArrow(.down)
        }
        YankBuffer.isLineWise = true
    }

    private func executeChangeLine() {
        synth.sendCmdLeft()
        synth.selectToEndOfLine()
        synth.sendDelete()
    }

    // MARK: - Paste

    private func executePasteAfter() {
        if YankBuffer.isLineWise {
            // Paste line below: go to end of line, newline, paste.
            synth.sendEnd()
            synth.sendReturn()
            synth.paste()
        } else {
            // Paste after cursor: move right, paste.
            synth.sendArrow(.right)
            synth.paste()
        }
    }

    private func executePasteBefore() {
        if YankBuffer.isLineWise {
            // Paste line above: go to start of line, newline, up, paste.
            synth.sendCmdLeft()
            synth.sendReturn()
            synth.sendArrow(.up)
            synth.paste()
        } else {
            // Paste before cursor: move left, paste.
            synth.sendArrow(.left)
            synth.paste()
        }
    }

    // MARK: - Insert triggers

    private func executeInsertTrigger(_ trigger: InsertTrigger) {
        switch trigger {
        case .i:
            // Insert at current position - just switch mode.
            break

        case .a:
            synth.sendArrow(.right)

        case .A:
            synth.sendCmdRight()

        case .I:
            synth.sendCmdLeft()

        case .s:
            synth.sendForwardDelete()

        case .o:
            synth.sendCmdRight()
            synth.sendReturn()

        case .O:
            synth.sendCmdLeft()
            synth.sendReturn()
            synth.sendArrow(.up)

        case .esc:
            break
        }
    }
}
