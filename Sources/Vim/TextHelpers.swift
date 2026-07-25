import Foundation

/// Shared text position helpers used by operators and motion handlers.
func lineAndColumn(for offset: Int, in lines: [String]) -> (Int, Int) {
    var remaining = offset
    for (i, line) in lines.enumerated() {
        if remaining <= line.count {
            return (i, remaining)
        }
        remaining -= line.count + 1
    }
    return (lines.count - 1, lines.last?.count ?? 0)
}

func offset(forLine line: Int, column: Int, in lines: [String]) -> Int {
    var offset = 0
    for i in 0..<line {
        offset += lines[i].count + 1
    }
    return offset + min(column, lines[line].count)
}
