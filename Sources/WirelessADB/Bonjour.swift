import Foundation
import os

let log = Logger(subsystem: "io.github.thegbguy.wirelessadb", category: "adb")

struct FoundService: Equatable { let name: String; let host: String; let port: Int }

/// Browses a Bonjour service type (e.g. `_adb-tls-pairing._tcp.`) and reports resolved IPv4 endpoints.
/// Retries failed resolves, reports removals, and can be restarted (e.g. after wake).
final class ServiceFinder: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private var browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]
    private var attempts: [String: Int] = [:]
    private let type: String
    private var running = false
    var onFound: ((FoundService) -> Void)?
    var onRemoved: ((String) -> Void)?

    init(type: String) {
        self.type = type
        super.init()
    }

    func start() {
        running = true
        browser = NetServiceBrowser()
        browser.delegate = self
        browser.searchForServices(ofType: type, inDomain: "local.")
    }

    func stop() {
        running = false
        browser.stop()
        services.values.forEach { $0.stop() }
        services.removeAll()
        attempts.removeAll()
    }

    func restart() { stop(); start() }

    func netServiceBrowser(_ b: NetServiceBrowser, didFind s: NetService, moreComing: Bool) {
        log.debug("found \(self.type, privacy: .public) \(s.name, privacy: .public)")
        services[s.name]?.stop()
        services[s.name] = s
        attempts[s.name] = 0
        s.delegate = self
        s.resolve(withTimeout: 10)
    }

    func netServiceBrowser(_ b: NetServiceBrowser, didRemove s: NetService, moreComing: Bool) {
        log.debug("removed \(s.name, privacy: .public)")
        services[s.name]?.stop()
        services[s.name] = nil
        attempts[s.name] = nil
        onRemoved?(s.name)
    }

    func netServiceBrowser(_ b: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        log.error("browse \(self.type, privacy: .public) failed: \(errorDict, privacy: .public)")
        retryBrowse()
    }

    func netServiceBrowserDidStopSearch(_ b: NetServiceBrowser) {
        // Unexpected stops (sleep, network change) — browse again.
        if running && b === browser { retryBrowse() }
    }

    private func retryBrowse() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.running else { return }
            self.start()
        }
    }

    func netServiceDidResolveAddress(_ s: NetService) {
        let ips = s.addresses?.compactMap(Self.ipv4) ?? []
        // Prefer routable addresses over link-local 169.254.x.x.
        guard let host = ips.first(where: { !$0.hasPrefix("169.254.") }) ?? ips.first, s.port > 0 else { return }
        log.info("resolved \(s.name, privacy: .public) -> \(host, privacy: .public):\(s.port)")
        onFound?(FoundService(name: s.name, host: host, port: s.port))
    }

    func netService(_ s: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let n = (attempts[s.name] ?? 0) + 1
        attempts[s.name] = n
        log.error("resolve \(s.name, privacy: .public) failed (\(n)): \(errorDict, privacy: .public)")
        guard n < 5 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(n) * 2) { [weak self] in
            guard let self, self.services[s.name] === s else { return }
            s.resolve(withTimeout: 10)
        }
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
