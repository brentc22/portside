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

    @objc func stop(_ sender: NSMenuItem) { end(sender, signal: SIGTERM, docker: "stop") }
    @objc func forceQuit(_ sender: NSMenuItem) { end(sender, signal: SIGKILL, docker: "kill") }

    /// Processes get a signal; containers go through `docker`, because their pid is the
    /// VM's port proxy and killing that would take every container down with it.
    private func end(_ sender: NSMenuItem, signal sig: Int32, docker command: String) {
        guard let target = sender.representedObject as? StopTarget else { return }
        for pid in target.pids { kill(pid, sig) }
        onChange()
        guard !target.containerIDs.isEmpty else { return }
        let arguments = [command] + target.containerIDs
        Task { [weak self] in
            // `docker stop` waits up to 10 s for the container to exit.
            await Task.detached(priority: .userInitiated) {
                _ = DockerCLI.run(arguments, timeout: 20)
            }.value
            self?.onChange()
        }
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

/// What Stop and Force Quit act on: plain processes and Docker containers.
final class StopTarget: NSObject {
    let pids: [Int32]
    let containerIDs: [String]

    init(_ servers: [Server]) {
        pids = servers.filter { $0.container == nil }.map(\.pid)
        containerIDs = servers.compactMap { $0.container?.id }
    }
}

/// A directory to open with a specific application (editor or terminal).
final class AppTarget: NSObject {
    let path: String
    let app: URL
    init(path: String, app: URL) { self.path = path; self.app = app }
}
