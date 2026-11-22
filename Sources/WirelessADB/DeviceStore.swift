import Foundation

struct Device: Identifiable, Hashable {
    let serial: String
    let name: String
    /// All adb transports for this physical device (an mDNS name and an ip:port can coexist).
    var transports: [String]
    var id: String { serial }
    var wireless: Bool { Self.isWireless(serial) }
    static func isWireless(_ s: String) -> Bool { s.contains(":") || s.contains("._adb-tls-connect") }
}

/// "adb-R5CW90MFWHE-MPCVuF" -> "R5CW90MFWHE"
func hardwareSerial(fromServiceName name: String) -> String? {
    let parts = name.split(separator: "-")
    return parts.count >= 3 && parts[0] == "adb" ? String(parts[1]) : nil
}

@MainActor
final class DeviceStore: ObservableObject {
    @Published var devices: [Device] = []
    @Published var lastError: String?
    @Published var autoConnect: Bool = UserDefaults.standard.object(forKey: "autoConnect") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoConnect, forKey: "autoConnect") }
    }

    private let finder = ServiceFinder(type: "_adb-tls-connect._tcp.")
    private var discovered: [String: FoundService] = [:]   // keyed by service name
    private var timer: Timer?

    init() {
        if ADB.path == nil { lastError = "adb not found" }
        finder.onFound = { [weak self] svc in
            Task { @MainActor in
                guard let self else { return }
                self.discovered[svc.name] = svc
                if self.autoConnect { await self.connect(svc) }
            }
        }
        finder.start()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    func refresh() {
        Task {
            let r = await ADB.run(["devices", "-l"])
            guard r.status == 0 else { lastError = r.output; return }
            lastError = nil
            let all: [Device] = r.output.split(separator: "\n").dropFirst().compactMap { line in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 2, parts[1] == "device" else { return nil }
                let model = parts.first { $0.hasPrefix("model:") }?.dropFirst(6).replacingOccurrences(of: "_", with: " ")
                return Device(serial: parts[0], name: model ?? parts[0], transports: [parts[0]])
            }
            // Merge wireless transports that point at the same phone.
            var merged: [Device] = []
            var index: [String: Int] = [:]
            for d in all {
                let key = d.wireless ? "wifi:" + physicalKey(d.serial) : "usb:" + d.serial
                if let i = index[key] {
                    merged[i].transports.append(d.serial)
                } else {
                    index[key] = merged.count
                    merged.append(d)
                }
            }
            devices = merged
        }
    }

    private func physicalKey(_ serial: String) -> String {
        if serial.contains("._adb-tls-connect") {
            return hardwareSerial(fromServiceName: serial) ?? serial
        }
        if let svc = discovered.values.first(where: { "\($0.host):\($0.port)" == serial }) {
            return hardwareSerial(fromServiceName: svc.name) ?? serial
        }
        return serial.split(separator: ":").first.map(String.init) ?? serial   // fall back to IP
    }

    private var connecting: Set<String> = []

    func connect(_ svc: FoundService) async {
        guard !connecting.contains(svc.name) else { return }
        connecting.insert(svc.name); defer { connecting.remove(svc.name) }
        // adb's own mDNS backend usually auto-connects; give it a moment, then check fresh state.
        try? await Task.sleep(for: .seconds(3))
        if await ADB.isConnected(svc) { refresh(); return }
        _ = await ADB.run(["connect", "\(svc.host):\(svc.port)"])
        refresh()
    }

    func connectDiscovered() {
        Task { for svc in discovered.values { await connect(svc) } }
    }

    func disconnect(_ d: Device) {
        Task {
            for t in d.transports { _ = await ADB.run(["disconnect", t]) }
            refresh()
        }
    }
}
