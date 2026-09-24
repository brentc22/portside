import AppKit

/// Picks the first installed editor and terminal from a preference list,
/// so "Open in Editor" opens what you actually use.
enum InstalledApps {
    struct App: Sendable { let name: String; let url: URL }

    static let editors = [
        "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.microsoft.VSCode",
        "dev.zed.Zed",
        "com.exafunction.windsurf",
        "com.sublimetext.4",
        "com.apple.dt.Xcode",
    ]

    static let terminals = [
        "com.mitchellh.ghostty",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "com.github.wez.wezterm",
        "com.apple.Terminal",
    ]

    // Looked up once per launch: Launch Services queries aren't free, and the
    // installed editor doesn't change between two menu opens.
    static let editor = first(of: editors)
    static let terminal = first(of: terminals)

    private static func first(of bundleIDs: [String]) -> App? {
        for id in bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let name = FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                return App(name: name, url: url)
            }
        }
        return nil
    }
}
