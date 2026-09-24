import Foundation

/// A process holding one or more listening TCP sockets.
public struct Listener: Equatable, Sendable {
    public let pid: Int32
    public let command: String
    public let ports: [Int]

    public init(pid: Int32, command: String, ports: [Int]) {
        self.pid = pid
        self.command = command
        self.ports = ports
    }
}

/// Parses `lsof -F pcn` output into listeners.
///
/// lsof's field output is one field per line, keyed by its first character:
/// `p` starts a process, `c` is its command, `f` a file descriptor and `n` that
/// descriptor's name (`*:8080`, `127.0.0.1:5173`, `[::1]:3000`). A server bound to
/// both IPv4 and IPv6 shows the same port twice, so ports are de-duplicated.
public enum LsofParser {
    public static func parse(_ output: String) -> [Listener] {
        var result: [Listener] = []
        var pid: Int32?
        var command = ""
        var ports: [Int] = []

        func flush() {
            if let pid, !ports.isEmpty {
                result.append(Listener(pid: pid, command: command, ports: ports.sorted()))
            }
        }

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let key = line.first else { continue }
            let value = line.dropFirst()
            switch key {
            case "p":
                flush()
                pid = Int32(value)
                command = ""
                ports = []
            case "c":
                command = String(value)
            case "n":
                if let port = port(fromName: value), !ports.contains(port) {
                    ports.append(port)
                }
            default:
                continue
            }
        }
        flush()
        return result
    }

    /// `*:8080` → 8080, `[::1]:5173` → 5173. Anything after the last colon.
    private static func port(fromName name: Substring) -> Int? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        return Int(name[name.index(after: colon)...])
    }
}
