import AppKit
import PortsideCore

/// Checks GitHub Releases once a day and offers to install a newer version, the way
/// Sparkle-based apps do (Install / Later / Skip This Version), without the dependency.
@MainActor
final class Updater {
    static let shared = Updater()

    private let feed = URL(string: "https://api.github.com/repos/brentc22/portside/releases/latest")!
    private let appName = "Portside"
    private let defaults = UserDefaults.standard
    private enum Key {
        static let automatic = "automaticallyChecksForUpdates"
        static let lastCheck = "lastUpdateCheck"
        static let skipped = "skippedUpdateVersion"
    }

    /// A newer release found by the last check; the menu shows it at the top.
    private(set) var available: Release?
    private(set) var isBusy = false
    private var timer: Timer?
    private var progress: NSPanel?

    var automaticallyChecks: Bool {
        get { defaults.object(forKey: Key.automatic) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.automatic) }
    }

    var currentVersion: AppVersion {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
            ?? AppVersion("0.0.0")!
    }

    /// Checks shortly after launch and then hourly whether a day has passed since the last check.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        timer?.tolerance = 5 * 60
    }

    private func checkIfDue() {
        let lastCheck = defaults.object(forKey: Key.lastCheck) as? Date
        guard automaticallyChecks, UpdatePolicy.isCheckDue(lastCheck: lastCheck) else { return }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                var request = URLRequest(url: feed, timeoutInterval: 20)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let release = try Release.decode(data)
                defaults.set(Date(), forKey: Key.lastCheck)
                let skipped = defaults.string(forKey: Key.skipped)
                let newer = release.version.map { $0 > currentVersion } ?? false
                available = newer ? release : nil
                if UpdatePolicy.shouldOffer(release, current: currentVersion, skipped: skipped, userInitiated: userInitiated) {
                    offer(release)
                } else if userInitiated {
                    inform("You're up to date", "Portside \(currentVersion) is the latest version.")
                }
            } catch {
                NSLog("Portside: update check failed: \(error)")
                if userInitiated {
                    inform("Couldn't check for updates", error.localizedDescription, style: .warning)
                }
            }
        }
    }

    /// Opens the offer again from the menu's "Update Available" item.
    func offerAvailable() {
        if let available { offer(available) }
    }

    // MARK: - Offer

    private func offer(_ release: Release) {
        guard let version = release.version else { return }
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Portside \(version) is available"
        alert.informativeText = "You have \(currentVersion). Install it now? Portside restarts, and your dev servers keep running."
        alert.accessoryView = notesView(release.body)
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")

        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: install(release, version: version)
        case .alertThirdButtonReturn:
            defaults.set(version.description, forKey: Key.skipped)
            available = nil
        default: break
        }
    }

    private func notesView(_ body: String?) -> NSView? {
        guard let body, !body.isEmpty else { return nil }
        let notes = (try? NSAttributedString(
            markdown: body,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? NSAttributedString(string: body)
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(x: 0, y: 0, width: 360, height: 160)
        scroll.borderType = .bezelBorder
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.textStorage?.setAttributedString(notes)
        text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        text.textColor = .labelColor
        return scroll
    }

    // MARK: - Install

    private func install(_ release: Release, version: AppVersion) {
        let destination = Bundle.main.bundleURL
        let parentIsWritable = FileManager.default.isWritableFile(atPath: destination.deletingLastPathComponent().path)
        // From `swift run`, or an /Applications we can't write to: hand over to the browser.
        guard destination.pathExtension == "app", parentIsWritable, let zipURL = release.zipURL(appName: appName) else {
            NSWorkspace.shared.open(release.htmlURL)
            return
        }

        showProgress("Downloading Portside \(version)…")
        Task {
            do {
                let (download, _) = try await URLSession.shared.download(from: zipURL)
                let workDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("PortsideUpdate-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
                let zip = workDir.appendingPathComponent("\(appName).zip")
                try FileManager.default.moveItem(at: download, to: zip)

                let bundleID = Bundle.main.bundleIdentifier ?? "com.brentc22.Portside"
                let newApp = try await Task.detached {
                    try UpdateInstaller.prepare(zip: zip, in: workDir, bundleID: bundleID, version: version)
                }.value

                let script = UpdateInstaller.swapScript(pid: ProcessInfo.processInfo.processIdentifier,
                                                        newApp: newApp, destination: destination)
                let swap = Process()
                swap.executableURL = URL(fileURLWithPath: "/bin/sh")
                swap.arguments = ["-c", script]
                try swap.run()  // outlives us: it waits for this process to exit
                NSApp.terminate(nil)
            } catch {
                hideProgress()
                NSLog("Portside: update failed: \(error)")
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = "Couldn't install the update"
                alert.informativeText = "\(error.localizedDescription)\n\nYou can download it from GitHub instead."
                alert.addButton(withTitle: "Open Download Page")
                alert.addButton(withTitle: "Cancel")
                NSApp.activate()
                if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.htmlURL) }
            }
        }
    }

    private func showProgress(_ message: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 76),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Portside Update"
        let label = NSTextField(labelWithString: message)
        let bar = NSProgressIndicator()
        bar.isIndeterminate = true
        bar.startAnimation(nil)
        let stack = NSStackView(views: [label, bar])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        bar.widthAnchor.constraint(equalToConstant: 260).isActive = true
        panel.contentView = stack
        panel.center()
        panel.level = .floating
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        progress = panel
    }

    private func hideProgress() {
        progress?.close()
        progress = nil
    }

    private func inform(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = text
        NSApp.activate()
        alert.runModal()
    }
}
