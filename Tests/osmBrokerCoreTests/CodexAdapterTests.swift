import XCTest
@testable import osmBrokerCore

final class CodexAdapterTests: XCTestCase {

    // MARK: - argv contract

    func testCodexArgvHasNoPrompt() {
        let adapter = CodexAdapter()
        let req = AdapterRequest(
            model: "gpt-5-codex",
            messages: [.init(role: "user", content: "SECRET_CODEX_PROMPT_X9F")],
            stream: true
        )
        let argv = adapter.argumentsForRequest(req)
        XCTAssertEqual(argv.first, "exec")
        XCTAssertTrue(argv.contains("--json"))
        XCTAssertTrue(argv.contains("--skip-git-repo-check"))
        XCTAssertTrue(argv.contains("-m"))
        XCTAssertTrue(argv.contains("gpt-5-codex"))
        XCTAssertFalse(argv.contains { $0.contains("SECRET_CODEX_PROMPT_X9F") },
                       "SPAWN-1: prompt must not be in argv")
    }

    func testCodexStdinHasPrompt() {
        let adapter = CodexAdapter()
        let req = AdapterRequest(
            model: "gpt-5",
            messages: [.init(role: "user", content: "compute 2+2")],
            stream: false
        )
        let stdin = adapter.stdinForRequest(req)
        let s = String(data: stdin ?? Data(), encoding: .utf8) ?? ""
        XCTAssertEqual(s, "compute 2+2",
                       "single-user-message should be sent verbatim, no markers")
    }

    func testCodexComposerMultiTurn() {
        let body = CodexAdapter.composeForCodex([
            .init(role: "system", content: "be terse"),
            .init(role: "user", content: "hi"),
            .init(role: "assistant", content: "hello"),
            .init(role: "user", content: "go"),
        ])
        XCTAssertTrue(body.contains("System note: be terse"))
        XCTAssertTrue(body.contains("Assistant said: hello"))
        XCTAssertTrue(body.contains("hi"))
        XCTAssertTrue(body.contains("go"))
    }

    // MARK: - JSONL parser

    func testParserAgentMessageBecomesTextDelta() {
        let line = #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"4"}}"#
        guard case .textDelta(let s) = CodexAdapter.parseLine(line) else {
            return XCTFail("expected textDelta")
        }
        XCTAssertEqual(s, "4")
    }

    func testParserAgentMessageWithMultilineText() {
        let line = #"{"type":"item.completed","item":{"type":"agent_message","text":"line1\nline2"}}"#
        guard case .textDelta(let s) = CodexAdapter.parseLine(line) else {
            return XCTFail("expected textDelta")
        }
        XCTAssertEqual(s, "line1\nline2")
    }

    func testParserNonAgentItemIgnored() {
        let line = #"{"type":"item.completed","item":{"type":"tool_call","name":"shell"}}"#
        XCTAssertNil(CodexAdapter.parseLine(line))
    }

    func testParserThreadStartedIgnored() {
        let line = #"{"type":"thread.started","thread_id":"abc"}"#
        XCTAssertNil(CodexAdapter.parseLine(line))
    }

    func testParserTurnStartedIgnored() {
        let line = #"{"type":"turn.started"}"#
        XCTAssertNil(CodexAdapter.parseLine(line))
    }

    func testParserTurnCompletedIgnored() {
        let line = #"{"type":"turn.completed","usage":{"input_tokens":1}}"#
        XCTAssertNil(CodexAdapter.parseLine(line))
    }

    func testParserErrorEventBecomesAdapterError() {
        let line = #"{"type":"error","message":"quota exceeded"}"#
        guard case .error(let msg, _, _) = CodexAdapter.parseLine(line) else {
            return XCTFail("expected error event")
        }
        XCTAssertEqual(msg, "quota exceeded")
    }

    func testParserGarbageReturnsNil() {
        XCTAssertNil(CodexAdapter.parseLine("not json"))
        XCTAssertNil(CodexAdapter.parseLine(""))
        XCTAssertNil(CodexAdapter.parseLine("Reading prompt from stdin..."))
        XCTAssertNil(CodexAdapter.parseLine("{ malformed }"))
    }

    // MARK: - Live system test (skipped when codex is missing)

    func testLiveCodexSimpleInference() async throws {
        guard CLIDetector.resolveOnPath("codex") != nil else {
            throw XCTSkip("codex not installed on this machine")
        }
        let adapter = CodexAdapter()
        let registry = ProcessRegistry()
        let req = AdapterRequest(
            model: "gpt-5.5",   // matches the default in `~/.codex/config.toml`
            messages: [.init(role: "user",
                             content: "Reply with exactly one word: pong.")],
            stream: true
        )
        let child: ChildHandle
        do {
            child = try await adapter.spawn(req, registry: registry)
        } catch {
            throw XCTSkip("spawn failed; codex may not be authenticated: \(error)")
        }

        var collected = ""
        var sawFinish = false
        for await event in adapter.events(stdout: child.stdout,
                                          stderr: child.stderr,
                                          exit: child.exit) {
            switch event {
            case .start:                break
            case .textDelta(let s):     collected += s
            case .finish:               sawFinish = true
            case .error(let m, _, _):
                throw XCTSkip("codex returned error (likely auth/quota): \(m)")
            }
            if sawFinish { break }
        }

        XCTAssertTrue(sawFinish, "stream did not finish cleanly")
        XCTAssertFalse(collected.isEmpty,
                       "codex returned empty text; check ~/.codex auth & quota")
        // The model was instructed to say "pong" only, but we don't fail the
        // test on disobedience — just on emptiness. Print for visibility.
        print("\n=== Codex live response ===\n\(collected)\n===========================\n")
    }
}
