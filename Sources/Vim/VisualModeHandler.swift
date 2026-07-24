import Foundation

// Helper shared from NormalModeHandler/Operator.swift to avoid duplicating logic.
// Duplicating here temporarily until a shared text utility is extracted.
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

/// Handles visual mode: extends the selection from an anchor as the user moves.
@MainActor
final class VisualModeHandler {
    private let vimState: VimState
    private let axMutator: AXMutator
    private let axObserver: AXFocusObserver?
    private var keySequence = KeySequence()

    init(vimState: VimState, axMutator: AXMutator, axObserver: AXFocusObserver?) {
        self.vimState = vimState
        self.axMutator = axMutator
        self.axObserver = axObserver
    }

    /// Handle a key in visual mode. Returns true if consumed.
    func handle(_ key: String) -> Bool {
        if key == "esc" {
            exitVisualMode()
            keySequence.reset()
            return true
        }

        if key == "d" || key == "x" {
            deleteSelection()
            keySequence.reset()
            return true
        }

        if key == "y" {
            yankSelection()
            keySequence.reset()
            return true
        }

        if key == "c" {
            changeSelection()
            keySequence.reset()
            return true
        }

        // Multi-key motions (e.g. gg, G already resolves via KeyMapping) need the
        // sequence buffer so the first key does not immediately fail.
        let result = keySequence.feed(key)
        switch result {
        case .incomplete:
            return true
        case .complete(let mapping):
            switch mapping.action {
            case .motion(let motion):
                extendSelection(with: motion, count: mapping.count)
            default:
                break
            }
            keySequence.reset()
            return true
        case .cancel:
            keySequence.reset()
            return true
        }
    }

    private func refreshElement() {
        if let element = axObserver?.currentFocusedElement() {
            axMutator.setElement(element)
        }
    }

    private func extendSelection(with motion: Motion, count: Int) {
        refreshElement()
        guard let text = axMutator.currentText() else { return }

        let anchor = vimState.visualAnchor

        // Read the current selection. If we can't, fall back to the anchor as cursor.
        let selRange = axMutator.currentSelectionRange()
        let cursorEnd: Int
        if let selRange {
            if selRange.start == anchor {
                cursorEnd = selRange.start + selRange.length
            } else {
                cursorEnd = selRange.start
            }
        } else {
            cursorEnd = anchor
        }

        let target = motion.targetOffset(from: cursorEnd, in: text, count: count)

        let start = min(anchor, target)
        let end = max(anchor, target)
        var startOffset = start
        var endOffset = end

        if vimState.visualLineWise {
            let lines = text.components(separatedBy: "\n")
            let startLine = lineAndColumn(for: startOffset, in: lines).0
            let endLine = lineAndColumn(for: endOffset, in: lines).0
            startOffset = offset(forLine: startLine, column: 0, in: lines)
            endOffset = endLine + 1 < lines.count
                ? offset(forLine: endLine + 1, column: 0, in: lines)
                : text.count
        }

        axMutator.setSelection(start: startOffset, length: endOffset - startOffset)
    }


    private func deleteSelection() {
        refreshElement()
        axMutator.insertText("")
        vimState.enterNormalMode()
        axMutator.moveCaret(to: vimState.visualAnchor)
    }

    private func yankSelection() {
        refreshElement()
        if let selected = axMutator.currentSelectionText() {
            YankBuffer.content = selected
        }
        let anchor = vimState.visualAnchor
        vimState.didYank = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.vimState.didYank = false
        }
        vimState.enterNormalMode()
        axMutator.moveCaret(to: anchor)
    }

    private func changeSelection() {
        refreshElement()
        axMutator.insertText("")
        vimState.enterInsertMode()
    }

    private func exitVisualMode() {
        let anchor = vimState.visualAnchor
        vimState.enterNormalMode()
        axMutator.moveCaret(to: anchor)
    }
}
