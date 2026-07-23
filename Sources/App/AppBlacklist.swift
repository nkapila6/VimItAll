import Foundation
import SwiftUI

/// Tracks apps where vimitall should pass through all keys unchanged.
@MainActor
final class AppBlacklist: ObservableObject {
    @AppStorage("blacklistedApps") private var blacklistRaw: String = ""

    /// Bundle IDs that should receive raw key events.
    var blacklistedBundleIds: Set<String> {
        Set(blacklistRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    init() {
        seedDefaultsIfNeeded()
    }

    func isBlacklisted(_ bundleId: String) -> Bool {
        blacklistedBundleIds.contains(bundleId)
    }

    func add(_ bundleId: String) {
        var ids = blacklistedBundleIds
        ids.insert(bundleId)
        save(ids)
    }

    func remove(_ bundleId: String) {
        var ids = blacklistedBundleIds
        ids.remove(bundleId)
        save(ids)
    }

    private func save(_ ids: Set<String>) {
        blacklistRaw = ids.sorted().joined(separator: ",")
    }

    private func seedDefaultsIfNeeded() {
        guard blacklistRaw.isEmpty else { return }
        // Only blacklist apps that have their own Vim mode and would conflict.
        // Browsers and Electron apps are no longer blacklisted since the keyboard
        // fallback strategy handles them.
        let defaults: Set<String> = [
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.microsoft.VSCode",
            "com.todesktop.230313mzl4w4u92",
            "com.neovim.neovim",
            "com.jetbrains.intellij",
            "com.jetbrains.pycharm",
            "com.googlecode.androidstudio",
            "org.gnu.Emacs",
            "com.vscodium.codium"
        ]
        save(defaults)
    }
}
