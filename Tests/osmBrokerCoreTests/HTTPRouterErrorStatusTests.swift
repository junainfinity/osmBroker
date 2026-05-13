import XCTest
import NIOHTTP1
@testable import osmBrokerCore

/// `HTTPRouter.httpStatusForErrorType` is the bridge between adapter-level
/// error types (strings like "invalid_request_error") and the actual HTTP
/// status the broker returns. Before the fix the broker always returned 500
/// for any adapter error; now it picks the right code so clients can branch
/// on it.
final class HTTPRouterErrorStatusTests: XCTestCase {

    func testInvalidRequestIs400() {
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "invalid_request_error", code: "model_not_supported"
        ), .badRequest)
    }

    func testAuthenticationIs401() {
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "authentication_error", code: "cli_not_authenticated"
        ), .unauthorized)
    }

    func testPermissionIs403() {
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "permission_error", code: "cli_forbidden"
        ), .forbidden)
    }

    func testModelNotFoundIs404() {
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "model_not_found", code: nil
        ), .notFound)
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "not_found_error", code: nil
        ), .notFound)
    }

    func testRateLimitIs429() {
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "rate_limit_exceeded", code: nil
        ), .tooManyRequests)
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "insufficient_quota", code: nil
        ), .tooManyRequests)
    }

    func testUnknownTypeFallsThroughTo500() {
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "some_unknown_error_type", code: nil
        ), .internalServerError)
        XCTAssertEqual(HTTPRequestRouter.httpStatusForErrorType(
            type: "internal_server_error", code: nil
        ), .internalServerError)
    }
}
