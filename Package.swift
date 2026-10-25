// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "daukey",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DauKeyEngine", targets: ["DauKeyEngine"]),
    ],
    targets: [
        .target(name: "DauKeyEngine"),
        .target(name: "DauKeyScript", dependencies: ["DauKeyEngine"]),
        .testTarget(name: "DauKeyEngineTests", dependencies: ["DauKeyEngine", "DauKeyScript"]),
    ]
)
