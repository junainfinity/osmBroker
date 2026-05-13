import Foundation
import Darwin

/// PRD §7 — flag port conflicts BEFORE attempting to start the broker so the
/// UI can surface the conflict inline and suggest an alternate port.
public enum PortPreflight {

    public enum Status: Equatable, Sendable {
        case free
        case inUse                      // EADDRINUSE
        case invalidHost                // EAI_NONAME / parse failure
        case permissionDenied           // EACCES — port < 1024 without privs
        case other(errno: Int32)
    }

    /// Try to bind a SOCK_STREAM TCP socket on (host, port). Close immediately.
    /// Returns `Status.free` only if bind succeeds.
    public static func check(host: String, port: Int) -> Status {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_flags = AI_PASSIVE

        var result: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        let rc = getaddrinfo(host, portStr, &hints, &result)
        guard rc == 0, let info = result else {
            return .invalidHost
        }
        defer { freeaddrinfo(result) }

        var addr: UnsafeMutablePointer<addrinfo>? = info
        while let cur = addr {
            let entry = cur.pointee
            let fd = socket(entry.ai_family, entry.ai_socktype, entry.ai_protocol)
            if fd < 0 { addr = entry.ai_next; continue }
            // SO_REUSEADDR — match what NIO uses, so a free port appears free.
            var yes: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
            let bindRC = bind(fd, entry.ai_addr, entry.ai_addrlen)
            let bindErr = errno
            close(fd)
            if bindRC == 0 {
                return .free
            }
            switch bindErr {
            case EADDRINUSE:    return .inUse
            case EACCES:        return .permissionDenied
            default:            addr = entry.ai_next
            }
        }
        return .other(errno: errno)
    }

    /// Suggest the next free port after `start`, scanning up to `range`. Used
    /// by the UI when a port conflict is reported (PRD §7 — "suggest an
    /// available alternative").
    public static func suggestAlternate(host: String, after start: Int, range: Int = 20) -> Int? {
        for offset in 1...range {
            let candidate = start + offset
            if candidate > 65535 { return nil }
            if case .free = check(host: host, port: candidate) {
                return candidate
            }
        }
        return nil
    }
}
