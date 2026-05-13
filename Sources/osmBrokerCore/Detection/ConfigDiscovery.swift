import Foundation

/// Pulls the *user's actual* model preferences out of each CLI's on-disk
/// config. The Models tab uses this so we show real model IDs rather than
/// the registry's static fallback list.
///
/// Codex: `~/.codex/config.toml` carries a top-level `model = "..."` line.
/// Claude: `~/.claude/settings.json` *may* carry a model preference under
///         `model` or `defaults.model` (and varies by version). We try a few
///         shapes and gracefully fall back to nil.
public enum ConfigDiscovery {

    public struct Result: Sendable, Equatable {
        /// Models discovered from the CLI's own config files. Empty if the
        /// CLI doesn't have a writable config or we couldn't find one.
        public let discovered: [String]
        /// Model the CLI is *currently* configured to use by default.
        /// Useful for badging in the UI ("primary").
        public let primary: String?

        public init(discovered: [String], primary: String?) {
            self.discovered = discovered
            self.primary = primary
        }
    }

    // MARK: - Codex

    public static func codex(homeDir: String = NSHomeDirectory()) -> Result {
        let path = (homeDir as NSString).appendingPathComponent(".codex/config.toml")
        guard let body = try? String(contentsOfFile: path, encoding: .utf8) else {
            return Result(discovered: [], primary: nil)
        }
        let model = parseTOMLString(key: "model", in: body)
        var all: [String] = []
        if let m = model { all.append(m) }
        // Look for profile sections [profiles.<name>] with their own model.
        for line in extractProfileModels(in: body) where !all.contains(line) {
            all.append(line)
        }
        return Result(discovered: all, primary: model)
    }

    // MARK: - Claude Code

    public static func claude(homeDir: String = NSHomeDirectory()) -> Result {
        // Try the documented location first.
        let candidates = [
            ".claude/settings.json",
            ".claude/config.json",
            ".config/claude/settings.json"
        ]
        for relative in candidates {
            let path = (homeDir as NSString).appendingPathComponent(relative)
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let dict = obj as? [String: Any] else { continue }

            var primary: String? = nil
            var all: [String] = []
            if let m = stringFromJSON(dict, keypath: ["model"]) { primary = m; all.append(m) }
            else if let m = stringFromJSON(dict, keypath: ["defaults", "model"]) { primary = m; all.append(m) }
            return Result(discovered: all, primary: primary)
        }
        return Result(discovered: [], primary: nil)
    }

    // MARK: - Generic helpers

    /// Minimal TOML scanner: finds a top-level `<key> = "<value>"` line. Tolerates
    /// surrounding whitespace and inline comments. Returns the first occurrence.
    static func parseTOMLString(key: String, in text: String) -> String? {
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#") { continue }
            // Strip comments after the value.
            let nocomment: String
            if let hash = line.firstIndex(of: "#"),
               // ensure the # is outside of any quoted value
               line[..<hash].filter({ $0 == "\"" }).count % 2 == 0 {
                nocomment = String(line[..<hash]).trimmingCharacters(in: .whitespaces)
            } else {
                nocomment = line
            }
            guard let eq = nocomment.firstIndex(of: "=") else { continue }
            let lhs = nocomment[..<eq].trimmingCharacters(in: .whitespaces)
            if lhs != key { continue }
            var rhs = nocomment[nocomment.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
            // unquote
            if rhs.hasPrefix("\"") && rhs.hasSuffix("\"") && rhs.count >= 2 {
                rhs = String(rhs.dropFirst().dropLast())
            }
            return rhs.isEmpty ? nil : rhs
        }
        return nil
    }

    /// Scan for `[profiles.<name>]` sections and pull their `model = "..."`
    /// values. Used by Codex which can carry many named configs.
    static func extractProfileModels(in text: String) -> [String] {
        var out: [String] = []
        var inProfile = false
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                inProfile = line.hasPrefix("[profiles.") || line.hasPrefix("[profile.")
                continue
            }
            guard inProfile else { continue }
            if line.hasPrefix("model"),
               let model = parseTOMLString(key: "model", in: String(raw)) {
                out.append(model)
            }
        }
        return out
    }

    private static func stringFromJSON(_ dict: [String: Any], keypath: [String]) -> String? {
        var node: Any = dict
        for k in keypath {
            guard let cur = node as? [String: Any], let next = cur[k] else { return nil }
            node = next
        }
        return node as? String
    }
}
