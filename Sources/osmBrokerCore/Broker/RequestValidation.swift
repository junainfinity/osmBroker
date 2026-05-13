import Foundation

/// Validation rules from [[Security-Requirements]] VAL-1..3. Pure functions,
/// trivially unit-testable.
public enum RequestValidation {

    /// VAL-1: model IDs match this regex. Anything else returns nil.
    /// Allowed: alnum, dot, underscore, colon, slash, hyphen, length 1..128.
    public static func sanitizedModel(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard (1...128).contains(trimmed.count) else { return nil }
        for ch in trimmed.unicodeScalars {
            let v = ch.value
            let isAlnum = (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v)
            let isAllowedPunct = ch == "." || ch == "_" || ch == ":" || ch == "/" || ch == "-"
            if !(isAlnum || isAllowedPunct) { return nil }
        }
        return trimmed
    }

    public enum BodyError: Error, Equatable {
        case malformedJSON(String)
        case missingModel
        case modelInvalid
        case missingMessages
        case tooManyMessages
        case messageTooLong
        case totalTooLong
        case roleInvalid(String)
    }

    public struct ParsedRequest {
        public let model: String
        public let messages: [AdapterRequest.Message]
        public let stream: Bool
    }

    /// VAL-2 / VAL-3: parse body bytes into a clean AdapterRequest-friendly
    /// shape. Caller passes this off to the appropriate adapter.
    public static func parseOpenAIChatCompletion(_ data: Data) throws -> ParsedRequest {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw BodyError.malformedJSON(error.localizedDescription)
        }
        guard let dict = raw as? [String: Any] else {
            throw BodyError.malformedJSON("body is not a JSON object")
        }
        return try parseCommon(dict)
    }

    public static func parseAnthropicMessages(_ data: Data) throws -> ParsedRequest {
        let raw: Any
        do {
            raw = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw BodyError.malformedJSON(error.localizedDescription)
        }
        guard let dict = raw as? [String: Any] else {
            throw BodyError.malformedJSON("body is not a JSON object")
        }
        // Anthropic uses `system` as a top-level field. Prepend it to messages
        // before delegating to common shape.
        var dict2 = dict
        var messages = (dict["messages"] as? [[String: Any]]) ?? []
        if let system = dict["system"] as? String, !system.isEmpty {
            messages.insert(["role": "system", "content": system], at: 0)
            dict2["messages"] = messages
        }
        return try parseCommon(dict2)
    }

    private static func parseCommon(_ dict: [String: Any]) throws -> ParsedRequest {
        guard let modelRaw = dict["model"] as? String else {
            throw BodyError.missingModel
        }
        guard let model = sanitizedModel(modelRaw) else {
            throw BodyError.modelInvalid
        }
        guard let messagesAny = dict["messages"] as? [[String: Any]] else {
            throw BodyError.missingMessages
        }
        if messagesAny.count > 256 {
            throw BodyError.tooManyMessages
        }

        var totalChars = 0
        var messages: [AdapterRequest.Message] = []
        messages.reserveCapacity(messagesAny.count)
        for raw in messagesAny {
            guard let role = raw["role"] as? String else {
                throw BodyError.roleInvalid("missing")
            }
            switch role.lowercased() {
            case "system", "user", "assistant": break
            default: throw BodyError.roleInvalid(role)
            }
            // Content can be plain string or an array of `{type:"text", text:"…"}`
            // chunks (Anthropic shape). Concatenate the text parts.
            let content: String
            if let s = raw["content"] as? String {
                content = s
            } else if let parts = raw["content"] as? [[String: Any]] {
                var pieces: [String] = []
                for part in parts {
                    if (part["type"] as? String) == "text",
                       let t = part["text"] as? String {
                        pieces.append(t)
                    }
                }
                content = pieces.joined(separator: "\n")
            } else {
                content = ""
            }
            if content.count > 64_000 {
                throw BodyError.messageTooLong
            }
            totalChars += content.count
            if totalChars > 256_000 {
                throw BodyError.totalTooLong
            }
            messages.append(.init(role: role.lowercased(), content: content))
        }

        let stream = (dict["stream"] as? Bool) ?? false
        return ParsedRequest(model: model, messages: messages, stream: stream)
    }
}
