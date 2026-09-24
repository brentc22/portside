import Foundation

/// Takes a snapshot of every listening TCP socket owned by the current user.
public enum Scanner {
    public static func scan() -> Snapshot {
        let servers = LsofParser.parse(runLsof()).map { listener in
            let cwd = ProcessInspector.cwd(of: listener.pid)
            let args = ProcessInspector.arguments(of: listener.pid)
            // A process started from `/` or `~` isn't a project, even if `~` is a git repo
            // (dotfiles). Only directories below home count.
            let git = cwd.flatMap { isProjectDirectory($0) ? GitContext.resolve(from: $0) : nil }
            return Server(pid: listener.pid, command: listener.command,
                          tool: ToolDetector.label(command: listener.command, arguments: args),
                          ports: listener.ports, cwd: cwd, git: git,
                          startedAt: ProcessInspector.startDate(of: listener.pid))
        }
        return Snapshot(servers: servers)
    }

    static func isProjectDirectory(_ path: String) -> Bool {
        let home = NSHomeDirectory()
        return path.hasPrefix(home + "/") || path.hasPrefix("/Volumes/")
    }

    /// `-n -P`: no DNS or port-name lookups (those make lsof take seconds).
    /// `+c 0`: full command names instead of the first 9 characters.
    private static func runLsof() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-nP", "+c", "0", "-iTCP", "-sTCP:LISTEN", "-F", "pcn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // lsof exits 1 when nothing matches; the output is still valid (empty).
        return String(decoding: data, as: UTF8.self)
    }
}
