import Foundation

/// A running Docker container with published TCP ports.
///
/// On macOS every published port is held by the VM's proxy process (`OrbStack Helper`,
/// `com.docker.backend`), so lsof alone sees one process with all ports. `docker ps`
/// says which container each port belongs to.
public struct Container: Equatable, Sendable {
    public let id: String
    public let name: String
    public let image: String
    public let ports: [Int]
    /// The project directory: Compose's working dir, or the Supabase CLI's workdir.
    public let workdir: String?

    public init(id: String, name: String, image: String, ports: [Int], workdir: String?) {
        self.id = id
        self.name = name
        self.image = image
        self.ports = ports
        self.workdir = workdir
    }
}

/// Parses `docker ps --format '{{json .}}'`: one JSON object per line.
public enum DockerPS {
    static let workdirLabels = ["com.docker.compose.project.working_dir", "com.supabase.cli.workdir"]

    public static func parse(_ output: String) -> [Container] {
        output.split(separator: "\n").compactMap { line in
            guard let data = line.data(using: .utf8),
                  let row = try? JSONDecoder().decode(Row.self, from: data) else { return nil }
            let ports = hostPorts(row.Ports ?? "")
            guard !ports.isEmpty else { return nil }
            let labels = parseLabels(row.Labels ?? "")
            return Container(id: row.ID, name: row.Names, image: row.Image ?? "", ports: ports,
                             workdir: workdirLabels.lazy.compactMap { labels[$0] }.first)
        }
    }

    private struct Row: Decodable {
        let ID: String
        let Names: String
        let Image: String?
        let Ports: String?
        let Labels: String?
    }

    /// `0.0.0.0:8088->8080/tcp, [::]:8088->8080/tcp, 5432/tcp, 0.0.0.0:7000-7001->7000-7001/tcp`
    /// → `[7000, 7001, 8088]`. Unpublished ports (no `->`) and UDP are skipped.
    static func hostPorts(_ field: String) -> [Int] {
        var ports: Set<Int> = []
        for entry in field.split(separator: ",") {
            let entry = entry.trimmingCharacters(in: .whitespaces)
            guard entry.hasSuffix("/tcp"), let arrow = entry.range(of: "->") else { continue }
            let host = entry[..<arrow.lowerBound]
            guard let colon = host.lastIndex(of: ":") else { continue }
            let spec = host[host.index(after: colon)...]
            let bounds = spec.split(separator: "-").compactMap { Int($0) }
            if bounds.count == 1 {
                ports.insert(bounds[0])
            } else if bounds.count == 2, bounds[0] <= bounds[1], bounds[1] - bounds[0] < 1000 {
                ports.formUnion(bounds[0]...bounds[1])
            }
        }
        return ports.sorted()
    }

    /// `a=1,b=2` → `["a": "1", "b": "2"]`. A value with a comma in it is cut off there,
    /// which is fine for the path labels we read.
    static func parseLabels(_ field: String) -> [String: String] {
        var labels: [String: String] = [:]
        for pair in field.split(separator: ",") {
            guard let eq = pair.firstIndex(of: "=") else { continue }
            labels[String(pair[..<eq])] = String(pair[pair.index(after: eq)...])
        }
        return labels
    }
}

/// Runs the `docker` CLI. A menu bar app gets a bare PATH, so the binary is looked up
/// in the places Docker Desktop, OrbStack, Colima and Homebrew install it.
public enum DockerCLI {
    static let candidates = [
        NSHomeDirectory() + "/.orbstack/bin/docker",
        "/usr/local/bin/docker",
        "/opt/homebrew/bin/docker",
        "/Applications/Docker.app/Contents/Resources/bin/docker",
        "/Applications/OrbStack.app/Contents/MacOS/xbin/docker",
    ]

    public static var path: String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Output of `docker <arguments>`, or nil when docker is missing, fails or takes
    /// longer than `timeout` (a daemon that is still starting can hang).
    @discardableResult
    public static func run(_ arguments: [String], timeout: TimeInterval = 3) -> String? {
        guard let path else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        do { try process.run() } catch { return nil }

        // Read while it runs so a full pipe buffer can't stall the process.
        nonisolated(unsafe) var data = Data()
        let reader = DispatchQueue.global(qos: .utility)
        let readDone = DispatchSemaphore(value: 0)
        reader.async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = readDone.wait(timeout: .now() + 1)
            return nil
        }
        readDone.wait()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
