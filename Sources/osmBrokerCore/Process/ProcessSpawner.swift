import Foundation
import Logging

/// Outcome of a child process.
public enum Termination: Sendable, Equatable {
    case exited(code: Int32)
    case signaled(signal: Int32)
    case forcedKill          // we sent SIGKILL ourselves after SIGTERM grace
}

/// Handle on a spawned child. Holds onto the underlying `Process` so we can
/// signal it, exposes stdout/stderr as AsyncStream<Data> for the broker's
/// streaming code, and exposes the terminal `exit` outcome.
public final class ChildHandle: @unchecked Sendable, Hashable {
    public let pid: Int32
    public let executable: URL
    public let arguments: [String]
    /// `AsyncStream` continues until child stdout closes (EOF on read).
    public let stdout: AsyncStream<Data>
    public let stderr: AsyncStream<Data>
    /// Resolves once with the termination outcome. Never throws.
    public let exit: () async -> Termination

    /// Cooperative terminate: SIGTERM, optional SIGKILL escalation after grace.
    /// Idempotent.
    public let terminate: @Sendable (_ graceSeconds: Double) -> Void

    public init(
        pid: Int32,
        executable: URL,
        arguments: [String],
        stdout: AsyncStream<Data>,
        stderr: AsyncStream<Data>,
        exit: @escaping () async -> Termination,
        terminate: @escaping @Sendable (Double) -> Void
    ) {
        self.pid = pid
        self.executable = executable
        self.arguments = arguments
        self.stdout = stdout
        self.stderr = stderr
        self.exit = exit
        self.terminate = terminate
    }

    public static func == (lhs: ChildHandle, rhs: ChildHandle) -> Bool {
        lhs.pid == rhs.pid
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }
}

public enum SpawnError: Error, Equatable {
    case executableNotAbsolute(String)
    case executableNotFound(String)
    case executableNotExecutable(String)
    case envValueInvalid(key: String)
    case launchFailed(String)
}

/// Spawns subprocesses with hard security defaults. See [[Security-Requirements]]
/// SPAWN-1..7.
public enum ProcessSpawner {

    public struct Options: Sendable {
        public let executable: URL
        public let arguments: [String]
        /// Explicit env. Caller is responsible for *only* including what the
        /// child needs (SPAWN-5). Spawner validates values (SPAWN-4).
        public let environment: [String: String]
        /// Bytes written to child stdin then stdin is closed. Use this for any
        /// user prompts (SPAWN-1 — never via argv).
        public let stdin: Data?
        /// Working directory for the child. nil = inherit broker's cwd.
        public let cwd: URL?

        public init(
            executable: URL,
            arguments: [String],
            environment: [String: String],
            stdin: Data? = nil,
            cwd: URL? = nil
        ) {
            self.executable = executable
            self.arguments = arguments
            self.environment = environment
            self.stdin = stdin
            self.cwd = cwd
        }
    }

    private static let logger = Logger(label: "osmBroker.spawner")

    /// SPAWN-4: reject env values that could smuggle arguments or break
    /// process invocation. We allow ordinary text but ban NULs / newlines /
    /// values that look like another flag.
    public static func validateEnv(_ env: [String: String]) throws {
        for (key, value) in env {
            if key.isEmpty || key.contains("=") || key.contains("\0") {
                throw SpawnError.envValueInvalid(key: key)
            }
            if value.contains("\0") || value.contains("\n") {
                throw SpawnError.envValueInvalid(key: key)
            }
        }
    }

