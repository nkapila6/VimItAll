import ApplicationServices

/// Performs text mutations on the currently focused AXUIElement.
final class AXMutator {
    private var element: AXUIElement?

    func setElement(_ element: AXUIElement) {
        self.element = element
    }

    func moveCaret(to offset: Int) {
        setSelection(start: offset, length: 0)
    }

    func setSelection(start: Int, length: Int) {
        guard let element else { return }
        var range = CFRange(location: start, length: length)
        guard let axValue = AXValueCreate(.cfRange, &range) else { return }
        _ = element.setAttribute(kAXSelectedTextRangeAttribute as String, value: axValue)
    }

    func insertText(_ text: String) {
        guard let element else { return }
        _ = element.setAttribute(kAXSelectedTextAttribute as String, value: text as CFString)
    }

    func deleteRange(start: Int, length: Int) {
        setSelection(start: start, length: length)
        insertText("")
    }

    func replaceRange(start: Int, length: Int, with text: String) {
        setSelection(start: start, length: length)
        insertText(text)
    }

    func currentCaretOffset() -> Int? {
        guard let element else { return nil }
        guard let rangeValue = element.attribute(kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange(location: 0, length: 0)
        let axValue = rangeValue as! AXValue
        AXValueGetValue(axValue, .cfRange, &range)
        return range.location
    }

    /// Returns the full selection range (location and length).
    func currentSelectionRange() -> (start: Int, length: Int)? {
        guard let element else { return nil }
        guard let rangeValue = element.attribute(kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange(location: 0, length: 0)
        let axValue = rangeValue as! AXValue
        AXValueGetValue(axValue, .cfRange, &range)
        return (range.location, range.length)
    }

    func currentText() -> String? {
        guard let element else { return nil }
        return element.attribute(kAXValueAttribute) as? String
    }

    func currentSelectionText() -> String? {
        guard let element else { return nil }
        return element.attribute(kAXSelectedTextAttribute) as? String
    }
}
