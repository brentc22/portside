import Foundation
import PortsideCore

// Line-buffer stdout so CI logs show which test was running if one hangs.
setvbuf(stdout, nil, _IOLBF, 0)

print("LsofParser")
T.test("parses processes, dedupes IPv4/IPv6 and sorts ports") {
    let output = """
    p647
    crapportd
    f11
    n*:49152
    f12
    n*:49152
    p25159
    cnode
    f14
    n[::1]:8080
    f15
    n127.0.0.1:3000
    f16
    n127.0.0.1:8080
    """
    let result = LsofParser.parse(output)
    T.equal(result, [
        Listener(pid: 647, command: "rapportd", ports: [49152]),
        Listener(pid: 25159, command: "node", ports: [3000, 8080]),
    ])
}
T.test("empty output gives no listeners") {
    T.equal(LsofParser.parse(""), [])
}
T.test("process without a port is dropped") {
    T.equal(LsofParser.parse("p1\ncfoo\nf3\nnsomething-without-port\n"), [])
}

print("ProcArgs")
T.test("skips exec path and padding, stops at argc") {
    var buffer: [UInt8] = []
    withUnsafeBytes(of: Int32(3)) { buffer.append(contentsOf: $0) }
    for s in ["/usr/local/bin/node", "\0\0\0", "node\0", "node_modules/.bin/vite\0", "--port\0", "ENV=1\0"] {
        buffer.append(contentsOf: Array(s.utf8))
    }
    // exec path needs its own terminator before the padding
    T.equal(ProcArgs.parse(buffer), ["node", "node_modules/.bin/vite", "--port"])
}
T.test("garbage buffer gives no args") {
    T.equal(ProcArgs.parse([1, 0]), [])
}

print("ToolDetector")
T.test("finds the tool behind node") {
    T.equal(ToolDetector.label(command: "node", arguments: ["node", "/r/node_modules/.bin/vite"]), "vite")
    T.equal(ToolDetector.label(command: "node", arguments: ["node", "/r/node_modules/next/dist/bin/next", "dev"]), "next")
    T.equal(ToolDetector.label(command: "node", arguments: ["node", "/r/node_modules/wrangler/bin/wrangler.js", "dev"]), "wrangler")
}
T.test("scoped packages use the package name") {
    T.equal(ToolDetector.label(command: "node", arguments: ["node", "/r/node_modules/@sveltejs/kit/svelte-kit.js"]), "svelte-kit")
}
T.test("python -m shows the module") {
    T.equal(ToolDetector.label(command: "Python", arguments: ["python3", "-m", "http.server", "8000"]), "http.server")
}
T.test("unknown process falls back to its command") {
    T.equal(ToolDetector.label(command: "node", arguments: ["node", "server.js"]), "node")
    T.equal(ToolDetector.label(command: "com.docker.backend", arguments: []), "docker")
}

print("GitContext")
let fm = FileManager.default
let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("portside-tests-\(UUID().uuidString)").resolvingSymlinksInPath()
@MainActor func write(_ path: String, _ contents: String) throws {
    let url = tmp.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try contents.write(to: url, atomically: true, encoding: .utf8)
}

