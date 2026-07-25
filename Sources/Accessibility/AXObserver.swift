import AppKit
import ApplicationServices
import os.log

/// Wraps the system-wide AXUIElement for focus tracking and text element queries.
/// @unchecked Sendable: thread safety is handled by dispatching callbacks to main.
final class AXFocusObserver: @unchecked Sendable {
    private let systemWide = AXUIElementCreateSystemWide()
    private var observer: AXObserver?
    private var onChange: (() -> Void)?
    private var focusedElement: AXUIElement?
    private let log = OSLog(subsystem: "app.vimitall.vimitall", category: "AXObserver")

    /// Returns the currently focused text element, or nil if focus is not on a text field/area.
    func currentFocusedTextElement() -> AXTextElement? {
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused)
        guard result == .success, let element = focused else { return nil }
        // AXUIElement is a CF opaque type; force-cast is safe.
        let axElement = element as! AXUIElement
        let actualRole = axElement.attribute(kAXRoleAttribute) as? String ?? "nil"

        // Accept any element that exposes editable text content.
        // Browsers and Electron apps may use non-standard roles, but a real
        // text input will have a String kAXValueAttribute and a settable value.
        let text = axElement.attribute(kAXValueAttribute) as? String
        let hasSelection = axElement.attribute(kAXSelectedTextRangeAttribute) != nil

        guard let text, !text.isEmpty || hasSelection else {
            os_log("focused element role %{public}@ has no readable text - skipping", log: log, type: .info, actualRole)
            focusedElement = nil
            return nil
        }

        // Verify the value is settable - otherwise we can't move the caret.
        let supportsEdit = axElement.isAttributeSettable(kAXValueAttribute)
        guard supportsEdit else {
            os_log("focused element role %{public}@ text is not editable - skipping", log: log, type: .info, actualRole)
            focusedElement = nil
            return nil
        }

        focusedElement = axElement
        os_log("focused element role %{public}@ accepted as text target", log: log, type: .info, actualRole)

        let caretOffset: Int
        let selectionLength: Int

        if let rangeValue = axElement.attribute(kAXSelectedTextRangeAttribute) {
            var range = CFRange(location: 0, length: 0)
            // AXValue is a CF opaque type; force-cast is safe.
            let axValue = rangeValue as! AXValue
            AXValueGetValue(axValue, .cfRange, &range)
            caretOffset = range.location
            selectionLength = range.length
        } else {
            caretOffset = 0
            selectionLength = 0
        }

        return AXTextElement(
            text: text,
            caretOffset: caretOffset,
            selectionLength: selectionLength,
            supportsEdit: supportsEdit
        )
    }

    /// Returns the currently focused AXUIElement for mutation operations.
    func currentFocusedElement() -> AXUIElement? {
        _ = currentFocusedTextElement()
        return focusedElement
    }

    /// Starts tracking focus changes. Calls onChange on the main thread when focus moves.
    func startFocusTracking(onChange: @escaping () -> Void) {
        self.onChange = onChange

        let callback: AXObserverCallback = { _, element, _, refcon in
            guard let refcon else { return }
            let observer = Unmanaged<AXFocusObserver>.fromOpaque(refcon).takeUnretainedValue()
            // AXObserver callbacks run on the AX event thread, not main.
            // Dispatch to main since onChange accesses @MainActor state.
            DispatchQueue.main.async {
                observer.onChange?()
            }
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverCreate(getpid(), callback, &observer)
        guard result == .success, let observer else { return }

        AXObserverAddNotification(
            observer,
            systemWide,
            kAXFocusedUIElementChangedNotification as CFString,
            selfPtr
        )

        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    deinit {
        if let observer {
            AXObserverRemoveNotification(observer, systemWide, kAXFocusedUIElementChangedNotification as CFString)
            let runLoopSource = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
    }
}

// MARK: - AXUIElement convenience helpers

extension AXUIElement {
    func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, name as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    func isAttributeSettable(_ name: String) -> Bool {
        var settable: DarwinBoolean = false
        let result = AXUIElementIsAttributeSettable(self, name as CFString, &settable)
        return result == .success && settable.boolValue
    }

    func setAttribute(_ name: String, value: CFTypeRef) -> Bool {
        return AXUIElementSetAttributeValue(self, name as CFString, value) == .success
    }
}
