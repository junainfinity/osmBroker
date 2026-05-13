import Foundation
@testable import osmBrokerCore

/// Test-only adapter that runs `echo-words.sh` from the test bundle's
/// Fixtures. Used by integration tests so we don't need a real Claude/Codex
/// install on the machine running CI.
struct FakeEchoAdapter: Adapter {
    let def: AgentDef
    /// Override the registry's `claude` binary so detection lands on our
    /// fixture script instead. We do this by *not* using `resolveExecutable`
    /// from the default impl — see `spawn` below.
    let executableURL: URL

    init(modelID: String = "fake-echo-1") {
        // Pretend to be "claude" so all routing keyed off agent id still works
        // in tests; replace fallbackModels with a single sentinel ID.
        self.def = AgentDef(
            id: "fakeecho", name: "Fake Echo", monogram: "Fe",
            subtitle: "Test-only adapter",
            bin: "echo-words.sh", fallbackBins: [],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: nil, installCommand: nil,
            fallbackModels: [modelID]
        )
        guard let url = Bundle.module.url(forResource: "echo-words", withExtension: "sh",
                                          subdirectory: "Fixtures") else {
            fatalError("Tests/Fixtures/echo-words.sh missing")
        }
        self.executableURL = url
    }

    func resolveExecutable() -> URL? { executableURL }

    func argumentsForRequest(_ request: AdapterRequest) -> [String] {
        []
    }

    func stdinForRequest(_ request: AdapterRequest) -> Data? {
        Data(PromptComposer.composePlain(request).utf8)
    }
}
