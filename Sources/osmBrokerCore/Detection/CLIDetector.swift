import Foundation

public struct RunningProcess: Identifiable, Hashable, Sendable {
    public let pid: Int32
    public let command: String
    /// Resident set size in bytes, when available from `ps`. Phase 2 fills this
    /// in (PRD §3.1 — "current memory footprint").
    public let rssBytes: Int64?
    /// System user running the process (PRD §3.1 — "system user").
    public let user: String?

    public init(pid: Int32, command: String, rssBytes: Int64? = nil, user: String? = nil) {
        self.pid = pid
        self.command = command
        self.rssBytes = rssBytes
        self.user = user
    }

    public var id: Int32 { pid }
}

/// Outcome of probing a single `AgentDef` against the local system.
public struct DetectedAgent: Identifiable, Equatable, Sendable {
    public let def: AgentDef
    /// Absolute executable path, or nil if not installed.
    public let resolvedPath: String?
    /// First-line output of `<bin> --version`, trimmed. Nil if probe failed or
    /// the CLI doesn't honour `--version`.
    public let version: String?
    /// PIDs currently running with a matching basename.
    public let processes: [RunningProcess]
    /// Models known for this CLI right now. Initially the curated fallback list;
    /// the model-discovery layer (per CLI) will replace this later.
    public let models: [String]

    public init(
        def: AgentDef,
        resolvedPath: String?,
        version: String?,
        processes: [RunningProcess],
        models: [String]
    ) {
        self.def = def
        self.resolvedPath = resolvedPath
        self.version = version
        self.processes = processes
        self.models = models
    }

    public var id: String { def.id }
    public var isInstalled: Bool { resolvedPath != nil }
    public var isRunning: Bool { !processes.isEmpty }

    public static func notInstalled(_ def: AgentDef) -> DetectedAgent {
        DetectedAgent(def: def, resolvedPath: nil, version: nil, processes: [], models: [])
    }
}

/// PATH search + version probe + running-process scan. No global state; safe to
/// call from any actor — `detectAll()` itself hops to a background queue.
public enum CLIDetector {

    // MARK: - PATH search

    /// PATH directories searched. Process PATH first, then well-known user
    /// toolchain bins because GUI-launched macOS apps inherit a minimal PATH
    /// (Homebrew, asdf, volta, etc. are otherwise invisible).
    public static var searchPath: [String] {
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        var dirs = envPath.split(separator: ":").map(String.init)

        let home = NSHomeDirectory()
        let extras: [String] = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "\(home)/.local/bin",
            "\(home)/.bun/bin",
            "\(home)/.cargo/bin",
            "\(home)/.deno/bin",
            "\(home)/.volta/bin",
            "\(home)/.npm-global/bin",
            "\(home)/.npm/bin",
            "\(home)/.yarn/bin",
            "\(home)/Library/pnpm",
            "\(home)/.local/share/pnpm",
            "\(home)/Library/Application Support/fnm",
            "\(home)/.codex/bin",
            "\(home)/.claude/local"
        ]
        for extra in extras where !dirs.contains(extra) {
            dirs.append(extra)
        }
        return dirs
    }

    /// First executable file matching `bin` across `searchPath`.
    public static func resolveOnPath(_ bin: String) -> String? {
        let fm = FileManager.default
        for dir in searchPath {
            let candidate = (dir as NSString).appendingPathComponent(bin)
            if fm.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Version probe

    /// Runs `<path> --version` with a 1.5-second wall-clock cap.
    public static func probeVersion(at path: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["--version"]

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe  = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe

        do {
            try proc.run()
        } catch {
            return nil
        }
        // Close stdin write-end so the child sees EOF immediately; otherwise a
        // CLI that polls stdin (e.g. `gemini`) waits the full 1.5s timeout.
        try? inPipe.fileHandleForWriting.close()

        // Bounded wait.
        let deadline = Date().addingTimeInterval(1.5)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            proc.terminate()
            // Give it a moment to die, then SIGKILL.
            Thread.sleep(forTimeInterval: 0.1)
            if proc.isRunning {
                kill(proc.processIdentifier, SIGKILL)
            }
            return nil
        }

        let outData = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let errData = (try? errPipe.fileHandleForReading.readToEnd()) ?? Data()
        let combined = (String(data: outData, encoding: .utf8) ?? "")
            + (String(data: errData, encoding: .utf8) ?? "")

        let firstLine = combined
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespaces)
        return (firstLine?.isEmpty == false) ? firstLine : nil
    }

    // MARK: - Running-process scan

    public struct PSRow: Sendable {
        public let pid: Int32
        public let comm: String
        public let rssBytes: Int64?
        public let user: String?
    }

    /// One `ps` pass that captures pid, basename, RSS (KiB), and user.
    /// PRD §3.1 calls for memory and user on the active card.
    public static func snapshotRunningProcesses() -> [PSRow] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        // -A all users, -x include daemons, -c basename for COMM, blank-suppress
        // headers via trailing `=`. `rss` is in KiB.
        proc.arguments = ["-Axc", "-o", "pid=,rss=,user=,comm="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        do {
            try proc.run()
        } catch {
            return []
        }
        proc.waitUntilExit()

        let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        let myPid = ProcessInfo.processInfo.processIdentifier
        var out: [PSRow] = []
        for line in text.split(whereSeparator: \.isNewline) {
            // Format: <pid> <rss-KiB> <user> <comm with possible spaces>
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ",
                                      maxSplits: 3,
                                      omittingEmptySubsequences: true)
            guard parts.count == 4 else { continue }
            guard let pid = Int32(parts[0]), pid != myPid else { continue }
            let rssKiB = Int64(parts[1])
            let user = String(parts[2])
            let comm = String(parts[3]).trimmingCharacters(in: .whitespaces)
            out.append(PSRow(
                pid: pid,
                comm: comm,
                rssBytes: rssKiB.map { $0 * 1024 },
                user: user
            ))
        }
        return out
    }

    public static func matchingProcesses(
        for def: AgentDef,
        in snapshot: [PSRow]
    ) -> [RunningProcess] {
        let needles = Set([def.bin] + def.fallbackBins)
        return snapshot
            .filter { needles.contains($0.comm) }
            .map { RunningProcess(pid: $0.pid, command: $0.comm,
                                  rssBytes: $0.rssBytes, user: $0.user) }
    }

    // MARK: - Aggregate detection

    /// Probe every adapter in the registry. Returns results in registry order.
    /// Runs on `.userInitiated` so the UI stays responsive.
    public static func detectAll() async -> [DetectedAgent] {
        await Task.detached(priority: .userInitiated) { () -> [DetectedAgent] in
            let snapshot = snapshotRunningProcesses()
            var out: [DetectedAgent] = []
            out.reserveCapacity(AgentRegistry.all.count)

            for def in AgentRegistry.all {
                var resolved: String? = resolveOnPath(def.bin)
                if resolved == nil {
                    for fallback in def.fallbackBins {
                        if let r = resolveOnPath(fallback) {
                            resolved = r
                            break
                        }
                    }
                }

                let version  = resolved.flatMap(probeVersion(at:))
                let procs    = matchingProcesses(for: def, in: snapshot)

                out.append(DetectedAgent(
                    def: def,
                    resolvedPath: resolved,
                    version: version,
                    processes: procs,
                    models: def.fallbackModels
                ))
            }
            return out
        }.value
    }
}
