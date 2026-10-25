// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HopperBridge",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "HopperMCPServer", targets: ["HopperMCPServer"])
    ],
    targets: [
        .executableTarget(name: "HopperMCPServer", exclude: ["Resources"])
    ]
)
