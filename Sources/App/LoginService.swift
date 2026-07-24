import ServiceManagement

/// Wraps SMAppService for the "Start at login" preference.
/// Requires the app to be in /Applications and properly signed.
/// In debug builds from DerivedData, register() may fail silently.
@MainActor
enum LoginService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func enable() throws {
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        try SMAppService.mainApp.unregister()
    }
}
