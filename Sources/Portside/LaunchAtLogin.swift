import ServiceManagement

/// `SMAppService.mainApp` only works from a real .app bundle; from `swift run`
/// the item is hidden rather than failing silently.
@MainActor
enum LaunchAtLogin {
    static var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func toggle() {
        do {
            if isEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("Portside: launch at login failed: \(error)")
        }
    }
}
