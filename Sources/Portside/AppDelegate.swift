import AppKit
import PortsideCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var snapshot = Snapshot.empty
    private var timer: Timer?
    private lazy var builder = MenuBuilder(actions: Actions(onChange: { [weak self] in
        self?.refreshSoon()
    }))

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "server.rack", accessibilityDescription: "Portside")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.imagePosition = .imageLeading

        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        refreshInBackground()
        // The count in the menu bar stays current without opening the menu.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshInBackground() }
        }

        // `open Portside.app --args --show-menu` pops the menu on launch — for
        // screenshots, since scripting can't click status items on macOS 27.
        if CommandLine.arguments.contains("--show-menu") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, let screen = NSScreen.main else { return }
                // Pop up below the top-right corner rather than from the button: a menu bar
                // manager (Stash, Bartender) may be hiding the button.
                let origin = NSPoint(x: screen.frame.maxX - 420, y: screen.visibleFrame.maxY - 8)
                self.menu.popUp(positioning: nil, at: origin, in: nil)
            }
        }
    }

    // A scan takes ~40 ms, so the menu scans synchronously when it opens:
    // stale rows (a server you just stopped) are worse than a tiny delay.
    func menuNeedsUpdate(_ menu: NSMenu) {
        apply(Scanner.scan())
        builder.build(into: menu, snapshot: snapshot)
    }

    private func refreshInBackground() {
        Task.detached(priority: .utility) {
            let fresh = Scanner.scan()
            await MainActor.run { self.apply(fresh) }
        }
    }

    /// Processes take a moment to exit after SIGTERM.
    private func refreshSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.refreshInBackground()
        }
    }

    /// `--only-under <path>` limits the menu to repos below that path (demo screenshots).
    private let onlyUnder: String? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--only-under"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }()

    private func apply(_ fresh: Snapshot) {
        snapshot = onlyUnder.map { fresh.onlyRepos(under: $0) } ?? fresh
        let count = snapshot.devServerCount
        statusItem.button?.title = count > 0 ? " \(count)" : ""
        statusItem.button?.toolTip = count == 1 ? "1 dev server running" : "\(count) dev servers running"
    }
}
