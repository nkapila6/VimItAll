import Foundation

enum KeySequenceResult {
    case incomplete
    case complete(KeyMapping)
    case cancel
}

/// Tracks multi-key sequences (counts, dd, gg, jk leader) and resolves them to a KeyMapping.
struct KeySequence {
    private var buffer: String = ""
    private var lastKeyTime: Date = .distantPast
    private let timeout: TimeInterval = 30.0

    mutating func feed(_ key: String) -> KeySequenceResult {
        let now = Date()
        if now.timeIntervalSince(lastKeyTime) > timeout {
            buffer = ""
        }
        lastKeyTime = now

        buffer.append(key)

        // Check for leading digit count: e.g., "3", "12"
        if let count = parseCount(buffer) {
            // If the buffer is purely digits, wait for more.
            if buffer.allSatisfy({ $0.isNumber }) {
                return .incomplete
            }
            // Strip the count prefix and resolve the rest.
            let countStr = String(count)
            let rest = String(buffer.dropFirst(countStr.count))
            if let mapping = KeyMapping.resolve(rest) {
                return .complete(mapping.withCount(count))
            }
            return .cancel
        }

        // Try to resolve the full buffer.
        if let mapping = KeyMapping.resolve(buffer) {
            return .complete(mapping)
        }

        // Check if buffer could be a prefix of a known multi-key sequence.
        if isPrefixOfKnownSequence(buffer) {
            return .incomplete
        }

        return .cancel
    }

    mutating func reset() {
        buffer = ""
        lastKeyTime = .distantPast
    }

    private func parseCount(_ s: String) -> Int? {
        // Must start with 1-9, then 0-9 digits.
        guard let first = s.first, first.isNumber, first != "0" else { return nil }
        var digits = ""
        for ch in s {
            guard ch.isNumber else { break }
            digits.append(ch)
        }
        return Int(digits)
    }

    private func isPrefixOfKnownSequence(_ s: String) -> Bool {
        let known = ["dd", "gg", "yy", "cc"]
        for seq in known {
            if seq.hasPrefix(s) { return true }
        }
        // d/c/y are operator prefixes that may be followed by a motion (dw, cw, yw, etc.)
        if s == "d" || s == "c" || s == "y" { return true }
        return false
    }
}
