import Foundation
import Darwin

/// LAN-facing IPv4 discovery. We walk `getifaddrs(3)` and return non-loopback,
/// non-link-local IPv4 addresses on real interfaces.
public enum NetworkInfo {
    public struct Interface: Equatable, Sendable {
        public let name: String
        public let ipv4: String

        public init(name: String, ipv4: String) {
            self.name = name
            self.ipv4 = ipv4
        }
    }

    /// All non-loopback IPv4 addresses, in `getifaddrs` order.
    public static func ipv4Interfaces() -> [Interface] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let start = head else { return [] }
        defer { freeifaddrs(head) }

        var results: [Interface] = []
        var ptr: UnsafeMutablePointer<ifaddrs>? = start
        while let cur = ptr {
            let entry = cur.pointee
            defer { ptr = entry.ifa_next }

            guard let saAddr = entry.ifa_addr else { continue }
            guard saAddr.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let ifname = String(cString: entry.ifa_name)
            if ifname == "lo0" { continue }                       // skip loopback
            if entry.ifa_flags & UInt32(IFF_UP) == 0 { continue } // skip down interfaces

            var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let code = getnameinfo(
                saAddr,
                socklen_t(saAddr.pointee.sa_len),
                &hostBuf, socklen_t(hostBuf.count),
                nil, 0,
                NI_NUMERICHOST
            )
            guard code == 0 else { continue }
            let ip = String(cString: hostBuf)
            if ip.hasPrefix("169.254.") { continue }              // skip link-local
            if ip == "0.0.0.0" { continue }

            results.append(Interface(name: ifname, ipv4: ip))
        }
        return results
    }

    /// Best guess for the address other hosts on the LAN should reach us on.
    /// Prefers `en0` (Wi-Fi/Ethernet on Apple Silicon laptops), then `en1`,
    /// then any remaining interface that isn't a virtual bridge/awdl/utun.
    public static func primaryLANAddress() -> String? {
        let all = ipv4Interfaces()
        if let en0 = all.first(where: { $0.name == "en0" }) { return en0.ipv4 }
        if let en1 = all.first(where: { $0.name == "en1" }) { return en1.ipv4 }
        let real = all.first { iface in
            !iface.name.hasPrefix("utun") &&
            !iface.name.hasPrefix("awdl") &&
            !iface.name.hasPrefix("llw") &&
            !iface.name.hasPrefix("bridge") &&
            !iface.name.hasPrefix("anpi") &&
            !iface.name.hasPrefix("ap")
        }
        return real?.ipv4
    }
}
