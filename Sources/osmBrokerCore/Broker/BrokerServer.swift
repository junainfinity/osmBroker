import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import Logging

/// Thin façade around a SwiftNIO HTTP/1 server tailored to osmBroker's needs:
/// bearer-auth gated `/v1/models`, `/v1/chat/completions`, `/v1/messages`.
/// PRD §4.1, §3.5.
public actor BrokerServer {

    public struct Config: Sendable {
        public let host: String
        public let port: Int
        public let apiKey: String
        public let bodyByteLimit: Int
        /// Read-only snapshot of the broker's configured adapters and which
        /// model IDs are *enabled*. Built by the UI layer just before start.
        public let modelCatalog: ModelCatalog

        public init(
            host: String,
            port: Int,
            apiKey: String,
            modelCatalog: ModelCatalog,
            bodyByteLimit: Int = 1_048_576
        ) {
            self.host = host
            self.port = port
            self.apiKey = apiKey
            self.modelCatalog = modelCatalog
            self.bodyByteLimit = bodyByteLimit
        }
    }

    public struct ModelCatalog: Sendable {
        /// Pair: (modelID, adapter). Order matters — first match wins for
        /// duplicate model IDs across adapters.
        public let entries: [Entry]

        public struct Entry: Sendable {
            public let modelID: String
            public let adapter: Adapter
            public init(modelID: String, adapter: Adapter) {
                self.modelID = modelID
                self.adapter = adapter
            }
        }

        public init(entries: [Entry]) { self.entries = entries }

        public func adapter(forModel id: String) -> Adapter? {
            entries.first { $0.modelID == id }?.adapter
        }
    }

    public enum ServerError: Error, Equatable {
        case alreadyRunning
        case portInUse(Int)
        case portPermissionDenied(Int)
        case bindFailed(String)
        case emptyAPIKey
    }

    private let logger = Logger(label: "osmBroker.server")
    private var group: MultiThreadedEventLoopGroup?
    private var channel: Channel?
    private var registry = ProcessRegistry()
    private(set) public var runningConfig: Config?

    public init() {}

    public var isRunning: Bool { channel != nil }

    public func start(_ config: Config) async throws {
        if isRunning { throw ServerError.alreadyRunning }
        // AUTH-5: empty key blocks startup.
        if config.apiKey.isEmpty { throw ServerError.emptyAPIKey }

        // PRD §7 — preflight port conflict.
        switch PortPreflight.check(host: config.host, port: config.port) {
        case .free:                 break
        case .inUse:                throw ServerError.portInUse(config.port)
        case .permissionDenied:     throw ServerError.portPermissionDenied(config.port)
        case .invalidHost, .other:  throw ServerError.bindFailed("invalid host or other error")
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let registry = self.registry
        let apiKey = config.apiKey
        let bodyLimit = config.bodyByteLimit
        let catalog = config.modelCatalog
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 128)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline(withErrorHandling: true).flatMap {
                    channel.pipeline.addHandler(HTTPRequestRouter(
                        apiKey: apiKey,
                        bodyLimit: bodyLimit,
                        catalog: catalog,
                        registry: registry
                    ))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        do {
            let channel = try await bootstrap.bind(host: config.host, port: config.port).get()
            self.group = group
            self.channel = channel
            self.runningConfig = config
            self.logger.info("broker listening on \(config.host):\(config.port)")
        } catch {
            try? await group.shutdownGracefully()
            throw ServerError.bindFailed(String(describing: error))
        }
    }

    public func stop() async {
        guard let channel = channel else { return }
        try? await channel.close()
        try? await group?.shutdownGracefully()
        self.channel = nil
        self.group = nil
        await registry.killAll(grace: 1.0)
        await registry.waitForAllToExit(timeout: 3.0)
        runningConfig = nil
        logger.info("broker stopped, children reaped")
    }
}
