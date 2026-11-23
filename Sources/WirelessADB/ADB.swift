import Foundation

enum ADB {
    static let path: String? = {
        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let v = env[key] { candidates.append("\(v)/platform-tools/adb") }
        }
        candidates += [
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }()

    /// Serials of transports currently in "device" state.
    static func connectedSerials() async -> [String] {
        let r = await run(["devices"])
        return r.output.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            return parts.count >= 2 && parts[1] == "device" ? String(parts[0]) : nil
        }
    }

    /// True if adb already has a transport for this mDNS service (by name or ip:port).
    static func isConnected(_ svc: FoundService) async -> Bool {
        let target = "\(svc.host):\(svc.port)"
        return await connectedSerials().contains { $0 == target || $0.hasPrefix(svc.name + ".") }
    }

    private static var lastServerRestart = Date.distantPast

    /// `adb connect` that recovers from macOS Local Network privacy blocking the adb server.
    /// The server inherits that permission from whichever app launched it (Terminal, an IDE…);
    /// if that app lacks it, connections fail with "No route to host" even though the phone is reachable.
    /// Restarting the server from this app makes it inherit our permission.
    @MainActor
    static func connect(_ target: String) async -> Result {
        var r = await run(["connect", target])
        if r.output.contains("No route to host"), Date().timeIntervalSince(lastServerRestart) > 60 {
            log.error("adb server can't reach \(target, privacy: .public); restarting it from WirelessADB")
            lastServerRestart = Date()
            _ = await run(["kill-server"])
            let s = await run(["start-server"])
            if s.status != 0 { log.error("start-server: \(s.output, privacy: .public)") }
            r = await run(["connect", target])
        }
        return r
    }

    struct Result { let status: Int32; let output: String }

    static func run(_ args: [String], timeout: TimeInterval = 20) async -> Result {
        guard let path else { return Result(status: -1, output: "adb not found (install Android platform-tools)") }
        return await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: path)
                p.arguments = args
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = pipe
                do {
                    try p.run()
                    // Kill hung calls (e.g. `adb connect` to an unreachable host).
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if p.isRunning { log.error("adb \(args.joined(separator: " "), privacy: .public) timed out"); p.terminate() }
                    }
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
                    log.info("adb \(args.joined(separator: " "), privacy: .public) -> \(p.terminationStatus)")
                    cont.resume(returning: Result(status: p.terminationStatus,
                                                  output: String(decoding: data, as: UTF8.self)
                                                    .trimmingCharacters(in: .whitespacesAndNewlines)))
                } catch {
                    cont.resume(returning: Result(status: -1, output: error.localizedDescription))
                }
            }
        }
    }
}
