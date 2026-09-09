// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyStat",
    platforms: [.macOS(.v12)],
    targets: [
        .target(name: "MyStatCore"),
        .executableTarget(
            name: "MyStat",
            dependencies: ["MyStatCore"],
            path: "Sources/MyStat",
            exclude: ["Info.plist"]
        ),
        .testTarget(name: "MyStatCoreTests", dependencies: ["MyStatCore"])
    ]
)
