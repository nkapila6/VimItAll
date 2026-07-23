import Foundation

/// Snapshot of the focused text element's state.
struct AXTextElement {
    let text: String
    let caretOffset: Int
    let selectionLength: Int
    let supportsEdit: Bool
}
