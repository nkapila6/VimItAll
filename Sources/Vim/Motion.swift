import Foundation

enum Motion: String {
    case left = "h"
    case down = "j"
    case up = "k"
    case right = "l"
    case wordForward = "w"
    case wordBack = "b"
    case wordEnd = "e"
    case wordForwardWORD = "W"
    case wordBackWORD = "B"
    case wordEndWORD = "E"
    case lineStart = "0"
    case lineEnd = "$"
    case documentStart = "gg"
    case documentEnd = "G"
}

extension Motion {
    /// Pure function: given current caret offset, full text, and a count, returns the new caret offset.
    /// Does not clamp to text bounds here; callers should clamp.
    func targetOffset(from caret: Int, in text: String, count: Int) -> Int {
        let lines = text.components(separatedBy: "\n")
        let (currentLine, currentCol) = lineAndColumn(for: caret, in: lines)

        switch self {
        case .left:
            return max(0, caret - count)

        case .right:
            return min(text.count, caret + count)

        case .down:
            let targetLine = min(lines.count - 1, currentLine + count)
            let targetCol = min(currentCol, lines[targetLine].count)
            return offset(forLine: targetLine, column: targetCol, in: lines)

        case .up:
            let targetLine = max(0, currentLine - count)
            let targetCol = min(currentCol, lines[targetLine].count)
            return offset(forLine: targetLine, column: targetCol, in: lines)

        case .wordForward:
            return wordForwardOffset(from: caret, in: text, count: count)

        case .wordBack:
            return wordBackOffset(from: caret, in: text, count: count)

        case .wordEnd:
            return wordEndOffset(from: caret, in: text, count: count)

        case .wordForwardWORD:
            return wordForwardWORDOffset(from: caret, in: text, count: count)

        case .wordBackWORD:
            return wordBackWORDOffset(from: caret, in: text, count: count)

        case .wordEndWORD:
            return wordEndWORDOffset(from: caret, in: text, count: count)

        case .lineStart:
            return offset(forLine: currentLine, column: 0, in: lines)

        case .lineEnd:
            return offset(forLine: currentLine, column: lines[currentLine].count, in: lines)

        case .documentStart:
            return 0

        case .documentEnd:
            return text.count
        }
    }
}

// MARK: - Helpers

private extension Motion {
    /// Returns (lineIndex, columnIndex) for a given character offset.
    func lineAndColumn(for offset: Int, in lines: [String]) -> (Int, Int) {
        var remaining = offset
        for (i, line) in lines.enumerated() {
            if remaining <= line.count {
                return (i, remaining)
            }
            // +1 for the newline character
            remaining -= line.count + 1
        }
        return (lines.count - 1, lines.last?.count ?? 0)
    }

    /// Returns the character offset for a given line and column.
    func offset(forLine line: Int, column: Int, in lines: [String]) -> Int {
        var offset = 0
        for i in 0..<line {
            offset += lines[i].count + 1 // +1 for newline
        }
        return offset + min(column, lines[line].count)
    }

    // MARK: Word motion

    /// Vim-style word: a word is a sequence of alphanumeric/underscore chars, or a sequence of other non-whitespace chars.
    func isWordChar(_ ch: Character) -> Bool {
        return ch.isLetter || ch.isNumber || ch == "_"
    }

    func charType(_ ch: Character) -> Int {
        if ch.isWhitespace || ch.isNewline { return 0 }
        if isWordChar(ch) { return 1 }
        return 2 // punctuation
    }

    func wordForwardOffset(from caret: Int, in text: String, count: Int) -> Int {
        let chars = Array(text)
        var pos = caret
        var moves = 0

        while moves < count && pos < chars.count {
            let currentType = charType(chars[pos])
            // Skip current word characters.
            while pos < chars.count && charType(chars[pos]) == currentType {
                pos += 1
            }
            // Skip whitespace between words.
            while pos < chars.count && charType(chars[pos]) == 0 {
                pos += 1
            }
            moves += 1
        }
        return pos
    }

