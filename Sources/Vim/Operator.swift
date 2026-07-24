import Foundation
import CoreGraphics

enum OperatorResult {
    case stayNormal
    case enterInsert
}

enum Operator: String {
    case deleteChar = "x"
    case deleteLine = "dd"
    case yankLine = "yy"
    case pasteAfter = "p"
    case pasteBefore = "P"
    case undo = "u"
    case deleteToEnd = "D"
    case changeToEnd = "C"
    case changeLine = "cc"
    case substituteLine = "S"
    case deleteCharBefore = "X"
    case joinLines = "J"
}

/// Shared yank buffer for copy/paste operations.
/// MainActor-isolated to satisfy Swift 6 strict concurrency.
@MainActor
enum YankBuffer {
    static var content: String = ""
    /// Set by the keyboard strategy when yanking/deleting lines.
    /// Tells paste whether to insert a newline before/after the pasted content.
    static var isLineWise: Bool = false
}

@MainActor
extension Operator {
    /// Perform the operator action using the given mutator and count.
    /// Returns a mode hint so callers can switch to insert for change operations.
    func perform(with mutator: AXMutator, count: Int) -> OperatorResult {
        guard let text = mutator.currentText() else { return .stayNormal }
        guard let caret = mutator.currentCaretOffset() else { return .stayNormal }

        let lines = text.components(separatedBy: "\n")
        let (currentLine, currentCol) = lineAndColumn(for: caret, in: lines)

        switch self {
        case .deleteChar:
            let deleteLen = min(count, text.count - caret)
            mutator.deleteRange(start: caret, length: deleteLen)
            return .stayNormal

        case .deleteLine:
            let startLine = currentLine
            let endLine = min(lines.count - 1, currentLine + count - 1)
            let startOffset = offset(forLine: startLine, column: 0, in: lines)
            let endOffset: Int
            if endLine + 1 < lines.count {
                endOffset = offset(forLine: endLine + 1, column: 0, in: lines)
            } else {
                endOffset = text.count
            }
            // Yank the deleted lines to the buffer before deleting.
            var yankedLines: [String] = []
            for lineNum in startLine...endLine {
                yankedLines.append(lines[lineNum])
            }
            YankBuffer.content = yankedLines.joined(separator: "\n")
            YankBuffer.isLineWise = true
            mutator.deleteRange(start: startOffset, length: endOffset - startOffset)
            return .stayNormal

        case .yankLine:
            let startLine = currentLine
            let endLine = min(lines.count - 1, currentLine + count - 1)
            // Yank line text without trailing newlines.
            var yankedLines: [String] = []
            for lineNum in startLine...endLine {
                yankedLines.append(lines[lineNum])
            }
            YankBuffer.content = yankedLines.joined(separator: "\n")
            YankBuffer.isLineWise = true
            return .stayNormal

        case .pasteAfter:
            guard !YankBuffer.content.isEmpty else { return .stayNormal }
            if YankBuffer.isLineWise {
                let lineEndOffset = offset(forLine: currentLine, column: lines[currentLine].count, in: lines)
                // Use replaceRange with length 0 to insert without relying on
                // a separate moveCaret call that might race with the insert.
                mutator.replaceRange(start: lineEndOffset, length: 0, with: "\n" + YankBuffer.content)
            } else {
                // Char-wise: insert after the cursor.
                mutator.replaceRange(start: min(text.count, caret + 1), length: 0, with: YankBuffer.content)
            }
            return .stayNormal

        case .pasteBefore:
            guard !YankBuffer.content.isEmpty else { return .stayNormal }
            if YankBuffer.isLineWise {
                let lineStartOffset = offset(forLine: currentLine, column: 0, in: lines)
                mutator.replaceRange(start: lineStartOffset, length: 0, with: YankBuffer.content + "\n")
            } else {
                // Char-wise: insert at the cursor.
                mutator.replaceRange(start: caret, length: 0, with: YankBuffer.content)
            }
            return .stayNormal

        case .deleteCharBefore:
            let deleteLen = min(count, caret)
            guard deleteLen > 0 else { return .stayNormal }
            mutator.deleteRange(start: caret - deleteLen, length: deleteLen)
            return .stayNormal

        case .deleteToEnd:
            let lineEndOffset = offset(forLine: currentLine, column: lines[currentLine].count, in: lines)
            let deleteLen = max(0, lineEndOffset - caret)
            guard deleteLen > 0 else { return .stayNormal }
            mutator.deleteRange(start: caret, length: deleteLen)
            return .stayNormal

        case .changeToEnd:
            let lineEndOffset = offset(forLine: currentLine, column: lines[currentLine].count, in: lines)
            let deleteLen = max(0, lineEndOffset - caret)
            if deleteLen > 0 {
                mutator.deleteRange(start: caret, length: deleteLen)
            }
            return .enterInsert

        case .changeLine, .substituteLine:
            // Delete the full line content but keep the empty line, then enter insert mode.
            let startOffset = offset(forLine: currentLine, column: 0, in: lines)
            let endOffset: Int
            if currentLine + 1 < lines.count {
                endOffset = offset(forLine: currentLine + 1, column: 0, in: lines)
            } else {
                endOffset = text.count
            }
            mutator.deleteRange(start: startOffset, length: endOffset - startOffset)
            return .enterInsert

        case .joinLines:
            guard currentLine + 1 < lines.count else { return .stayNormal }
            let currentLineEnd = offset(forLine: currentLine, column: lines[currentLine].count, in: lines)
            let nextLineStart = offset(forLine: currentLine + 1, column: 0, in: lines)
            // Remove the newline and collapse any leading whitespace on the next line.
            var nextLine = lines[currentLine + 1]
            while nextLine.first?.isWhitespace == true {
                nextLine.removeFirst()
            }
            let replacement = (lines[currentLine].last?.isWhitespace == true ? "" : " ") + nextLine
            mutator.replaceRange(start: currentLineEnd, length: nextLineStart - currentLineEnd, with: replacement)
            return .stayNormal

        case .undo:
            // Send Cmd+Z via CGEvent synthesis, tagged so our event tap ignores it.
            let source = CGEventSource(stateID: .hidSystemState)
            let marker = Int64(KeyboardSynthesizer.synthMarker)
            guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
                  let zDown = CGEvent(keyboardEventSource: source, virtualKey: 0x06, keyDown: true),
                  let zUp = CGEvent(keyboardEventSource: source, virtualKey: 0x06, keyDown: false),
                  let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
                return .stayNormal
            }
            for ev in [cmdDown, zDown, zUp, cmdUp] {
                ev.flags = .maskCommand
                ev.setIntegerValueField(.eventSourceUserData, value: marker)
            }
            cmdDown.post(tap: .cghidEventTap)
            zDown.post(tap: .cghidEventTap)
            zUp.post(tap: .cghidEventTap)
            cmdUp.post(tap: .cghidEventTap)
            return .stayNormal
        }
    }
}

// MARK: - Line/offset helpers (shared with Motion)

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
