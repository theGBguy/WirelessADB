import SwiftUI
import AppKit

@main
struct WirelessADBApp: App {
    @StateObject private var devices = DeviceStore()
    @StateObject private var pairing = PairingModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(devices: devices, pairing: pairing)
        } label: {
            Image(systemName: devices.devices.isEmpty ? "iphone.slash" : "iphone.radiowaves.left.and.right")
        }
        .menuBarExtraStyle(.menu)

        Window("Pair with QR code", id: "pair") {
            PairView(model: pairing, onDone: { devices.refresh() })
        }
        .windowResizability(.contentSize)
    }
}

struct MenuContent: View {
    @ObservedObject var devices: DeviceStore
    @ObservedObject var pairing: PairingModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if devices.devices.isEmpty {
            Text("No devices connected")
        } else {
            ForEach(devices.devices) { d in
                Menu("\(d.name)  ·  \(d.wireless ? "Wi-Fi" : "USB")") {
                    Text(d.serial)
                    Button("Copy serial") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(d.serial, forType: .string)
                    }
                    if d.wireless {
                        Button("Disconnect") { devices.disconnect(d) }
                    }
                }
            }
        }
        Divider()
        Button("Pair new device with QR code…") {
            pairing.start()
            openWindow(id: "pair")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("p")
        Button("Connect paired devices now") { devices.connectDiscovered() }
        Toggle("Auto-connect paired devices", isOn: $devices.autoConnect)
        Button("Refresh") { devices.refresh() }
            .keyboardShortcut("r")
        if let err = devices.lastError {
            Divider()
            Text(err).foregroundStyle(.secondary)
        }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
