import Foundation

/// Where a directory sits in git: which repository, which checkout, which branch.
///
/// Resolved by reading `.git` files directly instead of shelling out to `git`,
/// which matters when this runs for every listener on every refresh.
public struct GitContext: Equatable, Sendable {
    /// The main checkout — shared by all worktrees of the same repository.
    public let repoRoot: String
    /// The checkout the directory is in; equals `repoRoot` unless it's a linked worktree.
    public let checkoutRoot: String
    /// Branch name, or a short SHA when HEAD is detached.
    public let branch: String?
    public let isLinkedWorktree: Bool

    public var repoName: String { (repoRoot as NSString).lastPathComponent }

    public init(repoRoot: String, checkoutRoot: String, branch: String?, isLinkedWorktree: Bool) {
        self.repoRoot = repoRoot
        self.checkoutRoot = checkoutRoot
        self.branch = branch
        self.isLinkedWorktree = isLinkedWorktree
    }

    public static func resolve(from path: String, fileManager fm: FileManager = .default) -> GitContext? {
        // Walk with NSString paths: on macOS 14/15, URL("/").deletingLastPathComponent()
        // returns "/..", so a URL-based "until parent == self" loop never ends.
        var current = (path as NSString).standardizingPath
        while current.hasPrefix("/") {
            let dir = URL(fileURLWithPath: current)
            let dotGit = dir.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: dotGit.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue
                    ? mainCheckout(at: dir, gitDir: dotGit)
                    : linkedWorktree(at: dir, pointer: dotGit)
            }
            if current == "/" { return nil }
            current = (current as NSString).deletingLastPathComponent
        }
        return nil
    }

    private static func mainCheckout(at root: URL, gitDir: URL) -> GitContext {
        GitContext(repoRoot: root.path, checkoutRoot: root.path,
                   branch: readBranch(gitDir: gitDir), isLinkedWorktree: false)
    }

    /// A linked worktree's `.git` is a file: `gitdir: <main>/.git/worktrees/<name>`.
    /// That directory holds its own HEAD and a `commondir` pointing back at `<main>/.git`.
    private static func linkedWorktree(at root: URL, pointer: URL) -> GitContext? {
        guard let contents = try? String(contentsOf: pointer, encoding: .utf8),
              let line = contents.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") })
        else { return nil }
        let raw = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        let gitDir = URL(fileURLWithPath: resolve(raw, against: root.path))

        var commonDir = gitDir
        if let common = try? String(contentsOf: gitDir.appendingPathComponent("commondir"), encoding: .utf8) {
            let trimmed = common.trimmingCharacters(in: .whitespacesAndNewlines)
            commonDir = URL(fileURLWithPath: resolve(trimmed, against: gitDir.path))
        }
        // `<main>/.git` → `<main>`; a bare repository has no checkout, so keep the dir itself.
        let repoRoot = commonDir.lastPathComponent == ".git"
            ? commonDir.deletingLastPathComponent().path
            : commonDir.path
        return GitContext(repoRoot: repoRoot, checkoutRoot: root.path,
                          branch: readBranch(gitDir: gitDir),
                          isLinkedWorktree: repoRoot != root.path)
    }

    /// Resolves a path from a git pointer file against the directory holding it.
    /// NSString path math instead of `URL(relativeTo:)`, whose handling of `..`
    /// differs between macOS versions.
    public static func resolve(_ path: String, against base: String) -> String {
        let joined = path.hasPrefix("/") ? path : (base as NSString).appendingPathComponent(path)
        return (joined as NSString).standardizingPath
    }

    private static func readBranch(gitDir: URL) -> String? {
        guard let head = try? String(contentsOf: gitDir.appendingPathComponent("HEAD"), encoding: .utf8)
        else { return nil }
        let value = head.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("ref: refs/heads/") { return String(value.dropFirst("ref: refs/heads/".count)) }
        if value.hasPrefix("ref: ") { return String(value.dropFirst("ref: ".count)) }
        return value.isEmpty ? nil : String(value.prefix(7))
    }
}
