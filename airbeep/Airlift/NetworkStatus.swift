import AirliftFFI
import Darwin
import Foundation

/// Local interface enumeration via `getifaddrs`.
///
/// Everything here is read from the interface table only — deterministic and
/// offline, with no route probes or test connections.
enum NetworkStatus {
    struct Interface {
        let name: String
        let ipv4: String
        let isUp: Bool
        let isRunning: Bool
    }

    /// All IPv4 interfaces, in system order.
    static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let current = cursor {
            defer { cursor = current.pointee.ifa_next }
            guard let addr = current.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard let ipv4 = numericHost(addr) else { continue }
            let flags = current.pointee.ifa_flags
            result.append(
                Interface(
                    name: String(cString: current.pointee.ifa_name),
                    ipv4: ipv4,
                    isUp: flags & UInt32(IFF_UP) != 0,
                    isRunning: flags & UInt32(IFF_RUNNING) != 0
                )
            )
        }
        return result
    }

    private static func numericHost(_ addr: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let length = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }
        return String(cString: host)
    }

    static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec")
            || name.hasPrefix("tap") || name.hasPrefix("ppp")
    }

    /// Wi-Fi is carrying traffic. `en0` is Wi-Fi on both iPhone and iPad
    /// (cellular shows up as `pdp_ip*`). The interface flags matter more than
    /// mere presence, since a stale `en0` entry can linger after Wi-Fi drops.
    static var wifiActive: Bool {
        interfaces().contains { $0.name == "en0" && $0.isUp && $0.isRunning }
    }

    /// A loopback VPN tunnel is up (LocalDevVPN, SideStore WireGuard, …).
    static var loopbackTunnelActive: Bool {
        interfaces().contains { isTunnelInterface($0.name) && $0.isUp && $0.isRunning }
    }

    /// The tunnel's own address, for the runtime log and setup screen. This
    /// is *not* a dial target — in a loopback VPN the device RSD endpoint is
    /// the peer address, typically the tunnel address with the last octet
    /// decremented.
    static var tunnelInterfaceAddress: String? {
        interfaces().first { isTunnelInterface($0.name) && $0.isUp && $0.isRunning }?.ipv4
    }

    /// Extra candidate hosts for the Rust core. Tunnel interfaces are excluded
    /// on purpose: dialing our own tunnel address reaches the wrong end of a
    /// loopback VPN. Non-tunnel addresses cover the case where the tunnel
    /// listener yields a port but no host. Wi-Fi first.
    static func tunnelHostCandidates() -> [String] {
        let usable = interfaces().filter {
            !isTunnelInterface($0.name) && !$0.ipv4.hasPrefix("127.") && $0.isUp && $0.isRunning
        }
        var result: [String] = []
        for iface in usable where iface.name == "en0" {
            if !result.contains(iface.ipv4) { result.append(iface.ipv4) }
        }
        for iface in usable where iface.name != "en0" {
            if !result.contains(iface.ipv4) { result.append(iface.ipv4) }
        }
        return result
    }

    /// Push the configured host plus runtime interface candidates into the
    /// Rust core, so tunnel dials adapt to the current network configuration.
    /// The configured host stays primary; the Rust side appends its own
    /// built-in LocalDevVPN fallbacks after our candidates.
    static func syncTargetHostsToAirlift() {
        // The user's Advanced-settings override wins over the build-time value.
        let configured = TargetHostConfig.effective
        let isCustom = TargetHostConfig.isCustomized
        if !configured.isEmpty {
            _ = configured.withCString { al_set_target_host($0) }
        }

        var candidates = tunnelHostCandidates()
        if !configured.isEmpty && !candidates.contains(configured) {
            candidates.insert(configured, at: 0)
        }
        AirBeepLog.shared.append(
            "network: target=\(configured)\(isCustom ? " (custom)" : "") "
                + "candidates=\(candidates.isEmpty ? "none" : candidates.joined(separator: ",")) "
                + "wifi=\(wifiActive) tunnel=\(tunnelInterfaceAddress ?? "down")"
        )

        // al_set_target_hosts copies the strings; strdup keeps them alive for
        // the duration of the call and free() releases them right after.
        let cStrings = candidates.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var pointers = cStrings.map { UnsafePointer($0) }
        pointers.withUnsafeBufferPointer { buffer in
            if let base = buffer.baseAddress {
                _ = al_set_target_hosts(base, buffer.count)
            }
        }
    }
}
