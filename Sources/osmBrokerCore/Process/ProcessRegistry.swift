import Foundation
import Darwin
import Logging

/// Signal-handler-safe mirror of currently-tracked PIDs. POSIX signal handlers
/// cannot run Swift async code or take ordinary locks; `os_unfair_lock` is
/// documented as safe to acquire from a signal handler on Darwin.
private final class SignalSafePIDMirror: @unchecked Sendable {
    static let shared = SignalSafePIDMirror()
    private var lock = os_unfair_lock()
    private var pids: Set<Int32> = []

    func add(_ pid: Int32) {
        os_unfair_lock_lock(&lock)
        pids.insert(pid)
        os_unfair_lock_unlock(&lock)
    }
    func remove(_ pid: Int32) {
        os_unfair_lock_lock(&lock)
        pids.remove(pid)
        os_unfair_lock_unlock(&lock)
    }
    func snapshot() -> [Int32] {
        os_unfair_lock_lock(&lock)
        let copy = Array(pids)
        os_unfair_lock_unlock(&lock)
        return copy
    }
}

/// Tracks every child the broker has spawned. On Stop / quit, calls
/// `killAll(grace:)` to ensure no zombies survive.
///
/// PRD §7 — "Zombie Processes: When osmBroker is quit, it must execute a clean
/// teardown sequence."
public actor ProcessRegistry {
    public static let shared = ProcessRegistry()

    private var children: [Int32: ChildHandle] = [:]
    private let logger = Logger(label: "osmBroker.registry")

    public init() {}

    public func register(_ child: ChildHandle) {
        children[child.pid] = child
        SignalSafePIDMirror.shared.add(child.pid)
        logger.debug("registered pid=\(child.pid) bin=\(child.executable.lastPathComponent)")
        // Auto-unregister when this child terminates naturally.
        let pid = child.pid
        Task { [weak self, exit = child.exit] in
            _ = await exit()
            await self?.unregister(pid: pid)
        }
    }

    public func unregister(pid: Int32) {
        if children.removeValue(forKey: pid) != nil {
            SignalSafePIDMirror.shared.remove(pid)
            logger.debug("unregistered pid=\(pid)")
        }
    }

    /// Snapshot of tracked PIDs that is safe to read from a POSIX signal
    /// handler. Used by the app's `ShutdownReaper` to send SIGTERM on quit.
    /// Returns all tracked PIDs across every `ProcessRegistry` instance.
    public nonisolated static func signalSafePIDs() -> [Int32] {
        SignalSafePIDMirror.shared.snapshot()
    }

    public func pids() -> [Int32] {
        children.keys.sorted()
    }

    public func count() -> Int { children.count }

    /// SIGTERM every tracked child, escalate to SIGKILL after `grace`.
    /// Returns once we've issued the signals; doesn't wait for reap.
    public func killAll(grace: Double = 2.0) async {
        let snapshot = Array(children.values)
        for child in snapshot {
            child.terminate(grace)
        }
        logger.info("killAll: signaled \(snapshot.count) child process(es)")
    }

    /// Wait until every registered child has exited or `timeout` elapses.
    /// Used by integration tests; not on the hot path.
    public func waitForAllToExit(timeout: Double = 5.0) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !children.isEmpty && Date() < deadline {
            // Spin lightly: check exit status by sending sig 0 (no-op probe).
            let snapshot = Array(children.keys)
            for pid in snapshot {
                if kill(pid, 0) == -1 && errno == ESRCH {
                    children.removeValue(forKey: pid)
                }
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
