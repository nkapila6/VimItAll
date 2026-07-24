import Foundation

enum VimMode {
    case normal
    case insert
    case visual
}

/// Stores the last change for `.` repeat.
struct LastChange {
    let op: Operator
    let motion: Motion?
    let count: Int
}

/// Stores the last find command for `;` and `,` repeat.
struct LastFind {
    let char: Character
    let forward: Bool
    let till: Bool
}

@MainActor
final class VimState: ObservableObject {
    @Published var mode: VimMode = .insert
    @Published var currentCount: Int? = nil
    @Published var pendingOperator: Operator? = nil
    @Published var visualAnchor: Int = 0
    @Published var visualLineWise: Bool = false

    /// Pending find state: set when f/F/t/T is pressed, consumed when next key arrives.
    var pendingFind: (forward: Bool, till: Bool)? = nil

    /// Last find command for ; and , repeat.
    var lastFind: LastFind? = nil

    /// Last change for . repeat.
    var lastChange: LastChange? = nil

    func enterNormalMode() {
        mode = .normal
        reset()
        clearVisualState()
    }

    func enterInsertMode() {
        mode = .insert
        reset()
        clearVisualState()
    }

    func enterVisualMode(anchor: Int, lineWise: Bool) {
        mode = .visual
        reset()
        visualAnchor = anchor
        visualLineWise = lineWise
    }

    func reset() {
        currentCount = nil
        pendingOperator = nil
        pendingFind = nil
    }

    private func clearVisualState() {
        visualAnchor = 0
        visualLineWise = false
    }
}
