import Foundation

/// Parses the buffer returned by `sysctl(KERN_PROCARGS2)`.
///
/// Layout: a 32-bit argc, the executable path, NUL padding, then argc
/// NUL-terminated arguments, followed by the environment (ignored here).
public enum ProcArgs {
    public static func parse(_ buffer: [UInt8]) -> [String] {
        guard buffer.count > 4 else { return [] }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = 4

        // Skip the executable path, then the padding after it.
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }

        var args: [String] = []
        while args.count < argc, index < buffer.count {
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            args.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return args
    }
}
