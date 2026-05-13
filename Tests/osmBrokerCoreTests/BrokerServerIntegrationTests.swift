import XCTest
@testable import osmBrokerCore

/// End-to-end: real NIO server on an ephemeral port, real HTTP request via
/// URLSession, real subprocess (echo-words.sh) behind the FakeEchoAdapter.
final class BrokerServerIntegrationTests: XCTestCase {

    private var server: BrokerServer!
    private var port: Int = 0
    private let apiKey = "test-key-osm"

    /// Each test gets a distinct port. XCTest runs tests in parallel by
    /// default; reusing 18080 across instances caused timeouts when two
    /// servers raced for the same socket.
    private static let portLock = NSLock()
    private static var nextPort: Int = 19000

    private static func allocatePort() -> Int {
        portLock.lock()
        defer { portLock.unlock() }
        let p = nextPort
        nextPort += 1
        return p
    }

    // MARK: - Fixture lifecycle

    override func setUp() async throws {
        try await super.setUp()

        var candidate = Self.allocatePort()
        while case .inUse = PortPreflight.check(host: "127.0.0.1", port: candidate) {
            candidate = Self.allocatePort()
            if candidate > 22000 {
                XCTFail("no free port found in test range")
                return
            }
        }
        port = candidate

        let adapter = FakeEchoAdapter()
        let catalog = BrokerServer.ModelCatalog(entries: [
            .init(modelID: "fake-echo-1", adapter: adapter)
        ])
        server = BrokerServer()
        try await server.start(.init(host: "127.0.0.1", port: port,
                                     apiKey: apiKey, modelCatalog: catalog))
    }

    override func tearDown() async throws {
        await server.stop()
        try await super.tearDown()
    }

    // MARK: - Auth (Security-Tests AUTH-1/2)

    func testMissingAuthIs401() async throws {
        let (data, response) = try await get("/v1/models", auth: nil)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let err = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(err["type"] as? String, "authentication_error")
    }

    func testWrongAuthIs401() async throws {
        let (_, response) = try await get("/v1/models", auth: "wrong-token")
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 401)
    }

    func testRightAuthIs200() async throws {
        let (_, response) = try await get("/v1/models", auth: apiKey)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
    }

    // MARK: - GET /v1/models

    func testModelsListIncludesConfiguredModel() async throws {
        let (data, response) = try await get("/v1/models", auth: apiKey)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["object"] as? String, "list")
        let entries = try XCTUnwrap(json["data"] as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?["id"] as? String, "fake-echo-1")
    }

    // MARK: - POST /v1/chat/completions (streaming)

    func testChatCompletionsStreamingHappyPath() async throws {
        let body: [String: Any] = [
            "model": "fake-echo-1",
            "stream": true,
            "messages": [
                ["role": "user", "content": "alpha beta gamma"]
            ]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (response, lines) = try await postSSE("/v1/chat/completions",
                                                  auth: apiKey, body: bodyData)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual((response as? HTTPURLResponse)?
                        .value(forHTTPHeaderField: "Content-Type"),
                       "text/event-stream")

        let dataLines = lines.filter { $0.hasPrefix("data: ") }
        XCTAssertGreaterThanOrEqual(dataLines.count, 3,
                                    "expected ≥ 3 SSE frames, got: \(dataLines)")
        XCTAssertTrue(dataLines.contains("data: [DONE]"))

        // Reconstruct the content; should include our prompt's words.
        var content = ""
        for line in dataLines where line != "data: [DONE]" {
            let payload = String(line.dropFirst("data: ".count))
            if let data = payload.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let text = delta["content"] as? String {
                content += text
            }
        }
        XCTAssertTrue(content.contains("alpha"), "missing alpha; got \(content)")
        XCTAssertTrue(content.contains("beta"),  "missing beta; got \(content)")
        XCTAssertTrue(content.contains("gamma"), "missing gamma; got \(content)")
    }

    // MARK: - Bad model / bad body

    func testUnknownModelIs404() async throws {
        let body: [String: Any] = [
            "model": "nonexistent-model-7x",
            "messages": [["role": "user", "content": "hi"]]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await post("/v1/chat/completions",
                                              auth: apiKey, body: bodyData)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let err = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(err["code"] as? String, "model_not_found")
    }

    func testMalformedJSONIs400() async throws {
        let (data, response) = try await post("/v1/chat/completions",
                                              auth: apiKey, body: Data("not-json".utf8))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let err = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(err["code"] as? String, "malformed_json")
    }

    func testInvalidModelNameIs400() async throws {
        let body: [String: Any] = [
            "model": "this has spaces and ; punctuation",
            "messages": [["role": "user", "content": "hi"]]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await post("/v1/chat/completions",
                                              auth: apiKey, body: bodyData)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 400)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let err = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(err["code"] as? String, "model_invalid")
    }

    // MARK: - Body limit (NET-4)

    func testBodyTooLargeIs413() async throws {
        // Build a 1.5 MiB-ish payload — over the default 1 MiB cap.
        let big = String(repeating: "A", count: 1_600_000)
        let body: [String: Any] = [
            "model": "fake-echo-1",
            "messages": [["role": "user", "content": big]]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await post("/v1/chat/completions",
                                           auth: apiKey, body: bodyData)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 413)
    }

    // MARK: - Unknown endpoint

    func testUnknownEndpointIs404() async throws {
        let (_, response) = try await get("/v1/bogus", auth: apiKey)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
    }

    // MARK: - HTTP helpers

    private func get(_ path: String, auth: String?) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = "GET"
        if let auth { req.addValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        return try await URLSession.shared.data(for: req)
    }

    private func post(_ path: String, auth: String?, body: Data) async throws -> (Data, URLResponse) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = "POST"
        req.httpBody = body
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth { req.addValue("Bearer \(auth)", forHTTPHeaderField: "Authorization") }
        return try await URLSession.shared.data(for: req)
    }

    /// POSTs `body` and reads SSE lines until the stream ends (or hits 5 s).
    private func postSSE(_ path: String, auth: String,
                         body: Data) async throws -> (URLResponse, [String]) {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        req.httpMethod = "POST"
        req.httpBody = body
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(auth)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5

        let (bytes, response) = try await URLSession.shared.bytes(for: req)
        var lines: [String] = []
        for try await line in bytes.lines {
            lines.append(line)
        }
        return (response, lines)
    }
}
