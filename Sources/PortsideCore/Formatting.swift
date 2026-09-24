import Foundation

public enum Formatting {
    /// `3m`, `2h 5m`, `4d 1h` — compact enough for a menu row.
    public static func uptime(since start: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let minutes = seconds / 60, hours = minutes / 60, days = hours / 24
        if days > 0 { return "\(days)d \(hours % 24)h" }
        if hours > 0 { return "\(hours)h \(minutes % 60)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    /// Shortens a path under the home directory to `~/…`.
    public static func abbreviate(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}
