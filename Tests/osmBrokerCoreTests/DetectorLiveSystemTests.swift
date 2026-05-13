import XCTest
@testable import osmBrokerCore

/// Tests that probe the actual machine running the tests. They `XCTSkip` when
/// the relevant CLI isn't installed, so CI without those tools stays green.
/// Used for "does our detector see Codex / Claude on my Mac?" sanity checks.
final class DetectorLiveSystemTests: XCTestCase {

    // MARK: - Helpers

    /// Resolve a binary via PATH using the same logic as the detector. Returns
    /// nil if not found — the test skips in that case.
    private func resolved(_ bin: String) -> String? {
        CLIDetector.resolveOnPath(bin)
    }

    // MARK: - Codex

    func testCodexIsDetectedIfInstalled() async throws {
        guard let expectedPath = resolved("codex") else {
            throw XCTSkip("codex is not on PATH on this machine; skipping live check")
        }

        let agents = await CLIDetector.detectAll()
        let codex = agents.first { $0.id == "codex" }
        let codex_ = try XCTUnwrap(codex, "registry should always include `codex`")

        XCTAssertTrue(codex_.isInstalled,
                      "codex DetectedAgent.isInstalled should be true; got \(codex_)")
        XCTAssertEqual(codex_.resolvedPath, expectedPath,
                       "resolved path should match `which codex`")
        XCTAssertNotNil(codex_.version,
                        "expected --version to produce a non-nil string; got \(String(describing: codex_.version))")
        XCTAssertEqual(codex_.def.bin, "codex")
        XCTAssertEqual(codex_.def.bridge, .stdin)
        XCTAssertEqual(codex_.def.nativeProtocol, .openai)
        XCTAssertFalse(codex_.def.fallbackModels.isEmpty,
                       "registry should carry curated fallback models for codex")
    }

    // MARK: - Claude (also expected on this dev machine; same shape)

    func testClaudeIsDetectedIfInstalled() async throws {
        guard let expectedPath = resolved("claude") ?? resolved("openclaude") else {
            throw XCTSkip("claude / openclaude not on PATH; skipping")
        }
        let agents = await CLIDetector.detectAll()
        let claude = agents.first { $0.id == "claude" }
        let claude_ = try XCTUnwrap(claude)

        XCTAssertTrue(claude_.isInstalled)
        XCTAssertEqual(claude_.resolvedPath, expectedPath)
        XCTAssertEqual(claude_.def.bin, "claude")
        XCTAssertEqual(claude_.def.bridge, .stdin)
        XCTAssertEqual(claude_.def.nativeProtocol, .anthropic)
    }

    // MARK: - Summary print (info only — passes always)

    /// Emits a one-line summary of what the detector sees on this machine. Useful
    /// when running `swift test --filter DetectorLiveSystemTests` from the
    /// command line to verify reality matches the UI's claims.
    func testPrintDetectionSummary() async throws {
        let agents = await CLIDetector.detectAll()
        let installed = agents.filter(\.isInstalled)
        let lines = installed.map { a -> String in
            "  • \(a.def.id) — \(a.resolvedPath ?? "?") — \(a.version ?? "(no version)")"
        }
        print("\n=== osmBroker detection summary ===")
        print("Installed: \(installed.count) of \(agents.count)")
        for line in lines { print(line) }
        print("===================================\n")
        XCTAssertGreaterThanOrEqual(installed.count, 0)
    }
}