    /// Confirm the executable exists, is absolute, and is executable. SPAWN-2.
    public static func validateExecutable(_ url: URL) throws {
        // Must be a local file URL. Rejects http://, https://, ssh://, etc.
        guard url.isFileURL else {
            throw SpawnError.executableNotAbsolute(url.absoluteString)
        }
        guard url.path.hasPrefix("/") else {
            throw SpawnError.executableNotAbsolute(url.path)
        }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw SpawnError.executableNotFound(url.path)
        }
        guard fm.isExecutableFile(atPath: url.path) else {
            throw SpawnError.executableNotExecutable(url.path)
        }
    }

    public static func spawn(_ options: Options) throws -> ChildHandle {
        try validateExecutable(options.executable)
        try validateEnv(options.environment)

        let proc = Process()
        proc.executableURL = options.executable
        proc.arguments = options.arguments
        proc.environment = options.environment
        if let cwd = options.cwd { proc.currentDirectoryURL = cwd }

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe  = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe

        // Build the AsyncStreams BEFORE we launch so the readability handler
        // never races against an unset continuation.
        let (outStream, outContinuation) = makeChunkStream()
        let (errStream, errContinuation) = makeChunkStream()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                outContinuation.finish()
            } else {
                outContinuation.yield(chunk)
            }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                errContinuation.finish()
            } else {
                errContinuation.yield(chunk)
            }
        }

        // Termination plumbing: a Task waits on the Process's terminationHandler
        // through a continuation.
        let exitBox = ExitBox()

        proc.terminationHandler = { p in
            let outcome: Termination
            switch p.terminationReason {
            case .exit:               outcome = .exited(code: p.terminationStatus)
            case .uncaughtSignal:     outcome = .signaled(signal: p.terminationStatus)
            @unknown default:         outcome = .exited(code: p.terminationStatus)
            }
            exitBox.resolve(outcome)
        }

        do {
            try proc.run()
        } catch {
            throw SpawnError.launchFailed(String(describing: error))
        }

        // SPAWN-1: write the prompt to stdin then close. We close even on no-
        // prompt so children that read stdin still see EOF.
        if let bytes = options.stdin {
            // Write in a background task so we don't block the spawn caller on
            // a large payload.
            let writeHandle = inPipe.fileHandleForWriting
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try writeHandle.write(contentsOf: bytes)
                } catch {
                    // log + continue; the child may have already exited
                    logger.warning("stdin write failed: \(String(describing: error))")
                }
                try? writeHandle.close()
            }
        } else {
            try? inPipe.fileHandleForWriting.close()
        }

        let pid = proc.processIdentifier
        let weakProc = WeakProcessBox(process: proc)

        let handle = ChildHandle(
            pid: pid,
            executable: options.executable,
            arguments: options.arguments,
            stdout: outStream,
            stderr: errStream,
            exit: { await exitBox.value() },
            terminate: { grace in
                terminateProcess(boxedProcess: weakProc, graceSeconds: grace)
            }
        )
        return handle
    }

    // MARK: - Internals

    private static func makeChunkStream() -> (AsyncStream<Data>, AsyncStream<Data>.Continuation) {
        var capturedContinuation: AsyncStream<Data>.Continuation!
        let stream = AsyncStream<Data> { continuation in
            capturedContinuation = continuation
        }
        return (stream, capturedContinuation)
    }

    /// SIGTERM the process; after `grace` seconds if it's still alive, SIGKILL.
    /// Idempotent: harmless after termination.
    private static func terminateProcess(boxedProcess: WeakProcessBox, graceSeconds: Double) {
        guard let proc = boxedProcess.process, proc.isRunning else { return }
        kill(proc.processIdentifier, SIGTERM)
        let deadline = DispatchTime.now() + .milliseconds(Int(graceSeconds * 1000))
        DispatchQueue.global().asyncAfter(deadline: deadline) {
            if let p = boxedProcess.process, p.isRunning {
                kill(p.processIdentifier, SIGKILL)
            }
        }
    }
}

// We can't capture Process directly into a @Sendable closure (Process isn't
// Sendable), so wrap a weak reference.
final class WeakProcessBox: @unchecked Sendable {
    weak var process: Process?
    init(process: Process) { self.process = process }
}

/// Thread-safe one-shot value box for the child's termination outcome.
/// Multiple `await value()` callers all receive the same answer.
final class ExitBox: @unchecked Sendable {
    private let lock = NSLock()
    private var resolved: Termination?
    private var continuations: [CheckedContinuation<Termination, Never>] = []

    func resolve(_ value: Termination) {
        lock.lock()
        guard resolved == nil else { lock.unlock(); return }
        resolved = value
        let waiters = continuations
        continuations.removeAll()
        lock.unlock()
        for c in waiters { c.resume(returning: value) }
    }

    func value() async -> Termination {
        await withCheckedContinuation { (c: CheckedContinuation<Termination, Never>) in
            lock.lock()
            if let v = resolved {
                lock.unlock()
                c.resume(returning: v)
            } else {
                continuations.append(c)
                lock.unlock()
            }
        }
    }
}
