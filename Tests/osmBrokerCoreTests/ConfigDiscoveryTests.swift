import XCTest
@testable import osmBrokerCore

final class ConfigDiscoveryTests: XCTestCase {

    // MARK: - TOML key extraction

    func testParseTOMLSimpleString() {
        let body = #"""
        # Codex config
        model = "gpt-5.5"
        other = 1
        """#
        XCTAssertEqual(ConfigDiscovery.parseTOMLString(key: "model", in: body),
                       "gpt-5.5")
    }

    func testParseTOMLTrailingComment() {
        let body = #"model = "gpt-5"   # default model"#
        XCTAssertEqual(ConfigDiscovery.parseTOMLString(key: "model", in: body),
                       "gpt-5")
    }

    func testParseTOMLMissingKeyReturnsNil() {
        let body = "foo = 1\nbar = 2"
        XCTAssertNil(ConfigDiscovery.parseTOMLString(key: "model", in: body))
    }

    func testParseTOMLIgnoresCommentedLine() {
        let body = "# model = \"gpt-3.5\"\nmodel = \"gpt-5\""
        XCTAssertEqual(ConfigDiscovery.parseTOMLString(key: "model", in: body), "gpt-5")
    }

    // MARK: - Profile section extraction

    func testExtractProfileModels() {
        let body = #"""
        model = "gpt-5.5"

        [profiles.fast]
        model = "gpt-5-mini"

        [profiles.code]
        model = "gpt-5-codex"
        """#
        let profiles = ConfigDiscovery.extractProfileModels(in: body)
        XCTAssertEqual(profiles.sorted(), ["gpt-5-codex", "gpt-5-mini"])
    }

    // MARK: - End-to-end with a tmp home dir

    func testCodexDiscoveryEndToEnd() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("osm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".codex"),
            withIntermediateDirectories: true
        )
        let toml = #"""
        model = "gpt-5.5"
        model_reasoning_effort = "medium"

        [profiles.code]
        model = "gpt-5-codex"
        """#
        try toml.write(to: tmp.appendingPathComponent(".codex/config.toml"),
                       atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = ConfigDiscovery.codex(homeDir: tmp.path)
        XCTAssertEqual(result.primary, "gpt-5.5")
        XCTAssertTrue(result.discovered.contains("gpt-5.5"))
        XCTAssertTrue(result.discovered.contains("gpt-5-codex"))
    }

    func testCodexDiscoveryMissingConfigReturnsEmpty() {
        let result = ConfigDiscovery.codex(homeDir: "/nonexistent-dir-\(UUID().uuidString)")
        XCTAssertNil(result.primary)
        XCTAssertEqual(result.discovered, [])
    }

    func testClaudeDiscoveryFlatModel() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("osm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        // Value is opaque; the test pins parser behaviour, not the registry.
        let json = #"""
        { "model": "claude-sonnet-4-6", "other": true }
        """#
        try json.write(to: tmp.appendingPathComponent(".claude/settings.json"),
                       atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = ConfigDiscovery.claude(homeDir: tmp.path)
        XCTAssertEqual(result.primary, "claude-sonnet-4-6")
    }

    func testClaudeDiscoveryNestedDefaultsModel() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("osm-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: tmp.appendingPathComponent(".claude"),
            withIntermediateDirectories: true
        )
        let json = #"""
        { "defaults": { "model": "claude-opus-4-7" } }
        """#
        try json.write(to: tmp.appendingPathComponent(".claude/settings.json"),
                       atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let result = ConfigDiscovery.claude(homeDir: tmp.path)
        XCTAssertEqual(result.primary, "claude-opus-4-7")
    }
}
