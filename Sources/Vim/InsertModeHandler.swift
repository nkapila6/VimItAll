import Foundation
import CoreGraphics

/// Handles insert mode: passes through most keys, intercepts the configured mode-entry key.
@MainActor
final class InsertModeHandler {
    private let vimState: VimState
    private var buffer: String = ""
    private var bufferTimer: DispatchWorkItem?

    init(vimState: VimState) {
        self.vimState = vimState
    }

    /// Returns true if the key was consumed, false if passthrough.
    func handle(_ key: String) -> Bool {
        let modeEntryKey = UserDefaults.standard.string(forKey: "modeEntryKey") ?? "esc"

        switch modeEntryKey {
        case "esc":
            if key == "esc" {
                vimState.enterNormalMode()
                return true
            }
            return false

        case "ctrlBracket":
            // Ctrl+[ is intercepted in AppDelegate before modifier passthrough.
            if key == "ctrlBracket" {
                vimState.enterNormalMode()
                return true
            }
            return false

        case "jk":
            return handleSequence(key, sequence: "jk")

        case "custom":
            let custom = UserDefaults.standard.string(forKey: "customEntrySequence") ?? ""
            return handleSequence(key, sequence: custom)

        default:
            // Fallback: esc always works.
            if key == "esc" {
                vimState.enterNormalMode()
                return true
            }
            return false
        }
    }

    /// Handles a multi-character sequence like "jk" or a custom two-letter combo.
    /// Consumes keys while the sequence is being built. If the sequence completes,
    /// enters Normal mode. If it times out or mismatches, replays the buffered keys.
    private func handleSequence(_ key: String, sequence: String) -> Bool {
        guard !sequence.isEmpty else { return false }

        bufferTimer?.cancel()

        // esc always cancels and enters Normal mode.
        if key == "esc" {
            buffer = ""
            vimState.enterNormalMode()
            return true
        }

        buffer.append(key)

        if sequence.hasPrefix(buffer) {
            if buffer == sequence {
                // Complete match - enter Normal mode. No chars were typed.
                buffer = ""
                vimState.enterNormalMode()
                return true
            }
            // Partial match - consume the key, set a timeout to replay if no more keys come.
            let buffered = buffer
            bufferTimer = DispatchWorkItem { [weak self] in
                self?.replayKeys(buffered)
                self?.buffer = ""
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: bufferTimer!)
            return true
        } else {
            // Mismatch - replay buffered keys, then let this key through.
            replayKeys(buffer)
            buffer = ""
            return false
        }
    }

    /// Re-injects buffered keys as CGEvent unicode strings, tagged so our event tap ignores them.
    private func replayKeys(_ keys: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        for char in keys {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
            let chars = Array(String(char).utf16)
            down.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            up.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: chars)
            down.setIntegerValueField(.eventSourceUserData, value: Int64(KeyboardSynthesizer.synthMarker))
            up.setIntegerValueField(.eventSourceUserData, value: Int64(KeyboardSynthesizer.synthMarker))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }
}
