import XCTest
@testable import osmBrokerCore

final class AuthTests: XCTestCase {

    // MARK: - check()

    func testNoHeaderIsMissing() {
        XCTAssertEqual(Auth.check(authorizationHeader: nil, expecting: "secret"),
                       .missing)
        XCTAssertEqual(Auth.check(authorizationHeader: "", expecting: "secret"),
                       .missing)
    }

    func testNonBearerSchemeMalformed() {
        XCTAssertEqual(Auth.check(authorizationHeader: "Basic abc", expecting: "s"),
                       .malformed)
        XCTAssertEqual(Auth.check(authorizationHeader: "abc", expecting: "s"),
                       .malformed)
    }

    func testCaseInsensitiveScheme() {
        XCTAssertEqual(Auth.check(authorizationHeader: "bearer secret", expecting: "secret"),
                       .ok)
        XCTAssertEqual(Auth.check(authorizationHeader: "BEARER secret", expecting: "secret"),
                       .ok)
    }

    func testWrongTokenWrong() {
        XCTAssertEqual(Auth.check(authorizationHeader: "Bearer nope", expecting: "secret"),
                       .wrong)
    }

    func testRightTokenOK() {
        XCTAssertEqual(Auth.check(authorizationHeader: "Bearer secret", expecting: "secret"),
                       .ok)
    }

    func testEmptyExpectedKeyFailsClosed() {
        // AUTH-5: empty/unset key must never authorize.
        XCTAssertEqual(Auth.check(authorizationHeader: "Bearer anything", expecting: ""),
                       .wrong)
    }

    func testLeadingWhitespaceTolerated() {
        XCTAssertEqual(Auth.check(authorizationHeader: "   Bearer secret", expecting: "secret"),
                       .ok)
    }

    // MARK: - parseBearer()

    func testParseBearerBasic() {
        XCTAssertEqual(Auth.parseBearer("Bearer abc"), "abc")
    }

    func testParseBearerTrailingWhitespace() {
        XCTAssertEqual(Auth.parseBearer("Bearer abc   "), "abc")
    }

    func testParseBearerEmptyTokenIsNil() {
        XCTAssertNil(Auth.parseBearer("Bearer "))
        XCTAssertNil(Auth.parseBearer("Bearer    "))
    }

    func testParseBearerWrongSchemeNil() {
        XCTAssertNil(Auth.parseBearer("Basic abc"))
    }

    // MARK: - constantTimeEquals()

    func testConstantTimeEqualsExactMatch() {
        XCTAssertTrue(Auth.constantTimeEquals("foo", "foo"))
    }

    func testConstantTimeEqualsDifferent() {
        XCTAssertFalse(Auth.constantTimeEquals("foo", "bar"))
    }

    func testConstantTimeEqualsDifferentLengths() {
        XCTAssertFalse(Auth.constantTimeEquals("foo", "foobar"))
        XCTAssertFalse(Auth.constantTimeEquals("foobar", "foo"))
    }

    func testConstantTimeEqualsEmpty() {
        XCTAssertTrue(Auth.constantTimeEquals("", ""))
        XCTAssertFalse(Auth.constantTimeEquals("a", ""))
    }

    /// Loose timing check — not a strict guarantee (run-to-run variance),
    /// but catches the obvious naive short-circuit `==` regression. We measure
    /// many comparisons of strings that differ only at the last byte vs. the
    /// first byte; the two means should be within a small ratio.
    func testConstantTimeEqualsTimingApprox() {
        let target = String(repeating: "x", count: 256) + "Z"
        let earlyDiff = "Y" + String(repeating: "x", count: 256)  // differs at index 0
        let lateDiff  = String(repeating: "x", count: 256) + "Y"  // differs at last index

        let iterations = 50_000

        let earlyTime = measureNanos {
            for _ in 0..<iterations { _ = Auth.constantTimeEquals(target, earlyDiff) }
        }
        let lateTime = measureNanos {
            for _ in 0..<iterations { _ = Auth.constantTimeEquals(target, lateDiff) }
        }

        let ratio = Double(max(earlyTime, lateTime)) / Double(max(min(earlyTime, lateTime), 1))
        // A naive `==` would hit ratio >> 10 because Swift String `==` short-
        // circuits at the first differing byte. We allow up to 3x slack to
        // tolerate CI jitter; if our compare ever short-circuits, this fails.
        XCTAssertLessThan(ratio, 3.0,
                          "constantTimeEquals appears to short-circuit (ratio \(ratio))")
    }

    private func measureNanos(_ block: () -> Void) -> UInt64 {
        let start = DispatchTime.now()
        block()
        return DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
    }

    // MARK: - redactAuthorization()

    func testRedactBearer() {
        let input = "Authorization: Bearer sk-supersecret-token\nContent-Type: application/json"
        let out = Auth.redactAuthorization(input)
        XCTAssertFalse(out.contains("sk-supersecret-token"))
        XCTAssertTrue(out.contains("Bearer ***"))
        XCTAssertTrue(out.contains("Content-Type: application/json"))
    }

    func testRedactCaseInsensitiveHeaderName() {
        let input = "authorization: Bearer abc"
        XCTAssertFalse(Auth.redactAuthorization(input).contains("abc"))
    }

    func testRedactNonBearerScheme() {
        let input = "Authorization: Basic abc=="
        let out = Auth.redactAuthorization(input)
        XCTAssertFalse(out.contains("abc=="))
        XCTAssertTrue(out.contains("Authorization: ***"))
    }

    func testRedactNoAuthHeaderPassthrough() {
        let input = "Content-Type: application/json"
        XCTAssertEqual(Auth.redactAuthorization(input), input)
    }
}
