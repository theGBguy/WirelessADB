// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "WirelessADB",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "WirelessADB", path: "Sources/WirelessADB")]
)
