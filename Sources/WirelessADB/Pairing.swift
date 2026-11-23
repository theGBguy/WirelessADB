import SwiftUI
import CoreImage.CIFilterBuiltins

@MainActor
final class PairingModel: ObservableObject {
    enum State: Equatable { case waiting, pairing, connecting, done(String), failed(String) }

    @Published var state: State = .waiting
    @Published var qr: NSImage?

    private var name = ""
    private var password = ""
    private var pairFinder: ServiceFinder?
    private var connectFinder: ServiceFinder?
    private var pairedHost: String?

    func start() {
        stop()
        name = "studio-" + Self.random(8)
        password = Self.random(12)
        qr = Self.qrImage("WIFI:T:ADB;S:\(name);P:\(password);;")
        state = .waiting

        let f = ServiceFinder(type: "_adb-tls-pairing._tcp.")
        f.onFound = { [weak self] svc in Task { @MainActor in await self?.pair(svc) } }
        f.start()
        pairFinder = f
    }

    func stop() {
        pairFinder?.stop(); pairFinder = nil
        connectFinder?.stop(); connectFinder = nil
        pairedHost = nil
    }

    private func pair(_ svc: FoundService) async {
        guard svc.name == name, state == .waiting else { return }
        state = .pairing
        var last = ""
        for attempt in 1...3 {
            let r = await ADB.run(["pair", "\(svc.host):\(svc.port)", password])
            last = r.output
            if r.output.contains("Successfully paired") { break }
            log.error("pair attempt \(attempt): \(r.output, privacy: .public)")
            if r.output.localizedCaseInsensitiveContains("wrong password") { break }
            try? await Task.sleep(for: .seconds(1.5))
        }
        guard last.contains("Successfully paired") else {
            state = .failed(last.isEmpty ? "Pairing failed" : last)
            return
        }
        pairFinder?.stop()
        state = .connecting
        pairedHost = svc.host
        let c = ServiceFinder(type: "_adb-tls-connect._tcp.")
        c.onFound = { [weak self] svc in Task { @MainActor in await self?.connect(svc) } }
        c.start()
        connectFinder = c
        // If the connect service never shows up, say so instead of spinning forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            guard let self, self.state == .connecting else { return }
            self.state = .failed("Paired, but the phone didn't advertise a connection. Toggle Wireless debugging off and on.")
            self.connectFinder?.stop()
        }
    }

    private var connectingNow = false

    private func connect(_ svc: FoundService) async {
        guard state == .connecting, svc.host == pairedHost, !connectingNow else { return }
        connectingNow = true; defer { connectingNow = false }
        // The phone often needs a moment after pairing; adb may also auto-connect on its own.
        for attempt in 1...5 {
            try? await Task.sleep(for: .seconds(2))
            guard state == .connecting else { return }
            if await ADB.isConnected(svc) { break }
            let r = await ADB.connect("\(svc.host):\(svc.port)")
            if r.output.contains("connected to") { break }
            log.error("post-pair connect attempt \(attempt): \(r.output, privacy: .public)")
            if attempt == 5 { state = .failed(r.output); return }
        }
        state = .done("\(svc.host):\(svc.port)")
        connectFinder?.stop()
    }

    private static func random(_ n: Int) -> String {
        let chars = Array("abcdefghijkmnpqrstuvwxyz23456789")
        return String((0..<n).map { _ in chars.randomElement()! })
    }

    private static func qrImage(_ text: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)) else { return nil }
        let rep = NSCIImageRep(ciImage: out)
        let img = NSImage(size: rep.size)
        img.addRepresentation(rep)
        return img
    }
}

struct PairView: View {
    @ObservedObject var model: PairingModel
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            if let qr = model.qr {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 240, height: 240)
                    .padding(12)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            status
            HStack {
                Button("New code") { model.start() }
                Spacer()
                Button("Close") { model.stop(); NSApp.keyWindow?.close() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 320)
        .onChange(of: model.state) { _, s in if case .done = s { onDone() } }
        .onDisappear { model.stop() }
    }

    @ViewBuilder private var status: some View {
        switch model.state {
        case .waiting:
            Text("On the phone: Developer options › Wireless debugging › Pair device with QR code")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .pairing:
            Label("Pairing…", systemImage: "hourglass")
        case .connecting:
            Label("Paired. Connecting…", systemImage: "hourglass")
        case .done(let addr):
            Label("Connected \(addr)", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed(let msg):
            Text(msg).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