    func wordBackOffset(from caret: Int, in text: String, count: Int) -> Int {
        let chars = Array(text)
        var pos = min(caret, chars.count - 1)
        if pos < 0 { return 0 }
        var moves = 0

        // If we're at the start of a word, skip back over preceding whitespace first.
        if pos > 0 && charType(chars[pos]) != 0 && charType(chars[pos - 1]) == 0 {
            while pos > 0 && charType(chars[pos - 1]) == 0 {
                pos -= 1
            }
        }

        while moves < count && pos > 0 {
            let currentType = charType(chars[pos - 1])
            // Skip back over current word characters.
            while pos > 0 && charType(chars[pos - 1]) == currentType {
                pos -= 1
            }
            // Skip back over whitespace.
            while pos > 0 && charType(chars[pos - 1]) == 0 {
                pos -= 1
            }
            moves += 1
        }
        return pos
    }

    func wordEndOffset(from caret: Int, in text: String, count: Int) -> Int {
        let chars = Array(text)
        var pos = caret
        var moves = 0

        while moves < count && pos < chars.count {
            // If on whitespace, skip to next word.
            while pos < chars.count && charType(chars[pos]) == 0 {
                pos += 1
            }
            guard pos < chars.count else { break }
            let currentType = charType(chars[pos])
            // Move to end of this word.
            while pos < chars.count && charType(chars[pos]) == currentType {
                pos += 1
            }
            // pos is now one past the end of the word.
            moves += 1
        }
        // e positions the caret on the last character of the word.
        // If no movement happened, stay at current position.
        return moves > 0 ? max(0, pos - 1) : caret
    }

    // MARK: WORD motion (whitespace-delimited only)

    /// W: skip to start of next whitespace-delimited WORD.
    /// Move forward past current non-whitespace, then past whitespace.
    func wordForwardWORDOffset(from caret: Int, in text: String, count: Int) -> Int {
        let chars = Array(text)
        var pos = caret
        var moves = 0

        while moves < count && pos < chars.count {
            // Skip current non-whitespace chars.
            while pos < chars.count && !chars[pos].isWhitespace && !chars[pos].isNewline {
                pos += 1
            }
            // Skip whitespace.
            while pos < chars.count && (chars[pos].isWhitespace || chars[pos].isNewline) {
                pos += 1
            }
            moves += 1
        }
        return pos
    }

    /// B: move back to start of previous whitespace-delimited WORD.
    /// Skip back over whitespace, then skip back over non-whitespace.
    func wordBackWORDOffset(from caret: Int, in text: String, count: Int) -> Int {
        let chars = Array(text)
        var pos = min(caret, chars.count - 1)
        if pos < 0 { return 0 }
        var moves = 0

        // If at start of a WORD, skip back over preceding whitespace first.
        if pos > 0 && !chars[pos].isWhitespace && !chars[pos].isNewline
            && (chars[pos - 1].isWhitespace || chars[pos - 1].isNewline) {
            while pos > 0 && (chars[pos - 1].isWhitespace || chars[pos - 1].isNewline) {
                pos -= 1
            }
        }

        while moves < count && pos > 0 {
            // Skip back over current WORD chars.
            while pos > 0 && !chars[pos - 1].isWhitespace && !chars[pos - 1].isNewline {
                pos -= 1
            }
            // Skip back over whitespace.
            while pos > 0 && (chars[pos - 1].isWhitespace || chars[pos - 1].isNewline) {
                pos -= 1
            }
            moves += 1
        }
        return pos
    }

    /// E: move to end of current/next whitespace-delimited WORD.
    /// Skip forward over whitespace if on it, then to end of non-whitespace.
    func wordEndWORDOffset(from caret: Int, in text: String, count: Int) -> Int {
        let chars = Array(text)
        var pos = caret
        var moves = 0

        while moves < count && pos < chars.count {
            // If on whitespace, skip to next WORD.
            while pos < chars.count && (chars[pos].isWhitespace || chars[pos].isNewline) {
                pos += 1
            }
            guard pos < chars.count else { break }
            // Move to end of this WORD.
            while pos < chars.count && !chars[pos].isWhitespace && !chars[pos].isNewline {
                pos += 1
            }
            moves += 1
        }
        // E positions the caret on the last character of the WORD.
        // If no movement happened, stay at current position.
        return moves > 0 ? max(0, pos - 1) : caret
    }
}
