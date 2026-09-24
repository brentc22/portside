import Foundation
@testable import PortsideCore

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
T.test("normalize folds . and .. lexically") {
    T.equal(GitContext.normalize("../..", relativeTo: "/r/app/.git/worktrees/wt"), "/r/app/.git")
    T.equal(GitContext.normalize("../app/./.git", relativeTo: "/r/rel"), "/r/app/.git")
    T.equal(GitContext.normalize("/abs/.git", relativeTo: "/r"), "/abs/.git")
    T.equal(GitContext.normalize("../../..", relativeTo: "/r"), "/")
}
T.test("CRLF pointer files still resolve") {
    try write("crlf/.git", "gitdir: ../app/.git/worktrees/wt-feat\r\n")
    T.equal(GitContext.resolve(from: tmp.appendingPathComponent("crlf").path)?.repoRoot,
            tmp.appendingPathComponent("app").path)
}
T.test("submodule (gitdir without commondir) is its own repo") {
    try write("app/.git/modules/web/HEAD", "ref: refs/heads/main\n")
    try write("app/web/.git", "gitdir: ../.git/modules/web\n")
    let ctx = GitContext.resolve(from: tmp.appendingPathComponent("app/web").path)
    T.equal(ctx?.repoRoot, tmp.appendingPathComponent("app/web").path)
    T.equal(ctx?.isLinkedWorktree, false)
}
T.test("stale pointer to a missing gitdir gives nil") {
    try write("stale/.git", "gitdir: /nonexistent/.git/worktrees/gone\n")
    T.expect(GitContext.resolve(from: tmp.appendingPathComponent("stale").path) == nil, "expected nil")
}
T.test("repo reached through a symlink stays one repo") {
    try fm.createSymbolicLink(at: tmp.appendingPathComponent("link"), withDestinationURL: tmp.appendingPathComponent("app"))
    try write("wt-link/.git", "gitdir: \(tmp.path)/link/.git/worktrees/wt-feat\n")
    let main = GitContext.resolve(from: tmp.appendingPathComponent("link").path)
    let worktree = GitContext.resolve(from: tmp.appendingPathComponent("wt-link").path)
    T.equal(main?.repoRoot, tmp.appendingPathComponent("link").path)
    T.equal(worktree?.repoRoot, main?.repoRoot, "worktree and main checkout:")
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
            branch: String? = nil) -> Server {
    let git = repo.map { GitContext(repoRoot: $0, checkoutRoot: checkout ?? $0, branch: branch) }
    return Server(pid: pid, command: "node", tool: "vite", ports: [port], cwd: nil, git: git, startedAt: nil)
}
T.test("groups by repo, then checkout; main checkout first; other separate") {
    let snap = Snapshot(servers: [
        server(1, 8091, repo: "/r/vernast", checkout: "/r/wt-b", branch: "feat/b"),
        server(2, 8080, repo: "/r/vernast", branch: "main"),
        server(3, 7337, repo: "/r/testmail", branch: "main"),
        server(4, 5000, repo: nil),
        server(5, 8092, repo: "/r/vernast", checkout: "/r/wt-a", branch: "feat/a"),
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

print("AppVersion")
T.test("parses tags and compares numerically") {
    T.equal(AppVersion("v0.2.0")?.description, "0.2.0")
    T.equal(AppVersion("0.2")?.description, "0.2.0", "missing parts count as 0:")
    T.expect(AppVersion("1.10.0")! > AppVersion("1.9.9")!, "1.10.0 > 1.9.9")
    T.expect(AppVersion("0.2.0")! > AppVersion("0.1.9")!, "0.2.0 > 0.1.9")
    T.expect(AppVersion("0.1.0") == AppVersion("v0.1"), "0.1.0 == v0.1")
    T.equal(AppVersion("2.0.0-beta.1")?.description, "2.0.0", "pre-release suffix dropped:")
}
T.test("rejects what isn't a version") {
    T.expect(AppVersion("latest") == nil, "latest")
    T.expect(AppVersion("1.2.3.4") == nil, "four parts")
    T.expect(AppVersion("1..2") == nil, "empty part")
    T.expect(AppVersion("") == nil, "empty")
}

print("Release")
@MainActor func releaseJSON(tag: String, prerelease: Bool = false, assets: [String] = ["Portside.zip"]) -> Data {
    let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"# }
    return Data(#"""
    {"tag_name":"\#(tag)","html_url":"https://github.com/brentc22/portside/releases/tag/\#(tag)",
     "body":"- New icon","draft":false,"prerelease":\#(prerelease),"assets":[\#(list.joined(separator: ","))],
     "author":{"login":"brentc22"}}
    """#.utf8)
}
T.test("decodes GitHub's releases/latest and finds the zip") {
    let release = try Release.decode(releaseJSON(tag: "v0.2.0", assets: ["checksums.txt", "Portside-0.2.0.zip"]))
    T.equal(release.version, AppVersion("0.2.0"))
    T.equal(release.body, "- New icon")
    T.equal(release.zipURL(appName: "Portside")?.lastPathComponent, "Portside-0.2.0.zip")
    T.expect(release.zipURL(appName: "Stash") == nil, "other app's zip is not ours")
}
T.test("offers only newer, non-skipped, final releases") {
    let current = AppVersion("0.1.0")!
    let newer = try Release.decode(releaseJSON(tag: "v0.2.0"))
    let same = try Release.decode(releaseJSON(tag: "v0.1.0"))
    let beta = try Release.decode(releaseJSON(tag: "v0.3.0", prerelease: true))
    T.expect(UpdatePolicy.shouldOffer(newer, current: current, skipped: nil, userInitiated: false), "newer")
    T.expect(!UpdatePolicy.shouldOffer(same, current: current, skipped: nil, userInitiated: true), "same version")
    T.expect(!UpdatePolicy.shouldOffer(beta, current: current, skipped: nil, userInitiated: true), "prerelease")
    T.expect(!UpdatePolicy.shouldOffer(newer, current: current, skipped: "0.2.0", userInitiated: false),
             "skipped version stays quiet on automatic checks")
    T.expect(UpdatePolicy.shouldOffer(newer, current: current, skipped: "0.2.0", userInitiated: true),
             "but shows when the user asks")
    T.expect(UpdatePolicy.shouldOffer(newer, current: current, skipped: "0.1.5", userInitiated: false),
             "an older skip doesn't hide a newer release")
}
T.test("checks at most once a day") {
    let now = Date()
    T.expect(UpdatePolicy.isCheckDue(lastCheck: nil, now: now), "never checked")
    T.expect(!UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-3600), now: now), "an hour ago")
    T.expect(UpdatePolicy.isCheckDue(lastCheck: now.addingTimeInterval(-25 * 3600), now: now), "25 hours ago")
}

print("UpdateInstaller")
/// Builds a signed fake app and zips it the way `make zip` does.
@MainActor func fakeRelease(in dir: URL, bundleID: String = "com.brentc22.Portside", version: String = "0.2.0",
                 tamper: Bool = false) throws -> URL {
    try? fm.removeItem(at: dir)
    let app = dir.appendingPathComponent("build/Portside.app")
    try fm.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
    try fm.copyItem(atPath: "/usr/bin/true", toPath: app.appendingPathComponent("Contents/MacOS/Portside").path)
    let info: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version,
                              "CFBundleExecutable": "Portside", "CFBundlePackageType": "APPL"]
    info.write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true)
    try UpdateInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", app.path])
    if tamper {
        try Data("tampered".utf8).write(to: app.appendingPathComponent("Contents/MacOS/Portside"))
    }
    let zip = dir.appendingPathComponent("Portside.zip")
    try UpdateInstaller.run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
    return zip
}
let updateDir = tmp.appendingPathComponent("update")
T.test("accepts a signed app with the right id and version") {
    let zip = try fakeRelease(in: updateDir)
    let app = try UpdateInstaller.prepare(zip: zip, in: updateDir, bundleID: "com.brentc22.Portside",
                                          version: AppVersion("0.2.0")!)
    T.equal(app.lastPathComponent, "Portside.app")
}
@MainActor func prepareError(_ zip: URL) -> UpdateError? {
    do {
        _ = try UpdateInstaller.prepare(zip: zip, in: updateDir, bundleID: "com.brentc22.Portside",
                                        version: AppVersion("0.2.0")!)
        return nil
    } catch { return error as? UpdateError }
}
T.test("rejects another app, another version, or a broken signature") {
    T.equal(prepareError(try fakeRelease(in: updateDir, bundleID: "com.example.Evil")),
            .wrongApp(bundleID: "com.example.Evil"))
    T.equal(prepareError(try fakeRelease(in: updateDir, version: "0.1.9")),
            .wrongVersion(found: "0.1.9", expected: "0.2.0"))
    let tampered = prepareError(try fakeRelease(in: updateDir, tamper: true))
    if case .invalidSignature = tampered { T.expect(true, "") } else { T.expect(false, "got \(String(describing: tampered))") }
}
T.test("swap script replaces the app once the old process is gone") {
    let dir = tmp.appendingPathComponent("swap it's here")  // a quote in the path, on purpose
    try? fm.removeItem(at: dir)
    let installed = dir.appendingPathComponent("Applications/Portside.app")
    let fresh = dir.appendingPathComponent("work/Portside.app")
    try fm.createDirectory(at: installed, withIntermediateDirectories: true)
    try fm.createDirectory(at: fresh, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: installed.appendingPathComponent("marker"))
    try Data("new".utf8).write(to: fresh.appendingPathComponent("marker"))

    let finished = Process()
    finished.executableURL = URL(fileURLWithPath: "/usr/bin/true")
    try finished.run()
    finished.waitUntilExit()
    let script = UpdateInstaller.swapScript(pid: finished.processIdentifier, newApp: fresh,
                                            destination: installed, relaunch: false)
    try UpdateInstaller.run("/bin/sh", ["-c", script])

    T.equal(try String(contentsOf: installed.appendingPathComponent("marker"), encoding: .utf8), "new")
    T.expect(!fm.fileExists(atPath: fresh.path), "new copy was moved, not copied")
    T.expect(!fm.fileExists(atPath: dir.appendingPathComponent("work/previous.app").path), "backup cleaned up")
}

try? fm.removeItem(at: tmp)
T.finish()
