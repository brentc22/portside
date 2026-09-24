import AppKit
import PortsideCore

/// Everything a menu item can do. Each action reads its target from `representedObject`.
@MainActor
final class Actions: NSObject {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    @objc func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func copyString(_ sender: NSMenuItem) {
        guard let string = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    @objc func stop(_ sender: NSMenuItem) { signal(sender, SIGTERM) }
    @objc func forceQuit(_ sender: NSMenuItem) { signal(sender, SIGKILL) }

    private func signal(_ sender: NSMenuItem, _ sig: Int32) {
        guard let pids = sender.representedObject as? [Int32] else { return }
        for pid in pids { kill(pid, sig) }
        onChange()
    }

    @objc func revealInFinder(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    @objc func openWithApp(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? AppTarget else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: target.path)], withApplicationAt: target.app,
                                configuration: NSWorkspace.OpenConfiguration())
    }

    @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        LaunchAtLogin.toggle()
    }

    @objc func toggleAutomaticUpdates(_ sender: NSMenuItem) {
        Updater.shared.automaticallyChecks.toggle()
    }

    @objc func checkForUpdates(_ sender: NSMenuItem) {
        Updater.shared.check(userInitiated: true)
    }

    @objc func showAvailableUpdate(_ sender: NSMenuItem) {
        Updater.shared.offerAvailable()
    }
}

/// A directory to open with a specific application (editor or terminal).
final class AppTarget: NSObject {
    let path: String
    let app: URL
    init(path: String, app: URL) { self.path = path; self.app = app }
}
