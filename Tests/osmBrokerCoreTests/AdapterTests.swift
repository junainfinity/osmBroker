import XCTest
@testable import osmBrokerCore

final class AdapterTests: XCTestCase {

    // MARK: - PromptComposer

    func testComposePlainSingleUser() {
        let r = AdapterRequest(
            model: "m",
            messages: [.init(role: "user", content: "hello")],
            stream: false
        )
        XCTAssertEqual(PromptComposer.composePlain(r), "[USER]\nhello")
    }

    func testComposePlainSystemPlusUser() {
        let r = AdapterRequest(
            model: "m",
            messages: [
                .init(role: "system", content: "be terse"),
                .init(role: "user", content: "ping")
            ],
            stream: false
        )
        let out = PromptComposer.composePlain(r)
        XCTAssertTrue(out.contains("[SYSTEM]\nbe terse"))
        XCTAssertTrue(out.contains("[USER]\nping"))
        // System appears before user.
        XCTAssertLessThan(out.range(of: "[SYSTEM]")!.lowerBound,
                          out.range(of: "[USER]")!.lowerBound)
    }

    func testComposeAssistantTurnsKept() {
        let r = AdapterRequest(
            model: "m",
            messages: [
                .init(role: "user", content: "Q1"),
                .init(role: "assistant", content: "A1"),
                .init(role: "user", content: "Q2")
            ],
            stream: false
        )
        let out = PromptComposer.composePlain(r)
        XCTAssertTrue(out.contains("[ASSISTANT]\nA1"))
    }

    // MARK: - ClaudeAdapter buildArguments

    func testClaudeAdapterArgvHasModelButNotPrompt() {
        let adapter = ClaudeAdapter()
        let request = AdapterRequest(
            model: "sonnet",                 // alias per [[Claude-Model-Discovery]]
            messages: [.init(role: "user", content: "SECRET_PROMPT_TOKEN")],
            stream: true
        )
        let argv = adapter.argumentsForRequest(request)
        XCTAssertEqual(argv, ["-p", "--model", "sonnet"])
        XCTAssertFalse(argv.contains { $0.contains("SECRET_PROMPT_TOKEN") },
                       "SPAWN-1: prompt must not be in argv; got \(argv)")
    }

    func testClaudeAdapterStdinCarriesPrompt() {
        let adapter = ClaudeAdapter()
        let request = AdapterRequest(
            model: "sonnet",
            messages: [.init(role: "user", content: "hello world")],
            stream: true
        )
        let stdin = adapter.stdinForRequest(request)
        let s = String(data: stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("hello world"))
    }

    // MARK: - End-to-end against fake adapter

    func testFakeEchoAdapterRoundTrip() async throws {
        let adapter = FakeEchoAdapter()
        let registry = ProcessRegistry()
        let request = AdapterRequest(
            model: "fake-echo-1",
            messages: [.init(role: "user", content: "alpha beta gamma")],
            stream: true
        )

        let child = try await adapter.spawn(request, registry: registry)

        var events: [AdapterEvent] = []
        for await event in adapter.events(stdout: child.stdout,
                                          stderr: child.stderr,
                                          exit: child.exit) {
            events.append(event)
            if case .finish = event { break }
        }

        // We expect: .start, several .textDelta, then .finish(reason: "stop").
        XCTAssertEqual(events.first, .start)
        guard case .finish(let reason)? = events.last else {
            return XCTFail("expected .finish, got \(String(describing: events.last))")
        }
        XCTAssertEqual(reason, "stop")

        let combinedText = events.compactMap { event -> String? in
            if case .textDelta(let s) = event { return s } else { return nil }
        }.joined()
        // The composed prompt is `[USER]\nalpha beta gamma`. Echo splits on
        // whitespace so we should see those tokens emitted.
        XCTAssertTrue(combinedText.contains("alpha"))
        XCTAssertTrue(combinedText.contains("beta"))
        XCTAssertTrue(combinedText.contains("gamma"))
    }

    // MARK: - ErrorMapping

    func testErrorMappingQuota() {
        XCTAssertEqual(ErrorMapping.classify("OpenAI API: Quota exceeded for org_x").httpStatus,
                       429)
    }

    func testErrorMappingRateLimit() {
        XCTAssertEqual(ErrorMapping.classify("Rate limit hit, retry in 30s").httpStatus, 429)
    }

    func testErrorMappingPleaseLogin() {
        let r = ErrorMapping.classify("Please login to continue.")
        XCTAssertEqual(r.httpStatus, 401)
        XCTAssertEqual(r.code, "cli_not_authenticated")
    }

    func testErrorMappingNotSupportedIs400() {
        // Codex emits this for models the user's account tier can't reach.
        // The broker should propagate as 400 (invalid_request_error), not 500.
        let raw = #"The 'gpt-5' model is not supported when using Codex with a ChatGPT account."#
        let r = ErrorMapping.classify(raw)
        XCTAssertEqual(r.httpStatus, 400)
        XCTAssertEqual(r.type, "invalid_request_error")
        XCTAssertEqual(r.code, "model_not_supported")
    }

    func testErrorMappingGenericFallback() {
        XCTAssertEqual(ErrorMapping.classify("undocumented goof").httpStatus, 500)
    }
}
