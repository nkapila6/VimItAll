import Foundation
import os.log

/// Orchestrates normal mode: feeds keys to KeySequence, resolves to actions, executes them.
@MainActor
final class NormalModeHandler {
    private let vimState: VimState
    private let axMutator: AXMutator
    private let axObserver: AXFocusObserver?
    private var keySequence = KeySequence()
    private var pendingReplace = false
    private let log = OSLog(subsystem: "app.vimitall.vimitall", category: "Motion")

    init(vimState: VimState, axMutator: AXMutator, axObserver: AXFocusObserver?) {
        self.vimState = vimState
        self.axMutator = axMutator
        self.axObserver = axObserver
    }

    /// Handle a key string. Returns true if the event was consumed.
    func handle(_ key: String) -> Bool {
        if pendingReplace {
            pendingReplace = false
            performReplace(with: key)
            keySequence.reset()
            return true
        }

        // f/F/t/T second keystroke: the character to find.
        if vimState.pendingFind != nil {
            return handlePendingFind(key)
        }

        // Operator+motion second keystroke: the motion.
        if let pendingOp = vimState.pendingOperator {
            return handlePendingOperator(pendingOp, motionKey: key)
        }

        // Cancel any pending state if the user hits escape.
        if key == "esc" {
            pendingReplace = false
            vimState.reset()
            return false
        }

        let result = keySequence.feed(key)

        switch result {
        case .incomplete:
            // If the buffer is a single operator key (d/c/y), set pendingOperator
            // for operator+motion and reset the sequence so the next key is the motion.
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
            // In Normal mode, unmatched keys are swallowed - never typed into the buffer.
            keySequence.reset()
            return true
        }
    }

    // MARK: - Pending find (f/F/t/T)

    private func handlePendingFind(_ key: String) -> Bool {
        guard let (forward, till) = vimState.pendingFind else { return true }
        vimState.pendingFind = nil

        guard key != "esc", let char = key.first, key.count == 1 else {
            vimState.reset()
            return key == "esc" ? false : true
        }

        // Store for ; and , repeat.
        vimState.lastFind = LastFind(char: char, forward: forward, till: till)

        performFind(char: char, forward: forward, till: till)
        return true
    }

    private func performFind(char: Character, forward: Bool, till: Bool) {
        refreshElement()
        guard let text = axMutator.currentText() else { return }
        guard let caret = axMutator.currentCaretOffset() else { return }

        let lines = text.components(separatedBy: "\n")
        let (currentLine, currentCol) = lineAndColumn(for: caret, in: lines)
        let lineText = lines[currentLine]

        let target: Int?
        if forward {
            target = findForward(char: char, in: lineText, from: currentCol, till: till)
        } else {
            target = findBackward(char: char, in: lineText, from: currentCol, till: till)
        }

        guard let col = target else { return } // char not found, do nothing (Vim behavior)

        let lineStart = offset(forLine: currentLine, column: 0, in: lines)
        axMutator.moveCaret(to: lineStart + col)
        vimState.reset()
    }

    private func findForward(char: Character, in line: String, from col: Int, till: Bool) -> Int? {
        let chars = Array(line)
        // Start searching from col+1 (Vim f/F/t/T don't match the char under cursor)
        var i = col + 1
        while i < chars.count {
            if chars[i] == char {
                return till ? i - 1 : i
            }
            i += 1
        }
        return nil
    }

    private func findBackward(char: Character, in line: String, from col: Int, till: Bool) -> Int? {
        let chars = Array(line)
        var i = col - 1
        while i >= 0 {
            if chars[i] == char {
                return till ? i + 1 : i
            }
            i -= 1
        }
        return nil
    }

    // MARK: - Pending operator (d/c/y + motion)

    /// Returns the Operator for a single-key operator prefix, or nil.
    private func operatorForSingleKey(_ key: String) -> Operator? {
        switch key {
        case "d": return .deleteLine  // used as generic "delete" for operator+motion
        case "c": return .changeLine  // used as generic "change" for operator+motion
        case "y": return .yankLine    // used as generic "yank" for operator+motion
        default: return nil
        }
    }

    /// Returns true if the key is the same operator as the pending one (for dd/cc/yy).
    private func isRepeatOfPendingOperator(_ key: String, pending: Operator) -> Bool {
        switch pending {
        case .deleteLine: return key == "d"
        case .changeLine: return key == "c"
        case .yankLine: return key == "y"
        default: return false
        }
    }

    private var pendingOperatorMotionSequence = KeySequence()

