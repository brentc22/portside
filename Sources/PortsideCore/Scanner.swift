import Foundation

/// Takes a snapshot of every listening TCP socket owned by the current user.
public enum Scanner {
    public static func scan() -> Snapshot {
        let listeners = LsofParser.parse(runLsof())
        // `docker ps` costs ~90 ms, so only ask when a container proxy is listening.
        let containers = listeners.contains { isContainerProxy($0.command) }
            ? DockerPS.parse(DockerCLI.run(["ps", "--format", "{{json .}}"]) ?? "")
            : []

        let servers = listeners.flatMap { listener -> [Server] in
            let cwd = ProcessInspector.cwd(of: listener.pid)
            let args = ProcessInspector.arguments(of: listener.pid)
            let tool = ToolDetector.label(command: listener.command, arguments: args)
            let startedAt = ProcessInspector.startDate(of: listener.pid)
            guard isContainerProxy(listener.command), !containers.isEmpty else {
                return [server(listener, ports: listener.ports, tool: tool, cwd: cwd, startedAt: startedAt)]
            }
            let split = assign(ports: listener.ports, to: containers)
            var result = split.claimed.map { container, ports in
                // The proxy's cwd and start time say nothing about the container.
                server(listener, ports: ports, tool: container.name, cwd: container.workdir,
                       startedAt: nil, container: container)
            }
            if !split.rest.isEmpty {
                result.append(server(listener, ports: split.rest, tool: tool, cwd: cwd, startedAt: startedAt))
            }
            return result
        }
        return Snapshot(servers: servers)
    }

    private static func server(_ listener: Listener, ports: [Int], tool: String, cwd: String?,
                               startedAt: Date?, container: Container? = nil) -> Server {
        // A process started from `/` or `~` isn't a project, even if `~` is a git repo
        // (dotfiles). Only directories below home count.
        let git = cwd.flatMap { isProjectDirectory($0) ? GitContext.resolve(from: $0) : nil }
        return Server(pid: listener.pid, command: listener.command, tool: tool, ports: ports,
                      cwd: cwd, git: git, startedAt: startedAt, container: container)
    }

    /// The process that holds published container ports on the Mac side.
    static func isContainerProxy(_ command: String) -> Bool {
        let lower = command.lowercased()
        return lower.contains("docker") || lower.contains("orbstack")
    }

    /// Splits a proxy's ports over the containers that publish them; ports no
    /// container claims (the VM's own services) stay with the proxy.
    static func assign(ports: [Int], to containers: [Container]) -> (claimed: [(Container, [Int])], rest: [Int]) {
        var rest = ports
        var claimed: [(Container, [Int])] = []
        for container in containers {
            let mine = rest.filter(container.ports.contains)
            guard !mine.isEmpty else { continue }
            claimed.append((container, mine))
            rest.removeAll(where: mine.contains)
        }
        return (claimed, rest)
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
