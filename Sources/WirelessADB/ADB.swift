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

    struct Result { let status: Int32; let output: String }

    static func run(_ args: [String]) async -> Result {
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
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    p.waitUntilExit()
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