    private func handlePendingOperator(_ op: Operator, motionKey: String) -> Bool {
        // Same operator key again -> line-wise (dd, cc, yy).
        if isRepeatOfPendingOperator(motionKey, pending: op) {
            vimState.pendingOperator = nil
            pendingOperatorMotionSequence.reset()
            refreshElement()
            let result = op.perform(with: axMutator, count: 1)
            if result == .enterInsert {
                vimState.enterInsertMode()
            } else {
                vimState.reset()
            }
            vimState.lastChange = LastChange(op: op, motion: nil, count: 1)
            return true
        }

        // esc cancels.
        if motionKey == "esc" {
            vimState.pendingOperator = nil
            pendingOperatorMotionSequence.reset()
            vimState.reset()
            return false
        }

        // Feed into the sequence to handle multi-key motions like gg.
        let result = pendingOperatorMotionSequence.feed(motionKey)
        switch result {
        case .incomplete:
            return true
        case .complete(let mapping):
            pendingOperatorMotionSequence.reset()
            vimState.pendingOperator = nil
            switch mapping.action {
            case .motion(let motion):
                performOperatorOnMotion(op, motion: motion)
            default:
                break
            }
            return true
        case .cancel:
            pendingOperatorMotionSequence.reset()
            vimState.pendingOperator = nil
            vimState.reset()
            return true
        }
    }

    private func performOperatorOnMotion(_ op: Operator, motion: Motion) {
        refreshElement()
        guard let text = axMutator.currentText() else { return }
        guard let caret = axMutator.currentCaretOffset() else { return }

        let target = motion.targetOffset(from: caret, in: text, count: 1)
        let start = min(caret, target)
        let length = abs(target - caret)

        // For motions that don't move (e.g., w at end of text), do nothing.
        guard length > 0 else {
            vimState.reset()
            return
        }

        switch op {
        case .deleteLine:
            // d + motion: delete the range.
            axMutator.deleteRange(start: start, length: length)
            // Move caret to start of deleted range.
            axMutator.moveCaret(to: start)
            vimState.reset()
            vimState.lastChange = LastChange(op: op, motion: motion, count: 1)

        case .changeLine:
            // c + motion: delete the range and enter insert mode.
            axMutator.deleteRange(start: start, length: length)
            axMutator.moveCaret(to: start)
            vimState.enterInsertMode()
            vimState.lastChange = LastChange(op: op, motion: motion, count: 1)

        case .yankLine:
            // y + motion: yank the range, don't move cursor.
            let startIdx = text.index(text.startIndex, offsetBy: start)
            let endIdx = text.index(text.startIndex, offsetBy: start + length)
            YankBuffer.content = String(text[startIdx..<endIdx])
            YankBuffer.isLineWise = false
            flashYank()
            vimState.reset()
            vimState.lastChange = LastChange(op: op, motion: motion, count: 1)

        default:
            vimState.reset()
        }
    }

    // MARK: - Replace

    private func performReplace(with key: String) {
        guard key != "esc" else { return }
        if let element = axObserver?.currentFocusedElement() {
            axMutator.setElement(element)
        }
        guard let caret = axMutator.currentCaretOffset() else { return }
        axMutator.replaceRange(start: caret, length: 1, with: key)
    }

    // MARK: - Execute

    private func execute(_ mapping: KeyMapping) {
        let count = mapping.count

        switch mapping.action {
        case .motion(let motion):
            if let element = axObserver?.currentFocusedElement() {
                axMutator.setElement(element)
                os_log("got focused element for motion %{public}@", log: log, type: .info, motion.rawValue)
            } else {
                os_log("no focused element found for motion %{public}@", log: log, type: .error, motion.rawValue)
                return
            }
            guard let text = axMutator.currentText() else {
                os_log("could not read text for motion %{public}@", log: log, type: .error, motion.rawValue)
                return
            }
            guard let caret = axMutator.currentCaretOffset() else {
                os_log("could not read caret for motion %{public}@", log: log, type: .error, motion.rawValue)
                return
            }
            let target = motion.targetOffset(from: caret, in: text, count: count)
            os_log("motion %{public}@: caret=%d target=%d textLen=%d", log: log, type: .info, motion.rawValue, caret, target, text.count)
            axMutator.moveCaret(to: target)
            vimState.reset()

        case .operator(let op):
            if let element = axObserver?.currentFocusedElement() {
                axMutator.setElement(element)
            }
            let result = op.perform(with: axMutator, count: count)
            if result == .enterInsert {
                vimState.enterInsertMode()
            } else {
                vimState.reset()
            }
            // Flash the yank indicator when yanking.
            if op == .yankLine {
                flashYank()
            }
            // Store for . repeat (line-wise operators like dd, cc, yy).
            vimState.lastChange = LastChange(op: op, motion: nil, count: count)

        case .enterInsert(let trigger):
            if let element = axObserver?.currentFocusedElement() {
                axMutator.setElement(element)
            }
            executeInsertTrigger(trigger)
            vimState.enterInsertMode()

        case .enterVisual(let lineWise):
            if let element = axObserver?.currentFocusedElement() {
                axMutator.setElement(element)
            }
            guard let text = axMutator.currentText() else { return }
            guard let caret = axMutator.currentCaretOffset() else { return }
            vimState.enterVisualMode(anchor: caret, lineWise: lineWise)
            if lineWise {
                let lines = text.components(separatedBy: "\n")
                let currentLine = lineAndColumn(for: caret, in: lines).0
                let lineStart = offset(forLine: currentLine, column: 0, in: lines)
                let lineEnd = currentLine + 1 < lines.count
                    ? offset(forLine: currentLine + 1, column: 0, in: lines)
                    : text.count
                axMutator.setSelection(start: lineStart, length: lineEnd - lineStart)
            }

        case .pendingReplace:
            pendingReplace = true

        case .pendingFind(let forward, let till):
            vimState.pendingFind = (forward, till)

        case .repeatFind(let reverse):
            guard let lastFind = vimState.lastFind else { return }
            let forward = reverse ? !lastFind.forward : lastFind.forward
            performFind(char: lastFind.char, forward: forward, till: lastFind.till)

        case .repeatLastChange:
            guard let lastChange = vimState.lastChange else { return }
            replayLastChange(lastChange)

        case .passthrough:
            break
        }
    }

