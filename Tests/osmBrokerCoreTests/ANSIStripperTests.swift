import XCTest
@testable import osmBrokerCore

final class ANSIStripperTests: XCTestCase {

    // MARK: - One-shot stripping

    func testPlainTextPassThrough() {
        XCTAssertEqual(ANSIStripper.strip("hello world"), "hello world")
    }

    func testEmptyString() {
        XCTAssertEqual(ANSIStripper.strip(""), "")
    }

    func testStripsSGRColor() {
        let red = "\u{1B}[31mred\u{1B}[0m"
        XCTAssertEqual(ANSIStripper.strip(red), "red")
    }

    func testStripsMultipleSGR() {
        let s = "\u{1B}[1;31mBold red\u{1B}[0m and \u{1B}[32mgreen\u{1B}[0m"
        XCTAssertEqual(ANSIStripper.strip(s), "Bold red and green")
    }

    func testStripsCursorMovement() {
        // Cursor up 3, cursor right 5, clear line — all CSI sequences.
        let s = "\u{1B}[3A\u{1B}[5Cfoo\u{1B}[K"
        XCTAssertEqual(ANSIStripper.strip(s), "foo")
    }

    func testStripsOSCWindowTitle() {
        // OSC 0 sets window title, terminated by BEL.
        let s = "\u{1B}]0;my title\u{07}content"
        XCTAssertEqual(ANSIStripper.strip(s), "content")
    }

    func testProgressSpinnerCRRedraw() {
        // Common spinner pattern: line content, CR, new line content.
        // Result should only retain whatever followed the last CR before any LF.
        let s = "Loading 10%\rLoading 50%\rLoading 100%\n"
        XCTAssertEqual(ANSIStripper.strip(s), "Loading 100%\n")
    }

    func testBackspaceErasesPrevious() {
        let s = "abc\u{08}d"
        XCTAssertEqual(ANSIStripper.strip(s), "abd")
    }

    func testBELDropped() {
        let s = "ding\u{07}"
        XCTAssertEqual(ANSIStripper.strip(s), "ding")
    }

    func testRunawayCSIBoundedRecovery() {
        // 200 bytes of param bytes with no terminator — should not append them
        // to output; state should recover when something > 128 chars happens.
        let runaway = "\u{1B}[" + String(repeating: ";", count: 200) + "Z"
        let result = ANSIStripper.strip(runaway)
        XCTAssertFalse(result.contains(";"))
        XCTAssertEqual(result, "")
    }

    // MARK: - Streaming (chunked) stripping

    func testStreamingSplitEscape() {
        var s = ANSIStripper.Stripper()
        // Split the escape across two chunks.
        let a = s.append("hello \u{1B}")
        let b = s.append("[31mworld\u{1B}[0m!")
        XCTAssertEqual(a + b, "hello world!")
    }

    func testStreamingSplitOSC() {
        var s = ANSIStripper.Stripper()
        let a = s.append("\u{1B}]0;tit")
        let b = s.append("le\u{07}body")
        XCTAssertEqual(a + b, "body")
    }

    func testStreamingResetClearsPartialState() {
        var s = ANSIStripper.Stripper()
        _ = s.append("text \u{1B}[")
        s.reset()
        let after = s.append("more text")
        XCTAssertEqual(after, "more text")
    }
}
