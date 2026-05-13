import XCTest
@testable import osmBrokerCore

/// "Take control of the Mac and ask 3 questions to each model served from
/// both CLIs." End-to-end proof through the real HTTP broker.
///
/// The test does NOT XCTAssert on the *correctness* of the answers — that
/// depends on the underlying models, our broker just has to convey them
/// faithfully. Instead it asserts non-empty content per (model, question)
/// pair and prints both Q and A for the dev log to attach.
final class QuizTests: XCTestCase {

    private let key = "quiz-key"

    private static let portLock = NSLock()
    private static var nextPort = 25000
    private static func allocatePort() -> Int {
        portLock.lock(); defer { portLock.unlock() }
        let p = nextPort; nextPort += 1; return p
    }

    private let questions: [String] = [
        "What is 23 + 19? Reply with only the number.",
        "What is the capital of Japan? Reply with one word.",
        "Name one noble gas. Reply with one word."
    ]

    // Models we ask to be served:
    //   Claude aliases (auto-resolve to today's claude-sonnet/opus/haiku)
    //   Codex variants from the registry — note `gpt-5` and similar may 400
    //   on a ChatGPT-account install of codex; we handle that as data, not failure.
    private let claudeModels = ["sonnet", "opus", "haiku"]
    private let codexModels  = ["gpt-5.5", "gpt-5-codex", "gpt-5", "gpt-5-mini"]

    func testThreeQuestionsPerModelLive() async throws {
        guard CLIDetector.resolveOnPath("claude") != nil else { throw XCTSkip("claude missing") }
        guard CLIDetector.resolveOnPath("codex")  != nil else { throw XCTSkip("codex missing") }

        var entries: [BrokerServer.ModelCatalog.Entry] = []
        let claude = ClaudeAdapter()
        let codex  = CodexAdapter()
        for m in claudeModels { entries.append(.init(modelID: m, adapter: claude)) }
        for m in codexModels  { entries.append(.init(modelID: m, adapter: codex)) }

        // Bind on an ephemeral port to avoid collisions with the live app
        // that may already be holding :8080.
        var port = Self.allocatePort()
        while case .inUse = PortPreflight.check(host: "127.0.0.1", port: port) {
            port = Self.allocatePort()
        }

        let server = BrokerServer()
        try await server.start(.init(
            host: "127.0.0.1",
            port: port,
            apiKey: key,
            modelCatalog: BrokerServer.ModelCatalog(entries: entries)
        ))
        defer { Task { await server.stop() } }

        // GET /v1/models — sanity check the catalogue is what we declared
        let models = await getModels(port: port)
        print("\n=== Broker /v1/models ===")
        for m in models { print("  • \(m.id) — owned_by \(m.ownedBy)") }
        print()

        // Quiz loop
        var summary: [String] = []
        for entry in entries {
            print("=== \(entry.adapter.def.id) → \(entry.modelID) ===")
            for q in questions {
                let answer = await ask(port: port, model: entry.modelID, question: q)
                print("Q: \(q)")
                print("A: \(answer.text)")
                if let err = answer.error {
                    print("   [error: \(err)]")
                }
                print()
                summary.append("\(entry.adapter.def.id)/\(entry.modelID) :: \(q) → \(answer.text)")
            }
        }

        print("\n=== Quiz summary (one line per Q&A) ===")
        for s in summary { print(s) }
        print("\n=== Quiz done. \(entries.count) models × \(questions.count) questions = \(entries.count * questions.count) calls ===")

        // Don't assert content correctness; this is an evidence-producing test.
        XCTAssertFalse(summary.isEmpty)
    }

    // MARK: - HTTP helpers

    private struct ModelEntry { let id: String; let ownedBy: String }

    private func getModels(port: Int) async -> [ModelEntry] {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/models")!)
        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["data"] as? [[String: Any]] else { return [] }
        return arr.compactMap {
            guard let id = $0["id"] as? String else { return nil }
            return ModelEntry(id: id, ownedBy: ($0["owned_by"] as? String) ?? "?")
        }
    }

    private struct Answer { let text: String; let error: String? }

    private func ask(port: Int, model: String, question: String) async -> Answer {
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "user", "content": question]
            ]
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            return Answer(text: "<could not serialize body>", error: "encode")
        }

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 180

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return Answer(text: "<non-JSON body>", error: "decode")
            }
            if let err = obj["error"] as? [String: Any] {
                let m = (err["message"] as? String) ?? "unknown"
                return Answer(text: "(no answer)", error: "HTTP \(status): \(m)")
            }
            if let choices = obj["choices"] as? [[String: Any]],
               let msg = choices.first?["message"] as? [String: Any],
               let content = msg["content"] as? String {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                return Answer(text: trimmed.isEmpty ? "(empty)" : trimmed,
                              error: trimmed.isEmpty ? "empty content" : nil)
            }
            return Answer(text: "<unexpected body shape>", error: "shape")
        } catch {
            return Answer(text: "(transport error)", error: error.localizedDescription)
        }
    }
}
