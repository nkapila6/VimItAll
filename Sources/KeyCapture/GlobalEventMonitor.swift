import AppKit
import CoreGraphics
import os.log

// CGEvent is a CoreFoundation type designed for cross-thread use
// (event taps run on background threads). Safe to mark Sendable.
extension CGEvent: @unchecked Sendable {}

/// Captures global keyDown events via CGEventTap.
/// @unchecked Sendable: thread safety is handled by dispatching callbacks to main.
final class GlobalEventMonitor: @unchecked Sendable {
    private let callback: (CGEvent?) -> CGEvent?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let log = OSLog(subsystem: "app.vimitall.vimitall", category: "EventTap")

    init(callback: @escaping (CGEvent?) -> CGEvent?) {
        self.callback = callback
    }

    /// True if the event tap was successfully created and is active.
    private(set) var isActive = false

    func start() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<GlobalEventMonitor>.fromOpaque(refcon).takeUnretainedValue()

                // The event tap runs on the main run loop, so we're usually
                // already on the main thread. Check to avoid deadlock from
                // DispatchQueue.main.sync when called from main.
                if Thread.isMainThread {
                    let result = monitor.callback(event)
                    if let result {
                        return Unmanaged.passUnretained(result)
                    }
                    return nil
                }

                // Fallback for background-thread callbacks: dispatch sync.
                var result: CGEvent? = event
                DispatchQueue.main.sync {
                    result = monitor.callback(event)
                }
                if let result {
                    return Unmanaged.passUnretained(result)
                }
                return nil
            },
            userInfo: selfPtr
        ) else {
            os_log("CGEventTapCreate FAILED - accessibility permission not granted", log: log, type: .error)
            isActive = false
            return
        }

        eventTap = tap
        isActive = true
        os_log("CGEventTap created successfully", log: log, type: .info)
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Synthesize a key event. Stub for future use (e.g., undo via Cmd+Z).
    func synthesizeKey(keyCode: CGKeyCode, flags: CGEventFlags) {
        let marker = Int64(KeyboardSynthesizer.synthMarker)
        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true) else { return }
        event.flags = flags
        event.setIntegerValueField(.eventSourceUserData, value: marker)
        event.post(tap: .cghidEventTap)
        // Key up
        guard let upEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else { return }
        upEvent.flags = flags
        upEvent.setIntegerValueField(.eventSourceUserData, value: marker)
        upEvent.post(tap: .cghidEventTap)
    }
}
