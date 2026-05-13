import XCTest
@testable import osmBrokerCore

/// End-to-end through the HTTP broker against the real `claude` CLI.
/// Uses the `sonnet` alias (per [[Claude-Model-Discovery]] — `claude --help`
/// says aliases auto-resolve to the latest model).
///
/// Skipped if claude isn't on PATH or isn't authenticated. Slow (~20-30 s).
final class LiveClaudeBrokerTests: XCTestCase {

    private static let portLock = NSLock()
    private static var nextPort = 24000

    private static func allocatePort() -> Int {
        portLock.lock(); defer { portLock.unlock() }
        let p = nextPort; nextPort += 1; return p
    }

    private var server: BrokerServer!
    private var port: Int = 0
    private let apiKey = "live-claude-key"
    private let model = "sonnet"   // alias — claude resolves to today's claude-sonnet-4-x

    override func setUp() async throws {
        try await super.setUp()
        guard CLIDetector.resolveOnPath("claude") != nil else {
            throw XCTSkip("claude not on PATH")
        }

        var candidate = Self.allocatePort()
        while case .inUse = PortPreflight.check(host: "127.0.0.1", port: candidate) {
            candidate = Self.allocatePort()
        }
        port = candidate

        let catalog = BrokerServer.ModelCatalog(entries: [
            .init(modelID: model, adapter: ClaudeAdapter())
        ])
        server = BrokerServer()
        try await server.start(.init(host: "127.0.0.1", port: port,
                                     apiKey: apiKey, modelCatalog: catalog))
    }

    override func tearDown() async throws {
        await server?.stop()
        try await super.tearDown()
    }

    func testLiveClaudeStreaming() async throws {
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": [
                ["role": "user", "content": "Reply with exactly the single word: CLAUDE_LIVE_OK"]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 120  // claude can be slower than codex on a cold call

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
        print("\n=== /v1/chat/completions via broker \u{2192} claude (sonnet) ===\n\(content)\n=================================================\n")
        XCTAssertFalse(content.isEmpty,
                       "expected non-empty assistant content")
    }
}
