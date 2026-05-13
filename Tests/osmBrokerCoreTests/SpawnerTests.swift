import XCTest
@testable import osmBrokerCore

/// Tests against real subprocesses using fixture scripts.
final class SpawnerTests: XCTestCase {

    // Resolves a fixture by name from the test bundle's `Fixtures/` resources.
    private func fixture(_ name: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil,
                                          subdirectory: "Fixtures") else {
            XCTFail("fixture \(name) missing from Tests/Fixtures")
            return URL(fileURLWithPath: "/dev/null")
        }
        return url
    }

    // MARK: - Validation

    func testRejectsNonFileURL() {
        // SPAWN-2 defence-in-depth: a remote URL must never reach Process.run.
        let url = URL(string: "https://example.invalid/evil.sh")!
        XCTAssertThrowsError(try ProcessSpawner.validateExecutable(url)) { err in
            guard case SpawnError.executableNotAbsolute = err else {
                return XCTFail("expected executableNotAbsolute, got \(err)")
            }
        }
    }

    func testRejectsMissingExecutable() {
        let url = URL(fileURLWithPath: "/tmp/definitely-not-here-osm-\(UUID().uuidString)")
        XCTAssertThrowsError(try ProcessSpawner.validateExecutable(url)) { err in
            guard case SpawnError.executableNotFound = err else {
                return XCTFail("expected executableNotFound, got \(err)")
            }
        }
    }

    func testRejectsEnvWithNewline() {
        XCTAssertThrowsError(try ProcessSpawner.validateEnv(["A": "hello\nworld"])) { err in
            guard case SpawnError.envValueInvalid(let key) = err else {
                return XCTFail("expected envValueInvalid, got \(err)")
            }
            XCTAssertEqual(key, "A")
        }
    }

    func testRejectsEnvWithNUL() {
        XCTAssertThrowsError(try ProcessSpawner.validateEnv(["A": "hello\0world"])) { err in
            guard case SpawnError.envValueInvalid = err else { return XCTFail() }
        }
    }

    func testRejectsEnvKeyWithEquals() {
        XCTAssertThrowsError(try ProcessSpawner.validateEnv(["A=B": "v"])) { err in
            guard case SpawnError.envValueInvalid = err else { return XCTFail() }
        }
    }

    func testAcceptsWellFormedEnv() {
        XCTAssertNoThrow(try ProcessSpawner.validateEnv([
            "PATH": "/usr/bin:/bin",
            "HOME": "/Users/test",
            "MODEL": "sonnet"
        ]))
    }

    // MARK: - stdin / stdout round-trip

    func testStdinIsWrittenAndReadBack() async throws {
        let exe = fixture("echo-stdin.sh")
        let prompt = "hello osm\nsecond line\n"

        let options = ProcessSpawner.Options(
            executable: exe,
            arguments: [],
            environment: minimalEnv(),
            stdin: Data(prompt.utf8)
        )
        let child = try ProcessSpawner.spawn(options)

        var output = ""
        for await chunk in child.stdout {
            output += String(data: chunk, encoding: .utf8) ?? ""
            if output.contains("echo: second line") { break }
        }
        _ = await child.exit()

        XCTAssertTrue(output.contains("echo: hello osm"), "got: \(output)")
        XCTAssertTrue(output.contains("echo: second line"), "got: \(output)")
    }

    // SPAWN-1: prompt must never appear in argv. We spawn dump-argv.sh with a
    // user prompt routed through stdin and verify argv never sees it.
    func testSPAWN1_PromptNotInArgv() async throws {
        let exe = fixture("dump-argv.sh")
        let secretPrompt = "PROMPT_CANARY_8a9c"

        let options = ProcessSpawner.Options(
            executable: exe,
            arguments: ["--flag-only", "no-prompt-here"],
            environment: minimalEnv(),
            stdin: Data(secretPrompt.utf8)
        )
        let child = try ProcessSpawner.spawn(options)

        var argv = ""
        for await chunk in child.stdout {
            argv += String(data: chunk, encoding: .utf8) ?? ""
            if argv.contains("argc:") { break }
        }
        _ = await child.exit()

        XCTAssertFalse(argv.contains(secretPrompt),
                       "SPAWN-1 violated: prompt leaked into argv\n\(argv)")
        XCTAssertTrue(argv.contains("argv: --flag-only"))
        XCTAssertTrue(argv.contains("argv: no-prompt-here"))
        XCTAssertTrue(argv.contains("argc: 2"))
    }

    // SPAWN-5: explicit env. We pass a known set; child env must contain
    // exactly what we said, plus the kernel's auto-injected vars (__CF_USER_TEXT_ENCODING etc. on macOS).
    func testSPAWN5_ExplicitEnv() async throws {
        let exe = fixture("dump-env.sh")
        let options = ProcessSpawner.Options(
            executable: exe,
            arguments: [],
            environment: [
                "PATH": "/usr/bin:/bin",
                "OSM_CANARY": "yes-7a"
            ],
            stdin: nil
        )
        let child = try ProcessSpawner.spawn(options)

        var env = ""
        for await chunk in child.stderr { env += String(data: chunk, encoding: .utf8) ?? "" }
        for await chunk in child.stdout { env += String(data: chunk, encoding: .utf8) ?? "" }
        _ = await child.exit()

        XCTAssertTrue(env.contains("OSM_CANARY=yes-7a"))
        // The broker process's own bearer key/etc should never leak — we
        // never put one in, so a sanity check: no AUTH-related vars appear.
        XCTAssertFalse(env.contains("OSM_BEARER"))
        XCTAssertFalse(env.contains("OSMBROKER_BEARER"))
    }

    // SPAWN-7: registry.killAll() kills tracked children even when they're
    // sleeping forever. SIGKILL escalation after grace.
    func testSPAWN7_KillAllTerminatesChildren() async throws {
        let exe = fixture("sleep-forever.sh")
        let registry = ProcessRegistry() // fresh; not the shared singleton

        var spawned: [ChildHandle] = []
        for _ in 0..<3 {
            let options = ProcessSpawner.Options(
                executable: exe,
                arguments: [],
                environment: minimalEnv(),
                stdin: nil
            )
            let child = try ProcessSpawner.spawn(options)
            await registry.register(child)
            spawned.append(child)
        }

        let beforeCount = await registry.count()
        XCTAssertEqual(beforeCount, 3)

        await registry.killAll(grace: 0.2)
        await registry.waitForAllToExit(timeout: 3.0)

        // Each child should have exited via SIGTERM (or SIGKILL escalation).
        for child in spawned {
            let outcome = await child.exit()
            switch outcome {
            case .signaled, .forcedKill, .exited:
                break       // sh interprets SIGTERM as exit code 143; either is fine
            }
            XCTAssertEqual(kill(child.pid, 0), -1,
                           "pid \(child.pid) still alive after killAll")
        }
    }

    // MARK: - Helpers

    private func minimalEnv() -> [String: String] {
        [
            "PATH": "/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "LANG": "en_US.UTF-8",
            "TERM": "dumb"
        ]
    }
}
