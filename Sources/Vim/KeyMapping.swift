import Foundation

enum KeyAction: Equatable {
    case motion(Motion)
    case `operator`(Operator)
    case enterInsert(trigger: InsertTrigger)
    case enterVisual(lineWise: Bool)
    case pendingReplace
    case pendingFind(forward: Bool, till: Bool)
    case repeatFind(reverse: Bool)
    case repeatLastChange
    case passthrough
}

enum InsertTrigger: String {
    case i = "i"
    case a = "a"
    case A = "A"
    case I = "I"
    case s = "s"
    case o = "o"
    case O = "O"
    case esc = "esc"
}

struct KeyMapping {
    let action: KeyAction
    let count: Int

    init(action: KeyAction, count: Int = 1) {
        self.action = action
        self.count = count
    }

    func withCount(_ count: Int) -> KeyMapping {
        KeyMapping(action: action, count: count)
    }

    /// Resolve a key string to a KeyMapping. Returns nil for unmapped keys.
    static func resolve(_ keys: String) -> KeyMapping? {
        // Multi-character operators must be checked before single-char operators collide.
        if keys == "cc" {
            return KeyMapping(action: .operator(.changeLine))
        }

        // Single-key motions.
        if let motion = Motion(rawValue: keys) {
            return KeyMapping(action: .motion(motion))
        }

        // Single-key operators.
        if let op = Operator(rawValue: keys) {
            return KeyMapping(action: .operator(op))
        }

        // Insert triggers.
        if let trigger = InsertTrigger(rawValue: keys) {
            return KeyMapping(action: .enterInsert(trigger: trigger))
        }

        // Visual mode triggers.
        if keys == "v" {
            return KeyMapping(action: .enterVisual(lineWise: false))
        }
        if keys == "V" {
            return KeyMapping(action: .enterVisual(lineWise: true))
        }

        // r starts a two-step replace sequence.
        if keys == "r" {
            return KeyMapping(action: .pendingReplace)
        }

        // f/F/t/T start a two-step find sequence.
        if keys == "f" {
            return KeyMapping(action: .pendingFind(forward: true, till: false))
        }
        if keys == "F" {
            return KeyMapping(action: .pendingFind(forward: false, till: false))
        }
        if keys == "t" {
            return KeyMapping(action: .pendingFind(forward: true, till: true))
        }
        if keys == "T" {
            return KeyMapping(action: .pendingFind(forward: false, till: true))
        }

        // ; and , repeat the last find.
        if keys == ";" {
            return KeyMapping(action: .repeatFind(reverse: false))
        }
        if keys == "," {
            return KeyMapping(action: .repeatFind(reverse: true))
        }

        // . repeats the last change.
        if keys == "." {
            return KeyMapping(action: .repeatLastChange)
        }

        return nil
    }
}