T.test("main checkout, from a subdirectory") {
    try write("app/.git/HEAD", "ref: refs/heads/main\n")
    try fm.createDirectory(at: tmp.appendingPathComponent("app/src/lib"), withIntermediateDirectories: true)
    let ctx = GitContext.resolve(from: tmp.appendingPathComponent("app/src/lib").path)
    T.equal(ctx?.repoRoot, tmp.appendingPathComponent("app").path)
    T.equal(ctx?.checkoutRoot, tmp.appendingPathComponent("app").path)
    T.equal(ctx?.branch, "main")
    T.equal(ctx?.isLinkedWorktree, false)
    T.equal(ctx?.repoName, "app")
}
T.test("linked worktree points back at the main repo") {
    try write("app/.git/worktrees/wt-feat/HEAD", "ref: refs/heads/feat/planning\n")
    try write("app/.git/worktrees/wt-feat/commondir", "../..\n")
    try write("wt-feat/.git", "gitdir: \(tmp.path)/app/.git/worktrees/wt-feat\n")
    let ctx = GitContext.resolve(from: tmp.appendingPathComponent("wt-feat").path)
    T.equal(ctx?.repoRoot, tmp.appendingPathComponent("app").path)
    T.equal(ctx?.checkoutRoot, tmp.appendingPathComponent("wt-feat").path)
    T.equal(ctx?.branch, "feat/planning")
    T.equal(ctx?.isLinkedWorktree, true)
}
T.test("relative gitdir is resolved against the worktree") {
    try write("rel/.git", "gitdir: ../app/.git/worktrees/wt-feat\n")
    let ctx = GitContext.resolve(from: tmp.appendingPathComponent("rel").path)
    T.equal(ctx?.repoRoot, tmp.appendingPathComponent("app").path)
}
T.test("walking up from / terminates") {
    T.expect(GitContext.resolve(from: "/") == nil, "expected nil for /")
    T.expect(GitContext.resolve(from: "relative/path") == nil, "expected nil for a relative path")
}
T.test("detached HEAD shows a short sha") {
    try write("det/.git/HEAD", "3f2a9c1d8e7b6a5f4e3d2c1b0a9f8e7d6c5b4a39\n")
    T.equal(GitContext.resolve(from: tmp.appendingPathComponent("det").path)?.branch, "3f2a9c1")
}
T.test("directory outside git gives nil") {
    try fm.createDirectory(at: tmp.appendingPathComponent("plain"), withIntermediateDirectories: true)
    // /tmp itself is not in a repo, so walking up must end at / with nil.
    T.expect(GitContext.resolve(from: tmp.appendingPathComponent("plain").path) == nil, "expected nil")
}

print("Snapshot")
@MainActor func server(_ pid: Int32, _ port: Int, repo: String?, checkout: String? = nil,
            branch: String? = nil, worktree: Bool = false) -> Server {
    let git = repo.map { GitContext(repoRoot: $0, checkoutRoot: checkout ?? $0, branch: branch, isLinkedWorktree: worktree) }
    return Server(pid: pid, command: "node", tool: "vite", ports: [port], cwd: nil, git: git, startedAt: nil)
}
T.test("groups by repo, then checkout; main checkout first; other separate") {
    let snap = Snapshot(servers: [
        server(1, 8091, repo: "/r/vernast", checkout: "/r/wt-b", branch: "feat/b", worktree: true),
        server(2, 8080, repo: "/r/vernast", branch: "main"),
        server(3, 7337, repo: "/r/testmail", branch: "main"),
        server(4, 5000, repo: nil),
        server(5, 8092, repo: "/r/vernast", checkout: "/r/wt-a", branch: "feat/a", worktree: true),
        server(6, 3000, repo: "/r/vernast", branch: "main"),
    ])
    T.equal(snap.repos.map(\.name), ["testmail", "vernast"])
    let vernast = snap.repos[1]
    T.equal(vernast.checkouts.map(\.branch), ["main", "feat/a", "feat/b"])
    T.equal(vernast.checkouts[0].servers.map(\.pid), [6, 2], "sorted by port")
    T.equal(snap.other.map(\.pid), [4])
    T.equal(snap.devServerCount, 5)
}

print("Formatting")
T.test("uptime") {
    let now = Date(timeIntervalSince1970: 1_000_000)
    T.equal(Formatting.uptime(since: now.addingTimeInterval(-42), now: now), "42s")
    T.equal(Formatting.uptime(since: now.addingTimeInterval(-3 * 60), now: now), "3m")
    T.equal(Formatting.uptime(since: now.addingTimeInterval(-(2 * 3600 + 5 * 60)), now: now), "2h 5m")
    T.equal(Formatting.uptime(since: now.addingTimeInterval(-(4 * 86400 + 3600)), now: now), "4d 1h")
}
T.test("abbreviate home") {
    T.equal(Formatting.abbreviate("/Users/x/github/a", home: "/Users/x"), "~/github/a")
    T.equal(Formatting.abbreviate("/Users/xy/a", home: "/Users/x"), "/Users/xy/a")
    T.equal(Formatting.abbreviate("/Users/x", home: "/Users/x"), "~")
}

print("Scanner (live)")
T.test("scan runs and sees this machine's listeners without crashing") {
    let start = Date()
    let snap = Scanner.scan()
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    print("       \(snap.devServerCount) dev, \(snap.other.count) other, \(ms) ms")
    for repo in snap.repos {
        for c in repo.checkouts {
            for s in c.servers {
                print("       \(repo.name) [\(c.branch ?? "-")\(c.isLinkedWorktree ? " wt" : "")] :\(s.ports) \(s.tool)")
            }
        }
    }
    T.expect(ms < 2000, "scan took \(ms) ms")
}

try? fm.removeItem(at: tmp)
T.finish()
