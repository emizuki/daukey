// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "daukey",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DauKeyEngine", targets: ["DauKeyEngine"]),
        .executable(name: "daukey-driver", targets: ["DauKeyDriver"]),
        .executable(name: "daukey", targets: ["DauKey"]),
    ],
    targets: [
        .target(name: "DauKeyEngine"),
        .target(name: "DauKeyScript", dependencies: ["DauKeyEngine"]),
        .executableTarget(name: "DauKeyDriver", dependencies: ["DauKeyEngine", "DauKeyScript"]),
        .target(name: "DauKeyHook", dependencies: ["DauKeyEngine"]),
        .testTarget(name: "DauKeyHookTests", dependencies: ["DauKeyHook"]),
        .executableTarget(name: "DauKey", dependencies: ["DauKeyHook", "DauKeyEngine"]),
        .testTarget(name: "DauKeyTests", dependencies: ["DauKey"]),
        .testTarget(
            name: "DauKeyEngineTests",
            dependencies: ["DauKeyEngine", "DauKeyScript"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
