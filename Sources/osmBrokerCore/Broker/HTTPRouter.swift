import Foundation
import NIOCore
import NIOHTTP1
import Logging

/// One-per-connection NIO handler. Aggregates request bytes (1 MiB cap),
/// authenticates, then dispatches to the right route handler. Streaming
/// responses are written back as `.body` chunks over the channel.
final class HTTPRequestRouter: ChannelInboundHandler {
    typealias InboundIn  = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let apiKey: String
    private let bodyLimit: Int
    private let catalog: BrokerServer.ModelCatalog
    private let registry: ProcessRegistry
    private let logger = Logger(label: "osmBroker.http")

    private var head: HTTPRequestHead?
    private var body: ByteBuffer = ByteBuffer()
    private var rejected = false
    private var keepAlive = false

    init(apiKey: String,
         bodyLimit: Int,
         catalog: BrokerServer.ModelCatalog,
         registry: ProcessRegistry) {
        self.apiKey = apiKey
        self.bodyLimit = bodyLimit
        self.catalog = catalog
        self.registry = registry
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = self.unwrapInboundIn(data)
        switch part {
        case .head(let h):
            self.head = h
            self.body.clear()
            self.rejected = false
            self.keepAlive = h.isKeepAlive

        case .body(var buf):
            guard !rejected else { return }
            if body.readableBytes + buf.readableBytes > bodyLimit {
                rejected = true
                respondJSON(context: context,
                            status: .payloadTooLarge,
                            json: SSEEncoder.errorJSON(
                                message: "Request body exceeds \(bodyLimit) bytes.",
                                type: "invalid_request_error",
                                code: "body_too_large"))
                return
            }
            body.writeBuffer(&buf)

        case .end:
            guard !rejected, let head = head else { return }
            handle(head: head, body: body, context: context)
        }
    }

    // MARK: - Dispatch

