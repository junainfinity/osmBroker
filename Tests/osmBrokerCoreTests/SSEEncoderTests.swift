import XCTest
@testable import osmBrokerCore

final class SSEEncoderTests: XCTestCase {

    // MARK: - Primitive shape

    func testDataLineFraming() {
        let body = Data(#"{"k":"v"}"#.utf8)
        let frame = String(data: SSEEncoder.dataLine(body), encoding: .utf8)
        XCTAssertEqual(frame, "data: {\"k\":\"v\"}\n\n")
    }

    func testEventFraming() {
        let body = Data(#"{"x":1}"#.utf8)
        let frame = String(data: SSEEncoder.event("custom", json: body), encoding: .utf8)
        XCTAssertEqual(frame, "event: custom\ndata: {\"x\":1}\n\n")
    }

    // MARK: - OpenAI shape

    func testOpenAIRoleChunkShape() throws {
        let data = SSEEncoder.openAIRoleChunk(id: "chatcmpl-1", model: "m", created: 1700)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.hasPrefix("data: "))
        XCTAssertTrue(s.hasSuffix("\n\n"))

        let json = try jsonBody(s)
        XCTAssertEqual(json["id"] as? String, "chatcmpl-1")
        XCTAssertEqual(json["object"] as? String, "chat.completion.chunk")
        XCTAssertEqual(json["model"] as? String, "m")

        let choices = try XCTUnwrap(json["choices"] as? [[String: Any]])
        let delta = try XCTUnwrap(choices.first?["delta"] as? [String: Any])
        XCTAssertEqual(delta["role"] as? String, "assistant")
        XCTAssertNil(delta["content"])
    }

    func testOpenAIDeltaChunkContent() throws {
        let data = SSEEncoder.openAIDeltaChunk(id: "x", model: "m", created: 1, text: "Hello, world!")
        let json = try jsonBody(String(data: data, encoding: .utf8) ?? "")
        let choices = try XCTUnwrap(json["choices"] as? [[String: Any]])
        let delta = try XCTUnwrap(choices.first?["delta"] as? [String: Any])
        XCTAssertEqual(delta["content"] as? String, "Hello, world!")
    }

    func testOpenAIDeltaEscapesEmbeddedNewlines() throws {
        // Embedded \n must be JSON-escaped, not break the SSE framing.
        let data = SSEEncoder.openAIDeltaChunk(id: "x", model: "m", created: 1, text: "line1\nline2")
        let s = String(data: data, encoding: .utf8) ?? ""
        // SSE framing rule: exactly one `\n\n` (the frame terminator) and no
        // bare `\n` between `data: ` and the terminator.
        XCTAssertEqual(s.components(separatedBy: "\n\n").count, 2,
                       "SSE frame must contain exactly one terminating \\n\\n")
        let between = s.dropFirst("data: ".count).dropLast(2)
        XCTAssertFalse(between.contains("\n"),
                       "JSON payload must not contain raw newlines")

        let json = try jsonBody(s)
        let choices = try XCTUnwrap(json["choices"] as? [[String: Any]])
        let delta = try XCTUnwrap(choices.first?["delta"] as? [String: Any])
        XCTAssertEqual(delta["content"] as? String, "line1\nline2")
    }

    func testOpenAIStopChunkCarriesFinishReason() throws {
        let data = SSEEncoder.openAIStopChunk(id: "x", model: "m", created: 1, finishReason: "length")
        let json = try jsonBody(String(data: data, encoding: .utf8) ?? "")
        let choices = try XCTUnwrap(json["choices"] as? [[String: Any]])
        XCTAssertEqual(choices.first?["finish_reason"] as? String, "length")
    }

    func testOpenAIDoneSentinel() {
        let s = String(data: SSEEncoder.openAIDone(), encoding: .utf8)
        XCTAssertEqual(s, "data: [DONE]\n\n")
    }

    // MARK: - Anthropic shape

    func testAnthropicMessageStartHasEventLine() throws {
        let s = String(data: SSEEncoder.anthropicMessageStart(id: "msg_1", model: "claude-x"),
                       encoding: .utf8) ?? ""
        XCTAssertTrue(s.hasPrefix("event: message_start\n"))
        XCTAssertTrue(s.contains("\"type\":\"message_start\""))
        XCTAssertTrue(s.contains("\"id\":\"msg_1\""))
    }

    func testAnthropicContentBlockDeltaShape() throws {
        let s = String(data: SSEEncoder.anthropicContentBlockDelta(text: "ok"),
                       encoding: .utf8) ?? ""
        XCTAssertTrue(s.hasPrefix("event: content_block_delta\n"))
        XCTAssertTrue(s.contains("\"text\":\"ok\""))
    }

    // MARK: - Error envelope

    func testErrorJSONShape() throws {
        let data = SSEEncoder.errorJSON(message: "nope", type: "invalid_request_error", code: "x123")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let err = try XCTUnwrap(json["error"] as? [String: Any])
        XCTAssertEqual(err["message"] as? String, "nope")
        XCTAssertEqual(err["type"] as? String, "invalid_request_error")
        XCTAssertEqual(err["code"] as? String, "x123")
    }

    func testStreamErrorFraming() {
        let s = String(data: SSEEncoder.openAIStreamError(message: "boom",
                                                          type: "internal_server_error"),
                       encoding: .utf8) ?? ""
        XCTAssertTrue(s.hasPrefix("event: error\n"))
        XCTAssertTrue(s.contains("\"message\":\"boom\""))
        XCTAssertTrue(s.hasSuffix("\n\n"))
    }

    // MARK: - Helpers

    private func jsonBody(_ frame: String) throws -> [String: Any] {
        // Strip "data: " prefix and trailing \n\n; rest is JSON.
        var body = frame
        if body.hasPrefix("data: ") { body.removeFirst("data: ".count) }
        if body.hasSuffix("\n\n") { body.removeLast(2) }
        let data = Data(body.utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
