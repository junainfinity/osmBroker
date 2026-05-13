import Foundation

/// PRD §7 — translate CLI error output ("Quota exceeded", "Please login", etc.)
/// into typed responses for the client. We keep the patterns small and well-
/// tested; misclassification is fine (we fall back to a generic 500).
public enum ErrorMapping {

    public struct Result: Equatable, Sendable {
        public let httpStatus: Int
        public let type: String
        public let message: String
        public let code: String?
    }

    /// Patterns are checked in order. First match wins.
    private static let patterns: [(needle: String, result: Result)] = [
        ("quota exceeded", Result(
            httpStatus: 429, type: "insufficient_quota",
            message: "Underlying CLI reports quota exceeded.",
            code: "insufficient_quota"
        )),
        ("rate limit", Result(
            httpStatus: 429, type: "rate_limit_exceeded",
            message: "Underlying CLI hit a rate limit.",
            code: "rate_limit_exceeded"
        )),
        ("please login", Result(
            httpStatus: 401, type: "authentication_error",
            message: "Underlying CLI is not authenticated. Run the CLI's login command.",
            code: "cli_not_authenticated"
        )),
        ("not logged in", Result(
            httpStatus: 401, type: "authentication_error",
            message: "Underlying CLI is not authenticated. Run the CLI's login command.",
            code: "cli_not_authenticated"
        )),
        ("unauthorized", Result(
            httpStatus: 401, type: "authentication_error",
            message: "Underlying CLI returned 401 Unauthorized.",
            code: "cli_unauthorized"
        )),
        ("forbidden", Result(
            httpStatus: 403, type: "permission_error",
            message: "Underlying CLI returned 403 Forbidden.",
            code: "cli_forbidden"
        )),
        ("model not found", Result(
            httpStatus: 404, type: "model_not_found",
            message: "Underlying CLI does not recognize the requested model.",
            code: "model_not_found"
        )),
        ("not supported", Result(
            // Codex emits this for models the user's account-tier can't reach
            // (e.g. gpt-5/gpt-5-codex/gpt-5-mini on a ChatGPT-account install).
            // It's a configuration / account-tier issue, not an internal error.
            httpStatus: 400, type: "invalid_request_error",
            message: "Underlying CLI rejected this model: not supported on this account.",
            code: "model_not_supported"
        ))
    ]

    public static func classify(_ stderr: String) -> Result {
        let lower = stderr.lowercased()
        for (needle, result) in patterns {
            if lower.contains(needle) { return result }
        }
        return Result(
            httpStatus: 500,
            type: "internal_server_error",
            message: "Underlying CLI exited with an error.",
            code: nil
        )
    }
}
