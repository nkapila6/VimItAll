import AppKit
import ApplicationServices
import SwiftUI
import os.log

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var eventMonitor: GlobalEventMonitor?
    private var axObserver: AXFocusObserver?
    private var axMutator = AXMutator()
    private var vimState = VimState()
    private var keySequence = KeySequence()
    private var normalHandler: NormalModeHandler?
    private var insertHandler: InsertModeHandler?
    private var visualHandler: VisualModeHandler?
    private var keyboardStrategyHandler: KeyboardStrategyHandler?
    private var keyboardSynth: KeyboardSynthesizer?
    private var permissionTimer: Timer?
    private var blacklist = AppBlacklist()
    private var frontmostBundleId: String? = nil
    private let strategyLog = OSLog(subsystem: "app.vimitall.vimitall", category: "Strategy")
    /// Cached result of AX text availability. Invalidated on focus change and mode entry.
    private var cachedAXAvailable: Bool?
    private var isEnabled: Bool {
        get {
            // Default to true when the key hasn't been set yet.
            if UserDefaults.standard.object(forKey: "vimitallEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "vimitallEnabled")
        }
        set { UserDefaults.standard.set(newValue, forKey: "vimitallEnabled") }
    }
    /// Whether the keyboard fallback strategy is enabled in preferences.
    /// Defaults to true - use keyboard fallback when AX is unavailable.
    private var keyboardFallbackEnabled: Bool {
        // UserDefaults returns false for missing keys, so we need to handle
        // the "not set" case as true (default on).
        if UserDefaults.standard.object(forKey: "keyboardFallbackEnabled") == nil {
            return true
        }
        return UserDefaults.standard.bool(forKey: "keyboardFallbackEnabled")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBarController = StatusBarController(vimState: vimState)

        axObserver = AXFocusObserver()
        axObserver?.startFocusTracking { [weak self] in
            self?.cachedAXAvailable = nil
            self?.vimState.enterInsertMode()
        }

        normalHandler = NormalModeHandler(vimState: vimState, axMutator: axMutator, axObserver: axObserver)
        insertHandler = InsertModeHandler(vimState: vimState)
        visualHandler = VisualModeHandler(vimState: vimState, axMutator: axMutator, axObserver: axObserver)

        keyboardSynth = KeyboardSynthesizer()
        keyboardStrategyHandler = KeyboardStrategyHandler(vimState: vimState, synth: keyboardSynth!)

        // Trigger the native macOS Accessibility permission prompt.
        // The key "AXTrustedCheckOptionPrompt" is the value of kAXTrustedCheckOptionPrompt.
        // Using the literal avoids Swift 6 concurrency warnings on the global CFString.
        let options = ["AXTrustedCheckOptionPrompt": true] as NSDictionary
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)

        // Track the focused app so we can bypass blacklisted apps reliably.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(frontmostAppChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if blacklist.isBlacklisted(frontmostBundleId ?? "") {
            vimState.enterInsertMode()
        }

        tryStartEventMonitor()

        if eventMonitor?.isActive != true {
            // Poll until permission is granted, then start the tap.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
                let trusted = AXIsProcessTrusted()
                guard trusted else { return }
                timer.invalidate()
                self?.tryStartEventMonitor()
            }
        }
    }

    @objc private func frontmostAppChanged() {
        frontmostBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        cachedAXAvailable = nil
        let isBlocked = blacklist.isBlacklisted(frontmostBundleId ?? "")
        os_log("frontmost app changed: %{public}@ blacklisted=%d", log: strategyLog, type: .info, frontmostBundleId ?? "nil", isBlocked ? 1 : 0)
        if isBlocked {
            vimState.enterInsertMode()
        }
    }

    private func tryStartEventMonitor() {
        guard eventMonitor?.isActive != true else { return }
        eventMonitor = GlobalEventMonitor { [weak self] event in
            self?.handleKeyEvent(event)
        }
        eventMonitor?.start()
    }

    private func handleKeyEvent(_ event: CGEvent?) -> CGEvent? {
        guard let event else { return event }

        // Only intercept keyDown events.
        guard event.type == .keyDown else { return event }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        // Intercept Ctrl+[ as mode-entry key BEFORE modifier passthrough.
        // Ctrl+[ is keyCode 33 (left bracket) with control flag.
        if keyCode == 33 && flags.contains(.maskControl)
            && !flags.contains(.maskCommand) && !flags.contains(.maskAlternate) {
            let modeEntryKey = UserDefaults.standard.string(forKey: "modeEntryKey") ?? "esc"
            if modeEntryKey == "ctrlBracket" && vimState.mode == .insert {
                let consumed = insertHandler?.handle("ctrlBracket") ?? false
                return consumed ? nil : event
            }
        }

        // Always pass through OS-level shortcuts (Cmd, Ctrl, Option combos).
        // Vim motions are bare keys; only those should be intercepted.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            return event
        }

        // Skip events we synthesized ourselves (keyboard strategy feedback loop guard).
        if event.getIntegerValueField(.eventSourceUserData) == Int64(KeyboardSynthesizer.synthMarker) {
            return event
        }

        // Global enable/disable toggle.
        if !isEnabled { return event }

        // Update frontmost app on each key event as a fallback in case
        // didActivateApplicationNotification didn't fire.
        let currentApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if currentApp != frontmostBundleId {
            frontmostBundleId = currentApp
            cachedAXAvailable = nil
        }

        // Pass through everything when the frontmost app is blacklisted.
        if blacklist.isBlacklisted(frontmostBundleId ?? "") {
            return event
        }

        // Convert CGEvent to a key string for our logic.
        guard let keyString = keyString(from: event) else { return event }

        switch vimState.mode {
        case .normal:
            if useAXStrategy() {
                os_log("normal mode: using AX strategy", log: strategyLog, type: .debug)
                let consumed = normalHandler?.handle(keyString) ?? false
                return consumed ? nil : event
            } else {
                os_log("normal mode: using keyboard strategy", log: strategyLog, type: .debug)
                let consumed = keyboardStrategyHandler?.handle(keyString) ?? false
                return consumed ? nil : event
            }
        case .insert:
            let consumed = insertHandler?.handle(keyString) ?? false
            return consumed ? nil : event
        case .visual:
            if useAXStrategy() {
                os_log("visual mode: using AX strategy", log: strategyLog, type: .debug)
                let consumed = visualHandler?.handle(keyString) ?? false
                return consumed ? nil : event
            } else {
                os_log("visual mode: using keyboard strategy", log: strategyLog, type: .debug)
                let consumed = keyboardStrategyHandler?.handle(keyString) ?? false
                return consumed ? nil : event
            }
        }
    }

    /// Returns true if the AX strategy should be used for the current focused element.
    /// Falls back to keyboard strategy when AX text is unavailable or the preference is off.
    /// Caches the result per focus session to avoid re-querying on every keystroke.
    private func useAXStrategy() -> Bool {
        guard keyboardFallbackEnabled else { return true }

        // Check fresh every time - the AX query is fast and caching causes
        // stale results when switching between editable and non-editable elements.
        let available = axObserver?.currentFocusedTextElement() != nil
        return available
    }

    /// Convert a CGEvent to a human-readable key string for our Vim logic.
    private func keyString(from event: CGEvent) -> String? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // Check for escape (keyCode 53).
        if keyCode == 53 { return "esc" }

        // Check for return/enter (keyCode 36).
        if keyCode == 36 { return "enter" }

        // For regular characters, use CGEvent to get the unicode string.
        var uniCharCount: Int = 0
        var uniChars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(
            maxStringLength: 4,
            actualStringLength: &uniCharCount,
            unicodeString: &uniChars
        )

        if uniCharCount > 0 {
            let str = String(utf16CodeUnits: uniChars, count: uniCharCount)
            return str
        }

        return nil
    }
}
