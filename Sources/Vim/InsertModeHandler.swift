import Foundation

/// Handles insert mode: passes through all keys except esc.
@MainActor
final class InsertModeHandler {
    private let vimState: VimState

    init(vimState: VimState) {
        self.vimState = vimState
    }

    /// Returns true if the key was consumed (esc detected), false if passthrough.
    func handle(_ key: String) -> Bool {
        if key == "esc" {
            vimState.enterNormalMode()
            return true
        }
        return false
    }
}