    // MARK: - Repeat last change (.)

    private func replayLastChange(_ change: LastChange) {
        refreshElement()
        if let motion = change.motion {
            performOperatorOnMotion(change.op, motion: motion)
        } else {
            let result = change.op.perform(with: axMutator, count: change.count)
            if result == .enterInsert {
                vimState.enterInsertMode()
            } else {
                vimState.reset()
            }
        }
    }

    // MARK: - Helpers

    private func flashYank() {
        vimState.didYank = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.vimState.didYank = false
        }
    }

    private func refreshElement() {
        if let element = axObserver?.currentFocusedElement() {
            axMutator.setElement(element)
        }
    }

    private func executeInsertTrigger(_ trigger: InsertTrigger) {
        guard let text = axMutator.currentText() else { return }
        guard let caret = axMutator.currentCaretOffset() else { return }
        let lines = text.components(separatedBy: "\n")

        switch trigger {
        case .i:
            // Insert at current caret - just switch mode.
            break

        case .a:
            // Append after caret: move caret +1.
            axMutator.moveCaret(to: min(text.count, caret + 1))

        case .A:
            // Append at end of current line.
            let (currentLine, _) = lineAndColumn(for: caret, in: lines)
            let lineEnd = offset(forLine: currentLine, column: lines[currentLine].count, in: lines)
            axMutator.moveCaret(to: lineEnd)

        case .I:
            // Insert at start of current line.
            let (currentLine, _) = lineAndColumn(for: caret, in: lines)
            let lineStart = offset(forLine: currentLine, column: 0, in: lines)
            axMutator.moveCaret(to: lineStart)

        case .s:
            // Substitute char under cursor: delete one char then insert.
            let deleteLen = min(1, text.count - caret)
            if deleteLen > 0 {
                axMutator.deleteRange(start: caret, length: deleteLen)
            }

        case .o:
            // Open line below: insert newline at end of current line.
            let (currentLine, _) = lineAndColumn(for: caret, in: lines)
            let lineEnd = offset(forLine: currentLine, column: lines[currentLine].count, in: lines)
            axMutator.moveCaret(to: lineEnd)
            axMutator.insertText("\n")

        case .O:
            // Open line above: insert newline at start of current line.
            let (currentLine, _) = lineAndColumn(for: caret, in: lines)
            let lineStart = offset(forLine: currentLine, column: 0, in: lines)
            axMutator.moveCaret(to: lineStart)
            axMutator.insertText("\n")
            // Move caret up to the new empty line.
            axMutator.moveCaret(to: lineStart)

        case .esc:
            // Already handled by mode transition.
            break
        }
    }
}

// These helpers are duplicated from Operator.swift to avoid cross-file private access.
// In a real project they'd live in a shared utility.
private func lineAndColumn(for offset: Int, in lines: [String]) -> (Int, Int) {
    var remaining = offset
    for (i, line) in lines.enumerated() {
        if remaining <= line.count {
            return (i, remaining)
        }
        remaining -= line.count + 1
    }
    return (lines.count - 1, lines.last?.count ?? 0)
}

private func offset(forLine line: Int, column: Int, in lines: [String]) -> Int {
    var offset = 0
    for i in 0..<line {
        offset += lines[i].count + 1
    }
    return offset + min(column, lines[line].count)
}
