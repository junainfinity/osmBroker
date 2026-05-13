import XCTest
@testable import osmBrokerCore

/// End-to-end through the *actual* HTTP broker against the *actual* Codex CLI.
///
/// Skipped if codex isn't installed or isn't authenticated. Slow (10-30 s per
/// test wall-clock) because codex really runs.
final class LiveCodexBrokerTests: XCTestCase {

    private static let portLock = NSLock()
    private static var nextPort = 23000

    private static func allocatePort() -> Int {
        portLock.lock(); defer { portLock.unlock() }
        let p = nextPort; nextPort += 1; return p
    }

    private var server: BrokerServer!
    private var port: Int = 0
    private let apiKey = "live-codex-key"
    private let model = "gpt-5.5"   // matches ~/.codex/config.toml default

    override func setUp() async throws {
        try await super.setUp()
        guard CLIDetector.resolveOnPath("codex") != nil else {
            throw XCTSkip("codex not on PATH")
        }

        var candidate = Self.allocatePort()
        while case .inUse = PortPreflight.check(host: "127.0.0.1", port: candidate) {
            candidate = Self.allocatePort()
        }
        port = candidate

        let catalog = BrokerServer.ModelCatalog(entries: [
            .init(modelID: model, adapter: CodexAdapter())
        ])
        server = BrokerServer()
        try await server.start(.init(host: "127.0.0.1", port: port,
                                     apiKey: apiKey, modelCatalog: catalog))
    }

    override func tearDown() async throws {
        await server?.stop()
        try await super.tearDown()
    }

    // MARK: - GET /v1/models

    func testLiveModelsListShowsCodex() async throws {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/models")!)
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try XCTUnwrap(json["data"] as? [[String: Any]])
        XCTAssertTrue(entries.contains { ($0["id"] as? String) == self.model })
        XCTAssertEqual(entries.first?["owned_by"] as? String, "codex")
    }

    // MARK: - Streaming /v1/chat/completions

    func testLiveChatCompletionsStreaming() async throws {
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "user", "content": "Reply with the single word: BROKER_OK"]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60   // codex can take a while

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?
                        .value(forHTTPHeaderField: "Content-Type"),
                       "text/event-stream")

        var dataLines: [String] = []
        for try await line in bytes.lines {
            if line.hasPrefix("data: ") { dataLines.append(line) }
        }

        XCTAssertTrue(dataLines.contains("data: [DONE]"),
                      "missing [DONE]; got \(dataLines.count) data lines")

        var content = ""
        for line in dataLines where line != "data: [DONE]" {
            let payload = String(line.dropFirst("data: ".count))
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let text = delta["content"] as? String else { continue }
            content += text
        }
        print("\n=== /v1/chat/completions via broker → codex ===\n\(content)\n=================================================\n")
        XCTAssertFalse(content.isEmpty,
                       "expected non-empty assistant content")
    }

    // MARK: - Unary /v1/chat/completions (stream=false)

    func testLiveChatCompletionsUnary() async throws {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "user", "content": "Reply with the single word: BROKER_UNARY_OK"]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: req)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["object"] as? String, "chat.completion")
        let choices = try XCTUnwrap(json["choices"] as? [[String: Any]])
        let message = try XCTUnwrap(choices.first?["message"] as? [String: Any])
        XCTAssertEqual(message["role"] as? String, "assistant")
        let content = try XCTUnwrap(message["content"] as? String)
        XCTAssertFalse(content.isEmpty)
        print("\n=== /v1/chat/completions (unary) ===\n\(content)\n=====================================\n")
    }
}
