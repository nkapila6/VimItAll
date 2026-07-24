import SwiftUI
import UniformTypeIdentifiers

/// User preferences backed by UserDefaults.
@MainActor
final class PreferencesStore: ObservableObject {
    @AppStorage("leaderKey") var leaderKey: String = "esc"
    @AppStorage("enabled") var enabled: Bool = true
    @AppStorage("showModeIndicator") var showModeIndicator: Bool = true
    @AppStorage("keyboardFallbackEnabled") var keyboardFallbackEnabled: Bool = true
}

/// Small helper to refresh frontmost app info on the main actor.
@MainActor
private func currentFrontmostInfo() -> (name: String?, bundleId: String?) {
    let app = NSWorkspace.shared.frontmostApplication
    return (app?.localizedName, app?.bundleIdentifier)
}

/// SwiftUI preferences window content.
struct PreferencesView: View {
    @StateObject private var store = PreferencesStore()
    @StateObject private var blacklist = AppBlacklist()
    @State private var manualBundleId: String = ""
    @State private var currentInfo: (name: String?, bundleId: String?) = currentFrontmostInfo()

    var body: some View {
        Form {
            Section {
                Picker("Leader Key", selection: $store.leaderKey) {
                    Text("esc").tag("esc")
                }
                .pickerStyle(.radioGroup)

                Toggle("Enable vimitall", isOn: $store.enabled)

                Toggle("Show mode indicator in menu bar", isOn: $store.showModeIndicator)

                Toggle("Use keyboard fallback for unsupported apps", isOn: $store.keyboardFallbackEnabled)
            }

            Section("App Exceptions") {
                if let bundleId = currentInfo.bundleId {
                    HStack {
                        Text("Current app: \(currentInfo.name ?? bundleId) (\(bundleId))")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Add current app") {
                            blacklist.add(bundleId)
                        }
                    }
                } else {
                    Text("Current app bundle ID unavailable")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    TextField("Bundle identifier", text: $manualBundleId)
                    Button("Add") {
                        let trimmed = manualBundleId.trimmingCharacters(in: .whitespaces)
                        guard !trimmed.isEmpty else { return }
                        blacklist.add(trimmed)
                        manualBundleId = ""
                    }
                    Button("Browse...") {
                        showAppPicker()
                    }
                }

                List {
                    ForEach(Array(blacklist.blacklistedBundleIds).sorted(), id: \.self) { bundleId in
                        HStack {
                            Text(displayName(for: bundleId))
                            Spacer()
                            Button("Remove") {
                                blacklist.remove(bundleId)
                            }
                        }
                    }
                }
                .frame(height: 120)
            }
        }
        .padding()
        .frame(width: 420, height: 460)
        .onReceive(NotificationCenter.default.publisher(for: NSWorkspace.didActivateApplicationNotification)) { _ in
            currentInfo = currentFrontmostInfo()
        }
    }

    private func showAppPicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.title = "Select an app to blacklist"

        if panel.runModal() == .OK, let url = panel.url {
            if let bundle = Bundle(url: url), let bundleId = bundle.bundleIdentifier {
                blacklist.add(bundleId)
            }
        }
    }

    private func appNameForBundleId(_ bundleId: String) -> String? {
        let appsDir = URL(fileURLWithPath: "/Applications")
        guard let contents = try? FileManager.default.contentsOfDirectory(at: appsDir, includingPropertiesForKeys: nil) else {
            return nil
        }
        for appURL in contents where appURL.pathExtension == "app" {
            if let bundle = Bundle(url: appURL), bundle.bundleIdentifier == bundleId {
                return bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? appURL.deletingPathExtension().lastPathComponent
            }
        }
        return nil
    }

    private func displayName(for bundleId: String) -> String {
        if let name = appNameForBundleId(bundleId) {
            return "\(name) (\(bundleId))"
        }
        return bundleId
    }
}
