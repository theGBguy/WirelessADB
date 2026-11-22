import Foundation

struct Device: Identifiable, Hashable {
    let serial: String
    let name: String
    var id: String { serial }
    var wireless: Bool { serial.contains(":") || serial.contains("._adb-tls-connect") }
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
            devices = r.output.split(separator: "\n").dropFirst().compactMap { line in
                let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
                guard parts.count >= 2, parts[1] == "device" else { return nil }
                let model = parts.first { $0.hasPrefix("model:") }?.dropFirst(6).replacingOccurrences(of: "_", with: " ")
                return Device(serial: parts[0], name: model ?? parts[0])
            }
        }
    }

    func connect(_ svc: FoundService) async {
        let target = "\(svc.host):\(svc.port)"
        // Skip if already connected via this address or via its mDNS name.
        if devices.contains(where: { $0.serial == target || $0.serial.hasPrefix(svc.name) }) { return }
        _ = await ADB.run(["connect", target])
        refresh()
    }

    func connectDiscovered() {
        Task { for svc in discovered.values { await connect(svc) } }
    }

    func disconnect(_ d: Device) {
        Task { _ = await ADB.run(["disconnect", d.serial]); refresh() }
    }
}
