import AppKit
import PortsideCore

/// Turns a snapshot into menu items:
///
///     Vernast-v2.0                      ← repo
///       main                            ← checkout (submenu: Finder, Terminal, Editor, Stop all)
///         :8080  vite · 2h 5m           ← server (submenu: open, copy, stop)
///       feat/planning  (worktree)
///         :8091  vite · 12m
///     Other listeners (7)            ▸
@MainActor
struct MenuBuilder {
    let actions: Actions

    func build(into menu: NSMenu, snapshot: Snapshot) {
        menu.removeAllItems()
        if snapshot.repos.isEmpty {
            let empty = NSMenuItem(title: "No dev servers running", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for repo in snapshot.repos {
            menu.addItem(NSMenuItem.sectionHeader(title: repo.name))
            for checkout in repo.checkouts {
                menu.addItem(checkoutItem(checkout))
                for server in checkout.servers {
                    menu.addItem(serverItem(server, indent: 1))
                }
            }
        }

        if !snapshot.other.isEmpty {
            menu.addItem(.separator())
            let other = NSMenuItem(title: "Other listeners (\(snapshot.other.count))", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for server in snapshot.other { submenu.addItem(serverItem(server, indent: 0)) }
            other.submenu = submenu
            menu.addItem(other)
        }

        menu.addItem(.separator())
        if LaunchAtLogin.isAvailable {
            let login = item("Launch at Login", #selector(Actions.toggleLaunchAtLogin(_:)))
            login.state = LaunchAtLogin.isEnabled ? .on : .off
            menu.addItem(login)
        }
        menu.addItem(NSMenuItem(title: "Quit Portside", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: - Rows

    private func checkoutItem(_ checkout: CheckoutGroup) -> NSMenuItem {
        let title = NSMutableAttributedString(string: checkout.branch ?? "(no branch)",
                                              attributes: [.font: NSFont.menuFont(ofSize: 0)])
        if checkout.isLinkedWorktree {
            title.append(secondary("  worktree · \((checkout.path as NSString).lastPathComponent)"))
        }
        let row = NSMenuItem(title: checkout.branch ?? "", action: nil, keyEquivalent: "")
        row.attributedTitle = title
        row.image = symbol("arrow.triangle.branch")

        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(disabled(Formatting.abbreviate(checkout.path)))
        sub.addItem(.separator())
        if let editor = InstalledApps.editor {
            sub.addItem(item("Open in \(editor.name)", #selector(Actions.openWithApp(_:)),
                             object: AppTarget(path: checkout.path, app: editor.url), symbol: "chevron.left.forwardslash.chevron.right"))
        }
        if let terminal = InstalledApps.terminal {
            sub.addItem(item("Open in \(terminal.name)", #selector(Actions.openWithApp(_:)),
                             object: AppTarget(path: checkout.path, app: terminal.url), symbol: "terminal"))
        }
        sub.addItem(item("Reveal in Finder", #selector(Actions.revealInFinder(_:)),
                         object: checkout.path, symbol: "folder"))
        sub.addItem(item("Copy Path", #selector(Actions.copyString(_:)),
                         object: checkout.path, symbol: "doc.on.doc"))
        sub.addItem(.separator())
        let pids = checkout.servers.map(\.pid)
        let noun = pids.count == 1 ? "Server" : "\(pids.count) Servers"
        sub.addItem(item("Stop \(noun)", #selector(Actions.stop(_:)), object: pids, symbol: "stop.circle"))
        row.submenu = sub
        return row
    }

    private func serverItem(_ server: Server, indent: Int) -> NSMenuItem {
        let ports = server.ports.map { ":\($0)" }.joined(separator: " ")
        let title = NSMutableAttributedString(
            string: ports,
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)])
        title.append(NSAttributedString(string: "  \(server.tool)", attributes: [.font: NSFont.menuFont(ofSize: 0)]))
        if let start = server.startedAt {
            title.append(secondary("  · \(Formatting.uptime(since: start))"))
        }

        let row = NSMenuItem(title: ports, action: nil, keyEquivalent: "")
        row.attributedTitle = title
        row.indentationLevel = indent
        row.image = statusDot(isDev: server.git != nil)

        let sub = NSMenu()
        sub.autoenablesItems = false
        for port in server.ports {
            let url = URL(string: "http://localhost:\(port)")!
            sub.addItem(item("Open localhost:\(port)", #selector(Actions.openURL(_:)), object: url, symbol: "safari"))
        }
        if let port = server.ports.first {
            sub.addItem(item("Copy URL", #selector(Actions.copyString(_:)),
                             object: "http://localhost:\(port)", symbol: "link"))
        }
        sub.addItem(.separator())
        sub.addItem(item("Stop", #selector(Actions.stop(_:)), object: [server.pid], symbol: "stop.circle"))
        sub.addItem(item("Force Quit", #selector(Actions.forceQuit(_:)), object: [server.pid], symbol: "xmark.octagon"))
        sub.addItem(.separator())
        sub.addItem(disabled("PID \(server.pid) · \(server.command)"))
        if let cwd = server.cwd { sub.addItem(disabled(Formatting.abbreviate(cwd))) }
        row.submenu = sub
        return row
    }

    // MARK: - Helpers

    private func item(_ title: String, _ action: Selector,
                      object: Any? = nil, symbol name: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = actions
        item.representedObject = object
        if let name { item.image = symbol(name) }
        return item
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func secondary(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
        ])
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func statusDot(isDev: Bool) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular)
            .applying(.init(paletteColors: [isDev ? .systemGreen : .tertiaryLabelColor]))
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }
}
