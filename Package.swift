// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PortForwarder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "PortForwarder", targets: ["PortForwarder"])
    ],
    targets: [
        .executableTarget(
            name: "PortForwarder",
            path: "Sources"
        )
    ]
)
