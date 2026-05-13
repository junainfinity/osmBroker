import SwiftUI
import AppKit
import osmBrokerCore

@main
struct OsmBrokerApp: App {
    @StateObject private var state = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("osmBroker") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear { delegate.state = state }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        // Slimmer default — the prior 1200×780 left a yawning gap in the
        // centered title strip on wide displays. 1080×720 is denser and the
        // sidebar + main pane still get their full content widths.
        .defaultSize(width: 1080, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

/// PRD §7 — clean teardown on app quit. We hook three paths:
/// 1. `NSApplicationWillTerminate` for normal Cmd-Q quit (User → File → Quit).
/// 2. POSIX signal handler for SIGTERM/SIGINT (e.g. `kill osmBroker` from CLI).
/// 3. `atexit` for any other process death where Cocoa shutdown was skipped.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var state: AppState?

    private static var sharedReaper: ShutdownReaper?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Install signal + atexit hooks ONCE per process.
        if AppDelegate.sharedReaper == nil {
            AppDelegate.sharedReaper = ShutdownReaper()
            AppDelegate.sharedReaper?.install()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Run async teardown, then tell AppKit it's okay to quit.
        Task { [weak self] in
            await self?.state?.shutdownForQuit()
            NSApplication.shared.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

/// Bridges POSIX shutdown signals + `atexit` to the shared ProcessRegistry.
/// All paths converge on `killAll`. Idempotent — running twice is harmless.
final class ShutdownReaper: @unchecked Sendable {
    // Held alive forever because signal handlers fire post-deinit otherwise.
    private static var installed = false

    func install() {
        // POSIX signal handler — C function pointers can't capture, so we
        // dispatch back to a static reaper.
        signal(SIGTERM, ShutdownReaper.onSignal)
        signal(SIGINT,  ShutdownReaper.onSignal)
        atexit(ShutdownReaper.onAtexit)
        ShutdownReaper.installed = true
    }

    /// Called on SIGTERM/SIGINT. Async-signal-safety: we limit ourselves to
    /// `kill()` and `_exit`. The Swift Task we kick off may not actually run
    /// to completion (signal context), so we *also* synchronously kill the
    /// tracked PIDs we can see.
    private static let onSignal: @convention(c) (Int32) -> Void = { sig in
        // Best effort: send SIGTERM to all known children synchronously.
        for pid in registeredPidsForSignal() {
            kill(pid, SIGTERM)
        }
        _exit(128 + sig)
    }

    private static let onAtexit: @convention(c) () -> Void = {
        for pid in registeredPidsForSignal() {
            kill(pid, SIGTERM)
        }
    }

    /// Snapshot of tracked PIDs that's safe to read from a signal handler.
    /// We expose a synchronous mirror updated by ProcessRegistry whenever it
    /// registers / unregisters. Phase 1 keeps it simple: we read directly
    /// from `ProcessRegistry.signalSafePIDs` — see core extension.
    private static func registeredPidsForSignal() -> [Int32] {
        ProcessRegistry.signalSafePIDs()
    }
}