    private func handle(head: HTTPRequestHead, body: ByteBuffer, context: ChannelHandlerContext) {
        // LOG-2: never log the bearer.
        logger.info("\(head.method.rawValue) \(head.uri)")

        // AUTH-1/2: bearer check before anything else.
        let authHeader = head.headers.first(name: "Authorization")
        switch Auth.check(authorizationHeader: authHeader, expecting: apiKey) {
        case .ok: break
        case .missing, .malformed, .wrong:
            respondJSON(context: context,
                        status: .unauthorized,
                        json: SSEEncoder.errorJSON(
                            message: "Missing or invalid Authorization header. Use `Authorization: Bearer <key>`.",
                            type: "authentication_error",
                            code: "invalid_api_key"))
            return
        }

        // Strip query string for matching.
        let path = head.uri.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
                            .first.map(String.init) ?? head.uri

        switch (head.method, path) {
        case (.GET, "/v1/models"):
            handleModelsList(context: context)

        case (.POST, "/v1/chat/completions"):
            let data = bodyBytes(body)
            handleChatCompletions(body: data, context: context)

        case (.POST, "/v1/messages"):
            let data = bodyBytes(body)
            handleMessages(body: data, context: context)

        case (.GET, "/health"):
            respondJSON(context: context,
                        status: .ok,
                        json: Data(#"{"status":"ok"}"#.utf8))

        default:
            respondJSON(context: context,
                        status: .notFound,
                        json: SSEEncoder.errorJSON(
                            message: "Unknown endpoint \(path).",
                            type: "not_found_error",
                            code: nil))
        }
    }

    // MARK: - GET /v1/models

    private func handleModelsList(context: ChannelHandlerContext) {
        struct ModelEntry: Encodable {
            let id: String
            let object: String
            let owned_by: String
        }
        struct List: Encodable {
            let object: String
            let data: [ModelEntry]
        }
        let entries = catalog.entries.map { e in
            ModelEntry(id: e.modelID, object: "model", owned_by: e.adapter.def.id)
        }
        let list = List(object: "list", data: entries)
        let json = (try? JSONEncoder().encode(list)) ?? Data("{}".utf8)
        respondJSON(context: context, status: .ok, json: json)
    }

    // MARK: - POST /v1/chat/completions

    private func handleChatCompletions(body data: Data, context: ChannelHandlerContext) {
        let parsed: RequestValidation.ParsedRequest
        do {
            parsed = try RequestValidation.parseOpenAIChatCompletion(data)
        } catch let err as RequestValidation.BodyError {
            return respondJSON(context: context,
                               status: .badRequest,
                               json: SSEEncoder.errorJSON(
                                message: humanize(err),
                                type: "invalid_request_error",
                                code: code(for: err)))
        } catch {
            return respondJSON(context: context,
                               status: .badRequest,
                               json: SSEEncoder.errorJSON(
                                message: "Malformed body.",
                                type: "invalid_request_error",
                                code: "malformed_body"))
        }

        guard let adapter = catalog.adapter(forModel: parsed.model) else {
            return respondJSON(context: context,
                               status: .notFound,
                               json: SSEEncoder.errorJSON(
                                message: "Model `\(parsed.model)` is not exposed by this broker.",
                                type: "model_not_found",
                                code: "model_not_found"))
        }

        let request = AdapterRequest(model: parsed.model, messages: parsed.messages, stream: parsed.stream)
        if parsed.stream {
            startStreaming(adapter: adapter, request: request, shape: .openai, context: context)
        } else {
            startUnary(adapter: adapter, request: request, shape: .openai, context: context)
        }
    }

    // MARK: - POST /v1/messages

    private func handleMessages(body data: Data, context: ChannelHandlerContext) {
        let parsed: RequestValidation.ParsedRequest
        do {
            parsed = try RequestValidation.parseAnthropicMessages(data)
        } catch let err as RequestValidation.BodyError {
            return respondJSON(context: context,
                               status: .badRequest,
                               json: SSEEncoder.errorJSON(
                                message: humanize(err),
                                type: "invalid_request_error",
                                code: code(for: err)))
        } catch {
            return respondJSON(context: context,
                               status: .badRequest,
                               json: SSEEncoder.errorJSON(
                                message: "Malformed body.",
                                type: "invalid_request_error",
                                code: "malformed_body"))
        }

        guard let adapter = catalog.adapter(forModel: parsed.model) else {
            return respondJSON(context: context,
                               status: .notFound,
                               json: SSEEncoder.errorJSON(
                                message: "Model `\(parsed.model)` is not exposed by this broker.",
                                type: "model_not_found",
                                code: "model_not_found"))
        }

        let request = AdapterRequest(model: parsed.model, messages: parsed.messages, stream: parsed.stream)
        if parsed.stream {
            startStreaming(adapter: adapter, request: request, shape: .anthropic, context: context)
        } else {
            startUnary(adapter: adapter, request: request, shape: .anthropic, context: context)
        }
    }

    // MARK: - Streaming response engine

    private enum WireShape { case openai, anthropic }

    private func startStreaming(adapter: Adapter,
                                request: AdapterRequest,
                                shape: WireShape,
                                context: ChannelHandlerContext) {
        // Write head with content-type text/event-stream.
        let head = makeStreamingResponseHead()
        let promise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(self.wrapOutboundOut(.head(head)), promise: promise)

        let registryRef = registry
        let channel = context.channel
        let eventLoop = context.eventLoop
        let id = "chatcmpl-\(UUID().uuidString.prefix(20))"
        let created = Int(Date().timeIntervalSince1970)
        let model = request.model
        let keepAlive = self.keepAlive

        Task {
            do {
                let child = try await adapter.spawn(request, registry: registryRef)
                let events = adapter.events(stdout: child.stdout,
                                            stderr: child.stderr,
                                            exit: child.exit)
                for await event in events {
                    let frame = encode(event: event, shape: shape, id: id, model: model, created: created)
                    if let frame {
                        var pre = channel.allocator.buffer(capacity: frame.count)
                        pre.writeBytes(frame)
                        let buf = pre   // freeze; closure captures the let
                        let p = eventLoop.makePromise(of: Void.self)
                        eventLoop.execute {
                            channel.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))),
                                                  promise: p)
                        }
                    }
                    if case .finish = event { break }
                }
                // Always send [DONE] for OpenAI shape.
                if shape == .openai {
                    var pre = channel.allocator.buffer(capacity: 16)
                    pre.writeBytes(SSEEncoder.openAIDone())
                    let doneBuf = pre
                    let p = eventLoop.makePromise(of: Void.self)
                    eventLoop.execute {
                        channel.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(doneBuf))),
                                              promise: p)
                    }
                }
                // End the response.
                eventLoop.execute {
                    let endPromise = eventLoop.makePromise(of: Void.self)
                    channel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)),
                                          promise: endPromise)
                    endPromise.futureResult.whenComplete { _ in
                        if !keepAlive { channel.close(promise: nil) }
                    }
                }
            } catch let AdapterError.notInstalled(id) {
                writeStreamErrorAndEnd(
                    message: "Adapter `\(id)` is not installed on this Mac.",
                    type: "not_found_error",
                    code: "adapter_not_installed",
                    shape: shape, id: id, model: model, created: created,
                    channel: channel, eventLoop: eventLoop, keepAlive: keepAlive
                )
            } catch {
                writeStreamErrorAndEnd(
                    message: "Failed to spawn underlying CLI.",
                    type: "internal_server_error",
                    code: nil,
                    shape: shape, id: id, model: model, created: created,
                    channel: channel, eventLoop: eventLoop, keepAlive: keepAlive
                )
            }
        }
    }

    private func writeStreamErrorAndEnd(
        message: String, type: String, code: String?,
        shape: WireShape, id: String, model: String, created: Int,
        channel: Channel, eventLoop: EventLoop, keepAlive: Bool
    ) {
        let frame = SSEEncoder.openAIStreamError(message: message, type: type, code: code)
        var buf = channel.allocator.buffer(capacity: frame.count)
        buf.writeBytes(frame)
        eventLoop.execute {
            channel.writeAndFlush(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
            channel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
            if !keepAlive { channel.close(promise: nil) }
        }
    }

    private func startUnary(adapter: Adapter,
                            request: AdapterRequest,
                            shape: WireShape,
                            context: ChannelHandlerContext) {
        let registryRef = registry
        let channel = context.channel
        let eventLoop = context.eventLoop
        let id = "chatcmpl-\(UUID().uuidString.prefix(20))"
        let created = Int(Date().timeIntervalSince1970)
        let model = request.model
        let keepAlive = self.keepAlive

        Task {
            do {
                let child = try await adapter.spawn(request, registry: registryRef)
                var collected = ""
                var finishReason = "stop"
                for await event in adapter.events(stdout: child.stdout,
                                                  stderr: child.stderr,
                                                  exit: child.exit) {
                    switch event {
                    case .start: break
                    case .textDelta(let s): collected += s
                    case .finish(let r): finishReason = r
                    case .error(let msg, let type, let code):
                        let body = SSEEncoder.errorJSON(message: msg, type: type, code: code)
                        // Map type/code → HTTP status. Default 500 for unknown.
                        let status = Self.httpStatusForErrorType(type: type, code: code)
                        return await respondUnary(channel: channel, eventLoop: eventLoop,
                                                  keepAlive: keepAlive,
                                                  status: status,
                                                  json: body)
                    }
                }
                let body = unaryEnvelope(shape: shape, id: id, model: model,
                                         created: created, text: collected,
                                         finishReason: finishReason)
                await respondUnary(channel: channel, eventLoop: eventLoop,
                                   keepAlive: keepAlive,
                                   status: .ok, json: body)
            } catch let AdapterError.notInstalled(id) {
                let body = SSEEncoder.errorJSON(
                    message: "Adapter `\(id)` is not installed on this Mac.",
                    type: "not_found_error", code: "adapter_not_installed")
                await respondUnary(channel: channel, eventLoop: eventLoop,
                                   keepAlive: keepAlive,
                                   status: .notFound, json: body)
            } catch {
                let body = SSEEncoder.errorJSON(
                    message: "Failed to spawn underlying CLI.",
                    type: "internal_server_error", code: nil)
                await respondUnary(channel: channel, eventLoop: eventLoop,
                                   keepAlive: keepAlive,
                                   status: .internalServerError, json: body)
            }
        }
    }

    /// Map an adapter-error `type`/`code` to the HTTP status the broker should
    /// return to the client. Mirrors the surface in `ErrorMapping.classify` —
    /// when an adapter has already labelled the error with one of the typical
    /// OpenAI/Anthropic error types, honour it instead of blanket-500ing.
    static func httpStatusForErrorType(type: String, code: String?) -> HTTPResponseStatus {
        switch type {
        case "invalid_request_error":    return .badRequest          // 400
        case "authentication_error":     return .unauthorized        // 401
        case "permission_error":         return .forbidden           // 403
        case "not_found_error",
             "model_not_found":          return .notFound            // 404
        case "rate_limit_exceeded",
             "insufficient_quota":       return .tooManyRequests     // 429
        default:                         return .internalServerError // 500
        }
    }

    private func respondUnary(channel: Channel, eventLoop: EventLoop, keepAlive: Bool,
                              status: HTTPResponseStatus, json: Data) async {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(json.count))
        if keepAlive { headers.add(name: "Connection", value: "keep-alive") }
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1),
                                    status: status, headers: headers)
        var buf = channel.allocator.buffer(capacity: json.count)
        buf.writeBytes(json)
        eventLoop.execute {
            channel.write(NIOAny(HTTPServerResponsePart.head(head)), promise: nil)
            channel.write(NIOAny(HTTPServerResponsePart.body(.byteBuffer(buf))), promise: nil)
            channel.writeAndFlush(NIOAny(HTTPServerResponsePart.end(nil)), promise: nil)
            if !keepAlive { channel.close(promise: nil) }
        }
    }

    // MARK: - Encoding helpers

    private func encode(event: AdapterEvent, shape: WireShape,
                        id: String, model: String, created: Int) -> Data? {
        switch shape {
        case .openai:
            switch event {
            case .start:
                return SSEEncoder.openAIRoleChunk(id: id, model: model, created: created)
            case .textDelta(let s):
                return SSEEncoder.openAIDeltaChunk(id: id, model: model, created: created, text: s)
            case .finish(let r):
                return SSEEncoder.openAIStopChunk(id: id, model: model, created: created, finishReason: r)
            case .error(let msg, let type, let code):
                return SSEEncoder.openAIStreamError(message: msg, type: type, code: code)
            }
        case .anthropic:
            switch event {
            case .start:
                var data = SSEEncoder.anthropicMessageStart(id: id, model: model)
                data.append(SSEEncoder.anthropicContentBlockStart())
                return data
            case .textDelta(let s):
                return SSEEncoder.anthropicContentBlockDelta(text: s)
            case .finish(let r):
                var data = SSEEncoder.anthropicContentBlockStop()
                data.append(SSEEncoder.anthropicMessageDelta(stopReason: r == "stop" ? "end_turn" : r))
                data.append(SSEEncoder.anthropicMessageStop())
                return data
            case .error(let msg, let type, let code):
                return SSEEncoder.openAIStreamError(message: msg, type: type, code: code)
            }
        }
    }

    private func unaryEnvelope(shape: WireShape, id: String, model: String,
                               created: Int, text: String, finishReason: String) -> Data {
        switch shape {
        case .openai:
            struct Response: Encodable {
                struct Choice: Encodable {
                    struct Message: Encodable { let role: String; let content: String }
                    let index: Int
                    let message: Message
                    let finish_reason: String
                }
                let id: String
                let object: String
                let created: Int
                let model: String
                let choices: [Choice]
            }
            let body = Response(
                id: id, object: "chat.completion", created: created, model: model,
                choices: [.init(index: 0,
                                message: .init(role: "assistant", content: text),
                                finish_reason: finishReason)]
            )
            return (try? JSONEncoder().encode(body)) ?? Data("{}".utf8)
        case .anthropic:
            struct Response: Encodable {
                struct Block: Encodable { let type: String; let text: String }
                let id: String
                let type: String
                let role: String
                let model: String
                let content: [Block]
                let stop_reason: String
            }
            let body = Response(
                id: id, type: "message", role: "assistant", model: model,
                content: [.init(type: "text", text: text)],
                stop_reason: finishReason == "stop" ? "end_turn" : finishReason
            )
            return (try? JSONEncoder().encode(body)) ?? Data("{}".utf8)
        }
    }

    // MARK: - Plumbing

    private func makeStreamingResponseHead() -> HTTPResponseHead {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "Connection", value: keepAlive ? "keep-alive" : "close")
        headers.add(name: "X-Accel-Buffering", value: "no")
        return HTTPResponseHead(version: .init(major: 1, minor: 1),
                                status: .ok, headers: headers)
    }

    private func respondJSON(context: ChannelHandlerContext,
                             status: HTTPResponseStatus,
                             json: Data) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Content-Length", value: String(json.count))
        headers.add(name: "Connection", value: keepAlive ? "keep-alive" : "close")
        let head = HTTPResponseHead(version: .init(major: 1, minor: 1),
                                    status: status, headers: headers)
        var buf = context.channel.allocator.buffer(capacity: json.count)
        buf.writeBytes(json)
        context.write(self.wrapOutboundOut(.head(head)), promise: nil)
        context.write(self.wrapOutboundOut(.body(.byteBuffer(buf))), promise: nil)
        let promise = context.eventLoop.makePromise(of: Void.self)
        context.writeAndFlush(self.wrapOutboundOut(.end(nil)), promise: promise)
        if !keepAlive {
            promise.futureResult.whenComplete { _ in context.close(promise: nil) }
        }
    }

    private func bodyBytes(_ buf: ByteBuffer) -> Data {
        var b = buf
        guard let bytes = b.readBytes(length: b.readableBytes) else { return Data() }
        return Data(bytes)
    }

    private func humanize(_ err: RequestValidation.BodyError) -> String {
        switch err {
        case .malformedJSON(let detail):    return "Malformed JSON: \(detail)"
        case .missingModel:                 return "Missing required field `model`."
        case .modelInvalid:                 return "`model` is not a permitted identifier."
        case .missingMessages:              return "Missing required field `messages`."
        case .tooManyMessages:              return "Too many messages (max 256)."
        case .messageTooLong:               return "Individual message content exceeds 64 KiB."
        case .totalTooLong:                 return "Total message content exceeds 256 KiB."
        case .roleInvalid(let r):           return "Invalid message role `\(r)`."
        }
    }

    private func code(for err: RequestValidation.BodyError) -> String {
        switch err {
        case .malformedJSON:       return "malformed_json"
        case .missingModel:        return "missing_model"
        case .modelInvalid:        return "model_invalid"
        case .missingMessages:     return "missing_messages"
        case .tooManyMessages:     return "too_many_messages"
        case .messageTooLong:      return "message_too_long"
        case .totalTooLong:        return "total_too_long"
        case .roleInvalid:         return "role_invalid"
        }
    }
}
