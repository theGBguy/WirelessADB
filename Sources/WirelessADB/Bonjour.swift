import Foundation

struct FoundService { let name: String; let host: String; let port: Int }

/// Browses a Bonjour service type (e.g. `_adb-tls-pairing._tcp.`) and reports resolved IPv4 endpoints.
final class ServiceFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var pending: [NetService] = []
    private let type: String
    var onFound: ((FoundService) -> Void)?

    init(type: String) {
        self.type = type
        super.init()
        browser.delegate = self
    }

    func start() { browser.searchForServices(ofType: type, inDomain: "local.") }
    func stop() { browser.stop(); pending.forEach { $0.stop() }; pending.removeAll() }

    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        pending.append(s)
        s.delegate = self
        s.resolve(withTimeout: 10)
    }

    func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
        pending.removeAll { $0 == s }
    }

    func netServiceDidResolveAddress(_ s: NetService) {
        guard let host = s.addresses?.lazy.compactMap(Self.ipv4).first, s.port > 0 else { return }
        onFound?(FoundService(name: s.name, host: host, port: s.port))
    }

    private static func ipv4(_ data: Data) -> String? {
        data.withUnsafeBytes { raw -> String? in
            guard let base = raw.baseAddress, raw.count >= MemoryLayout<sockaddr_in>.size,
                  base.assumingMemoryBound(to: sockaddr.self).pointee.sa_family == sa_family_t(AF_INET)
            else { return nil }
            var addr = base.assumingMemoryBound(to: sockaddr_in.self).pointee.sin_addr
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            guard inet_ntop(AF_INET, &addr, &buf, socklen_t(INET_ADDRSTRLEN)) != nil else { return nil }
            return String(cString: buf)
        }
    }
}
