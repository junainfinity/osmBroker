import Foundation

/// Bearer-token authentication for inbound HTTP requests.
///
/// PRD §3.5 — "If the `Authorization: Bearer <Key>` header does not match the
/// user-defined string, it drops the connection with a 401 Unauthorized."
///
/// Security rules implemented here:
/// - AUTH-1/2: parse bearer + reject when missing/wrong
/// - AUTH-3: constant-time byte comparison
/// - AUTH-4 / LOG-2: redaction helper for logger sites
/// - AUTH-5: configure-time check that empty keys are rejected
///
/// See [[Security-Requirements]] for the full rule set.
public enum Auth {

    public enum Outcome: Equatable {
        case ok
        case missing
        case malformed
        case wrong
    }

    /// Compare an `Authorization` header to the configured key. Constant-time
    /// to defeat trivial timing oracles. Treats absent / malformed as failure.
    public static func check(authorizationHeader: String?, expecting key: String) -> Outcome {
        guard !key.isEmpty else {
            // AUTH-5: a misconfigured server must never authorize.
            // Fail closed.
            return .wrong
        }
        guard let header = authorizationHeader, !header.isEmpty else {
            return .missing
        }
        guard let presented = parseBearer(header) else {
            return .malformed
        }
        return constantTimeEquals(presented, key) ? .ok : .wrong
    }

    /// Extract the token portion of `Bearer <token>`. Case-insensitive on the
    /// scheme keyword. Returns nil if the header isn't a Bearer credential.
    public static func parseBearer(_ header: String) -> String? {
        // Allow leading whitespace per RFC 7235.
        let trimmed = header.drop { $0 == " " || $0 == "\t" }
        let scheme = "Bearer "
        guard trimmed.count > scheme.count else { return nil }
        let head = trimmed.prefix(scheme.count)
        guard head.lowercased() == scheme.lowercased() else { return nil }
        let token = trimmed.dropFirst(scheme.count)
            .trimmingCharacters(in: .whitespaces)
        return token.isEmpty ? nil : token
    }

    /// Constant-time byte comparison. Iterates the longer string in full so
    /// total work is independent of where bytes diverge. Returns false when
    /// lengths differ but still does a full sweep (no short-circuit).
    public static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8)
        let bb = Array(b.utf8)
        // We always iterate `max(ab.count, bb.count)` so the work — and the
        // wall-clock — doesn't depend on prefix-equal length.
        let n = max(ab.count, bb.count)
        var diff: UInt8 = ab.count == bb.count ? 0 : 1
        for i in 0..<n {
            let x = i < ab.count ? ab[i] : 0
            let y = i < bb.count ? bb[i] : 0
            diff |= x ^ y
        }
        return diff == 0
    }

    /// Replace any `Authorization: Bearer …` value with `Bearer ***` for safe
    /// logging. Also handles lowercase header name. Does not mutate other
    /// headers.
    ///
    /// LOG-2.
    public static func redactAuthorization(_ input: String) -> String {
        // Case-insensitive search for "authorization:"; replace whatever
        // follows on the same line. We don't try to be clever about the
        // exact bearer format — anything sensitive on the right of the colon
        // becomes "***".
        let lines = input.split(separator: "\n", omittingEmptySubsequences: false)
        let replaced = lines.map { line -> Substring in
            let lower = line.lowercased()
            if let range = lower.range(of: "authorization:") {
                let colonEnd = line.index(line.startIndex,
                                          offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))
                let prefix = line[..<colonEnd]
                // Detect Bearer to preserve the scheme keyword for readability.
                let rest = line[colonEnd...]
                if rest.lowercased().contains("bearer") {
                    return prefix + " Bearer ***"
                } else {
                    return prefix + " ***"
                }
            }
            return line
        }
        return replaced.joined(separator: "\n")
    }
}
