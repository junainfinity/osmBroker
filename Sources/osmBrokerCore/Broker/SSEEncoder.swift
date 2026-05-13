import Foundation

/// Server-Sent Events frame encoding for OpenAI- and Anthropic-shaped streams.
///
/// PRD §4.4 — repackage CLI text into "strictly formatted SSE chunks". The
/// shape `data: {…}\n\n` is what every OpenAI-compatible client expects.
///
/// All methods return the encoded bytes ready to write to a socket; no
/// trailing assumptions.
public enum SSEEncoder {

    // MARK: - OpenAI: /v1/chat/completions streaming

    public struct OpenAIChunk: Encodable {
        public struct Choice: Encodable {
            public struct Delta: Encodable {
                public let role: String?
                public let content: String?
            }
            public let index: Int
            public let delta: Delta
            public let finish_reason: String?
        }
        public let id: String
        public let object: String
        public let created: Int
        public let model: String
        public let choices: [Choice]
    }

    /// First chunk: announces role=assistant, no content yet.
    /// Mirrors OpenAI's behaviour so clients that key off `delta.role` work.
    public static func openAIRoleChunk(id: String, model: String, created: Int) -> Data {
        let chunk = OpenAIChunk(
            id: id,
            object: "chat.completion.chunk",
            created: created,
            model: model,
            choices: [.init(index: 0,
                            delta: .init(role: "assistant", content: nil),
                            finish_reason: nil)]
        )
        return dataLine(jsonEncode(chunk))
    }

    /// Subsequent chunks: a slice of content text.
    public static func openAIDeltaChunk(id: String, model: String, created: Int, text: String) -> Data {
        let chunk = OpenAIChunk(
            id: id,
            object: "chat.completion.chunk",
            created: created,
            model: model,
            choices: [.init(index: 0,
                            delta: .init(role: nil, content: text),
                            finish_reason: nil)]
        )
        return dataLine(jsonEncode(chunk))
    }

    /// Final structural chunk before `[DONE]`.
    public static func openAIStopChunk(id: String, model: String, created: Int,
                                       finishReason: String = "stop") -> Data {
        let chunk = OpenAIChunk(
            id: id,
            object: "chat.completion.chunk",
            created: created,
            model: model,
            choices: [.init(index: 0,
                            delta: .init(role: nil, content: nil),
                            finish_reason: finishReason)]
        )
        return dataLine(jsonEncode(chunk))
    }

    /// Stream terminator. OpenAI uses the literal `[DONE]` as payload.
    public static func openAIDone() -> Data {
        Data("data: [DONE]\n\n".utf8)
    }

    // MARK: - OpenAI: error envelope (non-streaming + stream-error)

    public struct ErrorEnvelope: Encodable {
        public struct ErrorBody: Encodable {
            public let message: String
            public let type: String
            public let code: String?
        }
        public let error: ErrorBody
    }

    public static func errorJSON(message: String, type: String, code: String? = nil) -> Data {
        jsonEncode(ErrorEnvelope(error: .init(message: message, type: type, code: code)))
    }

    /// When an error occurs mid-stream, send an SSE event named `error` with
    /// the standard envelope, then close.
    public static func openAIStreamError(message: String, type: String, code: String? = nil) -> Data {
        let body = jsonEncode(ErrorEnvelope(error: .init(message: message, type: type, code: code)))
        var out = Data("event: error\n".utf8)
        out.append(dataLine(body))
        return out
    }

    // MARK: - Anthropic: /v1/messages streaming

    // Anthropic's stream uses named events. Each event has both an `event:` line
    // and a `data:` line with the matching JSON.

    public struct AnthropicMessageStart: Encodable {
        public struct Message: Encodable {
            public let id: String
            public let type: String
            public let role: String
            public let model: String
            public let content: [String]
            public let stop_reason: String?
            public let stop_sequence: String?
        }
        public let type: String
        public let message: Message
    }

    public static func anthropicMessageStart(id: String, model: String) -> Data {
        let payload = AnthropicMessageStart(
            type: "message_start",
            message: .init(
                id: id, type: "message", role: "assistant", model: model,
                content: [], stop_reason: nil, stop_sequence: nil
            )
        )
        return event("message_start", json: jsonEncode(payload))
    }

    public static func anthropicContentBlockStart(index: Int = 0) -> Data {
        struct Payload: Encodable {
            struct Block: Encodable { let type: String; let text: String }
            let type: String
            let index: Int
            let content_block: Block
        }
        let payload = Payload(type: "content_block_start", index: index,
                              content_block: .init(type: "text", text: ""))
        return event("content_block_start", json: jsonEncode(payload))
    }

    public static func anthropicContentBlockDelta(text: String, index: Int = 0) -> Data {
        struct Payload: Encodable {
            struct Delta: Encodable { let type: String; let text: String }
            let type: String
            let index: Int
            let delta: Delta
        }
        let payload = Payload(type: "content_block_delta", index: index,
                              delta: .init(type: "text_delta", text: text))
        return event("content_block_delta", json: jsonEncode(payload))
    }

    public static func anthropicContentBlockStop(index: Int = 0) -> Data {
        struct Payload: Encodable {
            let type: String
            let index: Int
        }
        return event("content_block_stop",
                     json: jsonEncode(Payload(type: "content_block_stop", index: index)))
    }

    public static func anthropicMessageDelta(stopReason: String = "end_turn") -> Data {
        struct Payload: Encodable {
            struct Delta: Encodable { let stop_reason: String; let stop_sequence: String? }
            let type: String
            let delta: Delta
            let usage: [String: Int]
        }
        return event("message_delta",
                     json: jsonEncode(Payload(type: "message_delta",
                                              delta: .init(stop_reason: stopReason,
                                                           stop_sequence: nil),
                                              usage: [:])))
    }

    public static func anthropicMessageStop() -> Data {
        struct Payload: Encodable { let type: String }
        return event("message_stop",
                     json: jsonEncode(Payload(type: "message_stop")))
    }

    // MARK: - Primitives

    /// Encode `data: <json>\n\n`. Note: we do NOT split on \n inside JSON
    /// because the JSON encoder escapes embedded newlines into `\n`.
    public static func dataLine(_ json: Data) -> Data {
        var out = Data("data: ".utf8)
        out.append(json)
        out.append("\n\n".data(using: .utf8)!)
        return out
    }

    /// Encode `event: <name>\ndata: <json>\n\n`.
    public static func event(_ name: String, json: Data) -> Data {
        precondition(!name.contains("\n"), "SSE event names cannot contain newlines")
        var out = Data("event: \(name)\n".utf8)
        out.append(dataLine(json))
        return out
    }

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    private static func jsonEncode<T: Encodable>(_ value: T) -> Data {
        do {
            return try jsonEncoder.encode(value)
        } catch {
            // Fail closed with an inert payload — never crash the stream.
            return Data("{}".utf8)
        }
    }
}
