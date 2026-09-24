import Foundation

/// Where a directory sits in git: which repository, which checkout, which branch.
///
/// Resolved by reading `.git` files directly instead of shelling out to `git`,
/// which matters when this runs for every listener on every refresh. All path math
/// is lexical on plain strings: `URL`'s handling of `/` and `..` differs between
/// macOS versions, and `NSString.standardizingPath` resolves symlinks only when the
/// path contains `..` — either one splits a repo into two groups.
public struct GitContext: Equatable, Sendable {
    /// The main checkout — shared by all worktrees of the same repository.
    public let repoRoot: String
    /// The checkout the directory is in; equals `repoRoot` unless it's a linked worktree.
    public let checkoutRoot: String
    /// Branch name, or a short SHA when HEAD is detached.
    public let branch: String?

    public var isLinkedWorktree: Bool { repoRoot != checkoutRoot }
    public var repoName: String { (repoRoot as NSString).lastPathComponent }

    public init(repoRoot: String, checkoutRoot: String, branch: String?) {
        self.repoRoot = repoRoot
        self.checkoutRoot = checkoutRoot
        self.branch = branch
    }

    public static func resolve(from path: String) -> GitContext? {
        guard path.hasPrefix("/") else { return nil }
        var dir = normalize(path, relativeTo: "/")
        while true {
            let dotGit = normalize(".git", relativeTo: dir)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) {
                return isDirectory.boolValue
                    ? GitContext(repoRoot: dir, checkoutRoot: dir, branch: branch(gitDir: dotGit))
                    : pointer(checkout: dir, file: dotGit)
            }
            if dir == "/" { return nil }
            dir = (dir as NSString).deletingLastPathComponent
        }
    }

    /// A `.git` *file* holds `gitdir: <path>`. For a linked worktree that directory has a
    /// `commondir` leading back to the main repo's `.git`. Submodules and
    /// `--separate-git-dir` checkouts have none: they are their own repository.
    private static func pointer(checkout: String, file: String) -> GitContext? {
        guard let line = firstLine(of: file), line.hasPrefix("gitdir:") else { return nil }
        let gitDir = normalize(line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces),
                               relativeTo: checkout)
        // Stale pointer (main repo moved or worktree pruned): not a usable checkout.
        guard FileManager.default.fileExists(atPath: gitDir) else { return nil }
        let branch = branch(gitDir: gitDir)

        guard let common = firstLine(of: gitDir + "/commondir") else {
            return GitContext(repoRoot: checkout, checkoutRoot: checkout, branch: branch)
        }
        let commonDir = normalize(common, relativeTo: gitDir)
        // `<main>/.git` → `<main>`; a bare repository has no checkout, so keep the dir itself.
        let repoRoot = (commonDir as NSString).lastPathComponent == ".git"
            ? (commonDir as NSString).deletingLastPathComponent
            : commonDir
        return GitContext(repoRoot: repoRoot, checkoutRoot: checkout, branch: branch)
    }

    private static func branch(gitDir: String) -> String? {
        guard let head = firstLine(of: gitDir + "/HEAD"), !head.isEmpty else { return nil }
        guard head.hasPrefix("ref: ") else { return String(head.prefix(7)) }
        let ref = head.dropFirst("ref: ".count)
        return String(ref.hasPrefix("refs/heads/") ? ref.dropFirst("refs/heads/".count) : ref)
    }

    /// First line, trimmed — also strips the `\r` of a CRLF file.
    private static func firstLine(of path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return text.split(whereSeparator: \.isNewline).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    }

    /// Joins `path` onto `base` (unless absolute) and folds `.` and `..` without touching
    /// the filesystem.
    static func normalize(_ path: String, relativeTo base: String) -> String {
        let full = path.hasPrefix("/") ? path : base + "/" + path
        var parts: [Substring] = []
        for part in full.split(separator: "/") where part != "." {
            if part == ".." { _ = parts.popLast() } else { parts.append(part) }
        }
        return "/" + parts.joined(separator: "/")
    }
}
