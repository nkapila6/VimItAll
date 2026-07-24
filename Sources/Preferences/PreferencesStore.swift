import SwiftUI
import UniformTypeIdentifiers

/// User preferences backed by UserDefaults.
@MainActor
final class PreferencesStore: ObservableObject {
    @AppStorage("vimitallEnabled") var enabled: Bool = true
    @AppStorage("showModeIndicator") var showModeIndicator: Bool = true
    @AppStorage("keyboardFallbackEnabled") var keyboardFallbackEnabled: Bool = true
    @AppStorage("modeEntryKey") var modeEntryKey: String = "esc"
    @AppStorage("customEntrySequence") var customEntrySequence: String = "jk"
    @AppStorage("showFocusHighlight") var showFocusHighlight: Bool = false
}

/// Small helper to refresh frontmost app info on the main actor.
@MainActor
private func currentFrontmostInfo() -> (name: String?, bundleId: String?) {
    let app = NSWorkspace.shared.frontmostApplication
    return (app?.localizedName, app?.bundleIdentifier)
}

/// SwiftUI preferences window content with custom tab bar.
struct PreferencesView: View {
    @StateObject private var store = PreferencesStore()
    @StateObject private var blacklist = AppBlacklist()
    @State private var selectedTab = 0

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar with icon + label buttons.
            VStack(alignment: .leading, spacing: 0) {
                tabButton(title: "General", icon: "gearshape.fill", index: 0)
                tabButton(title: "Display", icon: "eye.fill", index: 1)
                tabButton(title: "Strategy", icon: "rectangle.righthalf.inset.filled", index: 2)
                tabButton(title: "Exceptions", icon: "shield.fill", index: 3)
                Spacer()
            }
            .frame(width: 160)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Content area.
            VStack {
                switch selectedTab {
                case 0: GeneralTab(store: store)
                case 1: DisplayTab(store: store)
                case 2: StrategyTab(store: store)
                case 3: AppExceptionsTab(blacklist: blacklist)
                default: EmptyView()
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(width: 520, height: 420)
    }

    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { selectedTab = index }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                    .foregroundColor(selectedTab == index ? .accentColor : .secondary)
                Text(title)
                    .foregroundColor(selectedTab == index ? .primary : .secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(selectedTab == index ? Color.accentColor.opacity(0.15) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Enable vimitall", isOn: $store.enabled)
                Toggle("Start at login", isOn: Binding(
                    get: { LoginService.isEnabled },
                    set: { newValue in
                        do {
                            if newValue { try LoginService.enable() }
                            else { try LoginService.disable() }
                        } catch {
                            print("Failed to toggle login service: \(error)")
                        }
                    }
                ))
            }

            Section("Mode Entry") {
                Picker("Enter Normal mode with", selection: $store.modeEntryKey) {
                    Text("esc").tag("esc")
                    Text("jk").tag("jk")
                    Text("Ctrl+[").tag("ctrlBracket")
                    Text("Custom sequence").tag("custom")
                }
                .pickerStyle(.radioGroup)

                if store.modeEntryKey == "custom" {
                    TextField("Two-letter sequence (e.g. jk)", text: $store.customEntrySequence)
                        .frame(width: 200)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Display Tab

struct DisplayTab: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        Form {
            Section("Menu Bar") {
                Toggle("Show mode indicator", isOn: $store.showModeIndicator)
                Text("Colored dot in the menu bar showing N (normal), I (insert), or V (visual).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Focus Highlight") {
                Toggle("Highlight focused window", isOn: $store.showFocusHighlight)
                Text("Draws a colored border around the active window in Normal or Visual mode.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Strategy Tab

struct StrategyTab: View {
    @ObservedObject var store: PreferencesStore

    var body: some View {
        Form {
            Section("Keyboard Fallback") {
                Toggle("Use keyboard fallback for unsupported apps", isOn: $store.keyboardFallbackEnabled)
                Text("When enabled, vimitall uses simulated arrow keys in apps where text access is unavailable (Firefox, Chrome, Electron, etc.).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - App Exceptions Tab

struct AppExceptionsTab: View {
    @ObservedObject var blacklist: AppBlacklist
    @State private var manualBundleId: String = ""
    @State private var currentInfo: (name: String?, bundleId: String?) = currentFrontmostInfo()

    var body: some View {
        Form {
            Section("Add Exception") {
                if let bundleId = currentInfo.bundleId {
                    HStack {
                        Text("Current app: \(currentInfo.name ?? bundleId)")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Button("Add current app") {
                            blacklist.add(bundleId)
                        }
                    }
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
            }

            Section("Excluded Apps") {
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
        .formStyle(.grouped)
        .padding()
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
