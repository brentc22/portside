import Foundation

/// One listening process with everything the menu needs to show it.
public struct Server: Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let tool: String
    public let ports: [Int]
    public let cwd: String?
    public let git: GitContext?
    public let startedAt: Date?

    public init(pid: Int32, command: String, tool: String, ports: [Int],
                cwd: String?, git: GitContext?, startedAt: Date?) {
        self.pid = pid
        self.command = command
        self.tool = tool
        self.ports = ports
        self.cwd = cwd
        self.git = git
        self.startedAt = startedAt
    }
}

public struct CheckoutGroup: Equatable, Sendable {
    public let path: String
    public let branch: String?
    public let isLinkedWorktree: Bool
    public let servers: [Server]
}

public struct RepoGroup: Equatable, Sendable {
    public let name: String
    public let root: String
    public let checkouts: [CheckoutGroup]

    public var serverCount: Int { checkouts.reduce(0) { $0 + $1.servers.count } }
}

/// Servers split into the ones started from a git checkout (your dev servers)
/// and everything else that happens to listen (AirPlay, Spotify, Docker, …).
public struct Snapshot: Equatable, Sendable {
    public let repos: [RepoGroup]
    public let other: [Server]

    public static let empty = Snapshot(repos: [], other: [])

    public var devServerCount: Int { repos.reduce(0) { $0 + $1.serverCount } }

    public init(repos: [RepoGroup], other: [Server]) {
        self.repos = repos
        self.other = other
    }

    public init(servers: [Server]) {
        let byPort: (Server, Server) -> Bool = { ($0.ports.first ?? 0) < ($1.ports.first ?? 0) }

        let inRepo = servers.compactMap { server in server.git.map { (server, $0) } }

        repos = Dictionary(grouping: inRepo) { $0.1.repoRoot }.map { root, pairs in
            let checkouts = Dictionary(grouping: pairs) { $0.1.checkoutRoot }
                .map { path, pairs in
                    CheckoutGroup(path: path, branch: pairs[0].1.branch,
                                  isLinkedWorktree: pairs[0].1.isLinkedWorktree,
                                  servers: pairs.map(\.0).sorted(by: byPort))
                }
                // Main checkout first, then worktrees by branch name.
                .sorted { a, b in
                    if a.isLinkedWorktree != b.isLinkedWorktree { return !a.isLinkedWorktree }
                    return (a.branch ?? a.path).localizedStandardCompare(b.branch ?? b.path) == .orderedAscending
                }
            return RepoGroup(name: pairs[0].1.repoName, root: root, checkouts: checkouts)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        other = servers.filter { $0.git == nil }.sorted(by: byPort)
    }
}

extension Snapshot {
    /// Keeps only repos below `prefix` — used for screenshots of the demo repos.
    public func onlyRepos(under prefix: String) -> Snapshot {
        Snapshot(repos: repos.filter { $0.root.hasPrefix(prefix) }, other: other)
    }
}
