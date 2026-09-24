import Foundation

/// Names the dev tool behind a process: `node` is useless, `vite` is what you started.
public enum ToolDetector {
    /// Checked in order; the first hit in argv wins, so wrappers like `npx`
    /// or `npm exec` don't hide the real tool.
    static let knownTools = [
        "vite", "next", "wrangler", "astro", "nuxt", "remix", "react-router",
        "webpack", "storybook", "vitest", "playwright", "turbo", "expo", "svelte-kit",
        "parcel", "esbuild", "tsx", "nodemon", "json-server", "serve", "http-server",
        "supabase", "firebase", "netlify", "vercel", "hugo", "jekyll", "rails",
        "uvicorn", "gunicorn", "flask", "django", "manage.py", "php", "caddy",
    ]

    public static func label(command: String, arguments: [String]) -> String {
        for arg in arguments.dropFirst() {
            if let tool = tool(in: arg) { return tool }
        }
        if arguments.count >= 3, arguments[1] == "-m" { return arguments[2] }  // python -m http.server
        let lower = command.lowercased()
        if lower.contains("docker") || lower.contains("orbstack") { return "docker" }
        return command
    }

    private static func tool(in arg: String) -> String? {
        let parts = arg.split(separator: "/").map(String.init)
        // `…/node_modules/.bin/vite` or `…/node_modules/vite/bin/vite.js`
        if let nm = parts.firstIndex(of: "node_modules"), nm + 1 < parts.count {
            var name = parts[nm + 1]
            if name == ".bin", nm + 2 < parts.count { name = parts[nm + 2] }
            if name.hasPrefix("@"), nm + 2 < parts.count { name = parts[nm + 2] }  // @scope/pkg
            return normalize(name)
        }
        guard let last = parts.last else { return nil }
        let base = last.replacingOccurrences(of: ".js", with: "")
            .replacingOccurrences(of: ".mjs", with: "")
            .replacingOccurrences(of: ".cjs", with: "")
        return knownTools.contains(base) ? normalize(base) : nil
    }

    private static func normalize(_ name: String) -> String {
        switch name {
        case "kit": return "svelte-kit"
        case "manage.py": return "django"
        default: return name
        }
    }
}
